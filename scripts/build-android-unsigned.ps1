[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,
    [Parameter(Mandatory = $true)]
    [string]$WebSocketBaseUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ValidatedEndpoint {
    param(
        [string]$Value,
        [string]$Scheme,
        [string]$Name
    )

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) {
        throw "$Name deve ser uma URL absoluta."
    }
    if ($uri.Scheme -ne $Scheme -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw "$Name deve usar $Scheme e não pode conter credenciais, query ou fragmento."
    }
    if (
        $uri.AbsolutePath -ne "/" -or
        $uri.IsLoopback -or
        $uri.Host -match '(?i)(localhost|\.localhost|\.invalid)$'
    ) {
        throw "$Name deve conter uma origem pública, sem caminho nem host local ou placeholder."
    }
    return $uri.GetLeftPart([UriPartial]::Authority).TrimEnd("/")
}

$apiEndpoint = Get-ValidatedEndpoint $ApiBaseUrl "https" "API_BASE_URL"
$websocketEndpoint = Get-ValidatedEndpoint $WebSocketBaseUrl "wss" "WS_BASE_URL"
$frontendRoot = Join-Path $PSScriptRoot "..\frontend"

Push-Location $frontendRoot
try {
    & flutter build apk --release --no-pub `
        "--dart-define=API_BASE_URL=$apiEndpoint" `
        "--dart-define=WS_BASE_URL=$websocketEndpoint"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter falhou ao compilar o APK release."
    }

    & flutter build appbundle --release --no-pub `
        "--dart-define=API_BASE_URL=$apiEndpoint" `
        "--dart-define=WS_BASE_URL=$websocketEndpoint"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter falhou ao compilar o Android App Bundle release."
    }
}
finally {
    Pop-Location
}

Write-Host "APK unsigned: frontend\build\app\outputs\flutter-apk\app-release.apk"
Write-Host "AAB unsigned: frontend\build\app\outputs\bundle\release\app-release.aab"
