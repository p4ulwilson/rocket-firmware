#!/bin/bash
# Mycelium Mesh RocketRouters v3.11.14 — WSL Build Script
# Run from WSL: bash /mnt/d/Rocket-Routers-Website/firmware-build/build-v3.11.14.sh
#
# This build's fix — v3.11.13's SIM-check script ran but did NOTHING:
#
#   Flashed v3.11.13, still hard-rebooted. Checked the actual evidence on
#   the router (not guessing this time):
#     - `logread | grep rocket-sim-check` -> zero lines. Not "ran and did
#       nothing useful" — literally never logged anything at all.
#     - `uci show qmodem | grep -E 'state|enable_dial'` -> both modem
#       sections (4_1, 2_1) still sitting at their untouched defaults
#       (enable_dial='1', state='enabled').
#     - `uci show qmodem | grep -E '^qmodem\.(4_1|2_1)='` -> confirmed both
#       sections really are type `modem-device`, so the script's section
#       filter was never the problem.
#     - `uci get qmodem.4_1.at_port` / `qmodem.2_1.at_port` -> EMPTY at the
#       point the check ran, but came back populated (/dev/ttyUSB3,
#       /dev/ttyUSB8) once things settled later.
#
#   Root cause: 94b-rocket-sim-check (v3.11.13) slept a flat 20 seconds
#   then read at_port once. At_port wasn't populated yet — qmodem's own
#   modem_scan + the existing 92-rocket-pin-modem script don't finish
#   settling it until well after that (pin-modem alone sleeps 30s before
#   even its first attempt, then retries for up to ~70s more). The old code
#   did `[ -z "$AT_PORT" ] && continue` and silently skipped both modems —
#   no log line, no action, no error. A quiet no-op, not a failure anyone
#   could see.
#
#   Fix: 94b-rocket-sim-check now waits/retries for at_port to actually be
#   populated (up to ~90s, bounded — not the unbounded pattern we're
#   working around in qmodem itself), and logs explicitly if it ever gives
#   up. The underlying SIM-check / disable-on-no-SIM logic from v3.11.13 is
#   otherwise unchanged — that part was never demonstrated wrong, it just
#   never got the chance to run.
#
# Carries forward v3.11.12's routing fix (defaultroute='0'/peerdns='0' on
# both network.wwan and network.wwan2 — Paul-confirmed working, ping to
# 8.8.8.8 succeeds) and the rc.local GPIO revert, plus all earlier fixes
# unchanged: donate-gate removal (joinMesh() unlocks everything), Cake/SQM
# dashboard fixes, stale version banner fix, set -e / uci-delete fix,
# modem-count detection window, mwan3 policy names, wwan2 dhcp/usb1
# rework, Cake default-off.
#
# Deliberately NOT included: WPS-capable wpad package. That's reserved
# for a future build tied to the physical mesh button — not started yet.
#
# Build system notes (learned the hard way):
#   - Package manager: APK (not opkg) — pttuan's custom branch
#   - openwrt_one + abt_asr3000 must be disabled in filogic.mk (missing MT7981 BL31/uboot)
#   - Z8803BE image assembly bug: sysupgrade-tar/Image/Build silently skipped
#     → use manual assembly with sysupgrade-tar.sh after make completes
#   - sysupgrade: use -n -F flags (no config preserve, force non-verified image)
#   - ZBT-8803 is NOT in official OpenWRT — source must be pttuan/openwrt fork
#   - pttuan commit: fce4731b5c3323ad3652643d64bf0f78e51293b0

set -e

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

FIRMWARE_BUILD="/mnt/d/Rocket-Routers-Website/firmware-build"
OPENWRT_SRC="$HOME/src/openwrt"
VERSION="3.11.14"

echo -e "${BOLD}Mycelium Mesh RocketRouters v${VERSION} — Build Script${RESET}"
echo "=================================================="

# ── 1. Sanity checks ──────────────────────────────────────────────────────────
echo -e "\n${BOLD}[1/8] Checking build environment...${RESET}"

