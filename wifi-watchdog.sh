#!/bin/bash
# Self-healing Wi-Fi & SDIO watchdog for Orange Pi Zero 4 (AIC8800D80)

IFACE="${1:-wlan0}"
GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
[ -z "$GATEWAY" ] && GATEWAY="192.168.0.1"

if ! ping -c 2 -W 3 "$GATEWAY" >/dev/null 2>&1; then
  logger -t wifi-watchdog "Gateway $GATEWAY unreachable on $IFACE, recovering..."
  iw dev "$IFACE" set power_save off 2>/dev/null
  nmcli device disconnect "$IFACE" 2>/dev/null
  sleep 2
  nmcli device connect "$IFACE" 2>/dev/null || {
    logger -t wifi-watchdog "Reloading aic8800_fdrv kernel module..."
    modprobe -r aic8800_fdrv 2>/dev/null
    sleep 2
    modprobe aic8800_fdrv 2>/dev/null
    sleep 3
    nmcli device connect "$IFACE" 2>/dev/null
  }
fi
