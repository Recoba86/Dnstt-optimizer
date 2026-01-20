#!/bin/bash
# DNSTT Watchdog - Safe standalone script
# Only monitors and restarts, doesn't change any settings

LOGFILE="/var/log/dnstt-watchdog.log"
MAX_LOG_SIZE=102400  # 100KB

# Rotate log if too big
[ -f "$LOGFILE" ] && [ $(stat -f%z "$LOGFILE" 2>/dev/null || stat -c%s "$LOGFILE" 2>/dev/null) -gt $MAX_LOG_SIZE ] && > "$LOGFILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

# Find DNSTT service
DNSTT_SERVICE=$(systemctl list-unit-files | awk '{print $1}' | grep -E '^dnstt.*\.service$' | head -n1)
[ -z "$DNSTT_SERVICE" ] && exit 0

RESTART_NEEDED=0
REASON=""

# Check 1: Is service running?
if ! systemctl is-active --quiet "$DNSTT_SERVICE"; then
    RESTART_NEEDED=1
    REASON="Service not running"
fi

# Check 2: Is it listening on port 5300?
if [ $RESTART_NEEDED -eq 0 ]; then
    if ! ss -lunp 2>/dev/null | grep -q ':5300.*dnstt'; then
        RESTART_NEEDED=1
        REASON="Not listening on UDP 5300"
    fi
fi

# Check 3: Check if process is stuck (optional - memory check)
if [ $RESTART_NEEDED -eq 0 ]; then
    MEM_KB=$(ps -o rss= -C dnstt-server 2>/dev/null | head -1 | tr -d ' ')
    if [ -n "$MEM_KB" ] && [ "$MEM_KB" -gt 100000 ]; then  # > 100MB (for 512MB VPS)
        RESTART_NEEDED=1
        REASON="Memory too high: ${MEM_KB}KB"
    fi
fi

# Restart if needed
if [ $RESTART_NEEDED -eq 1 ]; then
    log "RESTART: $REASON"
    systemctl restart "$DNSTT_SERVICE"
    sleep 2
    if systemctl is-active --quiet "$DNSTT_SERVICE"; then
        log "RESTART: Success"
    else
        log "RESTART: Failed!"
    fi
fi
