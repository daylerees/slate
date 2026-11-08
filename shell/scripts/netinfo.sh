#!/bin/sh
# Connection details for the Wi-Fi panel, as KEY=value lines (empty when not connected)
dev=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '$2=="wifi" && $3=="connected" {print $1; exit}')
[ -n "$dev" ] || exit 0
nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$dev" 2>/dev/null | sed -n \
    -e 's/^IP4\.ADDRESS\[1\]:\(.*\)/ip=\1/p' -e 's/^IP4\.GATEWAY:\(.*\)/gateway=\1/p' -e 's/^IP4\.DNS\[1\]:\(.*\)/dns=\1/p'
nmcli -t -f IN-USE,FREQ,RATE,SECURITY,CHAN device wifi list ifname "$dev" --rescan no 2>/dev/null \
    | awk -F: '$1=="*" {print "freq="$2; print "rate="$3; print "security="$4; print "channel="$5; exit}'
# VPNs: NetworkManager VPN/WireGuard connections, and tunnels other apps run (e.g. Mullvad)
{ nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="vpn" || $2=="wireguard" {print $1}'
  nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '($2=="tun" || $2=="wireguard") && $3 ~ /^connected/ {print $1}'
} | sort -u | head -1 | sed 's/^/vpn=/'
