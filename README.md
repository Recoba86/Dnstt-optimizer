# DNSTT Smart Optimizer

A bash script to optimize and configure your DNSTT server for better performance and stability.

## Features
- **Smart Detection**: Automatically detects your DNSTT service and SSH service.
- **IPv6 Disabling**: Disables IPv6 to prevent leaks and improve compatibility.
- **UDP Tuning**: Optimizes system buffers (`rmem`, `wmem`) for high-throughput UDP traffic.
- **Swap Creation**: Creates a 1GB swap file if one doesn't exist, preventing OOM crashes.
- **Port Standardization**: Ensures DNSTT listens on port `5300` while preserving your existing keys and domain configuration.
- **SSH Tuning**: Adjusts `MaxSessions` for better SSH responsiveness.
- **Auto-Restart**: Adds a cron job to restart the service every 2 hours to maintain freshness.

## Usage

### 1. Download and Run
You can run the script directly on your server:

```bash
wget https://raw.githubusercontent.com/Recoba86/Dnstt-optimizer/main/optimize-dnstt.sh
chmod +x optimize-dnstt.sh
sudo ./optimize-dnstt.sh
```

### 2. Verify
The script will output a summary of the changes and current status.
Check the "SUMMARY" section at the end of the output.

## Requirements
- A Linux server (Ubuntu/Debian recommended)
- Root privileges (run with `sudo`)
- Existing DNSTT installation

## Contributing
Feel free to open issues or submit pull requests.
