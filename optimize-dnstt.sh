#!/bin/bash
set -e

log() { echo "[$(date +%H:%M:%S)] $1"; }

echo "=============================="
echo " DNSTT SMART OPTIMIZATION"
echo " (domain & key preserved)"
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

### IPv6 (safe)
log "Checking IPv6..."
if sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q 1; then
  log "IPv6 already disabled"
else
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
  grep -q disable_ipv6 /etc/sysctl.conf || cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
  log "IPv6 disabled"
fi

### UDP tuning (append once)
log "Checking UDP tuning..."
grep -q "DNSTT UDP tuning" /etc/sysctl.conf || cat <<EOF >> /etc/sysctl.conf

# DNSTT UDP tuning
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.udp_mem=65536 131072 262144
EOF
sysctl -p >/dev/null

### Swap (safe)
log "Checking swap..."
if swapon --show | grep -q '/swapfile'; then
  log "Swapfile already active"
else
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log "1GB swapfile created"
fi

### Read current ExecStart (authoritative)
log "Reading current DNSTT ExecStart..."
CURRENT_EXEC=$(systemctl cat "$DNSTT_SERVICE" | grep '^ExecStart=' | tail -n1 | sed 's/^ExecStart=//')

[ -z "$CURRENT_EXEC" ] && { log "ERROR: ExecStart not found"; exit 1; }

### Fix UDP bind ONLY (preserve domain/key/etc)
if echo "$CURRENT_EXEC" | grep -q -- "-udp 0.0.0.0:5300"; then
  log "DNSTT already IPv4-only"
else
  log "Fixing DNSTT UDP bind (preserving domain & key)"
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

  systemctl daemon-reexec >/dev/null
  systemctl restart "$DNSTT_SERVICE"
  sleep 2
fi

### Verify bind (real check)
if ss -lunp | grep -q ':5300.*dnstt'; then
  log "DNSTT is listening on UDP 5300 (OK)"
else
  log "ERROR: DNSTT not listening on UDP 5300"
  exit 1
fi

### SSH tuning (safe)
if [ -n "$SSH_SERVICE" ]; then
  log "Applying SSH MaxSessions (10)"
  grep -q "^MaxSessions" /etc/ssh/sshd_config \
    || echo "MaxSessions 10" >> /etc/ssh/sshd_config
  systemctl reload "$SSH_SERVICE" || true
fi

### Auto-restart cron (idempotent)
log "Ensuring DNSTT auto-restart cron..."
(crontab -l 2>/dev/null | grep -q 'dnstt-server') || \
  (crontab -l 2>/dev/null; echo "0 */2 * * * systemctl restart $DNSTT_SERVICE >/dev/null 2>&1") | crontab -

### Summary
echo "------------------------------"
echo "SUMMARY"
echo "DNSTT ExecStart : $FIXED_EXEC"
echo "SSH users       : $(who | wc -l)"
echo "SSH connections : $(ss -tn state established '( sport = :22 )' | wc -l)"
echo "DNSTT threads   : $(ps -o nlwp= -C dnstt-server 2>/dev/null || echo 0)"
echo "------------------------------"

log "DONE – safe on multi-domain servers"
