# Rocket Routers — Firmware Source

Custom OpenWrt firmware for the ZBT-Z8803BE travel router, built by Paul Wilson
(Rocket Routers, sole trader, Scotland). This is the source behind the
firmware running on Rocket Routers hardware: build scripts, package configs,
uci-defaults/init scripts, the on-device dashboard, and the mesh/blocklist
tooling.

Published so it can't quietly disappear. Use it, fork it, learn from it.

## What's in here

- `build-v*.sh` — image-builder build scripts, full version history (v2.5 → v3.11.16)
- `rocket-v*-metadata.config`, `rocket-vE*.config` — per-version OpenWrt package/metadata configs
- Numbered uci-defaults scripts (`92-` through `99-`) — first-boot config: modem/SIM setup,
  WiFi, mwan3 dual-WAN failover, Cake SQM, Yggdrasil mesh, WireGuard, branding, the
  community blocklist
- `hotplug-*` — hotplug handlers for modem/WAN bring-up and mesh WPS
- `rocket-dashboard.cgi` / `rocket-dashboard-router.cgi` — the on-router web dashboard
  (network status, WiFi, mesh, earn/donate tabs, on-device AI assistant)
- `rocket-sign-blocklist.sh`, `97-rocket-blocklist` — Ed25519-signed community blocklist:
  routers verify the signature before applying any rule, so an update can't be spoofed
- `mycelium-memory.html`, `README-MYCELIUM.md` — Mycelium mesh-memory feature docs
- `rocket-memory-mcp.py` — MCP server exposing router-side memory storage to an AI assistant

## What's deliberately not in here

- **Firmware binaries** (`*.bin`) — compiled output, not source, and far too large for a
  git repo (dozens of versions, 20–37MB each). Build them yourself with the scripts above
  against an OpenWrt SDK, or ask for a release build.
- **The blocklist signing private key** — kept on the production server only. Routers ship
  with just the public key, which is what they need to verify a blocklist update. The
  private key never leaves the server it's generated on; that's what makes the signature
  meaningful.
- **Any live API keys, auth tokens, or account config** — anything like that found in this
  folder during a cleanup pass was excluded, not redacted-in-place.
- **Customer-facing credential/card generator tools** — kept separate from the firmware
  source.

## Building

This was built using the OpenWrt image-builder workflow under WSL. Each
`build-v*.sh` script pulls in the matching `rocket-v*.config`/`rocket-vE*-metadata.config`
and bakes in the uci-defaults scripts above. You'll need an OpenWrt SDK/image-builder
release matching the target script's OpenWrt version.

## Hardware

- ZBT-Z8803BE travel router
- Quectel RM500U-EA 5G modem (USB ID `2c7c:0900`)

## License

GNU Affero General Public License v3.0 (AGPLv3) — see [LICENSE](LICENSE).
If you run a modified version of this on a network server, AGPLv3 requires you
to make that modified source available too.

## About Rocket Routers

Rocket Routers is run by one person — Paul Wilson, a sole trader in Scotland.
No company, no board, no investors. Site: [rocketrouters.co.uk](https://rocketrouters.co.uk)
