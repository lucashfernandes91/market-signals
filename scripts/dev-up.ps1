[CmdletBinding()]
param(
    [string]$AvdName = "Medium_Phone",
    [string]$AndroidPackage = "com.example.market_radar"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendRoot = Join-Path $projectRoot "backend"
$runtimeRoot = Join-Path $projectRoot ".run"
$logsRoot = Join-Path $runtimeRoot "logs"

New-Item -ItemType Directory -Force -Path $runtimeRoot, $logsRoot | Out-Null

function Write-Step {
    param([string]$Message)
    Write-Host "[Market Radar] $Message" -ForegroundColor Cyan
}

function Resolve-Executable {
    param(
        [string]$Name,
        [string]$Fallback = ""
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if ($Fallback -and (Test-Path -LiteralPath $Fallback)) {
        return $Fallback
    }

    throw "Executavel nao encontrado: $Name"
}

$dockerExe = Resolve-Executable "docker"
$uvExe = Resolve-Executable "uv" "C:\Python39\Scripts\uv.exe"
$adbExe = Resolve-Executable "adb" "R:\RedTeam\Android\Sdk\platform-tools\adb.exe"
$emulatorExe = Resolve-Executable "emulator" "R:\RedTeam\Android\Sdk\tools\emulator.exe"

function Test-DockerReady {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $dockerExe info --format "{{.ServerVersion}}" *> $null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return $exitCode -eq 0
}

if (-not (Test-DockerReady)) {
    $dockerDesktop = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path -LiteralPath $dockerDesktop)) {
        throw "Docker Desktop nao foi encontrado."
    }

    Write-Step "Iniciando Docker Desktop..."
    Start-Process -FilePath $dockerDesktop -WindowStyle Hidden

    $dockerDeadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $dockerDeadline -and -not (Test-DockerReady)) {
        Start-Sleep -Seconds 3
    }

    if (-not (Test-DockerReady)) {
        throw "Docker Desktop nao ficou pronto em 90 segundos."
    }
}

Write-Step "Subindo Redis..."
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & $dockerExe compose -f (Join-Path $projectRoot "docker-compose.yml") up -d redis
    $composeExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorAction
}
if ($composeExitCode -ne 0) {
    throw "Falha ao iniciar o Redis."
}

$backendEnvironment = @{
    DJANGO_SETTINGS_MODULE = "core.settings.development"
    REDIS_URL = "redis://127.0.0.1:6380/0"
    MARKET_PROVIDER = "binance"
    # Modo temporario do ambiente local; login e cadastro permanecem disponiveis.
    PERSONAL_MODE_ENABLED = "true"
    PERSONAL_MODE_EMAIL = "personal@market-radar.local"
    NOTIFICATION_PROVIDER = "stub"
}

Write-Step "Sincronizando catalogo de mercados..."
$previousEnvironment = @{}
foreach ($entry in $backendEnvironment.GetEnumerator()) {
    $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, "Process")
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
}

try {
    $seedProcess = Start-Process `
        -FilePath $uvExe `
        -ArgumentList @("run", "python", "manage.py", "seed_market") `
        -WorkingDirectory $backendRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logsRoot "seed-market.out.log") `
        -RedirectStandardError (Join-Path $logsRoot "seed-market.err.log") `
        -Wait `
        -PassThru
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }
}

if ($seedProcess.ExitCode -ne 0) {
    throw "Falha ao sincronizar o catalogo. Consulte .run\logs\seed-market.err.log."
}

function Start-BackendProcess {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    $pidPath = Join-Path $runtimeRoot "$Name.pid"
    if (Test-Path -LiteralPath $pidPath) {
        $savedPid = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue
        if ($savedPid -and (Get-Process -Id $savedPid -ErrorAction SilentlyContinue)) {
            Write-Step "$Name ja esta ativo (PID $savedPid)."
            return
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }

    $processEnvironment = $backendEnvironment.Clone()
    $processEnvironment["SERVICE_NAME"] = $Name
    $previousEnvironment = @{}
    foreach ($entry in $processEnvironment.GetEnumerator()) {
        $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, "Process")
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }

    try {
        $process = Start-Process `
            -FilePath $uvExe `
            -ArgumentList $Arguments `
            -WorkingDirectory $backendRoot `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logsRoot "$Name.out.log") `
            -RedirectStandardError (Join-Path $logsRoot "$Name.err.log") `
            -PassThru
    }
    finally {
        foreach ($entry in $previousEnvironment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
        }
    }

    Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ASCII
    Write-Step "$Name iniciado (PID $($process.Id))."
}

