# CapCut PC Auto-VPN Split-Tunnel (WireSock PowerShell)

Run only CapCut (and its helper/editor binaries) through a WireGuard VPN tunnel while keeping the rest of your PC (browsers, streaming, downloads) on your direct connection, with automatic disconnect when CapCut closes.

## One-Command Install (Run PowerShell as Administrator)

```powershell
irm https://raw.githubusercontent.com/darshanrathod27/capcut-pc-auto-vpn-split-tunnel/main/install.ps1 | iex
```

### Custom Paths & Config File

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/darshanrathod27/capcut-pc-auto-vpn-split-tunnel/main/install.ps1))) -ConfigPath "C:\path\to\your.conf" -CustomCapCutDir "D:\CapCut\Apps"
```

## How It Works

- **Auto-Detects CapCut & Latest Version**: Scans CapCut's install folder and newest version directory automatically so CapCut updates do not break split-tunneling.
- **Per-App Routing (AllowedApps)**: Uses WireSock (`wiresock-client.exe`) to route only CapCut processes through the tunnel (`MTU = 1420`, `PersistentKeepalive = 25`), leaving other apps on your normal network.
- **Auto-Start & Auto-Stop**: The CapCut (Split-Tunnel VPN) Desktop shortcut brings up the tunnel, launches CapCut, and stops `wiresock-client` when CapCut exits.

## Rollback

```powershell
irm https://raw.githubusercontent.com/darshanrathod27/capcut-pc-auto-vpn-split-tunnel/main/rollback.ps1 | iex
```

## Common User Issues & Fixes

- **Missing .conf popup**: Place a valid WireGuard `.conf` file in `%ProgramData%\CapCut_SplitTunnel_VPN\wireguard_source.conf` (never commit `.conf` files containing private keys to public repositories).
- **Some CapCut sub-processes bypass VPN**: Close CapCut completely so `build_split_config.ps1` refreshes the executable list from the latest version folder.
- **WireSock driver needs elevation**: Accept the UAC prompt when launching the shortcut so WireSock can bind the virtual adapter.

## License

MIT — see [LICENSE](LICENSE).
