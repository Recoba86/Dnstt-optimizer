#!/bin/bash
echo "========================================"
echo " DNSTT OPTIMIZER - COMPLETE UNINSTALL"
echo "========================================"

echo "[1/6] Removing sysctl changes..."
# Backup original
cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%s)

# Remove all our additions
sed -i '/disable_ipv6/d' /etc/sysctl.conf
sed -i '/# DNSTT/d' /etc/sysctl.conf
sed -i '/net.core.rmem/d' /etc/sysctl.conf
sed -i '/net.core.wmem/d' /etc/sysctl.conf
sed -i '/net.ipv4.udp_mem/d' /etc/sysctl.conf
sed -i '/net.core.netdev/d' /etc/sysctl.conf
sed -i '/vm.swappiness/d' /etc/sysctl.conf
sed -i '/vm.vfs_cache_pressure/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_mem/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_max_syn/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
# Remove empty lines at the end
sed -i -e :a -e '/^\s*$/d;N;ba' /etc/sysctl.conf 2>/dev/null || true
sysctl -p 2>/dev/null || true
echo "Done"

echo "[2/6] Removing DNSTT service override..."
rm -rf /etc/systemd/system/dnstt-server.service.d
systemctl daemon-reload
echo "Done"

echo "[3/6] Removing SSH config changes..."
sed -i '/^MaxSessions/d' /etc/ssh/sshd_config
sed -i '/^ClientAliveInterval/d' /etc/ssh/sshd_config
sed -i '/^ClientAliveCountMax/d' /etc/ssh/sshd_config
sed -i '/# DNSTT/d' /etc/ssh/sshd_config
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
echo "Done"

echo "[4/6] Removing watchdog script..."
rm -f /usr/local/bin/dnstt-watchdog.sh
echo "Done"

echo "[5/6] Removing cron jobs..."
crontab -l 2>/dev/null | grep -v 'dnstt' | crontab - 2>/dev/null || true
echo "Done"

echo "[6/6] Restarting DNSTT service..."
systemctl restart dnstt-server 2>/dev/null || true
echo "Done"

echo ""
echo "========================================"
echo " UNINSTALL COMPLETE!"
echo "========================================"
echo ""
echo "All changes have been removed."
echo "Please REBOOT the server:"
echo ""
echo "  sudo reboot"
echo ""
