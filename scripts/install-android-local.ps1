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

function Get-AdbDeviceStates {
    $deviceLines = Invoke-Capture -Command @("adb", "devices")
    $states = [ordered]@{}
    foreach ($line in ($deviceLines -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^([^\s]+)\s+([^\s]+)$") {
            $states[$matches[1]] = $matches[2]
        }
    }
    return $states
}

function Restart-AdbConnection {
    Write-Host "[etap] Refreshing Android USB debugging connection."
    & adb kill-server | Out-Host
    Start-Sleep -Seconds 2
    & adb start-server | Out-Host
    Start-Sleep -Seconds 2
    & adb reconnect | Out-Host
    Start-Sleep -Seconds 3
}

function Resolve-AdbDevice {
    param([string]$PreferredSerial)

    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw "adb is not available in PATH. Install Android platform-tools first."
    }

    $states = Get-AdbDeviceStates
    if ($states.Values -contains "offline") {
        Restart-AdbConnection
        $states = Get-AdbDeviceStates
    }

    $devices = @($states.Keys | Where-Object { $states[$_] -eq "device" })
    $blockedDevices = @($states.Keys | Where-Object { $states[$_] -ne "device" })

    if (-not [string]::IsNullOrWhiteSpace($PreferredSerial)) {
        if ($devices -notcontains $PreferredSerial) {
            $state = if ($states.Contains($PreferredSerial)) { $states[$PreferredSerial] } else { "not connected" }
            throw "Requested Android device '$PreferredSerial' is not ready. State: $state. Unlock the phone and accept USB debugging if prompted."
        }
        return $PreferredSerial
    }

    if ($devices.Count -eq 0) {
        if ($blockedDevices.Count -gt 0) {
            $blocked = ($blockedDevices | ForEach-Object { "$_=$($states[$_])" }) -join ', '
            throw "No ready Android device found. Current state: $blocked. Unlock the phone and accept USB debugging if prompted."
        }
        throw "No Android device found. Connect the phone and accept USB debugging."
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