if [ ! -d "$OPENWRT_SRC" ]; then
    echo -e "${RED}ERROR: OpenWrt source not found at $OPENWRT_SRC${RESET}"
    echo ""
    echo "First-time setup:"
    echo "  git clone https://github.com/pttuan/openwrt.git ~/src/openwrt"
    echo "  cd ~/src/openwrt"
    echo "  echo 'src-git qmodem https://github.com/FUjr/QModem.git' >> feeds.conf.default"
    echo "  ./scripts/feeds update -a"
    echo "  ./scripts/feeds install -a"
    exit 1
fi

if [ ! -f "$FIRMWARE_BUILD/97-rocket-modem" ]; then
    echo -e "${RED}ERROR: firmware-build folder not accessible at $FIRMWARE_BUILD${RESET}"
    echo "Check D: drive is mounted in WSL: ls /mnt/d/"
    exit 1
fi

if [ ! -f "$FIRMWARE_BUILD/rocket-dashboard.cgi" ]; then
    echo -e "${RED}ERROR: rocket-dashboard.cgi not found in $FIRMWARE_BUILD${RESET}"
    exit 1
fi

echo -e "${GREEN}OK — source tree found: $OPENWRT_SRC${RESET}"
cd "$OPENWRT_SRC"
echo "Branch: $(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD)"
echo "Last commit: $(git log --oneline -1)"

# Verify this is pttuan's fork (has ZBT-8803 support)
if ! git log --oneline | grep -q "zbt8803\|zbt-z8803\|ZBT"; then
    echo -e "${YELLOW}WARN: Could not confirm ZBT-8803 commit in git log.${RESET}"
    echo "Expected pttuan/openwrt fork. Check: git log --oneline | grep -i zbt"
fi

# ── 2. Strip Windows paths from WSL PATH ──────────────────────────────────────
echo -e "\n${BOLD}[2/8] Cleaning WSL PATH and disabling broken devices in filogic.mk...${RESET}"
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/[c-z]' | tr '\n' ':' | sed 's/:$//')
echo "  PATH cleaned (Windows /mnt/[c-z] entries stripped)"

FILOGIC="target/linux/mediatek/image/filogic.mk"
BROKEN_DEVICES="openwrt_one abt_asr3000"
for DEV in $BROKEN_DEVICES; do
    if grep -q "^TARGET_DEVICES += ${DEV}" "$FILOGIC" 2>/dev/null; then
        sed -i "s/^TARGET_DEVICES += ${DEV}/#TARGET_DEVICES += ${DEV}/" "$FILOGIC"
        echo -e "  ${YELLOW}Disabled: $DEV${RESET}"
    else
        echo -e "  ${GREEN}Already disabled: $DEV${RESET}"
    fi
done

# ── 3. Stage uci-defaults files ───────────────────────────────────────────────
echo -e "\n${BOLD}[3/8] Staging uci-defaults...${RESET}"
mkdir -p files/etc/uci-defaults

SCRIPTS=(
    "92-rocket-pin-modem"
    "93-rocket-iperf3"
    "93b-rocket-upnpd"
    "93c-rocket-vnstat"
    "94-rocket-mesh"
    "94b-rocket-sim-check"
    "95-rocket-topology-c"
    "95c-rocket-wireguard"
    "96-rocket-leds"
    "96-rocket-yggdrasil"
    "97-rocket-blocklist"
    "97-rocket-modem"
    "98-rocket-branding"
    "98-rocket-memory"
    "96-rocket-dns"
    "98-rocket-wifi"
    "99-rocket-mwan3"
)

for SCRIPT in "${SCRIPTS[@]}"; do
    SRC="$FIRMWARE_BUILD/$SCRIPT"
    if [ -f "$SRC" ]; then
        cp "$SRC" "files/etc/uci-defaults/$SCRIPT"
        echo "  staged: $SCRIPT"
    else
        echo -e "  ${YELLOW}SKIP (not found): $SCRIPT${RESET}"
    fi
done

chmod +x files/etc/uci-defaults/9*
echo -e "${GREEN}uci-defaults staged${RESET}"

# Version banner placeholder stamping (carried forward) — keeps
# /etc/rocket-routers-version and the branding system description
# matching whatever VERSION this script actually builds, build to build.
sed -i "s/__ROCKET_FW_VERSION__/${VERSION}/g" "files/etc/uci-defaults/99-rocket-mwan3"
sed -i "s/__ROCKET_FW_VERSION__/${VERSION}/g" "files/etc/uci-defaults/98-rocket-branding"
echo -e "${GREEN}version banner stamped (v${VERSION})${RESET}"

