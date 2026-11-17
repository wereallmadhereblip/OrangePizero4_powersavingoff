#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[✗] Please run as root (sudo ./install.sh)"
  exit 1
fi

echo "[*] Applying Orange Pi Zero 4 Wi-Fi & SDIO stability fixes..."

# 1. Disable AIC8800D80 kernel driver power-saving modes
cat << 'MODCONF' > /etc/modprobe.d/aic8800.conf
options aic8800_fdrv ps_on=0 dpsm=0 uapsd_timeout=0
MODCONF
echo "[✓] Configured /etc/modprobe.d/aic8800.conf (ps_on=0, dpsm=0, uapsd_timeout=0)"

# 2. Disable NetworkManager Wi-Fi power saving
mkdir -p /etc/NetworkManager/conf.d
cat << 'NMCONF' > /etc/NetworkManager/conf.d/10-wifi-stability.conf
[connection]
wifi.powersave = 2
NMCONF
iw dev wlan0 set power_save off 2>/dev/null || true
echo "[✓] Disabled NetworkManager & iw Wi-Fi power saving"

# 3. Lock active wlan0 connection to current router BSSID to prevent SDIO scan hangs
if command -v nmcli >/dev/null 2>&1 && command -v iw >/dev/null 2>&1; then
  CON_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep ':wlan0$' | cut -d: -f1)
  BSSID=$(iw dev wlan0 link 2>/dev/null | awk '/Connected to/ {print $3}')
  if [ -n "$CON_NAME" ] && [ -n "$BSSID" ]; then
    nmcli con modify "$CON_NAME" 802-11-wireless.bssid "$BSSID" 2>/dev/null || true
    echo "[✓] Locked '$CON_NAME' to BSSID $BSSID (disables background roaming scans)"
  fi
fi

# 4. Mask systemd sleep/suspend targets so server never suspends
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
echo "[✓] Masked systemd sleep & suspend targets"

# 5. Install self-healing Wi-Fi watchdog & 3-minute cron job
install -m 0755 wifi-watchdog.sh /usr/local/sbin/wifi-watchdog.sh
(crontab -l 2>/dev/null | grep -v wifi-watchdog; echo "*/3 * * * * /usr/local/sbin/wifi-watchdog.sh") | crontab -
echo "[✓] Installed /usr/local/sbin/wifi-watchdog.sh (runs every 3 minutes)"

# 6. Update initramfs so modprobe options persist at early boot
if command -v update-initramfs >/dev/null 2>&1; then
  echo "[*] Updating initramfs..."
  update-initramfs -u
  echo "[✓] initramfs updated"
fi

echo ""
echo "[✓] Installation complete! Reboot once (`sudo reboot`) to apply driver flags cleanly."
