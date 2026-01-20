#!/bin/bash
set -e

log() { echo "[$(date +%H:%M:%S)] $1"; }

echo "========================================"
echo " DNSTT OPTIMIZER v3 (Ultra-Light Edition)"
echo " For small VPS: 512MB RAM / 1 vCPU"
echo "========================================"

### Detect DNSTT service
DNSTT_SERVICE=$(systemctl list-unit-files | awk '{print $1}' | grep -E '^dnstt.*\.service$' | head -n1)
[ -z "$DNSTT_SERVICE" ] && { log "DNSTT service not found"; exit 1; }
log "DNSTT detected: $DNSTT_SERVICE"

### Detect SSH service
SSH_SERVICE=""
systemctl list-units --type=service | grep -q ssh.service  && SSH_SERVICE="ssh"
systemctl list-units --type=service | grep -q sshd.service && SSH_SERVICE="sshd"
[ -n "$SSH_SERVICE" ] && log "SSH service: $SSH_SERVICE"

### IPv6 disable
log "Disabling IPv6..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
sed -i '/disable_ipv6/d' /etc/sysctl.conf 2>/dev/null || true
cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
log "IPv6 disabled"

### Memory-optimized tuning for 512MB VPS
log "Applying ultra-light memory tuning..."
sed -i '/# DNSTT/,/^$/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.rmem/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.wmem/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.udp_mem/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.netdev/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/vm.swappiness/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/vm.vfs_cache_pressure/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp/d' /etc/sysctl.conf 2>/dev/null || true

cat <<EOF >> /etc/sysctl.conf

# DNSTT Ultra-Light (512MB VPS)
# Small buffers to save RAM
net.core.rmem_max=1048576
net.core.wmem_max=1048576
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.udp_mem=8192 16384 32768
net.core.netdev_max_backlog=1000

# Memory management - use swap aggressively
vm.swappiness=80
vm.vfs_cache_pressure=200

# TCP optimizations for low memory
net.ipv4.tcp_rmem=4096 32768 262144
net.ipv4.tcp_wmem=4096 32768 262144
net.ipv4.tcp_mem=8192 16384 32768
net.ipv4.tcp_max_syn_backlog=256
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
EOF
sysctl -p >/dev/null 2>&1 || true
log "Ultra-light tuning applied"

### Swap (512MB VPS needs more swap!)
log "Checking swap..."
if swapon --show | grep -q '/swapfile'; then
  SWAP_SIZE=$(swapon --show | grep swapfile | awk '{print $3}')
  log "Swapfile active: $SWAP_SIZE"
else
  log "Creating 1GB swapfile..."
  dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none 2>/dev/null || \
  fallocate -l 1G /swapfile 2>/dev/null
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log "1GB swapfile created"
fi

### Read current ExecStart
log "Reading current DNSTT ExecStart..."
CURRENT_EXEC=$(systemctl cat "$DNSTT_SERVICE" 2>/dev/null | grep '^ExecStart=' | tail -n1 | sed 's/^ExecStart=//')
[ -z "$CURRENT_EXEC" ] && { log "ERROR: ExecStart not found"; exit 1; }

### Configure DNSTT with memory limits
log "Configuring DNSTT with resource limits..."
FIXED_EXEC=$(echo "$CURRENT_EXEC" | sed 's/-udp [^ ]*/-udp 0.0.0.0:5300/')

mkdir -p /etc/systemd/system/${DNSTT_SERVICE}.d
cat <<EOF > /etc/systemd/system/${DNSTT_SERVICE}.d/override.conf
[Service]
ExecStart=
ExecStart=${FIXED_EXEC}
Restart=always
RestartSec=5
WatchdogSec=60
LimitNOFILE=4096
MemoryMax=200M
MemoryHigh=150M
Nice=-5
EOF

systemctl daemon-reexec >/dev/null 2>&1 || systemctl daemon-reload >/dev/null 2>&1
systemctl restart "$DNSTT_SERVICE"
sleep 2
log "DNSTT configured with 200MB memory limit"

### Verify bind
if ss -lunp 2>/dev/null | grep -q ':5300.*dnstt'; then
  log "DNSTT is listening on UDP 5300 (OK)"
else
  log "WARNING: DNSTT may not be listening on UDP 5300"
fi

### SSH tuning (fewer sessions for low memory)
if [ -n "$SSH_SERVICE" ]; then
  log "Applying SSH MaxSessions (15)"
  sed -i '/^MaxSessions/d' /etc/ssh/sshd_config 2>/dev/null || true
  sed -i '/^ClientAliveInterval/d' /etc/ssh/sshd_config 2>/dev/null || true
  sed -i '/^ClientAliveCountMax/d' /etc/ssh/sshd_config 2>/dev/null || true
  cat <<EOF >> /etc/ssh/sshd_config
MaxSessions 15
ClientAliveInterval 30
ClientAliveCountMax 3
EOF
  systemctl reload "$SSH_SERVICE" 2>/dev/null || true
fi

### Watchdog script (auto-restart if DNSTT freezes)
log "Creating watchdog script..."
cat <<'WATCHDOG' > /usr/local/bin/dnstt-watchdog.sh
#!/bin/bash
# DNSTT Watchdog - restarts if service is unresponsive
SERVICE="$1"
if ! ss -lunp 2>/dev/null | grep -q ':5300.*dnstt'; then
    logger "DNSTT Watchdog: Service not listening, restarting..."
    systemctl restart "$SERVICE"
fi
# Also restart if memory usage is too high
MEM_USED=$(ps -o rss= -C dnstt-server 2>/dev/null | head -1)
if [ -n "$MEM_USED" ] && [ "$MEM_USED" -gt 180000 ]; then
    logger "DNSTT Watchdog: Memory too high (${MEM_USED}KB), restarting..."
    systemctl restart "$SERVICE"
fi
WATCHDOG
chmod +x /usr/local/bin/dnstt-watchdog.sh

### Cron: watchdog every 5 min + restart every hour
log "Configuring cron jobs..."
(crontab -l 2>/dev/null | grep -v 'dnstt' | grep -v '^$'
echo "*/5 * * * * /usr/local/bin/dnstt-watchdog.sh $DNSTT_SERVICE >/dev/null 2>&1"
echo "0 * * * * systemctl restart $DNSTT_SERVICE >/dev/null 2>&1"
) | crontab - 2>/dev/null || true

### Clear caches now
log "Clearing memory caches..."
sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

### Summary
echo "========================================"
echo "SUMMARY (Ultra-Light for 512MB VPS)"
echo "========================================"
echo "DNSTT Service   : $DNSTT_SERVICE"
echo "Memory Limit    : 200MB (hard) / 150MB (soft)"
echo "Watchdog        : Every 5 minutes"
echo "Auto-restart    : Every 1 hour"
echo "Current RAM     : $(free -m | awk '/Mem:/ {print $3"/"$2}') MB"
echo "Swap            : $(free -m | awk '/Swap:/ {print $3"/"$2}') MB"
echo "DNSTT Memory    : $(ps -o rss= -C dnstt-server 2>/dev/null | awk '{printf "%.1f", $1/1024}' || echo "0") MB"
echo "========================================"

log "DONE – Optimized for 512MB VPS!"