# Gate file for 99-rocket-mwan3: presence activates mwan3 load-balance/failover.
# Without this, the script silently exits in cell-only mode and the dual-WAN
# SQM seeding never runs, regardless of modem count. This is the universal
# Plus/Pro/Supreme image, so always stage it.
echo "Mycelium Mesh RocketRouters - mwan3 load-balance/failover enabled" > files/etc/rocket-mwan3-enable
echo -e "${GREEN}mwan3-enable gate file staged${RESET}"

# ── 4. Stage hotplug scripts ──────────────────────────────────────────────────
echo -e "\n${BOLD}[4/8] Staging hotplug scripts...${RESET}"

mkdir -p files/etc/hotplug.d/usb
mkdir -p files/etc/hotplug.d/net
mkdir -p files/etc/hotplug.d/block
mkdir -p files/etc/hotplug.d/button

if [ -f "$FIRMWARE_BUILD/hotplug-usb-20-quectel-smarty-apn" ]; then
    cp "$FIRMWARE_BUILD/hotplug-usb-20-quectel-smarty-apn" \
       "files/etc/hotplug.d/usb/20-quectel-smarty-apn"
    chmod +x "files/etc/hotplug.d/usb/20-quectel-smarty-apn"
    echo "  staged: hotplug.d/usb/20-quectel-smarty-apn"
else
    echo -e "  ${RED}ERROR: hotplug-usb-20-quectel-smarty-apn not found!${RESET}"
    exit 1
fi

if [ -f "$FIRMWARE_BUILD/hotplug-net-30-wwan-up" ]; then
    cp "$FIRMWARE_BUILD/hotplug-net-30-wwan-up" \
       "files/etc/hotplug.d/net/30-wwan-up"
    chmod +x "files/etc/hotplug.d/net/30-wwan-up"
    echo "  staged: hotplug.d/net/30-wwan-up"
else
    echo -e "  ${RED}ERROR: hotplug-net-30-wwan-up not found!${RESET}"
    exit 1
fi

# 31-wwan2-up: auto ifup wwan2 when usb1 appears (second modem). Carried
# forward unchanged — companion to 30-wwan-up, needed since wwan2 is a real
# dhcp interface instead of the dead modemmanager proto. Only fires/matters
# on dual-modem (Supreme) units; harmless no-op on single-modem units.
if [ -f "$FIRMWARE_BUILD/hotplug-net-31-wwan2-up" ]; then
    cp "$FIRMWARE_BUILD/hotplug-net-31-wwan2-up" \
       "files/etc/hotplug.d/net/31-wwan2-up"
    chmod +x "files/etc/hotplug.d/net/31-wwan2-up"
    echo "  staged: hotplug.d/net/31-wwan2-up"
else
    echo -e "  ${RED}ERROR: hotplug-net-31-wwan2-up not found!${RESET}"
    exit 1
fi

if [ -f "$FIRMWARE_BUILD/hotplug-block-30-ssd-mount" ]; then
    cp "$FIRMWARE_BUILD/hotplug-block-30-ssd-mount" \
       "files/etc/hotplug.d/block/30-ssd-mount"
    chmod +x "files/etc/hotplug.d/block/30-ssd-mount"
    echo "  staged: hotplug.d/block/30-ssd-mount"
else
    echo -e "  ${RED}ERROR: hotplug-block-30-ssd-mount not found!${RESET}"
    exit 1
fi

# 00-mesh-wps: case "MESH" button (internally GPIO key "wps") - hold 2-8s
# toggles local 802.11s mesh, >=8s reserved (logged-only) for future WPS.
# NOTE: still just a logged reservation in this build — no actual
# WPS-capable wpad package staged. That's a separate, not-yet-started task.
if [ -f "$FIRMWARE_BUILD/hotplug-button-00-mesh-wps" ]; then
    cp "$FIRMWARE_BUILD/hotplug-button-00-mesh-wps" \
       "files/etc/hotplug.d/button/00-mesh-wps"
    chmod +x "files/etc/hotplug.d/button/00-mesh-wps"
    echo "  staged: hotplug.d/button/00-mesh-wps"
