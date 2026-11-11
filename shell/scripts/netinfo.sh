#!/bin/sh
# Connection details for the network panel, as KEY=value lines (empty when not connected).
# On a cable (an ethernet device that's connected) they're the cable's, with wired=<device>;
# otherwise the Wi-Fi's
# Every network device (DEVICE:TYPE:STATE), asked once: for the wired and Wi-Fi devices and the VPN tunnels
devices=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null)
wired=$(printf '%s\n' "$devices" | awk -F: '$2=="ethernet" && $3=="connected" {print $1; exit}')
wifi=$(printf '%s\n' "$devices" | awk -F: '$2=="wifi" && $3=="connected" {print $1; exit}')
dev=${wired:-$wifi}
[ -n "$dev" ] || exit 0
nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$dev" 2>/dev/null | sed -n \
    -e 's/^IP4\.ADDRESS\[1\]:\(.*\)/ip=\1/p' -e 's/^IP4\.GATEWAY:\(.*\)/gateway=\1/p' -e 's/^IP4\.DNS\[1\]:\(.*\)/dns=\1/p'
if [ -n "$wired" ]; then
    echo "wired=$wired"
    # (the link's speed, where the kernel says: -1 or nothing on some adapters)
    speed=$(cat "/sys/class/net/$wired/speed" 2>/dev/null)
    case "$speed" in ''|-*|0) ;; *) echo "rate=$speed Mbit/s" ;; esac
else
    nmcli -t -f IN-USE,FREQ,RATE,SECURITY,CHAN device wifi list ifname "$dev" --rescan no 2>/dev/null \
        | awk -F: '$1=="*" {print "freq="$2; print "rate="$3; print "security="$4; print "channel="$5; exit}'
fi
# VPNs: NetworkManager VPN/WireGuard connections, and tunnels other apps run (e.g. Mullvad)
{ nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="vpn" || $2=="wireguard" {print $1}'
  printf '%s\n' "$devices" | awk -F: '($2=="tun" || $2=="wireguard") && $3 ~ /^connected/ {print $1}'
} | sort -u | head -1 | sed 's/^/vpn=/'
