# Firmware C1 Build Handoff — Hidden Hands (WireGuard + Mesh + SFP+ Trunk)

## What C1 is
Firmware C1 is the "Hidden Hands" tier. It is Firmware C (SFP+ LAN trunk, 802.11s WiFi
mesh, cell WAN) with a full WireGuard site-to-site layer added on top.

```
Firmware C  = SFP+ LAN trunk + 802.11s mesh + cell WAN
Firmware C1 = Everything in C + WireGuard (wg0) encrypted site-to-site tunnel
```

Traffic between C1 sites travels inside a WireGuard tunnel over the cell uplink.
From the outside (ISP, landlord, sniffer) — nothing visible. Hidden hands.

---

## Product tier position

| Firmware | Tier           | Key features                                          |
|----------|----------------|-------------------------------------------------------|
| A1       | Home           | Cell uplink, simple plug and play                     |
| B1       | Home power     | Fibre + cell failover                                 |
| C        | Small business | SFP+ LAN trunk, 802.11s WiFi mesh, cell WAN           |
| **C1**   | **Hidden hands** | **C + WireGuard wg0, encrypted site-to-site**       |
| D        | Enterprise     | Multi-router mesh, bonded SIMs                        |
| E        | Mycelium       | Full freedom layer (future)                           |

---

## Status going into this build
- Firmware C v2.5.6 verified: cell WAN live, 802.11s mesh up (rocketmesh7, SAE),
  SFP+ in br-lan (LAN trunk), iperf3, modem pinned, LuCI clean.
- WireGuard packages already in package config (rocket-v2.5.4.config):
  - `kmod-wireguard=y`
  - `wireguard-tools=y`
  - `luci-app-wireguard=y`
- No new packages needed — C1 is config-only on top of C's package set.

---

## New files for C1

| File                          | Destination on router            | Purpose                          |
|-------------------------------|----------------------------------|----------------------------------|
| `95c-rocket-wireguard`        | /etc/uci-defaults/               | Keygen + wg0 + firewall setup    |
| `rocket-wg-showconf`          | /usr/bin/rocket-wg-showconf      | CLI: show key, QR, add peer      |
| `rocket-v2.6.0-metadata.config` | append to .config in openwrt   | Version strings for C1           |

---

## Build commands for Firmware C1 v2.6.0

```sh
cd ~/src/openwrt

# 1. Update version metadata
sed -i '/^CONFIG_VERSION_/d' .config
cat /mnt/d/Rocket-Routers-Website/firmware-build/rocket-v2.6.0-metadata.config >> .config

# 2. Stage uci-defaults (C scripts + new C1 WireGuard script)
mkdir -p files/etc/uci-defaults
mkdir -p files/usr/bin

cp /mnt/d/Rocket-Routers-Website/firmware-build/92-rocket-pin-modem   files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/93-rocket-iperf3       files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/94-rocket-mesh         files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/95-rocket-topology-c   files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/95c-rocket-wireguard   files/etc/uci-defaults/  # ← C1 ONLY
cp /mnt/d/Rocket-Routers-Website/firmware-build/96-rocket-leds         files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/97-rocket-modem        files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/98-rocket-wifi         files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/99-rocket-mwan3        files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/9*

# 3. Stage helper script
cp /mnt/d/Rocket-Routers-Website/firmware-build/rocket-wg-showconf    files/usr/bin/
chmod +x files/usr/bin/rocket-wg-showconf

# 4. Build
make defconfig
make package/base-files/clean
make -j$(nproc)

# 5. Copy output
cp bin/targets/mediatek/filogic/openwrt-*-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin \
   "/mnt/d/Rocket-Routers-Website/MY INFO/_ROUTER IMAGE/rocket plus/Hidden hands → Firmware C1 (SFP+ Fibre + WireGuard + encryption)/rocket-firmware-C1-v2.6.0 rocket plus C1 SFP+ trunk 1 modem + mesh + wireguard.bin"
```

---

## Key design decisions

### Keys generated on first boot — never baked in
Each C1 router generates its own WireGuard keypair on first boot via `wg genkey`.
Keys stored in `/etc/wireguard/` (chmod 700). Public key written to
`/etc/wireguard/publickey.txt` for easy retrieval.

### WireGuard subnet: 10.10.0.0/24
Site-to-site addressing convention:
```
Site A router: 10.10.0.1/24
Site B router: 10.10.0.2/24
Site C router: 10.10.0.3/24
```
Change with: `uci set network.wg0.addresses='10.10.0.X/24' && uci commit network`

### UDP port 51820
Standard WireGuard port. Firewall rule added to allow inbound UDP 51820 from WAN
(cell uplink) so remote peers can reach this router.

### Peer setup is post-flash
No peers baked in. After flashing:
1. `rocket-wg-showconf` — see your public key
2. `rocket-wg-showconf peer` — interactively add a remote site
3. Or use LuCI → Network → WireGuard → Add Peer

---

## Test plan

### Single router
1. Flash C1 v2.6.0
2. `cat /etc/rocket-firmware-variant` → should show "C1 / Hidden Hands" + public key
3. `wg show` → wg0 interface up, listening on UDP 51820
4. `rocket-wg-showconf` → displays public key, port, address
5. `rocket-wg-showconf qr` → QR code renders (needs qrencode installed)

### Two-router site-to-site test
1. Flash two routers with C1 v2.6.0
2. On Router A: `rocket-wg-showconf` — note public key, set address 10.10.0.1/24
3. On Router B: `rocket-wg-showconf` — note public key, set address 10.10.0.2/24
4. On Router A: `rocket-wg-showconf peer` — enter Router B's public key + WAN IP
5. On Router B: `rocket-wg-showconf peer` — enter Router A's public key + WAN IP
6. `ping 10.10.0.2` from Router A shell → should reply
7. `wg show wg0` → shows peer with recent handshake timestamp
8. Client on Site A LAN can ping client on Site B LAN via 10.10.0.x routing

---

## Folder to create for C1 firmware output
```
D:\Rocket-Routers-Website\MY INFO\_ROUTER IMAGE\rocket plus\
  Hidden hands → Firmware C1 (SFP+ Fibre + WireGuard + encryption)\
```

## Output filename convention
```
rocket-firmware-C1-v2.6.0 rocket plus C1 SFP+ trunk 1 modem + mesh + wireguard.bin
```

---

## Open items for next session
- [ ] Build C1 v2.6.0 on bench machine
- [ ] Flash and verify: wg0 up, key generated, firewall rules correct
- [ ] Two-router ping test over WireGuard
- [ ] Consider adding `qrencode` to package config for QR support out of the box
- [ ] Future: auto-key-exchange for Mycelium (Firmware E) — nodes discover and
      trust each other without manual peer setup
