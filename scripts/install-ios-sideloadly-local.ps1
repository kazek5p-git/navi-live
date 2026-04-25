param(
    [string]$IpaPath,
    [string]$MacHost = "mac_axela",
    [string]$RemoteRoot = "/tmp/navilive-ios-local",
    [int]$MaxAttempts = 3,
    [int]$TimeoutSec = 180,
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

function New-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$nativeIosDir = Join-Path $repoRoot "native-ios"
$sharedDir = Join-Path $repoRoot "shared"
$bridgePath = "C:\Users\Kazek\Desktop\iOS\Install-IPA-Sideloadly-Bridge.ps1"
$localIpaRoot = "C:\Users\Kazek\Desktop\iOS\NaviLive\Builds\Unsigned\local"
$localIpaPath = Join-Path $localIpaRoot "Navi-Live-local.ipa"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$localBuildScript = Join-Path $env:TEMP "navilive-ios-local-build-$stamp.sh"

if (-not (Test-Path -LiteralPath $bridgePath)) {
    throw "Sideloadly bridge script not found: $bridgePath"
}

if ([string]::IsNullOrWhiteSpace($IpaPath)) {
    $IpaPath = $localIpaPath
}

if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $nativeIosDir)) {
        throw "native-ios directory not found: $nativeIosDir"
    }
    if (-not (Test-Path -LiteralPath $sharedDir)) {
        throw "shared directory not found: $sharedDir"
    }

    New-Item -ItemType Directory -Force -Path $localIpaRoot | Out-Null

    Write-Host "[etap] Preparing local iOS build workspace on Mac."
    Invoke-Tool -Command @("ssh", $MacHost, "rm -rf '$RemoteRoot' && mkdir -p '$RemoteRoot'")
    Invoke-Tool -Command @("scp", "-r", $nativeIosDir, $sharedDir, "$($MacHost):$RemoteRoot/")

    $remoteBuildScript = @'
set -euo pipefail

cd "__REMOTE_ROOT__"

if command -v xcodegen >/dev/null 2>&1; then
  (cd native-ios && xcodegen generate)
fi

xcodebuild \
  -project native-ios/NaviLive.xcodeproj \
  -scheme NaviLive \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath native-ios/build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  clean build | tee native-ios-local-build.log

APP_PATH="native-ios/build/Build/Products/Release-iphoneos/NaviLive.app"
if [ ! -d "$APP_PATH" ]; then
  echo "No app bundle found at $APP_PATH" >&2
  exit 1
fi

rm -rf unsigned-ipa
mkdir -p unsigned-ipa/Payload
cp -R "$APP_PATH" unsigned-ipa/Payload/
(
  cd unsigned-ipa
  zip -qry ../Navi-Live-local.ipa Payload
)
'@.Replace("__REMOTE_ROOT__", $RemoteRoot)
    New-Utf8NoBomFile -Path $localBuildScript -Content $remoteBuildScript

    try {
        Write-Host "[etap] Building local unsigned iOS IPA on Mac."
        Invoke-Tool -Command @("scp", $localBuildScript, "$($MacHost):$RemoteRoot/build-ios-local.sh")
        Invoke-Tool -Command @("ssh", $MacHost, "chmod +x '$RemoteRoot/build-ios-local.sh' && '$RemoteRoot/build-ios-local.sh'")

        Write-Host "[etap] Downloading local IPA from Mac."
        Invoke-Tool -Command @("scp", "$($MacHost):$RemoteRoot/Navi-Live-local.ipa", $localIpaPath)
    } finally {
        Remove-Item -LiteralPath $localBuildScript -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $IpaPath)) {
    throw "IPA not found: $IpaPath"
}

Write-Host "[etap] Installing local iOS IPA through Sideloadly."
Write-Host "IPA: $IpaPath"
& $bridgePath -IpaPath $IpaPath -MaxAttempts $MaxAttempts -TimeoutSec $TimeoutSec
if ($LASTEXITCODE -ne 0) {
    throw "Sideloadly bridge failed with exit code $LASTEXITCODE."
}

Write-Host "[etap] iOS local install completed."
