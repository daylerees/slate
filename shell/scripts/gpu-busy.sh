#!/bin/sh
# How busy each graphics card is, for the battery panel's System section (panels/BatteryPanel.qml):
# one line per card that can say, while the panel is open:
#   busy <0-100>    the card's busy percent
#   asleep          the card is powered down (a laptop's second card, unused): it isn't asked,
#                   as asking would wake it and cost battery
# AMD cards say it themselves (gpu_busy_percent); NVIDIA's through nvidia-smi, when installed.
# Intel's graphics don't say without root tools, so they're left out, and with no card that
# can say there's nothing at all (the panel hides the row).
# (SLATE_SYS: the tests' stand-in for /sys)
sys=${SLATE_SYS:-/sys}
seen=" "
for card in "$sys"/class/drm/card[0-9]*; do
    case "${card##*/}" in *-*) continue ;; esac            # (a connector, like card0-DP-1)
    dev="$card/device"
    [ -r "$dev/vendor" ] || continue
    bus=$(basename "$(readlink -f "$dev")")
    case "$seen" in *" $bus "*) continue ;; esac
    seen="$seen$bus "
    vendor=$(cat "$dev/vendor" 2>/dev/null)
    case "$vendor" in 0x1002|0x10de) ;; *) continue ;; esac
    if [ "$(cat "$dev/power/runtime_status" 2>/dev/null)" = suspended ]; then
        echo asleep
        continue
    fi
    case "$vendor" in
        0x1002)
            b=$(cat "$dev/gpu_busy_percent" 2>/dev/null) && [ -n "$b" ] && echo "busy $b" ;;
        0x10de)
            command -v nvidia-smi >/dev/null 2>&1 || continue
            b=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i "$bus" 2>/dev/null | head -n 1 | tr -dc 0-9)
            [ -n "$b" ] && echo "busy $b" ;;
    esac
done
exit 0
