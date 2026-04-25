param(
    [string]$ApkPath,
    [string]$DeviceSerial,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

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

function Resolve-AdbDevice {
    param([string]$PreferredSerial)

    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw "adb is not available in PATH. Install Android platform-tools first."
    }

    $deviceLines = Invoke-Capture -Command @("adb", "devices")
    $devices = @()
    foreach ($line in ($deviceLines -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^([^\s]+)\s+device$") {
            $devices += $matches[1]
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredSerial)) {
        if ($devices -notcontains $PreferredSerial) {
            throw "Requested Android device '$PreferredSerial' is not connected. Connected devices: $($devices -join ', ')"
        }
        return $PreferredSerial
    }

    if ($devices.Count -eq 0) {
        throw "No authorized Android device found. Connect the phone and accept USB debugging."
    }

    if ($devices.Count -gt 1) {
        throw "More than one Android device is connected. Re-run with -DeviceSerial. Connected devices: $($devices -join ', ')"
    }

    return $devices[0]
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$androidDir = Join-Path $repoRoot "android"
$defaultApkPath = Join-Path $androidDir "app\build\release-asset\navi-live.apk"

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = $defaultApkPath
}

if (-not $SkipBuild) {
    Write-Host "[etap] Building local Android APK."
    Invoke-Tool -Command @(".\gradlew.bat", ":app:stageDebugReleaseAsset") -WorkingDirectory $androidDir
}

if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK not found: $ApkPath"
}

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
$serial = Resolve-AdbDevice -PreferredSerial $DeviceSerial

Write-Host "[etap] Installing local Android APK."
Write-Host "Device: $serial"
Write-Host "APK: $resolvedApk"

Invoke-Tool -Command @("adb", "-s", $serial, "install", "-r", "-d", $resolvedApk)

Write-Host "[etap] Android local install completed."
