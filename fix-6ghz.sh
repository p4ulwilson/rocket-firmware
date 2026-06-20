#!/bin/sh
# Fix 6 GHz radio (radio2) on Rocket Plus running v2.5
# Sets band=6g + fixed PSC channel 37 + EHT80 width
# Avoids ACS lookup that fails without AFC under US country code

uci set wireless.radio2.band='6g'
uci set wireless.radio2.channel='37'
uci set wireless.radio2.htmode='EHT80'
uci set wireless.radio2.country='US'
uci commit wireless
wifi reload
sleep 5
echo "=== After reload ==="
iw dev | grep -E "Interface|ssid|type|channel"
echo ""
echo "=== Radio2 detail ==="
iwinfo phy0.2-ap0 info 2>/dev/null || echo "still no info on radio2"
