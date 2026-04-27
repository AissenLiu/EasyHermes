param(
  [string]$PythonVersion = "3.11.9",
  [string]$NodeVersion = "20.11.1",
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
$NodeZip = Join-Path $PackageNodeDir "node-v$NodeVersion-win-x64.zip"
$GetPip = Join-Path $PackagePythonDir "get-pip.py"
$PythonExe = Join-Path $RuntimeDir "python\python.exe"
$NodeDir = Join-Path $RuntimeDir "node"
$NodeExe = Join-Path $NodeDir "node.exe"
$NpmCmd = Join-Path $NodeDir "npm.cmd"
$PyTag = ($PythonVersion -replace '^(\d+)\.(\d+).*$', '$1$2')
$AgentDir = Join-Path $Root "hermes-agent"
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

function Initialize-NodeRuntime {
  if (Test-Path $NodeExe) {
    return
  }

  $zip = Get-ChildItem -Path $PackageNodeDir -Filter "node-v*-win-x64.zip" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

  if ($null -eq $zip) {
    throw "Missing Windows Node.js zip in packages\node."
  }

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
  Expand-Archive -Path $zip.FullName -DestinationPath $tmp -Force
  $expanded = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
  if ($null -eq $expanded) {
    throw "Node.js zip did not contain an expected top-level directory."
  }
  Get-ChildItem -Path $expanded.FullName -Force | Move-Item -Destination $NodeDir
  Remove-Item $tmp -Recurse -Force
}

function Invoke-NpmCi([string]$Directory, [string]$Label) {
  $packageJson = Join-Path $Directory "package.json"
  if (-not (Test-Path $packageJson)) {
    return
  }

  $nodeModules = Join-Path $Directory "node_modules"
  if ((Test-Path $nodeModules) -and (-not $Refresh)) {
    return
  }

  Write-Step "Installing Node dependencies for $Label"
  Push-Location $Directory
  $oldPlaywright = $env:PLAYWRIGHT_BROWSERS_PATH
  try {
    $env:PLAYWRIGHT_BROWSERS_PATH = "0"
    & $NpmCmd ci --omit=dev --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
      throw "npm ci failed for $Label."
    }
  } finally {
    $env:PLAYWRIGHT_BROWSERS_PATH = $oldPlaywright
    Pop-Location
  }
}

function Install-AgentBrowserRuntime {
  $agentBrowser = Join-Path $AgentDir "node_modules\.bin\agent-browser.cmd"
  if (-not (Test-Path $agentBrowser)) {
    throw "agent-browser was not installed into hermes-agent\node_modules."
  }

  Write-Step "Installing agent-browser browser runtime"
  Push-Location $AgentDir
  $oldPlaywright = $env:PLAYWRIGHT_BROWSERS_PATH
  try {
    $env:PLAYWRIGHT_BROWSERS_PATH = "0"
    & $agentBrowser install
    if ($LASTEXITCODE -ne 0) {
      throw "agent-browser install failed."
    }
  } finally {
    $env:PLAYWRIGHT_BROWSERS_PATH = $oldPlaywright
    Pop-Location
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
New-Item -ItemType Directory -Force -Path $PackageNodeDir | Out-Null
New-Item -ItemType Directory -Force -Path $Wheelhouse | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

if ($Refresh -or -not (Test-Path $PythonZip)) {
  $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
  Write-Step "Downloading $url"
  Invoke-WebRequest -Uri $url -OutFile "$PythonZip.tmp"
  Move-Item -Force "$PythonZip.tmp" $PythonZip
}

if ($Refresh -or -not (Test-Path $NodeZip)) {
  $url = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip"
  Save-Url $url $NodeZip
}

if ($Refresh -or -not (Test-Path $GetPip)) {
  Save-Url "https://bootstrap.pypa.io/get-pip.py" $GetPip
}

if ($Refresh) {
  foreach ($path in @((Join-Path $RuntimeDir "python"), $NodeDir, (Join-Path $RuntimeDir ".install-stamp"))) {
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
    throw "No Python available for downloading wheels. Install Python or pass -DownloadPython."
  }

  Write-Step "Refreshing Windows wheelhouse with $DownloadPython"
  # GitHub runs this on Windows with the same Python version as the embedded
  # runtime, so pip resolves Windows wheels directly. A few DingTalk SDK helper
  # packages are pure-Python sdists without wheels, so allow those packages only.
  & $DownloadPython -m pip download `
    --dest $Wheelhouse `
    --only-binary=:all: `
    --no-binary alibabacloud-endpoint-util,alibabacloud-gateway-dingtalk,alibabacloud-gateway-spi `
    -r $ReqFile
  if ($LASTEXITCODE -ne 0) {
    throw "pip download failed."
  }
}

Initialize-NodeRuntime
Invoke-NpmCi $AgentDir "hermes-agent browser tools"
Install-AgentBrowserRuntime
Invoke-NpmCi (Join-Path $AgentDir "scripts\whatsapp-bridge") "WhatsApp bridge"
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
