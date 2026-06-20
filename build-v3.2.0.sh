#!/bin/bash
# Rocket Routers Firmware E v3.2.0 — WSL Build Script
# Run from WSL: bash /mnt/d/Rocket-Routers-Website/firmware-build/build-v3.2.0.sh
#
# Fixes in this build:
#   - APN permanent fix (three.co.uk + hotplug re-apply on USB connect)
#   - Yggdrasil keypair persistence (address stable across reboots)
#   - Firewall WAN zone by name (not fragile @zone[1] index)
#   - autoapn=1 kept (plug-and-play with any SIM)

set -e

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

FIRMWARE_BUILD="/mnt/d/Rocket-Routers-Website/firmware-build"
OPENWRT_SRC="$HOME/src/openwrt"
VERSION="3.2.0"

echo -e "${BOLD}Rocket Routers Firmware E v${VERSION} — Build Script${RESET}"
echo "=================================================="

# ── 1. Sanity checks ──────────────────────────────────────────────────────────
echo -e "\n${BOLD}[1/7] Checking build environment...${RESET}"

if [ ! -d "$OPENWRT_SRC" ]; then
    echo -e "${RED}ERROR: OpenWrt source not found at $OPENWRT_SRC${RESET}"
    echo "Expected pttuan's OpenWrt fork (main branch, ZBT Z8803BE support)."
    echo "Clone it first:"
    echo "  mkdir -p ~/src && cd ~/src"
    echo "  git clone https://github.com/pttuan/openwrt.git openwrt"
    echo "  cd openwrt && ./scripts/feeds update -a && ./scripts/feeds install -a"
    exit 1
fi

if [ ! -f "$FIRMWARE_BUILD/97-rocket-modem" ]; then
    echo -e "${RED}ERROR: firmware-build folder not accessible at $FIRMWARE_BUILD${RESET}"
    echo "Check D: drive is mounted in WSL: ls /mnt/d/"
    exit 1
fi

echo -e "${GREEN}OK — source tree found: $OPENWRT_SRC${RESET}"

cd "$OPENWRT_SRC"

# Show current branch / last commit
echo "Branch: $(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD)"
echo "Last commit: $(git log --oneline -1)"

# ── 2. Stage uci-defaults files ───────────────────────────────────────────────
echo -e "\n${BOLD}[2/7] Staging uci-defaults...${RESET}"
mkdir -p files/etc/uci-defaults

SCRIPTS=(
    "92-rocket-pin-modem"
    "93-rocket-iperf3"
    "93b-rocket-upnpd"
    "94-rocket-mesh"
    "95-rocket-topology-c"
    "95c-rocket-wireguard"
    "96-rocket-leds"
    "96-rocket-yggdrasil"
    "97-rocket-blocklist"
    "97-rocket-modem"
    "98-rocket-memory"
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

# ── 3. Stage supporting files ─────────────────────────────────────────────────
echo -e "\n${BOLD}[3/7] Staging supporting files...${RESET}"

# Memory CGI script
if [ -f "$FIRMWARE_BUILD/98-rocket-memory" ]; then
    mkdir -p files/www/cgi-bin
    # The CGI script itself is deployed by 98-rocket-memory at runtime
    echo "  memory node: deployed by 98-rocket-memory at first boot"
fi

# rocket-wg-showconf CLI tool
if [ -f "$FIRMWARE_BUILD/rocket-wg-showconf" ]; then
    mkdir -p files/usr/bin
    cp "$FIRMWARE_BUILD/rocket-wg-showconf" files/usr/bin/rocket-wg-showconf
    chmod +x files/usr/bin/rocket-wg-showconf
    echo "  staged: rocket-wg-showconf"
fi

echo -e "${GREEN}Supporting files staged${RESET}"

# ── 4. Update version metadata ────────────────────────────────────────────────
echo -e "\n${BOLD}[4/7] Setting version to E v${VERSION}...${RESET}"

METADATA="$FIRMWARE_BUILD/rocket-vE-v3.2.0-metadata.config"
if [ ! -f "$METADATA" ]; then
    echo -e "${RED}ERROR: $METADATA not found${RESET}"
    exit 1
fi

sed -i '/^CONFIG_VERSION_/d' .config
cat "$METADATA" >> .config
echo -e "${GREEN}Version metadata set: Rocket Plus E v${VERSION}${RESET}"

# Show what version will be baked in
grep "CONFIG_VERSION_" .config | grep -v "^#"

# ── 5. make defconfig ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}[5/7] Running make defconfig...${RESET}"
make defconfig 2>&1 | tail -5
echo -e "${GREEN}defconfig done${RESET}"

# ── 6. Clean base-files and build ─────────────────────────────────────────────
echo -e "\n${BOLD}[6/7] Building firmware (this takes a while, get a brew)...${RESET}"
echo "Cores available: $(nproc)"
echo "Started: $(date)"

make package/base-files/clean V=s 2>&1 | tail -3

# Build with all cores
make -j$(nproc) V=s 2>&1 | tee /tmp/rocket-build-v${VERSION}.log | grep -E "(ERROR|WARNING|Building|Compiling|Linking|Install)" | tail -50

BUILD_EXIT=${PIPESTATUS[0]}
echo "Finished: $(date)"

if [ $BUILD_EXIT -ne 0 ]; then
    echo -e "\n${RED}BUILD FAILED (exit code $BUILD_EXIT)${RESET}"
    echo "Full log: /tmp/rocket-build-v${VERSION}.log"
    echo "Last 30 lines:"
    tail -30 /tmp/rocket-build-v${VERSION}.log
    exit 1
fi

# ── 7. Copy output binary ─────────────────────────────────────────────────────
echo -e "\n${BOLD}[7/7] Copying output binary...${RESET}"

BIN_SRC=$(find bin/targets/mediatek/filogic/ -name "*zbtlink_zbt-z8803be*sysupgrade.bin" 2>/dev/null | head -1)

if [ -z "$BIN_SRC" ]; then
    echo -e "${RED}ERROR: Could not find sysupgrade binary in bin/targets/mediatek/filogic/${RESET}"
    ls bin/targets/mediatek/filogic/*.bin 2>/dev/null || echo "(no .bin files found)"
    exit 1
fi

BIN_SIZE=$(du -sh "$BIN_SRC" | cut -f1)
BIN_DEST="/mnt/d/Rocket-Routers-Website/firmware-build/rocket-firmware-E-v${VERSION}.bin"

cp "$BIN_SRC" "$BIN_DEST"

echo -e "${GREEN}${BOLD}"
echo "=================================================="
echo " BUILD COMPLETE — Rocket Plus E v${VERSION}"
echo "=================================================="
echo -e "${RESET}"
echo "  Binary: $BIN_DEST"
echo "  Size:   $BIN_SIZE"
echo "  Log:    /tmp/rocket-build-v${VERSION}.log"
echo ""
echo -e "${BOLD}Post-flash verification:${RESET}"
echo "  sms_tool -d /dev/ttyUSB2 at 'AT+CGDCONT?'    # → three.co.uk"
echo "  ping -c 3 8.8.8.8                             # → internet works"
echo "  ip -6 addr show dev ygg0 | grep 'inet6 2'     # → stable address"
echo "  uci get network.ygg0.private_key | wc -c      # → 65"
echo ""
echo "Flash command (from router SSH):"
echo "  sysupgrade -n /tmp/rocket-firmware-E-v${VERSION}.bin"
echo ""
