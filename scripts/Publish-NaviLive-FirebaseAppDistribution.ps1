[CmdletBinding()]
param(
    [string]$ApkPath = (Join-Path $PSScriptRoot '..\android\app\build\release-asset\navi-live.apk'),
    [string]$ReleaseNotesFile,
    [string]$FirebaseProjectId = 'navi-live-kazek5p',
    [string]$FirebaseAppId = '1:544314236646:android:05a4a4dca755c911aea527',
    [string]$TesterGroupAlias = 'navi-live-android-testers',
    [string]$FirebaseCliVersion = '15.28.2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RequiredPath {
    param([string]$Path, [string]$Description)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw "Nie znaleziono $Description`: $Path"
    }

    return $resolved.Path
}

$apk = Resolve-RequiredPath -Path $ApkPath -Description 'pliku APK'

if ([string]::IsNullOrWhiteSpace($env:FIREBASE_TOKEN) -and
    [string]::IsNullOrWhiteSpace($env:GOOGLE_APPLICATION_CREDENTIALS)) {
    throw 'Brak uwierzytelnienia Firebase. Ustaw FIREBASE_TOKEN albo GOOGLE_APPLICATION_CREDENTIALS poza repozytorium.'
}

if (-not [string]::IsNullOrWhiteSpace($env:GOOGLE_APPLICATION_CREDENTIALS)) {
    Resolve-RequiredPath -Path $env:GOOGLE_APPLICATION_CREDENTIALS -Description 'pliku poświadczeń Firebase' | Out-Null
}

$notesArguments = @()
if (-not [string]::IsNullOrWhiteSpace($ReleaseNotesFile)) {
    $notes = Resolve-RequiredPath -Path $ReleaseNotesFile -Description 'pliku informacji dla testerów'
    $notesArguments = @('--release-notes-file', $notes)
}
else {
    $notesArguments = @('--release-notes', "Navi Live Android - wersja testowa $(Get-Date -Format 'yyyy-MM-dd')")
}

Write-Host "Wysyłam APK Navi Live do Firebase App Distribution: $FirebaseProjectId / $TesterGroupAlias"
& npx --yes "firebase-tools@$FirebaseCliVersion" appdistribution:distribute $apk `
    --app $FirebaseAppId `
    --project $FirebaseProjectId `
    --groups $TesterGroupAlias `
    @notesArguments

if ($LASTEXITCODE -ne 0) {
    throw "Firebase App Distribution zakończyło się kodem $LASTEXITCODE."
}

Write-Host 'Wysyłka Navi Live do Firebase App Distribution zakończyła się pomyślnie.'
