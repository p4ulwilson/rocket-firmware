# Mycelium — Rocket Routers Firmware E

## A community blocklist, signed and verifiable.

Every Mycelium router enforces a community blocklist — cryptographically signed
and automatically applied. Bad actors get isolated from the mesh.

The blocklist is signed with an Ed25519 key kept on the production server, not
in this repository. Routers verify the signature before applying any rules, so a
blocklist update can't be spoofed by anyone who doesn't hold that key.

Rocket Routers is run by Paul, a sole trader — there's no company structure here,
just a published process: the community proposes, the system signs, routers apply.
The router enforces that process, not any one person's say in the moment.

Remove the blocklist script from your firmware? The mesh detects it and stops
routing your traffic. You are not banned by a person. You are rejected by every
other node simultaneously — automatically, cryptographically, permanently.

You cannot bribe a router. You cannot threaten a cryptographic key.
You cannot acquire a network that nobody owns.

**If you are here to harm people — the Mycelium already knows.**

---

## Why we built this

There is an underground network that has existed for over a billion years.
It connects trees, plants and living things across vast distances.
It is self-healing. It has no centre. Nobody owns it.
When part of it is damaged, it routes around the damage and carries on.
It is called Mycelium.

We named our firmware after it because that is exactly what we are building.

---

We live in a world where the tools meant to connect us are used to surveil us.
Where the platforms built for community harvest loneliness.
Where the networks designed for freedom are owned by people who profit from your data,
your behaviour, your fear, and your isolation.

We watched the motto "Don't be evil" get quietly removed.
We watched privacy become a premium feature you pay extra for.
We watched legislation get written by the very corporations it was meant to regulate.
We watched ancient symbols of unity get inverted into symbols of division.

We watched, and then we built something.

---

## What Mycelium is

Mycelium is open source router firmware built on OpenWrt.

It gives you:
- **WireGuard** encrypted tunnels between sites — your traffic is yours
- **Yggdrasil** auto-discovering global mesh — nodes find each other without a central server
- **802.11s WiFi mesh** — buildings connect seamlessly
- **Cell uplink with SFP+ LAN trunk** — fibre distribution with mobile resilience
- **No telemetry. No logging. No calling home.** Ever.

Two routers running Mycelium, anywhere on Earth, will find each other automatically.
No manual setup. No central authority. No single point that can be shut down.

The network grows like mycelium. Each node strengthens the whole.

---

## Who this is for

This is for people who believe privacy is a human right, not a product feature.

For the small business owner who does not want their traffic inspected.
For the family who wants their home network to be their own.
For the community that wants to connect without being monetised.
For the builder who wants to port this to their own hardware and make it better.
For the person who looks at the world and thinks — there has to be another way.

This is for the Gelflings. You know who you are.

---

## Who this is NOT for

This project exists to protect people, not to harm them.

**Mycelium is explicitly not for:**
- Those who would use privacy tools to exploit, abuse or harm others
- Those who would use encryption to hide the abuse of children
- Those who would use the mesh to harass, stalk or threaten
- Those who would weaponise freedom against the very people freedom is meant to protect
- Criminal enterprises of any kind

We are not naive. We know that tools of freedom can be misused.
Our answer is not to weaken the tools — it is to build a community with a conscience.

If you are found to be using Mycelium to harm others, the community will vote
to add your cryptographic identity to the blocklist. Every node on the network
will refuse to route your traffic. You will be isolated — not by a corporation,
not by a government, but by the people you betrayed.

The Mycelium heals around damage. That includes you.

---

## Acceptable Use

By using, building or distributing Mycelium firmware you agree:

1. You will not use this network to harm, exploit or abuse other people
2. You will not use this network to distribute content that exploits children
3. You will not use this network to conduct criminal operations against individuals
4. You will contribute back any improvements under the same AGPL licence
5. You will not attempt to centralise, capture or commercialise the network
   in ways that remove freedom from others

The licence is AGPL v3. The spirit is simpler: **do no harm, share everything.**

---

## Ownership

Nobody owns Mycelium.

Not Rocket Routers. Not its founders. Not any corporation.
The code belongs to everyone under the AGPL licence.
Profits from hardware sales go to community benefit — schools, the homeless,
people who need it more than we do.

If Rocket Routers disappeared tomorrow, Mycelium would continue.
That is the point. That was always the point.

---

## How to build for your hardware

Mycelium was first built for the ZBT Z8803BE (MediaTek Filogic / ARM64).
But the core — WireGuard, Yggdrasil, 802.11s mesh — runs on any OpenWrt device.

**Hardware-agnostic scripts (copy these as-is):**
- `95c-rocket-wireguard` — WireGuard setup
- `96-rocket-yggdrasil` — Yggdrasil / Mycelium mesh
- `94-rocket-mesh` — 802.11s WiFi backhaul

**Hardware-specific scripts (adapt these for your device):**
- `95-rocket-topology-c` — ethernet port assignment (eth1/eth2 names vary by board)
- `96-rocket-leds` — LED config (board-specific)
- `97-rocket-modem` — modem/USB setup (modem-specific)

**Steps:**
1. Set up an OpenWrt build environment for your target device
2. Copy the hardware-agnostic scripts into `files/etc/uci-defaults/`
3. Adapt the hardware-specific scripts for your board's interface names
4. Add the Yggdrasil packages to your `.config`:
   ```
   CONFIG_PACKAGE_yggdrasil=y
   CONFIG_PACKAGE_yggdrasil-jumper=y
   CONFIG_PACKAGE_luci-proto-yggdrasil=y
   CONFIG_PACKAGE_kmod-wireguard=y
   CONFIG_PACKAGE_wireguard-tools=y
   CONFIG_PACKAGE_luci-app-wireguard=y
   CONFIG_PACKAGE_wpad-mesh-mbedtls=y
   ```
5. Build, flash, join the Mycelium

If you port it to a new device, please submit it back.
Every new device supported is another strand in the network.

---

## The network

Once you are on Yggdrasil you are on a global encrypted mesh used by thousands
of people worldwide. Your Mycelium router joins this automatically.

Your Yggdrasil address is derived from your cryptographic public key.
It is yours. It does not change. No central authority assigned it.
No central authority can take it away.

This is what the internet was always supposed to be.

---

## Community

Forum, governance, blocklist management and community decisions:
**[rocketrouters.co.uk](https://rocketrouters.co.uk)**

Pull requests welcome. Bad actors are not.

---

*Built with the belief that connection is a human right.*
*Named after the network that has kept the world alive for a billion years.*
*Released freely, because that is the only way it works.*

**🍄 Mycelium — Rocket Routers Firmware E**
