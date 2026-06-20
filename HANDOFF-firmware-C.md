# Firmware C Build Handoff (Topology B — SFP+ as LAN trunk)

## Status going into this session
- Firmware A v2.5.5 verified working on bench:
  - Cell uplink live (Three UK, ping 1.1.1.1 ~60ms)
  - Mesh up on radio1 (rocketmesh7, SAE)
  - Wifi APs broadcasting on radio0/1/2 (rocketrouter7)
  - iperf3 server on port 5201 (LAN-only)
  - Modem at_port pinned to /dev/ttyUSB2 (auto via init.d/rocket-pin-modem)
  - Cellular Network menu removed (luci-proto-modemmanager dropped)
  - /etc/uci-defaults clean after first boot

## Goal: build Firmware C v2.5.5
Same source tree as A v2.5.5 + ADD `95-rocket-topology-c`.
That single script moves eth2 (SFP+) from br-wan to br-lan, making SFP+
the LAN trunk to the customer's fibre-LAN building distribution.
Cell stays primary uplink. No mwan3 gate (cell-only).

## Source files (already staged in /firmware-build/)
- 92-rocket-pin-modem  (uci-defaults)
- 93-rocket-iperf3     (uci-defaults)
- 94-rocket-mesh       (uci-defaults)
- 95-rocket-topology-c (uci-defaults) ← THIS IS C-SPECIFIC
- 96-rocket-leds       (uci-defaults)
- 97-rocket-modem      (uci-defaults)
- 98-rocket-wifi       (uci-defaults)
- 99-rocket-mwan3      (uci-defaults)
- rocket-v2.5.4.config (package selection — same for C)
- rocket-v2.5.5-metadata.config

## Build commands for Firmware C v2.5.5
```sh
cd ~/src/openwrt
sed -i '/^CONFIG_VERSION_/d' .config
cat /mnt/d/Rocket-Routers-Website/firmware-build/rocket-v2.5.5-metadata.config >> .config

# Update CONFIG_VERSION_PRODUCT to "Rocket Plus C" or similar before make
sed -i 's/CONFIG_VERSION_PRODUCT="Rocket Plus"/CONFIG_VERSION_PRODUCT="Rocket Plus C"/' .config
sed -i 's/CONFIG_VERSION_CODE="rocket-A-fibre-cell"/CONFIG_VERSION_CODE="rocket-C-sfp-lan"/' .config

mkdir -p files/etc/uci-defaults
cp /mnt/d/Rocket-Routers-Website/firmware-build/92-rocket-pin-modem  files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/93-rocket-iperf3     files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/94-rocket-mesh       files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/95-rocket-topology-c files/etc/uci-defaults/   # ← C ONLY
cp /mnt/d/Rocket-Routers-Website/firmware-build/96-rocket-leds       files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/97-rocket-modem      files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/98-rocket-wifi       files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/99-rocket-mwan3      files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/9*

make defconfig
make package/base-files/clean
make -j$(nproc)

# Output filename for Firmware C (TBD with Paul - likely):
cp bin/targets/mediatek/filogic/openwrt-*-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin \
   "/mnt/d/Rocket-Routers-Website/MY INFO/_ROUTER IMAGE/rocket plus/openwrt with firber isp topolgy firmware/topology B SFP+ LAN trunk/rocket-firmware-C-v2.5.5 rocket plus topology B SFP+ LAN trunk.bin"
```

## Hardware needed (Paul has)
- 2x SFP+ SR transceivers
- OM4 fibre cables
- 2x Goalake 4-port 2.5G + SFP+ switches

## Test plan
1. Flash C v2.5.5
2. Verify `cat /etc/rocket-firmware-variant` = "C / Topology B: SFP+ = LAN trunk..."
3. Plug SFP+ from router into Goalake switch via OM4 + SR modules
4. Plug laptop into Goalake switch
5. Laptop should DHCP from router on 192.168.1.x range (LAN side, not WAN)
6. Cell uplink still primary, traffic routes via cell
7. Verify `ip link show eth2` is in br-lan, NOT br-wan
8. iperf3 from laptop via Goalake switch to router → ~9.4 Gbit/s on 10G SFP+

## Open items for next session
- Confirm Firmware C output filename naming convention
- Build C v2.5.5
- Bench-test Topology C with Paul's switches
- Optionally: Firmware A "fibre-to-cell-failover" variant (drops /etc/rocket-mwan3-enable into files/) for Plus customers with copper FTTC + cell
- Future: Firmware B (Pro Supreme dual-modem load-balanced)

## Naming convention Paul cares about (DO NOT change)
"rocket-firmware-A-v2.5.X rocket plus fibre to cell for fallover.bin"
For C: filename TBD with Paul on next session.
