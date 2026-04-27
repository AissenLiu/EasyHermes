param(
  [string]$PythonVersion = "3.11.9",
  [string]$NodeVersion = "",
  [string]$DownloadPython = "",
  [switch]$Refresh,
  [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$PackagePythonDir = Join-Path $Root "packages\python"
$PackageNodeDir = Join-Path $Root "packages\node"
$Wheelhouse = Join-Path $Root "packages\wheelhouse"
$RuntimeDir = Join-Path $Root "runtime"
$DistDir = Join-Path $Root "dist"
$ReqFile = Join-Path $Root "packaging\windows\requirements-windows.txt"
$PythonZip = Join-Path $PackagePythonDir "python-$PythonVersion-embed-amd64.zip"
$GetPip = Join-Path $PackagePythonDir "get-pip.py"
$WebuiDir = Join-Path $Root "hermes-webui"
$NodeDir = Join-Path $RuntimeDir "node"
$NodeExe = Join-Path $NodeDir "node.exe"
$NpmCmd = Join-Path $NodeDir "npm.cmd"

function Write-Step([string]$Message) {
  Write-Host "[EazyHermes package] $Message"
}

function Save-Url([string]$Url, [string]$OutFile) {
  if ($Refresh -or -not (Test-Path $OutFile)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    Write-Step "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile "$OutFile.tmp"
    Move-Item -Force "$OutFile.tmp" $OutFile
  }
}

function Resolve-NodeVersion {
  if ($script:NodeVersion) {
    return
  }

  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "No Node.js available to resolve a Windows portable Node version. Install Node 24+ or pass -NodeVersion."
  }

  $script:NodeVersion = (& $cmd.Source -p "process.versions.node").Trim()
  if (-not $script:NodeVersion) {
    throw "Could not resolve Node.js version."
  }
}

function Initialize-NodeRuntime {
  Resolve-NodeVersion

  if (Test-Path $NodeExe) {
    return
  }

  $nodeZip = Join-Path $PackageNodeDir "node-v$script:NodeVersion-win-x64.zip"
  $url = "https://nodejs.org/dist/v$script:NodeVersion/node-v$script:NodeVersion-win-x64.zip"
  Save-Url $url $nodeZip

  Write-Step "Extracting Node.js runtime..."
  $tmp = Join-Path $RuntimeDir "node-extract"
  if (Test-Path $tmp) {
    Remove-Item $tmp -Recurse -Force
  }
  if (Test-Path $NodeDir) {
    Remove-Item $NodeDir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  New-Item -ItemType Directory -Force -Path $NodeDir | Out-Null
  Expand-Archive -Path $nodeZip -DestinationPath $tmp -Force
  $expanded = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
  if ($null -eq $expanded) {
    throw "Node.js zip did not contain an expected top-level directory."
  }
  Get-ChildItem -Path $expanded.FullName -Force | Move-Item -Destination $NodeDir
  Remove-Item $tmp -Recurse -Force
}

function Build-Webui {
  if (-not (Test-Path $NpmCmd)) {
    throw "Missing npm.cmd in embedded Node runtime."
  }

  Push-Location $WebuiDir
  $oldPath = $env:PATH
  try {
    $env:PATH = "$NodeDir;$env:PATH"
    Write-Step "Installing hermes-web-ui npm dependencies"
    & $NpmCmd install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
      throw "npm install failed."
    }

    Write-Step "Building hermes-web-ui"
    & $NpmCmd run build
    if ($LASTEXITCODE -ne 0) {
      throw "npm run build failed."
    }

    Write-Step "Pruning hermes-web-ui dev dependencies"
    & $NpmCmd prune --omit=dev --ignore-scripts --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
      throw "npm prune failed."
    }
  } finally {
    $env:PATH = $oldPath
    Pop-Location
  }
}

New-Item -ItemType Directory -Force -Path $PackagePythonDir | Out-Null
New-Item -ItemType Directory -Force -Path $PackageNodeDir | Out-Null
New-Item -ItemType Directory -Force -Path $Wheelhouse | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

if ($Refresh -or -not (Test-Path $PythonZip)) {
  $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
  Save-Url $url $PythonZip
}

if ($Refresh -or -not (Test-Path $GetPip)) {
  Save-Url "https://bootstrap.pypa.io/get-pip.py" $GetPip
}

if ($Refresh) {
  foreach ($path in @(
    (Join-Path $RuntimeDir "python"),
    (Join-Path $RuntimeDir "node"),
    (Join-Path $RuntimeDir "node-extract"),
    (Join-Path $RuntimeDir ".install-stamp"),
    (Join-Path $WebuiDir "dist"),
    (Join-Path $WebuiDir "node_modules")
  )) {
    if (Test-Path $path) {
      Remove-Item $path -Recurse -Force
    }
  }
  Get-ChildItem -Path $Wheelhouse -Filter "*.whl" -ErrorAction SilentlyContinue | Remove-Item -Force
}

$hasWheels = (Get-ChildItem -Path $Wheelhouse -Filter "*.whl" -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null
if ($Refresh -or -not $hasWheels) {
  if (-not $DownloadPython) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) {
      $DownloadPython = $cmd.Source
    }
  }
  if (-not $DownloadPython) {
    throw "No Python available for downloading wheels. Install Python $PythonVersion or pass -DownloadPython."
  }

  Write-Step "Refreshing slim Windows wheelhouse with $DownloadPython"
  & $DownloadPython -m pip download `
    --dest $Wheelhouse `
    --only-binary=:all: `
    -r $ReqFile
  if ($LASTEXITCODE -ne 0) {
    throw "pip download failed."
  }
}

Initialize-NodeRuntime
Build-Webui

Write-Step "Preparing embedded Python runtime"
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