function Test-ApiReady {
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:8001/health/ready/" -TimeoutSec 3
        return $health.status -eq "ok"
    }
    catch {
        return $false
    }
}

if (Test-ApiReady) {
    Write-Step "API ja esta ativa em http://127.0.0.1:8001."
}
else {
    Start-BackendProcess "web" @(
        "run", "daphne", "-b", "127.0.0.1", "-p", "8001", "core.asgi:application"
    )

    $apiDeadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $apiDeadline -and -not (Test-ApiReady)) {
        Start-Sleep -Seconds 2
    }

    if (-not (Test-ApiReady)) {
        throw "A API nao ficou pronta. Consulte .run\logs\web.err.log."
    }
}

Start-BackendProcess "market-ingestor" @("run", "python", "manage.py", "run_market_ingestor")
Start-BackendProcess "market-watchdog" @("run", "python", "manage.py", "run_market_watchdog")
Start-BackendProcess "alert-worker" @("run", "python", "manage.py", "run_alert_worker")
Start-BackendProcess "notification-worker" @("run", "python", "manage.py", "run_notification_worker")

function Get-EmulatorSerial {
    $deviceLine = & $adbExe devices | Where-Object { $_ -match "^emulator-\d+\s+device$" } | Select-Object -First 1
    if (-not $deviceLine) {
        return $null
    }
    return ($deviceLine -split "\s+")[0]
}

$emulatorSerial = Get-EmulatorSerial
if (-not $emulatorSerial) {
    $availableAvds = @(& $emulatorExe -list-avds | Where-Object { $_.Trim() })
    if ($availableAvds.Count -eq 0) {
        throw "Nenhum emulador Android foi encontrado."
    }

    $selectedAvd = if ($availableAvds -contains $AvdName) { $AvdName } else { $availableAvds[0] }
    Write-Step "Iniciando emulador $selectedAvd..."
    Start-Process -FilePath $emulatorExe -ArgumentList @(
        "-avd", $selectedAvd, "-gpu", "host"
    ) -WindowStyle Hidden

    $deviceDeadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deviceDeadline -and -not $emulatorSerial) {
        Start-Sleep -Seconds 3
        $emulatorSerial = Get-EmulatorSerial
    }

    if (-not $emulatorSerial) {
        throw "O emulador nao apareceu no ADB em 120 segundos."
    }
}
else {
    Write-Step "Emulador ja esta ativo: $emulatorSerial."
}

$bootDeadline = (Get-Date).AddSeconds(120)
do {
    $bootCompleted = (& $adbExe -s $emulatorSerial shell getprop sys.boot_completed 2>$null).Trim()
    if ($bootCompleted -eq "1") {
        break
    }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $bootDeadline)

if ($bootCompleted -ne "1") {
    throw "O Android nao concluiu o boot em 120 segundos."
}

Write-Step "Configurando acesso do app a API..."
& $adbExe -s $emulatorSerial reverse tcp:8001 tcp:8001 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao configurar adb reverse para a porta 8001."
}

$reverseMapping = @(& $adbExe -s $emulatorSerial reverse --list)
if (-not ($reverseMapping -match "tcp:8001\s+tcp:8001")) {
    throw "O redirecionamento da API para o emulador não foi confirmado."
}

& $adbExe -s $emulatorSerial shell nc -z -w 5 127.0.0.1 8001 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "O emulador não conseguiu acessar a API local pela porta 8001."
}

$installedPackage = & $adbExe -s $emulatorSerial shell pm path $AndroidPackage 2>$null
if (-not ($installedPackage -match "^package:")) {
    $apkPath = Join-Path $projectRoot "frontend\build\app\outputs\flutter-apk\app-debug.apk"
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "O app nao esta instalado e o APK nao existe em $apkPath."
    }

    Write-Step "Instalando APK existente..."
    & $adbExe -s $emulatorSerial install -r $apkPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao instalar o APK no emulador."
    }
}

Write-Step "Abrindo Market Radar..."
& $adbExe -s $emulatorSerial shell am force-stop $AndroidPackage | Out-Null
& $adbExe -s $emulatorSerial shell am start -n "$AndroidPackage/.MainActivity" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao abrir o Market Radar no emulador."
}

Write-Host ""
Write-Host "Ambiente online." -ForegroundColor Green
Write-Host "API: http://127.0.0.1:8001"
Write-Host "Redis: 127.0.0.1:6380"
Write-Host "Emulador: $emulatorSerial"
Write-Host "Logs: $logsRoot"
