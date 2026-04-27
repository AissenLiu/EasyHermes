param(
  [string]$PythonVersion = "3.11.9",
  [switch]$Refresh,
  [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$PackagePythonDir = Join-Path $Root "packages\python"
$Wheelhouse = Join-Path $Root "packages\wheelhouse"
$RuntimeDir = Join-Path $Root "runtime"
$DistDir = Join-Path $Root "dist"
$ReqFile = Join-Path $Root "packaging\windows\requirements-windows.txt"
$PythonZip = Join-Path $PackagePythonDir "python-$PythonVersion-embed-amd64.zip"
$GetPip = Join-Path $PackagePythonDir "get-pip.py"
$PythonExe = Join-Path $RuntimeDir "python\python.exe"

function Write-Step([string]$Message) {
  Write-Host "[EazyHermes package] $Message"
}

New-Item -ItemType Directory -Force -Path $PackagePythonDir | Out-Null
New-Item -ItemType Directory -Force -Path $Wheelhouse | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

if ($Refresh -or -not (Test-Path $PythonZip)) {
  $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
  Write-Step "Downloading $url"
  Invoke-WebRequest -Uri $url -OutFile "$PythonZip.tmp"
  Move-Item -Force "$PythonZip.tmp" $PythonZip
}

if ($Refresh -or -not (Test-Path $GetPip)) {
  Write-Step "Downloading get-pip.py"
  Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "$GetPip.tmp"
  Move-Item -Force "$GetPip.tmp" $GetPip
}

Write-Step "Preparing embedded Python runtime"
& (Join-Path $ScriptDir "start-eazyhermes.ps1") -PrepareOnly -ForceInstall:$Refresh

Write-Step "Refreshing wheelhouse"
& $PythonExe -m pip download --dest $Wheelhouse --only-binary=:all: -r $ReqFile
if ($LASTEXITCODE -ne 0) {
  throw "pip download failed."
}

Write-Step "Installing runtime from refreshed wheelhouse"
& (Join-Path $ScriptDir "start-eazyhermes.ps1") -PrepareOnly -ForceInstall

if (-not $SkipZip) {
  $zipPath = Join-Path $DistDir "EazyHermes-windows-offline.zip"
  if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
  }

  Write-Step "Creating $zipPath"
  $items = Get-ChildItem -Path $Root -Force | Where-Object {
    $_.Name -notin @(".git", "dist", "data", "workspace", "__pycache__")
  }
  Compress-Archive -Path $items.FullName -DestinationPath $zipPath -Force
  Write-Step "Offline bundle ready: $zipPath"
}