else
    echo -e "  ${RED}ERROR: hotplug-button-00-mesh-wps not found!${RESET}"
    exit 1
fi

# 98-fix-modem: removes dead usb0 route + ensures DNS when 4_1 modem comes up
mkdir -p files/etc/hotplug.d/iface
if [ -f "$FIRMWARE_BUILD/98-fix-modem" ]; then
    cp "$FIRMWARE_BUILD/98-fix-modem" \
       "files/etc/hotplug.d/iface/98-fix-modem"
    chmod +x "files/etc/hotplug.d/iface/98-fix-modem"
    echo "  staged: hotplug.d/iface/98-fix-modem"
else
    echo -e "  ${RED}WARNING: 98-fix-modem not found — skipping${RESET}"
fi

echo -e "${GREEN}Hotplug scripts staged${RESET}"

# ── 5. Stage supporting files ─────────────────────────────────────────────────
echo -e "\n${BOLD}[5/8] Staging supporting files...${RESET}"

if [ -f "$FIRMWARE_BUILD/rocket-wg-showconf" ]; then
    mkdir -p files/usr/bin
    cp "$FIRMWARE_BUILD/rocket-wg-showconf" files/usr/bin/rocket-wg-showconf
    chmod +x files/usr/bin/rocket-wg-showconf
    echo "  staged: rocket-wg-showconf"
fi

# Rocket Dashboard — CGI + LuCI menu entry + LuCI view
# No dashboard changes in THIS build — carries forward v3.11.11's fix
# (mycelium-build badge fallback uses __ROCKET_FW_VERSION__ instead of a
# stale hardcoded "3.10.1") unchanged. Still sed-stamp it here, same as
# 99-rocket-mwan3 and 98-rocket-branding above, so the staged copy carries
# the real v3.11.14, not the literal placeholder.
if [ -f "$FIRMWARE_BUILD/rocket-dashboard.cgi" ]; then
    mkdir -p files/www/cgi-bin
    cp "$FIRMWARE_BUILD/rocket-dashboard.cgi" files/www/cgi-bin/rocket
    sed -i "s/__ROCKET_FW_VERSION__/${VERSION}/g" files/www/cgi-bin/rocket
    chmod +x files/www/cgi-bin/rocket
    CGI_SIZE=$(wc -c < "$FIRMWARE_BUILD/rocket-dashboard.cgi")
    CGI_LINES=$(wc -l < "$FIRMWARE_BUILD/rocket-dashboard.cgi")
    echo "  staged: www/cgi-bin/rocket (${CGI_SIZE} bytes, ${CGI_LINES} lines, mycelium-version stamped v${VERSION})"
else
    echo -e "  ${RED}ERROR: rocket-dashboard.cgi not found!${RESET}"
    exit 1
fi

# Stage d3.min.js for topology map (bundled = no CDN dependency)
mkdir -p files/www
if [ -f "$FIRMWARE_BUILD/d3.min.js" ]; then
    cp "$FIRMWARE_BUILD/d3.min.js" files/www/d3.min.js
    echo "  staged: d3.min.js ($(wc -c < $FIRMWARE_BUILD/d3.min.js) bytes)"
else
    echo -e "  ${YELLOW}WARN: d3.min.js not found — topology map will lack D3${RESET}"
fi

if [ -f "$FIRMWARE_BUILD/rocket-dashboard-menu.json" ]; then
    mkdir -p files/usr/share/luci/menu.d
    cp "$FIRMWARE_BUILD/rocket-dashboard-menu.json" files/usr/share/luci/menu.d/rocket-dashboard.json
    echo "  staged: luci menu entry"
fi

if [ -f "$FIRMWARE_BUILD/rocket-dashboard-view.js" ]; then
    mkdir -p files/www/luci-static/resources/view/rocket
    cp "$FIRMWARE_BUILD/rocket-dashboard-view.js" \
       files/www/luci-static/resources/view/rocket/overview.js
    echo "  staged: luci view: rocket/overview"
fi

if [ -f "$FIRMWARE_BUILD/rocket-index.html" ]; then
    cp "$FIRMWARE_BUILD/rocket-index.html" files/www/index.html
    echo "  staged: www/index.html (root redirect → /cgi-bin/rocket)"
