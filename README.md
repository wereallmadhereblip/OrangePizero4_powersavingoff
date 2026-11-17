# 📡 orangepi-wifi-fix

Zero-dependency Wi-Fi & SDIO stability fix and self-healing watchdog for **Orange Pi Zero 4** (Allwinner H700 / `sun60iw2` with **AIC8800D80** SDIO Wi-Fi) running **Debian Trixie** or **Armbian**.

Fixes random 12–16 hour headless server disconnects caused by `aicwf_sdio_bus_pwrctl: bus down`, `sunxi_mmc_host: wait dma hold bit clear timeout`, and `wpa_supplicant: Failed to initiate AP scan`.

## ✨ What It Fixes

- **Disables AIC8800D80 Driver Power Saving (`/etc/modprobe.d/aic8800.conf`):** Sets `ps_on=0`, `dpsm=0`, and `uapsd_timeout=0` so the SDIO bus never enters deep sleep.
- **Disables NetworkManager & `iw` Power Save:** Forces `wifi.powersave = 2` and `power_save off`.
- **Stops Background Roaming Scans:** Locks your active `wlan0` NetworkManager profile to your router's BSSID so periodic AP scans don't wedge the SDIO DMA controller.
- **Masks Systemd Sleep Targets:** Prevents `sleep.target`, `suspend.target`, `hibernate.target`, and `hybrid-sleep.target` from suspending an idle server.
- **Self-Healing Watchdog (`/usr/local/sbin/wifi-watchdog.sh`):** Pings your default gateway every 3 minutes via cron and automatically reconnects `wlan0` or reloads `aic8800_fdrv` if unreachable.

## 🚀 Quick Install

**One-liner (fresh Debian Trixie / Armbian install):**

```bash
sudo bash -c 'git clone https://github.com /tmp/orangepi-wifi-fix && cd /tmp/orangepi-wifi-fix && chmod +x install.sh && ./install.sh'
```

**Or manually:**

```bash
git clone https://github.com
cd orangepi-wifi-fix
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

# Check watchdog logs
journalctl -t wifi-watchdog --no-pager
```
