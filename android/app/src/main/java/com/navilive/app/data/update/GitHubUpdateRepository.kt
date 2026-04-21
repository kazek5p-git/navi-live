package com.navilive.app.data.update

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.max

data class GitHubReleaseAsset(
    val name: String,
    val downloadUrl: String,
    val sizeBytes: Long,
)

data class GitHubReleaseInfo(
    val tagName: String,
    val versionLabel: String,
    val releaseName: String,
    val body: String,
    val htmlUrl: String,
    val publishedAt: String?,
    val asset: GitHubReleaseAsset,
)

class GitHubUpdateRepository(
    private val owner: String = "kazek5p-git",
    private val repo: String = "navilive",
) {

    suspend fun fetchLatestRelease(): GitHubReleaseInfo = withContext(Dispatchers.IO) {
        val endpoint = "https://api.github.com/repos/$owner/$repo/releases/latest"
        val payload = requestText(endpoint)
        val root = JSONObject(payload)
        val tagName = root.optString("tag_name").ifBlank {
            throw IllegalStateException("GitHub release did not include a tag.")
        }
        val asset = selectApkAsset(root.optJSONArray("assets"))
        GitHubReleaseInfo(
            tagName = tagName,
            versionLabel = normalizeVersionLabel(tagName),
            releaseName = root.optString("name").ifBlank { tagName },
            body = root.optString("body").trim(),
            htmlUrl = root.optString("html_url"),
            publishedAt = root.optString("published_at").takeIf { it.isNotBlank() },
            asset = asset,
        )
    }

    suspend fun downloadReleaseAsset(
        asset: GitHubReleaseAsset,
        destination: File,
        onProgress: (Int?) -> Unit,
    ): File = withContext(Dispatchers.IO) {
        destination.parentFile?.mkdirs()
        val temporary = File(destination.parentFile, "${destination.name}.part")
        if (temporary.exists()) {
            temporary.delete()
        }

        val connection = (URL(asset.downloadUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 20_000
            readTimeout = 60_000
            setRequestProperty("Accept", "application/octet-stream")
            setRequestProperty("User-Agent", "navilive/0.2 (github-updater)")
        }

        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                val payload = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                throw IllegalStateException("HTTP $status: $payload")
            }
            val contentLength = connection.contentLengthLong.takeIf { it > 0L }
            var bytesRead = 0L
            var lastProgress = -1
            connection.inputStream.use { input ->
                temporary.outputStream().buffered().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count <= 0) break
                        output.write(buffer, 0, count)
                        bytesRead += count
                        val progress = contentLength?.let { total ->
                            ((bytesRead * 100L) / max(total, 1L)).toInt().coerceIn(0, 100)
                        }
                        if (progress != lastProgress) {
                            lastProgress = progress ?: lastProgress
                            onProgress(progress)
                        }
                    }
                    output.flush()
                }
            }

            if (destination.exists()) {
                destination.delete()
            }
            temporary.renameTo(destination)
            onProgress(100)
            destination
        } finally {
            connection.disconnect()
            if (temporary.exists() && destination.exists()) {
                temporary.delete()
            }
        }
    }

    fun compareVersions(currentVersionLabel: String, remoteVersionLabel: String): Int {
        val current = parseComparableVersion(currentVersionLabel)
        val remote = parseComparableVersion(remoteVersionLabel)
        if (current == null || remote == null) {
            return remoteVersionLabel.compareTo(currentVersionLabel)
        }
        return remote.compareTo(current)
    }

    fun normalizeVersionLabel(raw: String): String {
        return raw.removePrefix("v").trim()
    }

    private fun selectApkAsset(assets: JSONArray?): GitHubReleaseAsset {
        if (assets == null || assets.length() == 0) {
            throw IllegalStateException("GitHub release does not contain any assets.")
        }

        val parsed = buildList {
            for (index in 0 until assets.length()) {
                val item = assets.optJSONObject(index) ?: continue
                val name = item.optString("name")
                val url = item.optString("browser_download_url")
                if (name.isBlank() || url.isBlank()) continue
                add(
                    GitHubReleaseAsset(
                        name = name,
                        downloadUrl = url,
                        sizeBytes = item.optLong("size"),
                    ),
                )
            }
        }

        return parsed.firstOrNull { it.name.equals("app-release.apk", ignoreCase = true) }
            ?: parsed.firstOrNull { it.name.equals("app-debug.apk", ignoreCase = true) }
            ?: parsed.firstOrNull { it.name.endsWith(".apk", ignoreCase = true) }
            ?: throw IllegalStateException("GitHub release does not contain an APK asset.")
    }

    private fun requestText(rawUrl: String): String {
        val connection = (URL(rawUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "navilive/0.2 (github-updater)")
        }
        return try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val payload = stream.bufferedReader().use { it.readText() }
            if (status !in 200..299) {
                throw IllegalStateException("HTTP $status: $payload")
            }
            payload
        } finally {
            connection.disconnect()
        }
    }

    private fun parseComparableVersion(raw: String): ComparableVersion? {
        val normalized = raw.removePrefix("v").trim()
        val match = VERSION_REGEX.matchEntire(normalized) ?: return null
        val core = match.groupValues[1]
            .split('.')
            .mapNotNull { it.toIntOrNull() }
        if (core.isEmpty()) return null
        val suffix = match.groupValues.getOrNull(2).orEmpty()
            .takeIf { it.isNotBlank() }
            ?.split('.', '-')
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        return ComparableVersion(core = core, suffix = suffix)
    }

    private data class ComparableVersion(
        val core: List<Int>,
        val suffix: List<String>,
    ) : Comparable<ComparableVersion> {
        override fun compareTo(other: ComparableVersion): Int {
            val maxSize = max(core.size, other.core.size)
            for (index in 0 until maxSize) {
                val thisValue = core.getOrElse(index) { 0 }
                val otherValue = other.core.getOrElse(index) { 0 }
                if (thisValue != otherValue) {
                    return thisValue.compareTo(otherValue)
                }
            }

            if (suffix.isEmpty() && other.suffix.isEmpty()) return 0
            if (suffix.isEmpty()) return 1
            if (other.suffix.isEmpty()) return -1

            val suffixLength = max(suffix.size, other.suffix.size)
            for (index in 0 until suffixLength) {
                val left = suffix.getOrNull(index) ?: return -1
                val right = other.suffix.getOrNull(index) ?: return 1
                val leftNumber = left.toIntOrNull()
                val rightNumber = right.toIntOrNull()
                val comparison = when {
                    leftNumber != null && rightNumber != null -> leftNumber.compareTo(rightNumber)
                    leftNumber != null -> -1
                    rightNumber != null -> 1
                    else -> left.compareTo(right, ignoreCase = true)
                }
                if (comparison != 0) return comparison
            }
            return 0
        }
    }

    private companion object {
        val VERSION_REGEX = Regex("""^([0-9]+(?:\.[0-9]+)*)(?:[-+]([0-9A-Za-z.-]+))?$""")
    }
}
