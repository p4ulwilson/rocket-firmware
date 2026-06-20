# Rocket Routers — Permanent Firmware Fixes v3.2.0

**Written:** 2026-05-14  
**Board:** ZBT-Z8803BE (MediaTek MT7988A / Filogic 880)  
**Firmware base:** https://github.com/pttuan/openwrt — `main` branch (ZBT Z8803BE support)  
**Modem:** Quectel RM500U-EA (Qualcomm X55, 5G Sub-6GHz)  
**SIM:** Smarty (Three UK), APN: three.co.uk  
**Current firmware:** Rocket E v3.1.0 (Mycelium)

---

## The Agreement

Every issue in this document has been diagnosed and fixed live at least once. That stops now.  
These fixes go into the firmware build. They run at first boot. They never break again.

---

## Issue 1 — APN Blank After Modem Reset

### What breaks
After a modem power cycle, USB reconnect, or `AT+CFUN=0/1` soft reset, the cellular data
connection drops. The modem shows registered on Three's network but no data flows.
Ping to 8.8.8.8 fails. `AT+CGDCONT?` shows a blank APN.

### Root cause
`97-rocket-modem` sets `AT+QCFG="autoapn",1` expecting the modem to detect the APN from
the SIM. Quectel's autoapn works for major global carriers with properly coded SIMs.
**Smarty on Three UK is an MVNO.** The SIM doesn't carry the APN in its service table.
autoapn returns nothing. The modem dials with a blank APN. No data session opens.

Additionally, `AT+CGDCONT` values are runtime-only on the RM500U-EA — they are NOT saved
to NV memory and are lost on every USB re-enumeration / soft reset.

### The fix
Two layers:

**Layer 1 — uci-defaults (runs once on firmware flash):**  
`autoapn=1` is kept — the firmware works plug-and-play with any SIM. `AT+CGDCONT` is
added alongside it, explicitly setting `three.co.uk` as a fallback for Smarty/Three.
On Three SIMs autoapn fails silently → modem uses the explicit APN. On other carrier
SIMs autoapn succeeds → modem uses the auto-detected APN instead.

**Layer 2 — hotplug script (runs every boot, every USB reconnect):**  
Deploy `/etc/hotplug.d/usb/20-quectel-smarty-apn` which fires when the RM500U-EA USB
device appears (`2c7c:0900`). It waits for `/dev/ttyUSB2` to settle then re-applies
`three.co.uk` via AT command. This ensures the APN survives modem power cycles,
firmware updates, USB glitches — everything.

### Files changed
- `97-rocket-modem` — add autoapn disable + AT+CGDCONT in setup block
- New hotplug script deployed by `97-rocket-modem`

### Test command
```sh
# After flash and first boot:
sms_tool -d /dev/ttyUSB2 at 'AT+CGDCONT?'
# Expected: +CGDCONT: 1,"IPV4V6","three.co.uk",...

# Simulate modem reset:
sms_tool -d /dev/ttyUSB2 at 'AT+CFUN=0'
sleep 5
sms_tool -d /dev/ttyUSB2 at 'AT+CFUN=1'
sleep 15
ping -c 3 8.8.8.8
# Expected: 3 replies
```

---

## Issue 2 — Yggdrasil Address Changes on Every Reboot

### What breaks
The router's Yggdrasil IPv6 address changes after every reboot. The Claude memory node
is unreachable because the address used in the MCP server config points to the old address.
Any Yggdrasil-based services (memory, mesh routing) break silently.

### Root cause
`/lib/netifd/proto/yggdrasil.sh` manages Yggdrasil as a netifd protocol. On
`setup_interface()` it reads UCI `network.ygg0.private_key`. If that value is **empty**,
it generates a brand-new keypair on the spot. The new key = new address.

`96-rocket-yggdrasil` (uci-defaults) generates `/etc/yggdrasil/yggdrasil.conf` on first
boot with a fresh keypair, and sets `network.ygg0.config_path` in UCI — but it never
extracts the private key and saves it to UCI `network.ygg0.private_key`. So the proto
script always sees an empty private_key and always generates a new one.

The conf file has the right key. UCI doesn't. Proto script ignores the conf file for key
material and uses UCI exclusively.

### The fix
Two layers:

**Layer 1 — uci-defaults update:**  
After generating `yggdrasil.conf` in `96-rocket-yggdrasil`, immediately extract the
`PrivateKey` field and save it to `network.ygg0.private_key` in UCI.

**Layer 2 — init.d persist script:**  
Deploy `/etc/init.d/rocket-ygg-persist` as a procd service with `start_order 19`
(before netifd at 20). On every boot, it reads the private key from the conf file and
writes it to UCI if they don't already match. This catches edge cases — firmware updates
that regenerate conf, manual key rotation, etc.

### Files changed
- `96-rocket-yggdrasil` — extract private key to UCI after keygen
- New `/etc/init.d/rocket-ygg-persist` deployed by `96-rocket-yggdrasil`

