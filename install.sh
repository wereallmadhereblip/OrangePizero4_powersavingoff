#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[✗] Please run as root (sudo ./install.sh)"
  exit 1
fi

echo "============================================================"
echo "  Orange Pi Zero 4 — Wi-Fi Power-Save Fix & SSH Hardening"
echo "============================================================"

# 1. Disable AIC8800D80 kernel driver power-saving modes
cat << 'MODCONF' > /etc/modprobe.d/aic8800.conf
options aic8800_fdrv ps_on=0 dpsm=0 uapsd_timeout=0
MODCONF
echo "[✓] Configured /etc/modprobe.d/aic8800.conf (ps_on=0, dpsm=0, uapsd_timeout=0)"

# 2. Keep SDIO MMC host controller (4021000.sdmmc) powered on permanently
cat << 'UDEVCONF' > /etc/udev/rules.d/90-sdio-no-pm.rules
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="4021000.sdmmc", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="mmc", ATTR{power/control}="on"
UDEVCONF
echo on > /sys/devices/platform/soc@3000000/4021000.sdmmc/power/control 2>/dev/null || true
echo "[✓] Disabled runtime power management on SDIO host controller"

# 3. Disable NetworkManager Wi-Fi power saving
mkdir -p /etc/NetworkManager/conf.d
cat << 'NMCONF' > /etc/NetworkManager/conf.d/10-wifi-stability.conf
[connection]
wifi.powersave = 2
NMCONF
iw dev wlan0 set power_save off 2>/dev/null || true
echo "[✓] Disabled NetworkManager & iw Wi-Fi power saving"

# 4. Lock active wlan0 connection to current router BSSID to prevent SDIO scan hangs
if command -v nmcli >/dev/null 2>&1 && command -v iw >/dev/null 2>&1; then
  CON_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep ':wlan0$' | cut -d: -f1)
  BSSID=$(iw dev wlan0 link 2>/dev/null | awk '/Connected to/ {print $3}')
  if [ -n "$CON_NAME" ] && [ -n "$BSSID" ]; then
    nmcli con modify "$CON_NAME" 802-11-wireless.bssid "$BSSID" 2>/dev/null || true
    echo "[✓] Locked '$CON_NAME' to BSSID $BSSID (disables background roaming scans)"
  fi
fi

# 5. Mask systemd sleep/suspend targets
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
echo "[✓] Masked systemd sleep & suspend targets"

# 6. Install self-healing Wi-Fi watchdog & 3-minute cron job
install -m 0755 wifi-watchdog.sh /usr/local/sbin/wifi-watchdog.sh
(crontab -l 2>/dev/null | grep -v wifi-watchdog; echo "*/3 * * * * /usr/local/sbin/wifi-watchdog.sh") | crontab -
echo "[✓] Installed /usr/local/sbin/wifi-watchdog.sh (runs every 3 minutes)"

# 7. SSH Custom Port & Fail2Ban Hardening
echo ""
RAND_PORT=$((49152 + RANDOM % 16383))
read -r -p "Change SSH port to reduce scanner noise? Enter port [1024-65535], Enter for [$RAND_PORT], or 'n' to skip: " INPUT_PORT </dev/tty || INPUT_PORT="n"

SSH_PORT=22
if [[ "$INPUT_PORT" != "n" && "$INPUT_PORT" != "N" ]]; then
  SSH_PORT="${INPUT_PORT:-$RAND_PORT}"
  if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1024 ] && [ "$SSH_PORT" -le 65535 ]; then
    mkdir -p /etc/ssh/sshd_config.d
    cat << SSHCONF > /etc/ssh/sshd_config.d/99-custom-port.conf
Port $SSH_PORT
SSHCONF
    sed -i 's/^Port 22/#Port 22/' /etc/ssh/sshd_config

    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
      ufw allow "$SSH_PORT"/tcp >/dev/null 2>&1 || true
    fi

    sshd -t
    systemctl daemon-reload
    systemctl restart ssh.socket 2>/dev/null || true
    systemctl restart ssh
    echo "[✓] SSH port changed to $SSH_PORT"
  else
    echo "[!] Invalid port '$SSH_PORT' — keeping port 22"
    SSH_PORT=22
  fi
fi

# Install & configure Fail2Ban for the active SSH port
if ! command -v fail2ban-client >/dev/null 2>&1; then
  echo "[*] Installing fail2ban..."
  apt-get update -qq && apt-get install -y -qq fail2ban
fi

SUBNET=$(ip -4 route show dev wlan0 2>/dev/null | awk '/proto kernel/ {print $1; exit}')
[ -z "$SUBNET" ] && SUBNET="192.168.0.0/24"

cat << F2BCONF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 $SUBNET
bantime = 1h
findtime = 10m
maxretry = 4

[sshd]
enabled = true
port = $SSH_PORT
F2BCONF
systemctl enable --now fail2ban >/dev/null 2>&1
systemctl restart fail2ban
echo "[✓] Fail2Ban active on SSH port $SSH_PORT (whitelisted LAN: $SUBNET)"

# 8. Update initramfs so modprobe options persist at early boot
if command -v update-initramfs >/dev/null 2>&1; then
  echo "[*] Updating initramfs..."
  update-initramfs -u
  echo "[✓] initramfs updated"
fi

echo ""
echo "[✓] Setup complete! Reboot once ('sudo reboot') to apply all driver flags."
if [ "$SSH_PORT" -ne 22 ]; then
  echo "[!] Remember to connect with: ssh -p $SSH_PORT root@$(hostname -I | awk '{print $1}')"
fi
