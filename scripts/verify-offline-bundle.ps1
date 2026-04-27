param(
  [string]$ZipPath = "dist\EazyHermes-windows-offline.zip",
  [switch]$RunPrepareOnly
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[EazyHermes verify] $Message"
}

function Assert-PathExists([string]$Path, [string]$Message) {
  if (-not (Test-Path $Path)) {
    throw $Message
  }
}

function Assert-GlobExists([string]$Pattern, [string]$Message) {
  $matches = Get-ChildItem -Path $Pattern -ErrorAction SilentlyContinue
  if ($null -eq $matches -or $matches.Count -eq 0) {
    throw $Message
  }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$ResolvedZip = if ([System.IO.Path]::IsPathRooted($ZipPath)) { $ZipPath } else { Join-Path $Root $ZipPath }

Assert-PathExists $ResolvedZip "Missing offline bundle zip: $ResolvedZip"

$ExtractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("eazyhermes-offline-verify-{0}" -f ([System.Guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Force -Path $ExtractRoot | Out-Null

try {
  Write-Step "Extracting $ResolvedZip"
  Expand-Archive -Path $ResolvedZip -DestinationPath $ExtractRoot -Force

  $BundleRoot = $ExtractRoot
  $requiredPaths = @(
    "start.bat",
    "scripts\start-eazyhermes.ps1",
    "scripts\prepare-offline-bundle.ps1",
    "runtime\python\python.exe",
    "runtime\node\node.exe",
    "packages\python\get-pip.py",
    "packaging\windows\requirements-windows.txt",
    "hermes-agent\pyproject.toml",
    "hermes-webui\package.json",
    "hermes-webui\dist\client\index.html",
    "hermes-webui\dist\server\index.js",
    "hermes-webui\node_modules\socket.io\package.json",
    "hermes-webui\node_modules\node-pty\package.json"
  )

  foreach ($relative in $requiredPaths) {
    Assert-PathExists (Join-Path $BundleRoot $relative) "Offline bundle is missing $relative"
  }

  Assert-GlobExists (Join-Path $BundleRoot "packages\python\python-*-embed-amd64.zip") "Offline bundle is missing Windows embeddable Python zip."
  Assert-GlobExists (Join-Path $BundleRoot "packages\node\node-v*-win-x64.zip") "Offline bundle is missing Windows portable Node.js zip."
  Assert-GlobExists (Join-Path $BundleRoot "packages\wheelhouse\*.whl") "Offline bundle is missing Python wheelhouse files."

  if ($RunPrepareOnly) {
    Write-Step "Running extracted startup self-check"
    $startScript = Join-Path $BundleRoot "scripts\start-eazyhermes.ps1"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startScript -PrepareOnly
    if ($LASTEXITCODE -ne 0) {
      throw "Extracted offline bundle startup self-check failed."
    }
  }

  Write-Step "Offline bundle verification passed."
} finally {
  if (Test-Path $ExtractRoot) {
    Remove-Item $ExtractRoot -Recurse -Force
  }
}
