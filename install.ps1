<#
.SYNOPSIS
  Universal 1-command CapCut PC Split-Tunnel VPN setup using WireSock.
.DESCRIPTION
  Auto-detects CapCut PC install directory and latest version folder across any drive,
  installs WireSock CLI via winget if missing, dynamically injects CapCut executables
  into AllowedApps (surviving CapCut updates), and creates a Desktop launcher that starts
  the tunnel for CapCut processes only and disconnects automatically when CapCut closes.
#>
[CmdletBinding()]
param(
  [string]$ConfigPath = "",
  [string]$CustomCapCutDir = ""
)

$ErrorActionPreference = "Continue"

function Resolve-CapCutRoot {
  param([string]$Override)
  if ($Override -and (Test-Path (Join-Path $Override "CapCut.exe"))) {
    return $Override
  }
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "CapCut\Apps"),
    (Join-Path $env:ProgramFiles "CapCut\Apps")
  )
  foreach ($drv in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 })) {
    $candidates += Join-Path "$($drv.Root)" "CapCut\Apps"
  }
  foreach ($c in ($candidates | Select-Object -Unique)) {
    if (Test-Path (Join-Path $c "CapCut.exe")) {
      return $c
    }
  }
  return $null
}

$ccRoot = Resolve-CapCutRoot -Override $CustomCapCutDir
if (-not $ccRoot) {
  Write-Warning "CapCut.exe not found automatically. Pass -CustomCapCutDir 'path\to\CapCut\Apps'."
  exit 1
}

Write-Output "Detected CapCut Apps Directory: $ccRoot"

$wsExe = @(
  "C:\Program Files\WireSock Secure Connect\sdk\wiresock-client.exe",
  "C:\Program Files\WireSock Secure Connect\bin\wiresock-client.exe",
  "C:\Program Files\WireSock VPN Client\bin\wiresock-client.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $wsExe) {
  Write-Output "Installing WireSock Secure Connect SDK via winget..."
  winget install --id NTKERNEL.WireSockVPNClientCLI --exact --source winget --accept-package-agreements --accept-source-agreements
  $wsExe = @(
    "C:\Program Files\WireSock Secure Connect\sdk\wiresock-client.exe",
    "C:\Program Files\WireSock Secure Connect\bin\wiresock-client.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

$workDir = Join-Path $env:ProgramData "CapCut_SplitTunnel_VPN"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$defaultConf = Join-Path $workDir "wireguard_source.conf"
if ($ConfigPath -and (Test-Path $ConfigPath)) {
  Copy-Item $ConfigPath $defaultConf -Force
}

$patcherPath = Join-Path $workDir "build_split_config.ps1"
$patcherCode = @"
param(
  [string]`$SourceConf = "$defaultConf",
  [string]`$CapCutRoot = "$ccRoot"
)
`$outConf = "$workDir\wireguard_capcut_only.conf"
if (-not (Test-Path `$SourceConf)) {
  Write-Error "Missing WireGuard .conf at `$SourceConf"
  exit 1
}

`$apps = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach (`$name in @("CapCut","VEHelper","CapCutService","ttdaemon","capcut-pc-editor","taskcontainer","bun","run_helper","push_detect","draft-converter")) {
  [void]`$apps.Add(`$name)
}

if (Test-Path `$CapCutRoot) {
  Get-ChildItem `$CapCutRoot -File -Filter "*.exe" -ErrorAction SilentlyContinue |
    Where-Object { `$_.BaseName -notmatch '^uninst' } |
    ForEach-Object { [void]`$apps.Add(`$_.BaseName) }

  `$latest = Get-ChildItem `$CapCutRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (`$latest) {
    Get-ChildItem `$latest.FullName -Recurse -File -Filter "*.exe" -ErrorAction SilentlyContinue |
      Where-Object { `$_.BaseName -notmatch '^uninst|crash|minidump|feedback' } |
      ForEach-Object { [void]`$apps.Add(`$_.BaseName) }
  }
}

`$allowed = (`$apps | Sort-Object) -join ", "
`$lines = (Get-Content `$SourceConf -Raw) -split "`r?`n" |
  Where-Object { `$_ -notmatch '^\s*(AllowedApps|DisallowedApps|MTU|PersistentKeepalive)\s*=' }

`$list = New-Object System.Collections.Generic.List[string]
`$setMtu = `$false
`$setApps = `$false

foreach (`$ln in `$lines) {
  `$list.Add(`$ln)
  if (`$ln -match '^\s*\[Interface\]\s*$' -and -not `$setMtu) {
    `$list.Add("MTU = 1420")
    `$setMtu = `$true
  } elseif (`$ln -match '^\s*\[Peer\]\s*$' -and -not `$setApps) {
    `$list.Add("AllowedApps = `$allowed")
    `$list.Add("PersistentKeepalive = 25")
    `$setApps = `$true
  }
}

[System.IO.File]::WriteAllLines(`$outConf, `$list, (New-Object System.Text.UTF8Encoding `$false))
"@
[System.IO.File]::WriteAllText($patcherPath, $patcherCode, (New-Object System.Text.UTF8Encoding $false))

$runnerPath = Join-Path $workDir "run_capcut_vpn.ps1"
$runnerCode = @"
`$ErrorActionPreference = "SilentlyContinue"
`$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not `$isAdmin) {
  Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"`$PSCommandPath`"" -Verb RunAs
  exit 0
}

Add-Type -AssemblyName PresentationFramework
`$srcConf = "$defaultConf"
`$actConf = "$workDir\wireguard_capcut_only.conf"

if (-not (Test-Path `$srcConf)) {
  [System.Windows.MessageBox]::Show("Place your WireGuard .conf file at:`n`$srcConf", "CapCut Split-Tunnel VPN")
  exit 1
}

& "$patcherPath" -SourceConf `$srcConf -CapCutRoot "$ccRoot"
`$ws = @(
  "C:\Program Files\WireSock Secure Connect\sdk\wiresock-client.exe",
  "C:\Program Files\WireSock Secure Connect\bin\wiresock-client.exe"
) | Where-Object { Test-Path `$_ } | Select-Object -First 1

if (-not `$ws) { exit 1 }

Stop-Process -Name "wiresock-client" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

`$proc = Start-Process -FilePath `$ws -ArgumentList "run -config `"`$actConf`" -log-level error" -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3

Start-Process -FilePath "$(Join-Path $ccRoot 'CapCut.exe')"
Start-Sleep -Seconds 10

while (Get-Process -Name "CapCut" -ErrorAction SilentlyContinue) {
  Start-Sleep -Seconds 3
}

if (`$proc -and -not `$proc.HasExited) {
  Stop-Process -Id `$proc.Id -Force -ErrorAction SilentlyContinue
}
Stop-Process -Name "wiresock-client" -Force -ErrorAction SilentlyContinue
"@
[System.IO.File]::WriteAllText($runnerPath, $runnerCode, (New-Object System.Text.UTF8Encoding $false))

$lnkPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "CapCut (Split-Tunnel VPN).lnk"
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnkPath)
$sc.TargetPath = "powershell.exe"
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerPath`""
$sc.IconLocation = "$(Join-Path $ccRoot 'CapCut.exe'),0"
$sc.Save()

Write-Output "Setup complete. Place your WireGuard .conf at: $defaultConf"
Write-Output "Desktop shortcut created: $lnkPath"
