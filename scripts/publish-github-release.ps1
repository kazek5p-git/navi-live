param(
    [string]$Tag,
    [string]$Title,
    [string]$NotesFile,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Get-RequiredValue {
    param(
        [string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing $Label."
    }

    return $Value.Trim()
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Command,
        [string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }

    try {
        & $Command[0] $Command[1..($Command.Length - 1)]
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $($Command -join ' ')"
        }
    } finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Invoke-Capture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Command,
        [string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }

    try {
        $output = & $Command[0] $Command[1..($Command.Length - 1)] 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($output | Out-String)
        }
        return ($output | Out-String).Trim()
    } finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Get-ReleaseNotes {
    param(
        [string]$Path,
        [string]$VersionLabel,
        [bool]$ReleaseExists,
        [string]$ExistingNotes
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return Get-Content -Path $Path -Raw -Encoding UTF8
    }

    if ($ReleaseExists -and -not [string]::IsNullOrWhiteSpace($ExistingNotes)) {
        return $ExistingNotes
    }

return @"
Navi Live $VersionLabel release.

- Android build published as navi-live.apk.
"@
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$androidDir = Join-Path $repoRoot "android"
$gradleFile = Join-Path $androidDir "app\build.gradle.kts"
$assetPath = Join-Path $androidDir "app\build\release-asset\navi-live.apk"
$tempPayloadPath = Join-Path $repoRoot ".release-payload.json"

$gradleText = Get-Content -Path $gradleFile -Raw -Encoding UTF8
$versionNameMatch = [regex]::Match($gradleText, 'versionName\s*=\s*"([^"]+)"')
$versionName = Get-RequiredValue -Value $versionNameMatch.Groups[1].Value -Label "versionName"

if ([string]::IsNullOrWhiteSpace($Tag)) {
    $Tag = "v$versionName"
}
$userProvidedTitle = -not [string]::IsNullOrWhiteSpace($Title)

$remoteUrl = Invoke-Capture -Command @("git", "-C", $repoRoot, "remote", "get-url", "origin")
$repoMatch = [regex]::Match($remoteUrl, 'github\.com[:/](.+?)(?:\.git)?$')
$repoSlug = Get-RequiredValue -Value $repoMatch.Groups[1].Value -Label "GitHub repo slug"
$targetBranch = Invoke-Capture -Command @("git", "-C", $repoRoot, "branch", "--show-current")

if (-not $SkipBuild) {
    Invoke-Tool -Command @(".\gradlew.bat", ":app:stageDebugReleaseAsset") -WorkingDirectory $androidDir
}

if (-not (Test-Path -Path $assetPath)) {
    throw "Release asset not found at $assetPath"
}

$releaseExists = $false
$release = $null
try {
    $releaseJson = Invoke-Capture -Command @("gh", "api", "repos/$repoSlug/releases/tags/$Tag")
    $release = $releaseJson | ConvertFrom-Json
    $releaseExists = $true
} catch {
    $releaseExists = $false
}

$notes = Get-ReleaseNotes -Path $NotesFile -VersionLabel $versionName -ReleaseExists $releaseExists -ExistingNotes $release.body
$effectiveTitle = if ($releaseExists -and -not $userProvidedTitle) {
    $release.name
} else {
    if ($userProvidedTitle) { $Title } else { $Tag }
}

$payload = $(
    if ($releaseExists) {
        @{
            name = $effectiveTitle
            body = $notes
        }
    } else {
        @{
            tag_name = $Tag
            target_commitish = $targetBranch
            name = $effectiveTitle
            body = $notes
        }
    }
) | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText(
    $tempPayloadPath,
    $payload,
    [System.Text.UTF8Encoding]::new($false)
)

try {
    if ($releaseExists) {
        Invoke-Tool -Command @("gh", "api", "repos/$repoSlug/releases/$($release.id)", "--method", "PATCH", "--input", $tempPayloadPath)
    } else {
        Invoke-Tool -Command @("gh", "api", "repos/$repoSlug/releases", "--method", "POST", "--input", $tempPayloadPath)
        $releaseJson = Invoke-Capture -Command @("gh", "api", "repos/$repoSlug/releases/tags/$Tag")
        $release = $releaseJson | ConvertFrom-Json
    }

    $assetsJson = Invoke-Capture -Command @("gh", "api", "repos/$repoSlug/releases/$($release.id)/assets")
    $assets = $assetsJson | ConvertFrom-Json
    foreach ($asset in $assets) {
        if ($asset.name -like "*.apk") {
            Invoke-Tool -Command @("gh", "api", "repos/$repoSlug/releases/assets/$($asset.id)", "--method", "DELETE")
        }
    }

    $uploadUrl = "https://uploads.github.com/repos/$repoSlug/releases/$($release.id)/assets?name=navi-live.apk"
    Invoke-Tool -Command @(
        "gh",
        "api",
        $uploadUrl,
        "--method",
        "POST",
        "--input",
        $assetPath,
        "-H",
        "Content-Type: application/vnd.android.package-archive"
    )

    $releaseJson = Invoke-Capture -Command @("gh", "api", "repos/$repoSlug/releases/tags/$Tag")
    $release = $releaseJson | ConvertFrom-Json
    $downloadUrl = ($release.assets | Where-Object { $_.name -eq "navi-live.apk" } | Select-Object -First 1).browser_download_url

    Write-Host "Release ready: $($release.html_url)"
    Write-Host "APK: $downloadUrl"
    Write-Host "Latest link: https://github.com/$repoSlug/releases/latest/download/navi-live.apk"
} finally {
    if (Test-Path -Path $tempPayloadPath) {
        Remove-Item -Path $tempPayloadPath -Force
    }
}