else
    echo -e "  ${YELLOW}SKIP: rocket-index.html not found${RESET}"
fi

# Custom SSH login banner (replaces OpenWrt default)
if [ -f "$FIRMWARE_BUILD/banner" ]; then
    sed "s/__ROCKET_VERSION__/${VERSION}/g" "$FIRMWARE_BUILD/banner" > files/etc/banner
    echo "  staged: etc/banner (Rocket Routers branding, v${VERSION})"
else
    echo -e "  ${YELLOW}SKIP: banner not found${RESET}"
fi

# conduit + cloudflared procd init scripts
mkdir -p files/etc/init.d

if [ -f "$FIRMWARE_BUILD/init-conduit" ]; then
    cp "$FIRMWARE_BUILD/init-conduit" files/etc/init.d/conduit
    chmod +x files/etc/init.d/conduit
    echo "  staged: etc/init.d/conduit (Matrix homeserver)"
else
    echo -e "  ${RED}ERROR: init-conduit not found!${RESET}"
    exit 1
fi

if [ -f "$FIRMWARE_BUILD/init-cloudflared" ]; then
    cp "$FIRMWARE_BUILD/init-cloudflared" files/etc/init.d/cloudflared
    chmod +x files/etc/init.d/cloudflared
    echo "  staged: etc/init.d/cloudflared (Cloudflare Tunnel)"
else
    echo -e "  ${RED}ERROR: init-cloudflared not found!${RESET}"
    exit 1
fi

echo -e "${GREEN}Supporting files staged${RESET}"

# ── 6. Update version metadata ────────────────────────────────────────────────
echo -e "\n${BOLD}[6/8] Setting version to v${VERSION}...${RESET}"

METADATA="$FIRMWARE_BUILD/rocket-vE-v${VERSION}-metadata.config"
if [ ! -f "$METADATA" ]; then
    echo -e "${RED}ERROR: $METADATA not found${RESET}"
    exit 1
fi

sed -i '/^CONFIG_VERSION_/d' .config
cat "$METADATA" >> .config

echo -e "${GREEN}Version metadata set: Mycelium Mesh RocketRouters Plus v${VERSION}${RESET}"
grep "CONFIG_VERSION_NUMBER" .config

# ── 6b. Append rocket-vE.config packages ─────────────────────────────────────
echo -e "\n${BOLD}[6b/8] Appending rocket-vE.config packages...${RESET}"
if [ -f "$FIRMWARE_BUILD/rocket-vE.config" ]; then
    grep -v "^CONFIG_VERSION_" "$FIRMWARE_BUILD/rocket-vE.config" | \
    grep -v "^#" | grep -v "^$" >> .config || true
    echo -e "${GREEN}rocket-vE.config packages appended${RESET}"
else
    echo -e "${YELLOW}WARN: rocket-vE.config not found — skipping${RESET}"
fi

for PKG in sms-tool uhttpd luci luci-base luci-theme-bootstrap; do
    if ! grep -q "CONFIG_PACKAGE_${PKG}=y" .config; then
        echo "CONFIG_PACKAGE_${PKG}=y" >> .config
        echo -e "  ${YELLOW}added missing: CONFIG_PACKAGE_${PKG}=y${RESET}"
    fi
done

make defconfig 2>&1 | tail -5
echo -e "${GREEN}defconfig done${RESET}"

# ── 7. Clean base-files and build ─────────────────────────────────────────────
echo -e "\n${BOLD}[7/8] Building firmware (get a brew — this takes a while)...${RESET}"
echo "Cores available: $(nproc)"
echo "Started: $(date)"

make package/base-files/clean V=s 2>&1 | tail -3

make -j$(nproc) V=s 2>&1 | tee /tmp/rocket-build-v${VERSION}.log | \
    grep --line-buffered -E "(ERROR|WARNING|Building|Compiling|Linking|Install|time:)"

BUILD_EXIT=${PIPESTATUS[0]}
echo "Finished: $(date)"

if [ $BUILD_EXIT -ne 0 ]; then
    echo -e "\n${RED}BUILD FAILED (exit code $BUILD_EXIT)${RESET}"
    echo "Full log: /tmp/rocket-build-v${VERSION}.log"
    tail -30 /tmp/rocket-build-v${VERSION}.log
    exit 1
