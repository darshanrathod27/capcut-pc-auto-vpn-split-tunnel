Stop-Process -Name "wiresock-client" -Force -ErrorAction SilentlyContinue
$lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "CapCut (Split-Tunnel VPN).lnk"
if (Test-Path $lnk) {
  Remove-Item $lnk -Force -ErrorAction SilentlyContinue
}
Write-Output "Stopped WireSock process and removed Desktop split-tunnel shortcut."
