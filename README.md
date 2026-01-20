# DNSTT Smart Optimizer

A safe, idempotent optimization script for DNSTT (DNS Tunnel) servers. This script performs system tuning while preserving your existing domain and key configurations.

## Features

- 🔍 **Auto-detects** DNSTT service (any naming convention)
- 🛡️ **Preserves** existing domain and key configurations
- 📦 **Idempotent** – safe to run multiple times
- ⚡ **Optimizes** UDP buffer sizes for better throughput
- 💾 **Creates** 1GB swap if not present
- 🔒 **Disables** IPv6 to prevent binding issues
- 🔄 **Sets up** automatic DNSTT restart every 2 hours
- 🔐 **Tunes** SSH MaxSessions

## Requirements

- Linux server (Debian/Ubuntu or RHEL/CentOS)
- Root access
- Running DNSTT service (installed via systemd)

## Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/dnstt-optimizer.git
cd dnstt-optimizer

# Make executable
chmod +x optimize-dnstt.sh
```

## Usage

Run with root privileges:

```bash
sudo ./optimize-dnstt.sh
```

### One-liner Installation & Run

```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/dnstt-optimizer/main/optimize-dnstt.sh | sudo bash
```

## What It Does

| Action | Description |
|--------|-------------|
| **IPv6 Disable** | Disables IPv6 to ensure DNSTT binds to IPv4 only |
| **UDP Tuning** | Increases UDP buffer sizes for better performance |
| **Swap Creation** | Creates 1GB swapfile if none exists |
| **DNSTT Fix** | Patches UDP bind to `0.0.0.0:5300` (IPv4) |
| **SSH Tuning** | Sets `MaxSessions 10` for SSH |
| **Auto-restart** | Adds cron job to restart DNSTT every 2 hours |

## Example Output

```
==============================
 DNSTT SMART OPTIMIZATION
 (domain & key preserved)
==============================
[23:04:54] DNSTT detected: dnstt-server.service
[23:04:54] SSH service: sshd
[23:04:54] Checking IPv6...
[23:04:54] IPv6 disabled
[23:04:54] Checking UDP tuning...
[23:04:54] Checking swap...
[23:04:55] 1GB swapfile created
[23:04:55] Reading current DNSTT ExecStart...
[23:04:55] Fixing DNSTT UDP bind (preserving domain & key)
[23:04:57] DNSTT is listening on UDP 5300 (OK)
[23:04:57] Applying SSH MaxSessions (10)
[23:04:57] Ensuring DNSTT auto-restart cron...
------------------------------
SUMMARY
DNSTT ExecStart : /usr/local/bin/dnstt-server -udp 0.0.0.0:5300 -doh ...
SSH users       : 1
SSH connections : 2
DNSTT threads   : 8
------------------------------
[23:04:57] DONE – safe on multi-domain servers
```

## Testing

### Pre-flight Checks

Before running, verify your DNSTT service is active:

```bash
# Check if DNSTT service exists
systemctl list-unit-files | grep dnstt

# Check current DNSTT status
systemctl status dnstt-server.service  # or your service name
```

### Post-run Verification

After running the script, verify the optimizations:

```bash
# 1. Check DNSTT is listening on UDP 5300
ss -lunp | grep 5300

# 2. Verify IPv6 is disabled
sysctl net.ipv6.conf.all.disable_ipv6
# Expected: net.ipv6.conf.all.disable_ipv6 = 1

# 3. Check UDP buffer settings
sysctl net.core.rmem_max net.core.wmem_max
# Expected: 26214400 for both

# 4. Verify swap is active
swapon --show
# Should show /swapfile with 1G size

# 5. Check cron job
crontab -l | grep dnstt
# Expected: 0 */2 * * * systemctl restart dnstt...

# 6. Verify SSH MaxSessions
grep MaxSessions /etc/ssh/sshd_config
# Expected: MaxSessions 10

# 7. Check DNSTT service status
systemctl status $(systemctl list-unit-files | awk '{print $1}' | grep -E '^dnstt.*\.service$' | head -n1)
```

### Quick Test Script

Run all verification checks at once:

```bash
echo "=== DNSTT Optimization Verification ===" && \
echo -e "\n[1] UDP 5300 Listener:" && ss -lunp | grep 5300 && \
echo -e "\n[2] IPv6 Status:" && sysctl net.ipv6.conf.all.disable_ipv6 && \
echo -e "\n[3] UDP Buffers:" && sysctl net.core.rmem_max net.core.wmem_max && \
echo -e "\n[4] Swap Status:" && swapon --show && \
echo -e "\n[5] Cron Job:" && crontab -l 2>/dev/null | grep dnstt && \
echo -e "\n[6] SSH MaxSessions:" && grep MaxSessions /etc/ssh/sshd_config && \
echo -e "\n=== All checks completed ==="
```

## Rollback

If you need to revert changes:

```bash
# Remove DNSTT service override
sudo rm -rf /etc/systemd/system/dnstt*.service.d
sudo systemctl daemon-reload
sudo systemctl restart dnstt-server.service

# Re-enable IPv6 (optional)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0

# Remove cron job
crontab -l | grep -v dnstt | crontab -
```

## License

MIT License

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.
