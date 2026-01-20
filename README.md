# DNSTT Smart Optimizer v2

A bash script to optimize and configure your DNSTT server for better performance and stability.

> **✅ Idempotent**: Safe to run multiple times - it will overwrite previous settings without errors.

## Features

- 🔍 **Smart Detection**: Automatically detects your DNSTT service and SSH service
- 🚫 **IPv6 Disabling**: Disables IPv6 to prevent leaks and improve compatibility
- 📡 **UDP Tuning**: Optimizes system buffers for limited/bad connections
- 💾 **Swap Creation**: Creates a 1GB swap file to prevent OOM crashes
- 🔌 **Port Standardization**: Ensures DNSTT listens on port `5300` (preserves your keys/domain)
- 🔐 **SSH Tuning**: Sets `MaxSessions 30` for better SSH tunneling
- ⏰ **Auto-Restart**: Cron job restarts service every 2 hours

## Quick Install

### One-liner (recommended)
```bash
curl -sL https://raw.githubusercontent.com/Recoba86/Dnstt-optimizer/main/optimize-dnstt.sh | sudo bash
```

### Download and Run
```bash
wget -O optimize-dnstt.sh https://raw.githubusercontent.com/Recoba86/Dnstt-optimizer/main/optimize-dnstt.sh
chmod +x optimize-dnstt.sh
sudo ./optimize-dnstt.sh
```

## Re-running on Servers

Already ran the script before? **No problem!** Just run it again:

```bash
curl -sL https://raw.githubusercontent.com/Recoba86/Dnstt-optimizer/main/optimize-dnstt.sh | sudo bash
```

The script will:
- Remove old settings from `/etc/sysctl.conf`
- Apply fresh optimized settings
- Update DNSTT service configuration
- Refresh cron jobs

## What Gets Changed

| Setting | Value | Purpose |
|---------|-------|---------|
| `rmem_max` / `wmem_max` | 4MB | Optimized for limited connections |
| `rmem_default` / `wmem_default` | 1MB | Default socket buffer size |
| `udp_mem` | 32768/65536/131072 | UDP memory limits |
| `netdev_max_backlog` | 5000 | Prevents packet drops |
| `MaxSessions` | 30 | SSH tunnel sessions |
| DNSTT UDP bind | `0.0.0.0:5300` | IPv4-only binding |

## Requirements

- Linux server (Ubuntu/Debian recommended)
- Root privileges (`sudo`)
- Existing DNSTT installation

## Verification

After running, check the "SUMMARY" section in the output:
```
------------------------------
SUMMARY
DNSTT ExecStart : /path/to/dnstt-server -udp 0.0.0.0:5300 ...
SSH users       : 2
SSH connections : 5
DNSTT threads   : 4
------------------------------
```

## Contributing

Feel free to open issues or submit pull requests!

## License

MIT