### Test command
```sh
# After first reboot:
YGG_ADDR=$(ip -6 addr show dev ygg0 2>/dev/null | grep "inet6 2" | awk '{print $2}' | cut -d/ -f1)
echo "Yggdrasil address: $YGG_ADDR"

# After second reboot — address must be identical:
ip -6 addr show dev ygg0 | grep "inet6 2"

# Verify UCI has private key:
uci get network.ygg0.private_key | wc -c
# Expected: 65 (64 hex chars + newline)

# Verify key matches conf:
UCI_KEY=$(uci get network.ygg0.private_key)
CONF_KEY=$(grep '"PrivateKey"' /etc/yggdrasil/yggdrasil.conf | sed 's/.*"\([0-9a-f]*\)".*/\1/')
[ "$UCI_KEY" = "$CONF_KEY" ] && echo "KEYS MATCH" || echo "MISMATCH — FIX FAILED"
```

---

## Issue 3 — fw4 Masquerade Not Applied to usb0

### What breaks
After modem connects on usb0 (NCM mode), LAN clients can't reach the internet. Packets
go into the router but don't exit via usb0. `tcpdump` shows packets arriving at usb0
but no return traffic. Source IP on egress is the router's internal LAN IP, not the
modem's IP — NAT isn't running.

### Root cause
`97-rocket-modem` adds `wwan` to the WAN firewall zone (`firewall.@zone[1].network`).
On Z8803BE the zone index may not be `[1]` — it depends on what other zones are defined
before the WAN zone in the UCI config. If the index is wrong, wwan gets added to the
wrong zone (or not added at all), and masquerade never applies to usb0 traffic.

### The fix
Stop relying on zone index. Use `uci show firewall | grep` to find the WAN zone by name,
then add wwan to it. Fallback: if no named zone found, create an explicit masquerade rule
in nftables via `/etc/nftables.d/`.

### Files changed
- `97-rocket-modem` — replace `@zone[1]` with name-based zone lookup

### Test command
```sh
# Verify wwan is in wan zone:
uci show firewall | grep wan
# Must show: firewall.@zone[X].network contains 'wwan'

# Verify masquerade rule in nftables:
nft list table inet fw4 | grep -A2 "postrouting"
# Must show masquerade rule for oifname usb0 or wwan zone

# End-to-end:
ping -c 3 8.8.8.8
```

---

## Issue 4 — opkg vs APK

### What breaks
Firmware uses a custom build from https://github.com/pttuan/openwrt/commits/zbt8803_25.12/
which has transitioned to APK package manager. Any script or documentation that uses
`opkg install` will fail silently or with "command not found".

### Root cause
Standard OpenWrt still ships with opkg. This custom branch ships with APK. They are not
compatible. APK syntax: `apk update && apk add <package>`.

### The fix
All scripts and documentation use APK. No opkg references anywhere in the firmware build.

### Reference
```sh
# Correct:
apk update
apk add python3

# Wrong (will fail on this firmware):
opkg update
opkg install python3
```

---

## Issue 5 — Modem USB Mode (NCM vs QMI)

### Status: NCM is correct for this board

Attempts were made to switch the RM500U-EA to QMI mode (`AT+QCFG="usbnet",0`) because QMI
provides better signal stats and carrier management. The modem accepted the command but
`cdc-wdm0` never appeared after USB re-enumeration on the Z8803BE. QMI mode requires
`kmod-usb-net-qmi-wwan` and proper USB device matching.

**Decision:** Keep NCM mode (`usbnet=5`). It works. `usb0` appears reliably. DHCP gets
an IP. Data flows. NCM is the correct mode for this board/firmware combination until QMI
kernel module support is verified.

Do not switch to QMI without:
1. Confirming `kmod-usb-net-qmi-wwan` is in the build
2. Confirming `cdc-wdm0` appears after USB enumeration
3. Testing that `uqmi` or `qmicli` can open the device

---

## Build Instructions for v3.2.0

### Updated files
```
firmware-build/
  96-rocket-yggdrasil    (updated — keypair persistence)
  97-rocket-modem        (updated — APN fix + hotplug script)
  PERMANENT-FIXES-v3.2.md (this file)
```

### Staging the build
```sh
cd ~/src/openwrt

# Update version metadata
sed -i '/^CONFIG_VERSION_/d' .config
# Edit rocket-vE-v3.2.0-metadata.config (create from v3.1.0 template, bump number)
cat /mnt/d/Rocket-Routers-Website/firmware-build/rocket-vE-v3.2.0-metadata.config >> .config

# Stage uci-defaults
mkdir -p files/etc/uci-defaults
cp /mnt/d/Rocket-Routers-Website/firmware-build/92-rocket-pin-modem    files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/93-rocket-iperf3        files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/93b-rocket-upnpd        files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/94-rocket-mesh          files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/95-rocket-topology-c    files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/95c-rocket-wireguard    files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/96-rocket-leds          files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/96-rocket-yggdrasil     files/etc/uci-defaults/  # UPDATED
cp /mnt/d/Rocket-Routers-Website/firmware-build/97-rocket-blocklist     files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/97-rocket-modem         files/etc/uci-defaults/  # UPDATED
cp /mnt/d/Rocket-Routers-Website/firmware-build/98-rocket-memory        files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/98-rocket-wifi          files/etc/uci-defaults/
cp /mnt/d/Rocket-Routers-Website/firmware-build/99-rocket-mwan3         files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/9*

make defconfig
make package/base-files/clean
make -j$(nproc)
```

