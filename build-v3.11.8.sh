#!/bin/bash
# Mycelium Mesh RocketRouters v3.11.8 — WSL Build Script
# Run from WSL: bash /mnt/d/Rocket-Routers-Website/firmware-build/build-v3.11.8.sh
#
# Three fixes in this build, on top of v3.11.7:
#
#   1. Cake/SQM dashboard bug #1 — cake_set looped over EVERY sqm section
#      and force-set .enabled on all of them, so turning Cake on for one
#      WAN (e.g. wwan2) silently flipped fibre/cell_a to enabled=1 too,
#      with download/upload still at 0 — which would throttle those links
#      to nothing the moment they became the active WAN. Fixed to only
#      touch the section actually being edited. Also fixed a false
#      negative in the "running" check: it only waited 1s after `sqm
#      restart` before checking for the cake qdisc; now polls up to 4s.
#
#   2. Cake/SQM dashboard bug #2 — sqm-scripts does a literal
#      /sys/class/net existence check on sqm.<section>.interface; it does
#      NOT resolve UCI logical names (wwan/wwan2) to a real device. The
#      old v3.11.4-era code stored the logical name there on the (wrong)
#      assumption that sqm-scripts/netifd hotplug needed it — live testing
#      proved the opposite: sqm refused to start with "SQM: ERROR: wwan2
#      does currently not exist". cake_set now stores the resolved real
#      device (e.g. usb1) instead. Confirmed live end-to-end through the
#      actual dashboard Cake toggle (not just a manual uci workaround):
#      cake off → all sections enabled:0/running:0; cake on → only the
#      active section shows enabled:1/running:1, with the cake qdisc
#      actually attached and bandwidth applied.
#
#   3. Stale version banner — 99-rocket-mwan3 hardcoded "v2.5.5"/"v2.5.6"
#      into /etc/rocket-routers-version on every first-boot run, so the
#      dashboard banner stayed stuck on an old version number forever
#      regardless of what was actually flashed (confirmed live: box was
#      demonstrably running v3.11.7's mwan3 fix while the banner still
#      said v2.5.5). 99-rocket-mwan3 now writes a __ROCKET_FW_VERSION__
#      placeholder; this build script stamps the real ${VERSION} into it
#      at staging time (see step 3 below), so the banner always matches
#      what's actually running, build to build, with no manual edits
#      needed in 99-rocket-mwan3 itself going forward.
#
# Original v3.11.7 changelog follows unchanged (set -e / uci-delete fix):
#
#   1. Dual-WAN STILL not activating after the v3.11.6 modem-count fix, even
#      though rocket-routers-profile now correctly read "rocket-supreme".
#      Diagnosed live: `ubus call network.interface.wwan2 status` still said
#      "Not found", and `uci show mwan3 | grep -E 'policy|member|interface'`
#      came back completely EMPTY (not even the single-modem sections seen
#      before v3.11.6) — strong evidence the dual-modem branch was being
#      entered but dying partway through, before any uci commit happened.
#      Root cause, found by tracing 99-rocket-mwan3 line by line: the script
#      runs with `set -e` (line 10). Inside the dual-modem branch it does
#      `uci -q delete network.wwan2 2>/dev/null` to clear any stale section
#      before recreating it — but on every first boot network.wwan2 has
#      never existed yet, so `uci delete` returns exit 1 (the -q flag only
#      suppresses the printed error, not the exit code). Under set -e, that
#      silently killed the ENTIRE script right there, before a single
#      mwan3_iface/member/policy call or `uci commit mwan3` ran. This is
#      exactly why MODEM_COUNT/profile detection (which runs earlier, before
#      this line) was correct, while everything after it was empty.
#      A second, identical latent bug was sitting a few lines later: the
#      WAN-zone-by-name probe loop (`for i in 0..9: uci get
#      firewall.@zone[$i].name`) also returns exit 1 once $i runs past the
#      last zone that actually exists — which would have killed the script
#      on the NEXT run, right after the delete fix, since it's the very next
#      thing reached.
#      Both bugs only ever existed in the dual-modem branch of
#      99-rocket-mwan3, and that branch had literally never executed before
#      v3.11.6 (it always took the single-modem path due to the old 30s/
#      break-on-first-modem detection bug) — so neither bug had a chance to
#      surface until now.
#      Fix: added `|| true` to both the `uci -q delete network.wwan2` line
#      and the zone-probe assignment, matching how 97-rocket-modem already
#      handles the identical pattern safely (that script has no `set -e`,
#      so it was never affected).
#
# Carries forward the v3.11.6 modem-count detection fix (60s window, break
# only on count>=2) and the v3.11.5 reboot-loop backgrounding fix unchanged.
# Reminder: the reboot loop itself is STILL OPEN/unconfirmed — watchdog
# theory weakened by evidence, brownout theory proposed but not yet
# investigated. Not touched in this build.
#
# Carries forward all four v3.11.4 fixes unchanged (mwan3 policy names,
# wwan2 dhcp/usb1 rework, cake_status/cake_set device resolution, Cake
# default-off).
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
VERSION="3.11.8"

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

