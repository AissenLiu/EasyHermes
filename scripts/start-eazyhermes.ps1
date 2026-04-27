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
$PythonScriptsDir = Join-Path $PythonDir "Scripts"
$PythonExe = Join-Path $PythonDir "python.exe"
$NodeDir = Join-Path $RuntimeDir "node"
$NodeExe = Join-Path $NodeDir "node.exe"
$PackagePythonDir = Join-Path $Root "packages\python"
$PackageNodeDir = Join-Path $Root "packages\node"
$Wheelhouse = Join-Path $Root "packages\wheelhouse"
$ReqFile = Join-Path $Root "packaging\windows\requirements-windows.txt"
$InstallStamp = Join-Path $RuntimeDir ".install-stamp"
$HermesBin = ""

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
  $requiredPaths = @(".", "..\..\hermes-agent")
  $seen = @{}
  $next = @()

  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "import site" -or $trimmed -eq "#import site") {
      continue
    }
    if ($requiredPaths -contains $trimmed) {
      $seen[$trimmed] = $true
    }
    $next += $line
  }

  foreach ($path in $requiredPaths) {
    if (-not $seen.ContainsKey($path)) {
      $next += $path
    }
  }
  $next += "import site"

  Set-Content -Path $pth.FullName -Value $next -Encoding ASCII
}