### Version metadata
Create `rocket-vE-v3.2.0-metadata.config`:
```
CONFIG_VERSION_NUMBER="3.2.0"
CONFIG_VERSION_CODE="rocket-E-mycelium"
# (all other fields same as v3.1.0)
```

### Post-flash verification checklist
```sh
# 1. APN set correctly
sms_tool -d /dev/ttyUSB2 at 'AT+CGDCONT?'
# → three.co.uk

# 2. Internet works
ping -c 3 8.8.8.8
# → 3 replies

# 3. Yggdrasil address stable
ip -6 addr show dev ygg0 | grep "inet6 2"
# → same address across reboots

# 4. UCI private key present
uci get network.ygg0.private_key | wc -c
# → 65

# 5. Masquerade active
nft list table inet fw4 | grep masquerade
# → at least one masquerade rule

# 6. Memory node responding
curl -s "http://[YGG_ADDR]:8765/cgi-bin/rocket-memory?action=stats"
# → JSON with node info

# 7. Firmware version
cat /etc/openwrt_release | grep VERSION
# → 3.2.0
```

---

## Notes for Future Sessions

- **APK, not opkg.** Always. Write it in every script comment.
- **NCM mode (usbnet=5), not QMI.** Works on Z8803BE. Don't change without full QMI verification.
- **Three/Smarty APN = three.co.uk.** autoapn doesn't work for MVNOs. Always explicit.
- **Yggdrasil private key lives in UCI network.ygg0.private_key.** The conf file is for Peers/Listen only.
- **fw4, not iptables.** This firmware uses nftables. iptables commands will appear to work on some kernels but the rules get overwritten by fw4 on restart.
- **Z8803BE flash:** sysupgrade -n (no config preserve on major version bumps), sysupgrade without -n for patches.
- **Memory store:** /etc/rocket/memory/store.json on overlayfs. Persistent across reboots. Not lost on sysupgrade without -n.
- **pttuan's repo:** https://github.com/pttuan/openwrt/commits/zbt8803_25.12/ — custom ZBT branch with APK and Z8803BE patches.
- **OneB1t research:** https://github.com/OneB1t/Z8803BE-research — hardware research. Note: stock ZBT firmware had "Tunnel Back Home (backdoor?)" in findings. Verify custom build doesn't include it.

---

## Issue 6 — WRONG CGI FILE BEING UPDATED (ROOT CAUSE OF "CHANGES NOT APPEARING") — CONFIRMED 2026-06-10

### What breaks
After SCPing rocket-dashboard.cgi to the router and doing a hard refresh, dashboard shows no changes.
md5sum on router matches local file — but behaviour is still old. Spent many sessions in circles over this.

### Root cause
Two completely different files exist on the router:
- `/www/cgi-bin/rocket` — what uhttpd ACTUALLY serves (cgi_prefix='/cgi-bin' in /etc/config/uhttpd)
- `/www/rocket-dashboard.cgi` — a stale workspace copy. Nothing reads this file. Ever.

Previous sessions SCPed to `/www/rocket-dashboard.cgi` by mistake. md5sum matched that dead file. Browser kept loading the untouched `/www/cgi-bin/rocket`.

### The fix
Always SCP to the correct path:
```
scp /mnt/d/Rocket-Routers-Website/firmware-build/rocket-dashboard.cgi root@192.168.1.1:/www/cgi-bin/rocket
```
Verify with: `md5sum /www/cgi-bin/rocket` on router — must match `md5sum` of local file.

### Rule
NEVER use `/www/rocket-dashboard.cgi` as SCP destination. Ever. For any reason.

---

## Issue 7 — MWAN3 LOSES CONFIG AFTER REBOOT — CONFIRMED 2026-06-10

### What breaks
After router reboot, `mwan3 status` shows "interface wan is disabled", all policies "unreachable".
Load balancing appears broken. Both modems physically working but mwan3 doesn't track them.

### Root cause
mwan3 wizard config reverts to tracking `wan`/`wanb` interface names after reboot.
These names don't exist in the QModem UCI config (actual names are `4_1` and `2_1`).

### The fix (manual, until baked into firmware)
Dashboard → Setup Wizard → click **"Apply Balanced"** after every reboot.
This restores mwan3 tracking: `4_1` (usb0, 50%) and `2_1` (usb1, 50%).

### Future fix
Bake the mwan3 config into a uci-defaults script so it survives reboot without wizard interaction.