# v3.11.8 fix: 99-rocket-mwan3 used to hardcode "v2.5.5"/"v2.5.6" into
# /etc/rocket-routers-version on every first-boot run, so the dashboard
# banner went stale the moment a new VERSION was built -- it kept showing
# the old number forever regardless of what was actually flashed. The
# script now writes a __ROCKET_FW_VERSION__ placeholder instead; stamp the
# real build version into it here so the banner always matches what's
# actually running.
sed -i "s/__ROCKET_FW_VERSION__/${VERSION}/g" "files/etc/uci-defaults/99-rocket-mwan3"
# Same placeholder/stale-version bug existed in 98-rocket-branding's system
# description (hardcoded "v3.10.1" forever) — stamp it here too.
sed -i "s/__ROCKET_FW_VERSION__/${VERSION}/g" "files/etc/uci-defaults/98-rocket-branding"
echo -e "${GREEN}version banner stamped (v${VERSION})${RESET}"

# Gate file for 99-rocket-mwan3: presence activates mwan3 load-balance/failover.
# Without this, the script silently exits in cell-only mode and the dual-WAN
# SQM seeding (section 7) never runs, regardless of modem count.
# This is the universal Plus/Pro/Supreme image, so always stage it — the
# script's own MODEM_COUNT branching already handles 0/1/2-modem cases.
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
# forward unchanged from v3.11.4 — companion to 30-wwan-up, needed since
# wwan2 is a real dhcp interface instead of the dead modemmanager proto.
# Only fires/matters on dual-modem (Supreme) units; harmless no-op on
# single-modem units since usb1 never appears there.
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
# Left unchanged — once wwan2 directly claims usb1 (mirroring how wwan already
# claims usb0), QModem should stop auto-creating the competing "4_1" interface.
# Kept staged as a safety net regardless.
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
# Carries forward the v3.11.4 cake_status/cake_set logical-vs-real-device fix
# unchanged. No dashboard changes in this build.
if [ -f "$FIRMWARE_BUILD/rocket-dashboard.cgi" ]; then
    mkdir -p files/www/cgi-bin
    cp "$FIRMWARE_BUILD/rocket-dashboard.cgi" files/www/cgi-bin/rocket
    chmod +x files/www/cgi-bin/rocket
    CGI_SIZE=$(wc -c < "$FIRMWARE_BUILD/rocket-dashboard.cgi")
    CGI_LINES=$(wc -l < "$FIRMWARE_BUILD/rocket-dashboard.cgi")
    echo "  staged: www/cgi-bin/rocket (${CGI_SIZE} bytes, ${CGI_LINES} lines)"
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
echo -e "${BOLD}Post-flash verification (SSH after reboot):${RESET}"
echo "  # NOTE: first boot on a dual-modem unit still takes up to ~60s longer"
echo "  # before mwan3/wwan2 finalise — that part is expected, unchanged from v3.11.6."
echo "  uptime"
echo "  cat /etc/rocket-routers-profile"
echo "  # expect: rocket-supreme"
echo "  ubus call network.interface.wwan2 status"
echo "  # expect: real status JSON — NOT \"Not found\" (this is the actual fix in this build)"
echo "  uci show mwan3 | grep -E 'policy|member|interface'"
echo "  # expect: wan_cells policy with wan_m1/wwan_m2/wwan2_m2 members — NOT empty"
echo "  # If this is still empty, grab: logread | grep rocket-uci-defaults"
echo "  # and check whether it stops right after 'Configuring dual-modem"
echo "  # load-balanced failover profile' — that would mean a third latent"
echo "  # set -e trap further down the same branch."
echo "  # Re-check earlier fixes are still intact (no regressions):"
echo "  uci show sqm | grep enabled"
echo "  gsmctl -A 'AT+QCFG=\"usbnet\"'"
echo ""
echo -e "${YELLOW}${BOLD}NOTE:${RESET} the reboot loop is a SEPARATE, still-open issue, not touched"
echo "in this build. If it recurs, that tells us nothing new about this fix —"
echo "watch for it independently and report uptime/dmesg as before."
