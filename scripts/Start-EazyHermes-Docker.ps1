param(
  [int]$Port = 8787,
  [switch]$NoBrowser,
  [switch]$BuildIfMissing
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$ComposeFile = Join-Path $Root "deploy\docker\compose.yml"
$ImageTar = Join-Path $Root "offline\images\eazyhermes-amd64.tar"
$ImageName = "eazyhermes:local"

function Write-Step([string]$Message) {
  Write-Host "[EazyHermes Docker] $Message"
}

function Wait-Health([string]$Url, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
      if ($resp.StatusCode -eq 200 -and $resp.Content -match '"status"\s*:\s*"ok"') {
        return $true
      }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  return $false
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker is not installed or not in PATH. Install Docker Desktop, then run start-docker.bat again."
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
  throw "Docker is installed but the daemon is not running. Start Docker Desktop first."
}

New-Item -ItemType Directory -Force -Path (Join-Path $Root "data") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "workspace") | Out-Null

$imageId = docker image ls $ImageName -q
if (-not $imageId) {
  if (Test-Path $ImageTar) {
    Write-Step "Loading offline image from $ImageTar"
    docker load -i $ImageTar
    if ($LASTEXITCODE -ne 0) {
      throw "docker load failed."
    }
  } elseif ($BuildIfMissing) {
    Write-Step "Offline image tar not found; building image locally."
    docker build -f (Join-Path $Root "deploy\docker\Dockerfile.eazyhermes") -t $ImageName $Root
    if ($LASTEXITCODE -ne 0) {
      throw "docker build failed."
    }
  } else {
    throw "Missing Docker image $ImageName and offline image tar. Run scripts\prepare-docker-offline.ps1 on an internet-connected machine first."
  }
}

$env:EAZYHERMES_WEBUI_PORT = [string]$Port
Write-Step "Starting container"
docker compose -f $ComposeFile up -d
if ($LASTEXITCODE -ne 0) {
  throw "docker compose up failed."
}

$url = "http://127.0.0.1:$Port"
if (Wait-Health -Url "$url/health" -TimeoutSeconds 60) {
  Write-Step "WebUI is ready: $url"
  if (-not $NoBrowser) {
    Start-Process $url | Out-Null
  }
} else {
  Write-Warning "WebUI did not report healthy within 60 seconds. Check logs with: docker compose -f deploy\docker\compose.yml logs --tail=100"
}

Write-Step "Use 'docker compose -f deploy\docker\compose.yml logs -f' to watch logs."

