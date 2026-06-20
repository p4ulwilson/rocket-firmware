# Rocket Routers Stats System — Setup Guide

One-time setup. About 10 minutes. Only needs doing once.

---

## What You're Setting Up

| File | What it does |
|------|-------------|
| `functions/collect.js` | Receives page view + scroll events from every visitor |
| `functions/stats-data.js` | Serves your private stats data (password-gated) |
| `js/rr-stats.js` | Tiny beacon script on index.html + why.html |
| `stats.html` | Your private dashboard at rocketrouters.co.uk/stats.html |

**Size impact:** ~3KB total. Basically nothing.

---

## Step 1 — Create the KV Namespace

Open a terminal / PowerShell in `D:\Rocket-Routers-Website` and run:

```
wrangler kv:namespace create RR_STATS
```

You'll get output like:
```
🌀  Creating namespace with title "rocketrouters-RR_STATS"
✨  Success!
Add the following to your configuration file in your kv_namespaces array:
{ binding = "RR_STATS", id = "abc123def456..." }
```

Copy that ID (the long string after `id = `).

---

## Step 2 — Update wrangler.toml

Open `D:\Rocket-Routers-Website\wrangler.toml` and replace `REPLACE_WITH_YOUR_KV_ID` with the ID you just copied.

---

## Step 3 — Set Environment Variables

Go to: **Cloudflare Dashboard → Pages → rocketrouters → Settings → Environment Variables**

Add these two variables (for both Production and Preview):

| Variable name | Value |
|--------------|-------|
| `STATS_KEY` | A password you choose (e.g. `rocketrouters-stats-2026`) — this is what you type into the stats page |
| `SALT` | Any random string (e.g. `rr-privacy-salt-99`) — used to hash visitor IPs for privacy |

---

## Step 4 — Deploy

Run the normal deploy bat:

```
D:\Rocket-Routers-Website\firmware-build\deploy-rocketrouters.bat
```

The `functions/` folder and `wrangler.toml` will be picked up automatically by Cloudflare Pages.

---

## Step 5 — Check It Works

1. Visit `https://www.rocketrouters.co.uk/stats.html`
2. Enter the STATS_KEY you set in Step 3
3. You should see the dashboard (empty at first — give it a few page visits)

To test tracking is working, visit the homepage and why.html, then reload stats.

---

## Viewing Your Stats

Just go to: `rocketrouters.co.uk/stats.html`

- Nobody else knows the URL exists
- Even if they find it, they need the password
- No link to it from the main site

---

## What Gets Tracked (Privacy-Respecting)

- ✅ Page views per page per day
- ✅ Unique visitors per day (IPs are hashed — not stored raw)
- ✅ Which country the visit came from (from Cloudflare headers, no IP lookup needed)
- ✅ Referrer domain (where they came from — Google, a forum, direct, etc.)
- ✅ Scroll depth (how far they actually read — 25%/50%/75%/90%)
- ❌ No cookies
- ❌ No tracking IDs
- ❌ No raw IPs stored

---

## Adding Tracking to More Pages

To track the blog posts etc., add this one line before `</body>` in any HTML file:

```html
<script src="/js/rr-stats.js" defer></script>
```

Already added to: `index.html`, `why.html`

---

## Note: Google Analytics Already on index.html

index.html already has Google Analytics (G-0B2Z734JZY). The Rocket Routers stats system runs alongside it and gives you private data you actually control. You could remove the GA tag if you want — up to you.

---

## Data Retention

Stats stored for 90 days rolling. Unique visitor counts stored for 2 days (enough for daily reporting). All automatic via Cloudflare KV TTLs.

## Free Tier Limits

Cloudflare KV free tier: 100k reads/day, 1k writes/day. For a typical site this size that's more than enough. If you ever get viral traffic and hit limits, the tracking just silently fails (never breaks the site).