function Initialize-PythonRuntime {
  if (Test-Path $PythonExe) {
    Enable-EmbeddedPythonSite
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
    throw "Missing Windows Node.js zip in packages\node. Run scripts\prepare-offline-bundle.ps1 first."
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

function Test-PythonRuntimeDependencies {
  & $PythonExe -c "import run_agent, aiohttp" 2>$null
  return $LASTEXITCODE -eq 0
}

function Install-DependenciesOffline {
  if ((Test-Path $InstallStamp) -and (-not $ForceInstall)) {
    if (Test-PythonRuntimeDependencies) {
      return
    }

    Write-Step "Existing runtime is missing required Python modules, reinstalling dependencies..."
  }

  Assert-PathExists $Wheelhouse "Missing packages\wheelhouse. Run scripts\prepare-offline-bundle.ps1 first."
  Assert-PathExists $ReqFile "Missing packaging\windows\requirements-windows.txt."

  Write-Step "Installing Python dependencies from local wheelhouse..."
  & $PythonExe -m pip install --no-index --find-links $Wheelhouse --no-build-isolation -r $ReqFile
  if ($LASTEXITCODE -ne 0) {
    throw "Dependency install failed."
  }

  Write-Step "Installing vendored hermes-agent..."
  $agentSpec = "${AgentDir}[cli,cron,pty]"
  & $PythonExe -m pip install --no-index --find-links $Wheelhouse --no-build-isolation $agentSpec
  if ($LASTEXITCODE -ne 0) {
    throw "Hermes package install failed."
  }

  New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
  Set-Content -Path $InstallStamp -Value (Get-Date -Format o) -Encoding ASCII
}

function Resolve-HermesBin {
  $candidates = @(
    (Join-Path $PythonScriptsDir "hermes.exe"),
    (Join-Path $PythonScriptsDir "hermes.cmd"),
    (Join-Path $PythonScriptsDir "hermes")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      $script:HermesBin = $candidate
      return
    }
  }

  throw "Missing Hermes CLI executable in runtime\python\Scripts."
}

function Set-RuntimeEnvironment {
  $dataDir = Join-Path $Root "data"
  $hermesHome = Join-Path $dataDir ".hermes"
  $webuiData = Join-Path $dataDir "webui"

  $env:PYTHONUTF8 = "1"
  $env:PYTHONPATH = (@($AgentDir, $env:PYTHONPATH) | Where-Object { $_ }) -join ";"
  $env:PATH = (@($NodeDir, $PythonDir, $PythonScriptsDir, $env:PATH) | Where-Object { $_ }) -join ";"
  $env:USERPROFILE = $dataDir
  $env:HOME = $dataDir
  $env:HERMES_HOME = $hermesHome
  $env:HERMES_BASE_HOME = $hermesHome
  $env:HERMES_BIN = $script:HermesBin
  $env:HOST = $HostName
  $env:PORT = [string]$Port
  $env:UPSTREAM = "http://127.0.0.1:8642"
  $env:UPLOAD_DIR = Join-Path $webuiData "upload"
  $env:HERMES_WEBUI_DATA_DIR = $webuiData
  $env:AUTH_DISABLED = "1"
}

function Test-EmbeddedRuntime {
  if (-not (Test-PythonRuntimeDependencies)) {
    throw "Embedded Python import check failed (run_agent/aiohttp). The offline package may be incomplete."
  }

  $serverEntry = Join-Path $WebuiDir "dist\server\index.js"
  Assert-PathExists $serverEntry "Missing hermes-web-ui build output. Run scripts\prepare-offline-bundle.ps1 first."
  Assert-PathExists (Join-Path $WebuiDir "node_modules") "Missing hermes-web-ui node_modules. Run scripts\prepare-offline-bundle.ps1 first."

  $packageJson = Join-Path $WebuiDir "package.json"
  & $NodeExe -e "const {createRequire}=require('module'); const req=createRequire(process.argv[1]); req.resolve('socket.io'); req.resolve('node-pty');" $packageJson
  if ($LASTEXITCODE -ne 0) {
    throw "Embedded Node dependency check failed. The offline package may be incomplete."
  }
}

function Wait-Health([string]$Url, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
      if ($resp.StatusCode -eq 200) {
        return $true
      }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  return $false
}

function Wait-EazyHermesReady([string]$Url, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $resp = Invoke-RestMethod -Uri $Url -TimeoutSec 3
      if ($null -ne $resp -and $resp.status -eq "ok" -and $resp.gateway -eq "running") {
        return $true
      }
    } catch {
      Start-Sleep -Milliseconds 500
      continue
    }

    Start-Sleep -Milliseconds 500
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
Install-PipOffline
Install-DependenciesOffline
Resolve-HermesBin
Set-RuntimeEnvironment
Test-EmbeddedRuntime

if ($PrepareOnly) {
  Write-Step "Runtime is ready."
  exit 0
}

$url = "http://127.0.0.1:$Port"
$serverEntry = Join-Path $WebuiDir "dist\server\index.js"
Write-Step "Starting WebUI at $url ..."

$proc = $null
try {
  $proc = Start-Process -FilePath $NodeExe -ArgumentList @($serverEntry) -WorkingDirectory $WebuiDir -NoNewWindow -PassThru
  $health = "http://$HostName`:$Port/health"
  if (Wait-EazyHermesReady -Url $health -TimeoutSeconds 90) {
    Write-Step "WebUI is ready: $url"
    if (-not $NoBrowser) {
      Start-Process $url | Out-Null
    }
  } else {
    $healthDetails = $null
    try {
      $healthDetails = Invoke-RestMethod -Uri $health -TimeoutSec 3
    } catch { }

    if ($null -ne $healthDetails -and $healthDetails.gateway -ne "running") {
      throw "WebUI started, but Hermes gateway is not healthy. Check data\.hermes\logs\gateway.log and data\.hermes\logs\errors.log for details."
    }

    Write-Warning "EazyHermes did not report fully healthy within 90 seconds. It may still be starting."
    $proc.Refresh()
    if ($proc.HasExited) {
      throw "WebUI process exited early with code $($proc.ExitCode). See the logs above for details."
    }
  }

  Write-Step "Press Ctrl+C to stop EazyHermes."
  if (-not $proc.HasExited) {
    Wait-Process -Id $proc.Id -ErrorAction SilentlyContinue
  }
} finally {
  if ($null -ne $proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
}
