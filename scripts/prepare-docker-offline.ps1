param(
  [string]$ImageName = "eazyhermes:local",
  [string]$OutputName = "eazyhermes-amd64.tar",
  [switch]$NoBuild,
  [switch]$Compress
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$Dockerfile = Join-Path $Root "deploy\docker\Dockerfile.eazyhermes"
$OutputDir = Join-Path $Root "offline\images"
$OutputPath = Join-Path $OutputDir $OutputName
if ($Compress -and -not $OutputPath.EndsWith(".gz")) {
  $CompressedOutputPath = "$OutputPath.gz"
} else {
  $CompressedOutputPath = $OutputPath
}

function Write-Step([string]$Message) {
  Write-Host "[EazyHermes Docker package] $Message"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker is not installed or not in PATH."
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
  throw "Docker daemon is not running."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (-not $NoBuild) {
  Write-Step "Building $ImageName"
  docker build -f $Dockerfile -t $ImageName $Root
  if ($LASTEXITCODE -ne 0) {
    throw "docker build failed."
  }
}

Write-Step "Saving image to $OutputPath"
docker save $ImageName -o $OutputPath
if ($LASTEXITCODE -ne 0) {
  throw "docker save failed."
}

if ($Compress) {
  if (Test-Path $CompressedOutputPath) {
    Remove-Item $CompressedOutputPath -Force
  }
  Write-Step "Compressing image to $CompressedOutputPath"
  if (Get-Command gzip -ErrorAction SilentlyContinue) {
    gzip -9 -f $OutputPath
  } else {
    throw "gzip is required when -Compress is set."
  }
  Write-Step "Offline Docker image ready: $CompressedOutputPath"
} else {
  Write-Step "Offline Docker image ready: $OutputPath"
}
