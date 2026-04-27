param(
  [string]$HostName = "127.0.0.1",
  [int]$Port = 8787,
  [switch]$NoBrowser,
  [switch]$PrepareOnly,
  [switch]$ForceInstall
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$AgentDir = Join-Path $Root "hermes-agent"
$WebuiDir = Join-Path $Root "hermes-webui"
$RuntimeDir = Join-Path $Root "runtime"
$PythonDir = Join-Path $RuntimeDir "python"
$PythonExe = Join-Path $PythonDir "python.exe"
$NodeDir = Join-Path $RuntimeDir "node"
$NodeExe = Join-Path $NodeDir "node.exe"
$PackagePythonDir = Join-Path $Root "packages\python"
$PackageNodeDir = Join-Path $Root "packages\node"
$Wheelhouse = Join-Path $Root "packages\wheelhouse"
$ReqFile = Join-Path $Root "packaging\windows\requirements-windows.txt"
$InstallStamp = Join-Path $RuntimeDir ".install-stamp"

function Write-Step([string]$Message) {
  Write-Host "[EazyHermes] $Message"
}

function Assert-PathExists([string]$Path, [string]$Message) {
  if (-not (Test-Path $Path)) {
    throw $Message
  }
}

function Enable-EmbeddedPythonSite {
  $pth = Get-ChildItem -Path $PythonDir -Filter "python*._pth" | Select-Object -First 1
  if ($null -eq $pth) {
    return
  }

  $lines = Get-Content -Path $pth.FullName
  $hasImportSite = $false
  $next = foreach ($line in $lines) {
    if ($line.Trim() -eq "import site") {
      $hasImportSite = $true
      $line
    } elseif ($line.Trim() -eq "#import site") {
      $hasImportSite = $true
      "import site"
    } else {
      $line
    }
  }
  if (-not $hasImportSite) {
    $next += "import site"
  }
  Set-Content -Path $pth.FullName -Value $next -Encoding ASCII
}

function Initialize-PythonRuntime {
  if (Test-Path $PythonExe) {
    return
  }

  $zip = Get-ChildItem -Path $PackagePythonDir -Filter "python-*-embed-amd64.zip" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

  if ($null -eq $zip) {
    throw "Missing Windows embeddable Python zip in packages\python. Run scripts\prepare-offline-bundle.ps1 on an internet-connected Windows machine first."
  }

  Write-Step "Extracting Python runtime..."
  New-Item -ItemType Directory -Force -Path $PythonDir | Out-Null
  Expand-Archive -Path $zip.FullName -DestinationPath $PythonDir -Force
  Enable-EmbeddedPythonSite
}

function Initialize-NodeRuntime {
  if (Test-Path $NodeExe) {
    return
  }

  $zip = Get-ChildItem -Path $PackageNodeDir -Filter "node-v*-win-x64.zip" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

  if ($null -eq $zip) {
    throw "Missing Windows Node.js zip in packages\node. Run scripts\prepare-offline-bundle.ps1 on an internet-connected Windows machine first."
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

function Add-BundledToolsToPath {
  $paths = @(
    $NodeDir,
    (Join-Path $AgentDir "node_modules\.bin"),
    (Join-Path $AgentDir "scripts\whatsapp-bridge\node_modules\.bin")
  )
  $existing = $env:PATH -split ';'
  $pathsToAdd = @($paths)
  [array]::Reverse($pathsToAdd)
  foreach ($path in $pathsToAdd) {
    if ((Test-Path $path) -and ($existing -notcontains $path)) {
      $env:PATH = "$path;$env:PATH"
    }
  }
  if (Test-Path $NodeExe) {
    $env:HERMES_NODE = $NodeExe
  }
  if (-not $env:PLAYWRIGHT_BROWSERS_PATH) {
    $env:PLAYWRIGHT_BROWSERS_PATH = "0"
  }
}

function Install-PipOffline {
  $pipCheck = & $PythonExe -c "import pip" 2>$null
  if ($LASTEXITCODE -eq 0) {
    return
  }

  $getPip = Join-Path $PackagePythonDir "get-pip.py"
  Assert-PathExists $getPip "Missing packages\python\get-pip.py. Run scripts\prepare-offline-bundle.ps1 first."
  Assert-PathExists $Wheelhouse "Missing packages\wheelhouse. Run scripts\prepare-offline-bundle.ps1 first."

  Write-Step "Installing pip from local wheelhouse..."
  & $PythonExe $getPip --no-index --find-links $Wheelhouse pip setuptools wheel
  if ($LASTEXITCODE -ne 0) {
    throw "pip bootstrap failed."
  }
}

function Install-DependenciesOffline {
  if ((Test-Path $InstallStamp) -and (-not $ForceInstall)) {
    return
  }

  Assert-PathExists $Wheelhouse "Missing packages\wheelhouse. Run scripts\prepare-offline-bundle.ps1 first."
  Assert-PathExists $ReqFile "Missing packaging\windows\requirements-windows.txt."

  Write-Step "Installing Python dependencies from local wheelhouse..."
  & $PythonExe -m pip install --no-index --find-links $Wheelhouse --no-build-isolation -r $ReqFile
  if ($LASTEXITCODE -ne 0) {
    throw "Dependency install failed."
  }

  Write-Step "Installing vendored hermes-agent and hermes-webui dependencies..."
  $agentSpec = "${AgentDir}[all]"
  $webuiReq = Join-Path $WebuiDir "requirements.txt"
  & $PythonExe -m pip install --no-index --find-links $Wheelhouse --no-build-isolation $agentSpec -r $webuiReq
  if ($LASTEXITCODE -ne 0) {
    throw "Hermes package install failed."
  }

  New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
  Set-Content -Path $InstallStamp -Value (Get-Date -Format o) -Encoding ASCII
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

Assert-PathExists $AgentDir "Missing hermes-agent directory."
Assert-PathExists $WebuiDir "Missing hermes-webui directory."

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "data\.hermes") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "data\webui") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "workspace") | Out-Null

Initialize-PythonRuntime
Initialize-NodeRuntime
Add-BundledToolsToPath
Install-PipOffline
Install-DependenciesOffline

if ($PrepareOnly) {
  Write-Step "Runtime is ready."
  exit 0
}

$env:PYTHONUTF8 = "1"
$env:HERMES_HOME = Join-Path $Root "data\.hermes"
$env:HERMES_BASE_HOME = $env:HERMES_HOME
$env:HERMES_WEBUI_AGENT_DIR = $AgentDir
$env:HERMES_WEBUI_PYTHON = $PythonExe
$env:HERMES_WEBUI_STATE_DIR = Join-Path $Root "data\webui"
$env:HERMES_WEBUI_DEFAULT_WORKSPACE = Join-Path $Root "workspace"
$env:HERMES_WEBUI_HOST = $HostName
$env:HERMES_WEBUI_PORT = [string]$Port
$env:HERMES_WEBUI_AUTO_INSTALL = "0"

$url = "http://127.0.0.1:$Port"
Write-Step "Starting WebUI at $url ..."

$proc = $null
try {
  $proc = Start-Process -FilePath $PythonExe -ArgumentList @((Join-Path $WebuiDir "server.py")) -WorkingDirectory $WebuiDir -NoNewWindow -PassThru
  $health = "http://$HostName`:$Port/health"
  if (Wait-Health -Url $health -TimeoutSeconds 35) {
    Write-Step "WebUI is ready: $url"
    if (-not $NoBrowser) {
      Start-Process $url | Out-Null
    }
  } else {
    Write-Warning "WebUI did not report healthy within 35 seconds. It may still be starting."
  }

  Write-Step "Press Ctrl+C to stop EazyHermes."
  Wait-Process -Id $proc.Id
} finally {
  if ($null -ne $proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
}
