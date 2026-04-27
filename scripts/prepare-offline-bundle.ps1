param(
  [string]$PythonVersion = "3.11.9",
  [string]$DownloadPython = "",
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
$WebuiDir = Join-Path $Root "hermes-webui"

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

function Install-WebuiVendorAssets {
  $vendor = Join-Path $WebuiDir "static\vendor"

  $katexDir = Join-Path $vendor "katex"
  $katexCss = Join-Path $katexDir "katex.min.css"
  Save-Url "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css" $katexCss
  Save-Url "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js" (Join-Path $katexDir "katex.min.js")

  $css = Get-Content -Raw -Path $katexCss
  $fontMatches = [regex]::Matches($css, 'url\((fonts/[^)]+)\)')
  foreach ($match in $fontMatches) {
    $fontRel = $match.Groups[1].Value.Trim('"', "'")
    Save-Url "https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/$fontRel" (Join-Path $katexDir $fontRel)
  }

  $prismDir = Join-Path $vendor "prism"
  Save-Url "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/themes/prism-tomorrow.min.css" (Join-Path $prismDir "prism-tomorrow.min.css")
  Save-Url "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/themes/prism.min.css" (Join-Path $prismDir "prism.min.css")
  Save-Url "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-core.min.js" (Join-Path $prismDir "prism-core.min.js")
  Save-Url "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/plugins/autoloader/prism-autoloader.min.js" (Join-Path $prismDir "prism-autoloader.min.js")
  $prismComponents = @(
    "markup", "css", "clike", "javascript", "typescript", "python", "bash",
    "powershell", "json", "yaml", "markdown", "sql", "diff", "go", "java",
    "c", "cpp", "csharp", "rust", "toml", "docker", "ini"
  )
  foreach ($component in $prismComponents) {
    Save-Url "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-$component.min.js" (Join-Path $prismDir "components\prism-$component.min.js")
  }

  Save-Url "https://cdn.jsdelivr.net/npm/mermaid@10.9.3/dist/mermaid.min.js" (Join-Path $vendor "mermaid\mermaid.min.js")
}

New-Item -ItemType Directory -Force -Path $PackagePythonDir | Out-Null
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
  foreach ($path in @((Join-Path $RuntimeDir "python"), (Join-Path $RuntimeDir ".install-stamp"))) {
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

Install-WebuiVendorAssets

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
