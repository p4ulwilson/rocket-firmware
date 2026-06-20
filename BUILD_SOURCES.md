# Rocket Routers Firmware — Build Sources Reference

## Hardware: Rocket Plus E (ZBT-8803BE)

| Field | Value |
|---|---|
| Device | ZBT ZBT-8803 BE |
| SoC | MediaTek MT7981B (Filogic 820) |
| Architecture | aarch64_cortex-a53 |
| OpenWRT Target | mediatek/filogic |
| WiFi | MT7996 (tri-band) |
| Revision on device | SNAPSHOT r33686+1-aa06d26879 |

**Note:** ZBT-8803 is NOT in official OpenWRT mainline (as of June 2026).
It is only in pttuan's fork (see below). Do not try to use the official
ImageBuilder — the `zbtlink,zbt-z8803be` profile does not exist there.

---

## Source Repositories

### 1. OpenWRT Source (with ZBT-8803 support)
```
Repo:    https://github.com/pttuan/openwrt
Fork of: https://github.com/openwrt/openwrt
Key commit: fce4731b5c3323ad3652643d64bf0f78e51293b0
Commit msg: "mediatek: filogic: Support ZBT zbt8803 router"
Local path: ~/src/openwrt   (in WSL)
Board name: zbtlink,zbt-z8803be
Profile:    zbtlink_zbt-z8803be
```

To clone fresh:
```bash
git clone https://github.com/pttuan/openwrt.git ~/src/openwrt
cd ~/src/openwrt
git checkout main   # or the specific commit above if needed
```

### 2. QModem Feed (custom modem management)
```
Repo:   https://github.com/FUjr/QModem
Stars:  ~393 (active project)
Provides:
  - qmodem
  - luci-app-qmodem-next
  - luci-app-qmodem-sms
  - tom_modem
  - sms-forwarder-next
  - ubus-at-daemon
```

Add to feeds:
```bash
echo "src-git qmodem https://github.com/FUjr/QModem.git" >> feeds.conf.default
./scripts/feeds update qmodem
./scripts/feeds install -a -p qmodem
```

---

## Build Environment

- **OS**: WSL (Ubuntu) on Windows
- **Source location**: `~/src/openwrt` (WSL path)
- **Firmware-build folder**: `/mnt/d/Rocket-Routers-Website/firmware-build/`
- **Config file**: `rocket-vE.config` (package list)
- **Metadata**: `rocket-vE-v{VERSION}-metadata.config` (version strings)
- **Build script**: `build-v{VERSION}.sh`

### Known Build Quirks (learned the hard way)

1. **Z8803BE image assembly bug** — the normal `make` process silently skips
   the sysupgrade image for this device. Use manual assembly after `make`:
   ```bash
   $OPENWRT_SRC/scripts/sysupgrade-tar.sh \
     --board "zbtlink,zbt-z8803be" \
     --kernel build_dir/target-.../zbtlink_zbt-z8803be-kernel.bin \
     --rootfs build_dir/target-.../root.squashfs \
     /tmp/output.bin
   ```

2. **Strip Windows paths from WSL PATH** before building or you get linker errors:
   ```bash
   export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/[c-z]' | tr '\n' ':')
   ```

3. **Disable broken devices in filogic.mk** — `openwrt_one` and `abt_asr3000`
   lack MT7981 BL31/uboot and cause build failures. Comment them out:
   ```bash
   sed -i "s/^TARGET_DEVICES += openwrt_one/#TARGET_DEVICES += openwrt_one/" \
     target/linux/mediatek/image/filogic.mk
   sed -i "s/^TARGET_DEVICES += abt_asr3000/#TARGET_DEVICES += abt_asr3000/" \
     target/linux/mediatek/image/filogic.mk
   ```

4. **Package manager on router is APK** (not opkg) — SNAPSHOT build.
   Use `apk add <package>` not `opkg install`.

5. **No `base64` command on router** — use `openssl enc -base64 -d -A` instead.

6. **WiFi firmware** — must include `kmod-mt7996e`, `kmod-mt7996-firmware-common`,
   `kmod-mt7996-firmware`, `kmod-mt7996-233-firmware`. Without these the radio
   is silently absent from `iwinfo` output.

7. **Flash command** — always use `-n -F` flags:
   ```bash
   sysupgrade -n -F /tmp/rocket-firmware-E-v{VERSION}.bin
   ```

---

## Dashboard (rocket-dashboard.cgi)

- **Location in build**: `files/www/cgi-bin/rocket` (no .cgi extension on router)
- **Source file**: `firmware-build/rocket-dashboard.cgi`
- **Size**: ~1.1MB, ~15,000+ lines
- **Language**: busybox ash (backend) + vanilla JS (frontend)
- **IMPORTANT**: Always use Python to edit — Edit tool truncates large files

### Phases completed
- Phase 1–4: Network setup wizard (guest WiFi, WAN2, port roles)
- Phase 5: mwan3 failover/load-balance wizard + pictogram status

---

## Versions

| Version | Filename | Key Changes |
|---|---|---|
| v3.8.3 | rocket-firmware-E-v3.8.3.bin | Topology map, BGP tracer, AI packet analyst, WiFi scheduler |
| v3.9.0 | rocket-firmware-E-v3.9.0.bin | Phase 5: mwan3 wizard, dual-WAN failover/load-balance UI |

---

## Build Steps (Quick Reference)

```bash
# From WSL, assuming ~/src/openwrt already cloned and configured:
bash /mnt/d/Rocket-Routers-Website/firmware-build/build-v3.9.0.sh

# If first-time setup needed:
cd ~/src/openwrt
./scripts/feeds update -a
./scripts/feeds install -a
cp /mnt/d/Rocket-Routers-Website/firmware-build/rocket-vE.config .config
make defconfig

# Then run the build script above
```

---

## Transfer & Flash

```bash
# SCP to router (direct cable or LAN)
scp /mnt/d/Rocket-Routers-Website/firmware-build/rocket-firmware-E-v3.9.0.bin \
    root@192.168.1.1:/tmp/

# Flash from router SSH
sysupgrade -n -F /tmp/rocket-firmware-E-v3.9.0.bin
```
