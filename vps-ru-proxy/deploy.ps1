#Requires -Version 5.1
# deploy.ps1 -- zapuskaetsya na Windows.
# Interaktivno zapraschivaet parametry VPS, kopiru faili po SCP,
# opcionalno zapuskaet setup.sh.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Direktoria, v kotoroy lezit sam skript (vps-ru-proxy/)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

# Faily dlya kopirovaniya na VPS
$FilesToCopy = @('setup.sh', 'docker-compose.yml', 'frps.toml')

# ============================================================
# Funkcii vyvoda
# ============================================================
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==== $Message ====" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERR]  $Message" -ForegroundColor Red
}

# Proverka $LASTEXITCODE posle vneshney komandy
function Assert-LastExitCode {
    param([string]$Context)
    if ($LASTEXITCODE -ne 0) {
        Write-Err "$Context failed (exit code $LASTEXITCODE)"
        exit 1
    }
}

# Read-Host s znacheniem po umolchaniyu v [skobkah]
function Read-WithDefault {
    param(
        [string]$Prompt,
        [string]$Default = ''
    )
    $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $value = Read-Host "  $label"
    if ([string]::IsNullOrWhiteSpace($value)) { $Default } else { $value.Trim() }
}

# ============================================================
# Shag 1: Proverka OpenSSH
# ============================================================
Write-Step "Proverka okruzheniya"

foreach ($tool in @('ssh', 'scp')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Err "'$tool' ne naiden. Nuzhen OpenSSH Client."
        Write-Host ""
        Write-Host "  Ustanovka (PowerShell ot administratora):" -ForegroundColor Yellow
        Write-Host "  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Ili: Parametry -> Prilozeniya -> Dop. komponenty -> Klient OpenSSH" -ForegroundColor Yellow
        exit 1
    }
}

$sshPath = (Get-Command ssh).Source
Write-Info "OpenSSH Client: $sshPath"

# ============================================================
# Shag 2: Interaktivnyy vvod parametrov
# ============================================================
Write-Step "Parametry podklyucheniya k VPS"
Write-Host "  (Enter -- prinyat znachenie po umolchaniyu v [skobkah])" -ForegroundColor Gray
Write-Host ""

# Host -- obyazatelnyy parametr
do {
    $VpsHost = Read-WithDefault -Prompt "IP-adres ili domen VPS"
    if ([string]::IsNullOrWhiteSpace($VpsHost)) {
        Write-Warn "Host ne mozhet byt pustym."
    }
} while ([string]::IsNullOrWhiteSpace($VpsHost))

$VpsUser   = Read-WithDefault -Prompt "SSH-polzovatel"   -Default "root"
$VpsPort   = Read-WithDefault -Prompt "SSH-port"         -Default "22"
$RemoteDir = Read-WithDefault -Prompt "Direktoriya"      -Default "/opt/vps-ru-proxy"

# Put k SSH-klyuchu -- neobyazatelen
$IdentityRaw  = Read-WithDefault -Prompt "Put k SSH-klyuchu (Enter -- sistemnyy po umolchaniyu)"
$IdentityFile = if ([string]::IsNullOrWhiteSpace($IdentityRaw)) { $null } else { $IdentityRaw }

# Zapustit li setup.sh posle kopirovaniya
$runRaw   = Read-WithDefault -Prompt "Zapustit setup.sh posle kopirovaniya? [y/N]" -Default "N"
$RunSetup = ($runRaw -eq 'y') -or ($runRaw -eq 'Y')

# ============================================================
# Svodka pered vypolneniem
# ============================================================
Write-Host ""
Write-Host "  Host:        $VpsHost"   -ForegroundColor Blue
Write-Host "  Polzovatel:  $VpsUser"   -ForegroundColor Blue
Write-Host "  Port:        $VpsPort"   -ForegroundColor Blue
Write-Host "  Direktoriya: $RemoteDir" -ForegroundColor Blue
if ($IdentityFile) {
    Write-Host "  SSH-klyuch:  $IdentityFile" -ForegroundColor Blue
}
$runLabel = if ($RunSetup) { "da" } else { "net" }
$runColor = if ($RunSetup) { "Yellow" } else { "Gray" }
Write-Host "  Zapusk:      $runLabel" -ForegroundColor $runColor
Write-Host ""

