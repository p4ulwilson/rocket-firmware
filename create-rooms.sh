#!/bin/sh
# Mycelium Community Rooms — one-time creation script
# Run on the router: sh /tmp/create-rooms.sh
# Requires: conduwuit running on localhost:6167, gov-token valid

TOKEN=$(cat /etc/rocket/gov-token 2>/dev/null)
BASE="http://localhost:6167/_matrix/client/v3/createRoom"

if [ -z "$TOKEN" ]; then
  echo "ERROR: No token found at /etc/rocket/gov-token"
  exit 1
fi

create_room(){
  ALIAS="$1"
  NAME="$2"
  TOPIC="$3"
  echo "Creating #${ALIAS}:rocketrouters.co.uk ..."
  curl -s -X POST "$BASE" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${NAME}\",\"topic\":\"${TOPIC}\",\"room_alias_name\":\"${ALIAS}\",\"preset\":\"public_chat\",\"visibility\":\"public\"}" \
    | grep -o '"room_id":"[^"]*"' || echo "  (may already exist)"
  sleep 0.5
}

create_room "build-your-own"    "🏗️ Build Your Own"            "Solar panels. Wind turbines. Rainwater harvesting. Battery storage. Off-grid, on-grid, or somewhere in between. If you can build it and own it, it lives here."
create_room "cars"              "🚗 Cars & Mechanics"           "Fix your own car. Own it properly. The garage that doesn't charge £120 an hour to tell you nothing."
create_room "community-created" "➕ Community Created"          "Propose a room. Community votes. Majority says yes — it exists. Nobody at the top decides what conversations are allowed."
create_room "computer-networks" "🌐 Computer Networks"          "What they are, how they work, how to build them. Baby steps to full beard."
create_room "computer-talk"     "💻 Computer Talk"              "Everything tech. Modems, switches, up-and-coming hardware. If it has a chip, it lives here."
create_room "dating"            "💕 Dating"                     "Private match only. Two people both say yes — a private encrypted room opens. Nobody else ever sees it. Consent first, always."
create_room "enviromental"      "🌿 EnviroMENTAL"               "Because that's exactly what they're doing to it. Climate, ecology, the world we're inheriting and the one we're leaving."
create_room "farming"           "🌱 Farming & Growing"          "Food sovereignty. Allotments. Permaculture. Feeding yourself without a supermarket."
create_room "freedom"           "🔓 Freedom"                    "Digital rights. Free speech. Censorship resistance. The things worth protecting."
create_room "general"           "💬 General"                    "Everything else. The kitchen. Everyone ends up here eventually."
create_room "geopolitics"       "🌍 Geopolitics"                "Real talk. No algorithm deciding what's allowed. No shadowban. No advertiser veto."
create_room "governance"        "⚖️ Governance"                 "Mesh votes, proposals, community decisions. The rules everyone agreed to, applied equally."
create_room "harm-reduction"    "💊 Health & Harm Reduction"    "People use substances. This is a place to do it more safely. Not the dark web. The lit one."
create_room "help"              "❓ Help"                        "New users, getting started, no stupid questions. Ever."
create_room "linux"             "🐧 Linux / OpenWrt / Windows\$" "The geek den. All operating systems welcome. Windows\$ is spelled that way on purpose."
create_room "make-friends"      "🤝 Make Friends"               "Just humans being humans. No algorithm needed."
create_room "mushmesh"          "🍄 Mushmesh"                   "The network itself. Firmware updates, mesh questions, router help, what's growing. P4ul sends love — direct questions here or at Claude."
create_room "news"              "📰 News"                       "Announcements, current events, things that matter."
create_room "security"          "🔒 Security"                   "Vulnerabilities, threat intel, staying safe online and off it."

echo ""
echo "Done. 19 rooms created."
echo "They will appear in the Community tab rooms directory automatically."
