#!/bin/bash
set -e

log() { echo "[$(date +%H:%M:%S)] $1"; }

echo "=============================="
echo " DNSTT SMART OPTIMIZATION v2"
echo " (idempotent - safe to re-run)"
echo "=============================="

### Detect DNSTT service
DNSTT_SERVICE=$(systemctl list-unit-files | awk '{print $1}' | grep -E '^dnstt.*\.service$' | head -n1)
[ -z "$DNSTT_SERVICE" ] && { log "DNSTT service not found"; exit 1; }
log "DNSTT detected: $DNSTT_SERVICE"

### Detect SSH service
SSH_SERVICE=""
systemctl list-units --type=service | grep -q ssh.service  && SSH_SERVICE="ssh"
systemctl list-units --type=service | grep -q sshd.service && SSH_SERVICE="sshd"
[ -n "$SSH_SERVICE" ] && log "SSH service: $SSH_SERVICE"

### IPv6 (safe - idempotent)
log "Checking IPv6..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

# Remove old entries and add fresh ones
sed -i '/disable_ipv6/d' /etc/sysctl.conf 2>/dev/null || true
cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
log "IPv6 disabled"

### UDP tuning (idempotent - removes old, adds new)
log "Applying UDP tuning..."
# Remove old DNSTT tuning block
sed -i '/# DNSTT UDP tuning/,/^$/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.rmem_max/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.wmem_max/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.rmem_default/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.wmem_default/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.ipv4.udp_mem/d' /etc/sysctl.conf 2>/dev/null || true
sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf 2>/dev/null || true

cat <<EOF >> /etc/sysctl.conf

# DNSTT UDP tuning (optimized for limited connections)
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.udp_mem=32768 65536 131072
net.core.netdev_max_backlog=5000
EOF
sysctl -p >/dev/null 2>&1 || true
log "UDP tuning applied"

### Swap (safe - skip if exists)
log "Checking swap..."
if swapon --show | grep -q '/swapfile'; then
  log "Swapfile already active"
else
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log "1GB swapfile created"
fi

### Read current ExecStart (authoritative)
log "Reading current DNSTT ExecStart..."
CURRENT_EXEC=$(systemctl cat "$DNSTT_SERVICE" 2>/dev/null | grep '^ExecStart=' | tail -n1 | sed 's/^ExecStart=//')

[ -z "$CURRENT_EXEC" ] && { log "ERROR: ExecStart not found"; exit 1; }

### Fix UDP bind ONLY (preserve domain/key/etc)
log "Configuring DNSTT UDP bind..."
FIXED_EXEC=$(echo "$CURRENT_EXEC" | sed 's/-udp [^ ]*/-udp 0.0.0.0:5300/')

mkdir -p /etc/systemd/system/${DNSTT_SERVICE}.d
cat <<EOF > /etc/systemd/system/${DNSTT_SERVICE}.d/override.conf
[Service]
ExecStart=
ExecStart=${FIXED_EXEC}
Restart=always
RestartSec=3
LimitNOFILE=65535
EOF

systemctl daemon-reexec >/dev/null 2>&1 || systemctl daemon-reload >/dev/null 2>&1
systemctl restart "$DNSTT_SERVICE"
sleep 2
log "DNSTT configured (IPv4-only on port 5300)"

### Verify bind (real check)
if ss -lunp 2>/dev/null | grep -q ':5300.*dnstt'; then
  log "DNSTT is listening on UDP 5300 (OK)"
else
  log "WARNING: DNSTT may not be listening on UDP 5300 (check manually)"
fi

### SSH tuning (idempotent)
if [ -n "$SSH_SERVICE" ]; then
  log "Applying SSH MaxSessions (30)"
  sed -i '/^MaxSessions/d' /etc/ssh/sshd_config 2>/dev/null || true
  echo "MaxSessions 30" >> /etc/ssh/sshd_config
  systemctl reload "$SSH_SERVICE" 2>/dev/null || true
fi

### Auto-restart cron (idempotent - remove old, add new)
log "Configuring DNSTT auto-restart cron..."
(crontab -l 2>/dev/null | grep -v 'dnstt' | grep -v '^$'; echo "0 */2 * * * systemctl restart $DNSTT_SERVICE >/dev/null 2>&1") | crontab - 2>/dev/null || true

### Summary
echo "------------------------------"
echo "SUMMARY"
echo "DNSTT ExecStart : $FIXED_EXEC"
echo "SSH users       : $(who | wc -l)"
echo "SSH connections : $(ss -tn state established '( sport = :22 )' 2>/dev/null | wc -l)"
echo "DNSTT threads   : $(ps -o nlwp= -C dnstt-server 2>/dev/null || echo 0)"
echo "------------------------------"

log "DONE – safe to re-run anytime!"