$confirm = Read-Host "  Prodolzit? [Y/n]"
if (($confirm -eq 'n') -or ($confirm -eq 'N')) {
    Write-Warn "Otmeneno."
    exit 0
}

# ============================================================
# Shag 3: Proverka lokalnyh faylov
# ============================================================
Write-Step "Proverka lokalnyh faylov"
$missing = $false
foreach ($file in $FilesToCopy) {
    $path = Join-Path $ScriptDir $file
    if (Test-Path $path) {
        Write-Info "$file"
    } else {
        Write-Err "Fayl ne naiden: $path"
        $missing = $true
    }
}
if ($missing) { exit 1 }

# ============================================================
# Formirovanie massivov opciy SSH i SCP
# ============================================================
# PowerShell peredaet massiv @() vneshney komande kak otdelnye argumenty
$SshOpts = @(
    '-p', $VpsPort,
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'ConnectTimeout=10'
)
# SCP: port zadaetsya flagom -P (zaglavnaya), v otlichie ot ssh -p
$ScpOpts = @(
    '-P', $VpsPort,
    '-o', 'StrictHostKeyChecking=accept-new'
)
if ($IdentityFile) {
    $SshOpts += @('-i', $IdentityFile)
    $ScpOpts += @('-i', $IdentityFile)
}

$Remote = $VpsUser + '@' + $VpsHost

# ============================================================
# Shag 4: Proverka SSH-soedineniya
# ============================================================
Write-Step "Proverka SSH $Remote : $VpsPort"
Write-Warn "Pri pervom podklyuchenii SSH mozhet poprosit podtverdit fingerprint."
Write-Warn "Esli nuzhen parol -- vvedite ego v poyavivshemsia pole."
Write-Host ""

ssh @SshOpts $Remote "echo [remote] OK"
Assert-LastExitCode "SSH-proverka"
Write-Info "SSH-soedinenie uspeshno"

# ============================================================
# Shag 5: Sozdanie direktorii na VPS
# ============================================================
Write-Step "Sozdanie direktorii $RemoteDir na VPS"
ssh @SshOpts $Remote "mkdir -p '$RemoteDir'"
Assert-LastExitCode "mkdir"
Write-Info "Direktoriya gotova"

# ============================================================
# Shag 6: Kopirovanie faylov
# ============================================================
Write-Step "Kopirovanie faylov -> $Remote : $RemoteDir"
foreach ($file in $FilesToCopy) {
    $localPath  = Join-Path $ScriptDir $file
    $remotePath = $Remote + ':' + $RemoteDir + '/' + $file
    scp @ScpOpts $localPath $remotePath
    Assert-LastExitCode "Kopirovanie $file"
    Write-Info "$file"
}

# ============================================================
# Shag 7: Prava na setup.sh
# ============================================================
Write-Step "Prava na setup.sh"
$chmodCmd = "chmod +x '" + $RemoteDir + "/setup.sh'"
ssh @SshOpts $Remote $chmodCmd
Assert-LastExitCode "chmod +x"
Write-Info "chmod +x -- gotovo"

# ============================================================
# Shag 8: Zapusk ili instrukciya
# ============================================================
if ($RunSetup) {
    Write-Step "Zapusk setup.sh na VPS"
    Write-Warn "Skript interaktivnyy -- mozhet zadavat voprosy."
    Write-Host ""
    # -t vydelyaet psevdo-TTY: nuzhen dlya read vnutri setup.sh
    ssh @SshOpts -t $Remote ("bash '" + $RemoteDir + "/setup.sh'")
    Assert-LastExitCode "setup.sh"
} else {
    Write-Host ""
    Write-Host "  Faily uspeshno skorpirovany!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Dlya zapuska ustanovki na VPS vypolnite:" -ForegroundColor Gray
    Write-Host ""

    # Sobiraem SSH-komandu cherez konkatenatsiu (bez kavychek vnutri strok)
    $portPart = if ($VpsPort -ne '22') { ' -p ' + $VpsPort } else { '' }
    $keyPart  = if ($IdentityFile) { ' -i ' + $IdentityFile } else { '' }
    $bashCmd  = "bash '" + $RemoteDir + "/setup.sh'"
    $fullCmd  = 'ssh' + $portPart + $keyPart + ' ' + $Remote + ' "' + $bashCmd + '"'
    Write-Host "  $fullCmd" -ForegroundColor Yellow
    Write-Host ""
}