fi

# ── 8. Manual image assembly (Z8803BE build system bug) ───────────────────────
echo -e "\n${BOLD}[8/8] Manual sysupgrade image assembly...${RESET}"

BUILD_LINUX="$OPENWRT_SRC/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic"
KERNEL="${BUILD_LINUX}/zbtlink_zbt-z8803be-kernel.bin"
ROOTFS="${BUILD_LINUX}/root.squashfs"

if [ ! -f "$KERNEL" ]; then
    echo -e "${RED}ERROR: kernel not found: $KERNEL${RESET}"
    echo "Searching for z8803 kernel..."
    find "$BUILD_LINUX" -name "*z8803*" 2>/dev/null
    exit 1
fi

if [ ! -f "$ROOTFS" ]; then
    echo -e "${RED}ERROR: rootfs not found: $ROOTFS${RESET}"
    exit 1
fi

SYSUPGRADE_BIN="/tmp/rocket-firmware-E-v${VERSION}-sysupgrade.bin"

TOPDIR="$OPENWRT_SRC" \
    "$OPENWRT_SRC/scripts/sysupgrade-tar.sh" \
    --board "zbtlink,zbt-z8803be" \
    --kernel "$KERNEL" \
    --rootfs "$ROOTFS" \
    "$SYSUPGRADE_BIN"

if [ ! -f "$SYSUPGRADE_BIN" ]; then
    echo -e "${RED}ERROR: sysupgrade-tar.sh did not produce output${RESET}"
    exit 1
fi

BIN_SIZE=$(du -sh "$SYSUPGRADE_BIN" | cut -f1)
BIN_DEST="/mnt/d/Rocket-Routers-Website/firmware-build/rocket-firmware-E-v${VERSION}.bin"
cp "$SYSUPGRADE_BIN" "$BIN_DEST"

echo -e "${GREEN}${BOLD}"
echo "=================================================="
echo " BUILD COMPLETE — Mycelium Mesh RocketRouters Plus v${VERSION}"
echo "=================================================="
echo -e "${RESET}"
echo "  Binary: $BIN_DEST"
echo "  Size:   $BIN_SIZE"
echo "  Log:    /tmp/rocket-build-v${VERSION}.log"
echo ""
echo -e "${BOLD}Transfer to router (direct cable):${RESET}"
echo "  scp $BIN_DEST root@192.168.1.1:/tmp/"
echo ""
echo -e "${BOLD}Flash from router SSH:${RESET}"
echo "  sysupgrade -n -F /tmp/rocket-firmware-E-v${VERSION}.bin"
echo ""
echo -e "${BOLD}Post-flash verification — THE thing this build exists to test:${RESET}"
echo "  # Give it a good 2-3 minutes after boot before checking — the SIM"
echo "  # check now deliberately waits longer (up to ~2 minutes worst case)"
echo "  # for at_port to actually populate before it does anything."
echo "  uptime"
echo "  cat /etc/rocket-routers-version"
echo "  # Confirm the SIM check actually ran and did the right thing this time:"
echo "  logread | grep rocket-sim-check"
echo "  uci show qmodem | grep -E 'state|enable_dial'"
echo "  # Re-check earlier fixes are still intact (no regressions):"
echo "  uci show sqm | grep enabled"
echo "  ubus call network.interface.wwan2 status"
echo "  uci show mwan3 | grep -E 'policy|member|interface'"
echo "  ping -c3 8.8.8.8"
echo ""
echo -e "${YELLOW}${BOLD}NOTE:${RESET} 'logread | grep rocket-sim-check' should NOT be empty"
echo "this time. The modem WITHOUT a SIM should log 'no SIM inserted -"
echo "disabling modem' and qmodem.<that-section>.state should read"
echo "'disabled'. The modem WITH a SIM should log 'SIM ready - ensuring"
echo "modem enabled' and dial/connect normally. If logread is STILL empty"
echo "after a few minutes, that's new information, not the same bug —"
echo "report it and we dig into why the script itself isn't firing at all."
echo "If the reboot loop is gone on repeated warm reboots, this fix holds."
