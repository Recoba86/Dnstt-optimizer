#!/bin/bash
set -e

log() { echo "[$(date +%H:%M:%S)] $1"; }

echo "========================================"
echo " DNSTT OPTIMIZER v4 (Balanced Edition)"
echo " For small VPS: 512MB-1GB RAM"
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

### Balanced tuning for 512MB-1GB VPS
log "Applying balanced tuning..."
sed -i '/# DNSTT/,/^$/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.rmem/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.wmem/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.udp_mem/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.netdev/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/vm.swappiness/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/vm.vfs_cache_pressure/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.tcp/d' /etc/sysctl.conf 2>/dev/null || true

cat <<EOF >> /etc/sysctl.conf

# DNSTT Balanced Tuning (512MB-1GB VPS)
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.core.rmem_default=2097152
net.core.wmem_default=2097152
net.ipv4.udp_mem=65536 131072 262144
net.core.netdev_max_backlog=2000

# Swap usage
vm.swappiness=60

# TCP settings
net.ipv4.tcp_rmem=4096 87380 8388608
net.ipv4.tcp_wmem=4096 65536 8388608
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_tw_reuse=1
EOF
sysctl -p >/dev/null 2>&1 || true
log "Balanced tuning applied"

### Swap
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

### Configure DNSTT (no memory limits - let it use what it needs)
log "Configuring DNSTT service..."
FIXED_EXEC=$(echo "$CURRENT_EXEC" | sed 's/-udp [^ ]*/-udp 0.0.0.0:5300/')

mkdir -p /etc/systemd/system/${DNSTT_SERVICE}.d
cat <<EOF > /etc/systemd/system/${DNSTT_SERVICE}.d/override.conf
[Service]
ExecStart=
ExecStart=${FIXED_EXEC}
Restart=always
RestartSec=5
LimitNOFILE=65535
Nice=-5
EOF

systemctl daemon-reexec >/dev/null 2>&1 || systemctl daemon-reload >/dev/null 2>&1
systemctl restart "$DNSTT_SERVICE"
sleep 2
log "DNSTT configured"

### Verify bind
if ss -lunp 2>/dev/null | grep -q ':5300.*dnstt'; then
  log "DNSTT is listening on UDP 5300 (OK)"
else
  log "WARNING: DNSTT may not be listening on UDP 5300"
fi

### SSH tuning
if [ -n "$SSH_SERVICE" ]; then
  log "Applying SSH settings..."
  sed -i '/^MaxSessions/d' /etc/ssh/sshd_config 2>/dev/null || true
  sed -i '/^ClientAliveInterval/d' /etc/ssh/sshd_config 2>/dev/null || true
  sed -i '/^ClientAliveCountMax/d' /etc/ssh/sshd_config 2>/dev/null || true
  cat <<EOF >> /etc/ssh/sshd_config
MaxSessions 20
ClientAliveInterval 60
ClientAliveCountMax 3
EOF
  systemctl reload "$SSH_SERVICE" 2>/dev/null || true
fi

### Watchdog script (simpler - just check if listening)
log "Creating watchdog script..."
cat <<'WATCHDOG' > /usr/local/bin/dnstt-watchdog.sh
#!/bin/bash
SERVICE="$1"
if ! ss -lunp 2>/dev/null | grep -q ':5300.*dnstt'; then
    logger "DNSTT Watchdog: Service not listening, restarting..."
    systemctl restart "$SERVICE"
fi
WATCHDOG
chmod +x /usr/local/bin/dnstt-watchdog.sh

### Cron: watchdog every 10 min + restart every 2 hours
log "Configuring cron jobs..."
(crontab -l 2>/dev/null | grep -v 'dnstt' | grep -v '^$'
echo "*/10 * * * * /usr/local/bin/dnstt-watchdog.sh $DNSTT_SERVICE >/dev/null 2>&1"
echo "0 */2 * * * systemctl restart $DNSTT_SERVICE >/dev/null 2>&1"
) | crontab - 2>/dev/null || true

### Summary
echo "========================================"
echo "SUMMARY (Balanced for 512MB-1GB VPS)"
echo "========================================"
echo "DNSTT Service   : $DNSTT_SERVICE"
echo "Buffer Size     : 8MB (balanced)"
echo "Watchdog        : Every 10 minutes"
echo "Auto-restart    : Every 2 hours"
echo "Current RAM     : $(free -m | awk '/Mem:/ {print $3"/"$2}') MB"
echo "Swap            : $(free -m | awk '/Swap:/ {print $3"/"$2}') MB"
echo "DNSTT Memory    : $(ps -o rss= -C dnstt-server 2>/dev/null | awk '{printf "%.1f", $1/1024}' || echo "0") MB"
echo "========================================"

log "DONE – Balanced optimization applied!"
