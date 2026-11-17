# 📡 OrangePizero4_powersavingoff

Zero-dependency Wi-Fi & SDIO power-saving fix, self-healing watchdog, and SSH port + Fail2Ban hardening script for **Orange Pi Zero 4** (Allwinner H700 / `sun60iw2` with **AIC8800D80** SDIO Wi-Fi) running **Debian Trixie** or **Armbian**.

## ✨ What It Configures

- **Disables AIC8800D80 Driver Power Saving (`/etc/modprobe.d/aic8800.conf`):** Sets `ps_on=0`, `dpsm=0`, and `uapsd_timeout=0` so the SDIO bus never enters deep sleep (`aicwf_sdio_bus_pwrctl: bus down`).
- **Locks SDIO Host Power Control (`/etc/udev/rules.d/90-sdio-no-pm.rules`):** Keeps `4021000.sdmmc` powered `on` so DMA transfers never time out (`wait dma hold bit clear timeout`).
- **Disables NetworkManager & `iw` Power Save:** Forces `wifi.powersave = 2` and `power_save off`.
- **Locks Router BSSID:** Binds `wlan0` to your router's MAC address (`802-11-wireless.bssid`) to stop periodic background roaming scans.
- **Masks Systemd Sleep Targets:** Prevents `sleep.target`, `suspend.target`, `hibernate.target`, and `hybrid-sleep.target` from suspending an idle server.
- **Self-Healing Watchdog (`/usr/local/sbin/wifi-watchdog.sh`):** Checks gateway reachability every 3 minutes via cron and recovers `wlan0` (via `nmcli`, `rfkill` + `aic8800_fdrv` reload, or clean reboot if hardware-wedged).
- **Custom SSH Port & Fail2Ban Hardening:** Prompts to move SSH to a custom 5-digit port (`1024–65535`, eliminating ~95%+ of automated port-22 scanner noise) and configures `fail2ban` to protect that port while whitelisting your local LAN subnet.

## 🚀 Quick Install

**One-liner (fresh Debian Trixie / Armbian install):**

```bash
sudo bash -c 'git clone https://github.com /tmp/OrangePizero4_powersavingoff && cd /tmp/OrangePizero4_powersavingoff && chmod +x install.sh && ./install.sh'
```

**Or manually:**

```bash
git clone https://github.com
cd OrangePizero4_powersavingoff
chmod +x install.sh
sudo ./install.sh
sudo reboot
```

## 🔍 Verify Status After Reboot

```bash
# Should print N, N, 0
cat /sys/module/aic8800_fdrv/parameters/{ps_on,dpsm,uapsd_timeout}

# Should print Power save: off
iw dev wlan0 get power_save

# Check Fail2Ban SSH jail status
sudo fail2ban-client status sshd

# Check watchdog logs
journalctl -t wifi-watchdog --no-pager
```
