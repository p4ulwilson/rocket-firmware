#!/bin/bash
# rocket-sign-blocklist.sh
# Run this on rocketrouters.co.uk server to publish a new community blocklist
# Keep rocket-routers-private.key SAFE on the server — never share it
#
# Usage:
#   ./rocket-sign-blocklist.sh blocklist.txt
#   → produces blocklist.txt.sig
#   Upload both files to rocketrouters.co.uk/mycelium/
#
# Blocklist format (one Yggdrasil IPv6 address per line, # for comments):
#   # Blocked: reason why
#   200:1234:5678:abcd::1
#   200:abcd::dead:beef

PRIVKEY="./rocket-routers-private.key"
BLOCKLIST="${1:-blocklist.txt}"

[ -f "$PRIVKEY" ]    || { echo "ERROR: private key not found: $PRIVKEY"; exit 1; }
[ -f "$BLOCKLIST" ]  || { echo "ERROR: blocklist not found: $BLOCKLIST"; exit 1; }

openssl pkeyutl -sign -inkey "$PRIVKEY" -out "${BLOCKLIST}.sig" -rawin -in "$BLOCKLIST"
echo "Signed: ${BLOCKLIST}.sig"
echo "Upload both files to: rocketrouters.co.uk/mycelium/"
echo "Every Mycelium router will pick this up within the hour."
