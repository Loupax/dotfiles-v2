#!/bin/sh
STATE=$(cat /proc/acpi/button/lid/*/state 2>/dev/null | awk '{print $NF}')
[ -z "$STATE" ] && exit 0

USER_NAME=""
for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
    seat=$(loginctl show-session "$s" -p Seat --value 2>/dev/null)
    active=$(loginctl show-session "$s" -p Active --value 2>/dev/null)
    if [ "$seat" = "seat0" ] && [ "$active" = "yes" ]; then
        USER_NAME=$(loginctl show-session "$s" -p Name --value 2>/dev/null)
        break
    fi
done
[ -z "$USER_NAME" ] && exit 0

UID_NUM=$(id -u "$USER_NAME") || exit 0
RUNTIME_DIR="/run/user/$UID_NUM"

WAYLAND_SOCK=$(basename "$(ls "$RUNTIME_DIR"/wayland-[0-9] 2>/dev/null | head -1)")
[ -z "$WAYLAND_SOCK" ] && exit 0

[ "$STATE" = "closed" ] && ACTION="--off" || ACTION="--on"
su - "$USER_NAME" -c "XDG_RUNTIME_DIR=$RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_SOCK wlopm $ACTION '*'"
