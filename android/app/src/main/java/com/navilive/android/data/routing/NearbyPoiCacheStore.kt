package com.navilive.android.data.routing

import android.content.Context
import com.navilive.android.model.GeoPoint
import com.navilive.android.model.NearbyPoiCacheState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

internal data class NearbyPoiCacheRecord(
    val id: String,
    val name: String,
    val address: String,
    val latitude: Double,
    val longitude: Double,
    val phone: String?,
    val website: String?,
    val kind: String,
    val searchableText: String,
    val fetchedAtMs: Long,
) {
    val point: GeoPoint = GeoPoint(latitude = latitude, longitude = longitude)
}

internal class NearbyPoiCacheStore(context: Context) {
    private val cacheFile = File(context.filesDir, CacheFileName)

    suspend fun loadRecords(): List<NearbyPoiCacheRecord> = withContext(Dispatchers.IO) {
        readSnapshot().records
    }

    suspend fun metadata(): NearbyPoiCacheState = withContext(Dispatchers.IO) {
        val snapshot = readSnapshot()
        NearbyPoiCacheState(
            cachedPlaceCount = snapshot.records.size,
            lastUpdatedAtMs = snapshot.lastUpdatedAtMs,
            lastCenter = snapshot.center,
        )
    }

    suspend fun saveMerged(
        records: List<NearbyPoiCacheRecord>,
        center: GeoPoint,
        fetchedAtMs: Long,
    ): NearbyPoiCacheState = withContext(Dispatchers.IO) {
        val merged = LinkedHashMap<String, NearbyPoiCacheRecord>()
        records.forEach { record -> merged[record.id] = record.copy(fetchedAtMs = fetchedAtMs) }
        readSnapshot().records
            .filter { fetchedAtMs - it.fetchedAtMs <= MaxRecordAgeMs }
            .forEach { record ->
                if (!merged.containsKey(record.id)) {
                    merged[record.id] = record
                }
            }

        val pruned = merged.values
            .sortedByDescending { it.fetchedAtMs }
            .take(MaxRecordCount)
        writeSnapshot(CacheSnapshot(fetchedAtMs, center, pruned))
        NearbyPoiCacheState(
            cachedPlaceCount = pruned.size,
            lastUpdatedAtMs = fetchedAtMs,
            lastCenter = center,
        )
    }

    suspend fun clear(): NearbyPoiCacheState = withContext(Dispatchers.IO) {
        cacheFile.delete()
        NearbyPoiCacheState()
    }

    private fun readSnapshot(): CacheSnapshot {
        if (!cacheFile.exists()) return CacheSnapshot()
        return runCatching {
            val root = JSONObject(cacheFile.readText())
            val center = if (root.has("centerLat") && root.has("centerLon")) {
                GeoPoint(
                    latitude = root.optDouble("centerLat"),
                    longitude = root.optDouble("centerLon"),
                )
            } else {
                null
            }
            val recordsJson = root.optJSONArray("records") ?: JSONArray()
            val records = buildList {
                for (index in 0 until recordsJson.length()) {
                    val item = recordsJson.optJSONObject(index) ?: continue
                    val id = item.optString("id").trim()
                    val name = item.optString("name").trim()
                    val lat = item.optDouble("lat", Double.NaN)
                    val lon = item.optDouble("lon", Double.NaN)
                    if (id.isBlank() || name.isBlank() || lat.isNaN() || lon.isNaN()) continue
                    add(
                        NearbyPoiCacheRecord(
                            id = id,
                            name = name,
                            address = item.optString("address"),
                            latitude = lat,
                            longitude = lon,
                            phone = item.optString("phone").ifBlank { null },
                            website = item.optString("website").ifBlank { null },
                            kind = item.optString("kind"),
                            searchableText = item.optString("searchableText"),
                            fetchedAtMs = item.optLong("fetchedAtMs", 0L),
                        ),
                    )
                }
            }
            CacheSnapshot(
                lastUpdatedAtMs = root.optLong("lastUpdatedAtMs", 0L).takeIf { it > 0L },
                center = center,
                records = records,
            )
        }.getOrDefault(CacheSnapshot())
    }

    private fun writeSnapshot(snapshot: CacheSnapshot) {
        val root = JSONObject()
            .put("version", 1)
            .put("lastUpdatedAtMs", snapshot.lastUpdatedAtMs ?: 0L)
        snapshot.center?.let { center ->
            root.put("centerLat", center.latitude)
            root.put("centerLon", center.longitude)
        }
        val records = JSONArray()
        snapshot.records.forEach { record ->
            records.put(
                JSONObject()
                    .put("id", record.id)
                    .put("name", record.name)
                    .put("address", record.address)
                    .put("lat", record.latitude)
                    .put("lon", record.longitude)
                    .put("phone", record.phone.orEmpty())
                    .put("website", record.website.orEmpty())
                    .put("kind", record.kind)
                    .put("searchableText", record.searchableText)
                    .put("fetchedAtMs", record.fetchedAtMs),
            )
        }
        root.put("records", records)
        cacheFile.parentFile?.mkdirs()
        cacheFile.writeText(root.toString())
    }

    private data class CacheSnapshot(
        val lastUpdatedAtMs: Long? = null,
        val center: GeoPoint? = null,
        val records: List<NearbyPoiCacheRecord> = emptyList(),
    )

    private companion object {
        const val CacheFileName = "nearby_poi_cache.json"
        const val MaxRecordCount = 1_200
        const val MaxRecordAgeMs = 14L * 24L * 60L * 60L * 1_000L
    }
}
