#!/bin/bash
# Refresh Rate Manager for Hyprland

set -euo pipefail

printf "\033[1;36m%s\033[0m\n" "⚡ Refresh Rate Manager"

# === CONFIGURATION ===
MONITOR="eDP-1"
LOW_REFRESH=60
HIGH_REFRESH=120

# === FUNCTIONS ===

get_battery_status() {
    cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1
}

get_power_profile() {
    powerprofilesctl get 2>/dev/null || echo "unknown"
}

get_monitor_info() {
    hyprctl monitors -j | jq -r ".[] | select(.name==\"$MONITOR\")"
}

switch_refresh() {
    local refresh="$1"
    local resolution="$2"
    local position="$3"
    local scale="$4"

    hyprctl keyword monitor "$MONITOR,${resolution}@${refresh},${position},${scale}" >/dev/null 2>&1
    notify-send -u low "Display" "Switched to ${refresh}Hz"
    printf "✅ Switched to %sHz\n" "$refresh"
}

# === MAIN LOGIC ===

BATTERY_STATUS=$(get_battery_status)
POWER_PROFILE=$(get_power_profile)

printf "🔋 Battery: %s | Power profile: %s\n" "$BATTERY_STATUS" "$POWER_PROFILE"

MONITOR_INFO=$(get_monitor_info)
if [[ -z "$MONITOR_INFO" || "$MONITOR_INFO" == "null" ]]; then
    printf "❌ Monitor '%s' not found via hyprctl.\n" "$MONITOR"
    exit 1
fi

CURRENT_REFRESH=$(echo "$MONITOR_INFO" | jq -r '.refreshRate' | cut -d'.' -f1)
RESOLUTION=$(echo "$MONITOR_INFO" | jq -r '"\(.width)x\(.height)"')
POSITION=$(echo "$MONITOR_INFO" | jq -r '"\(.x)x\(.y)"')
SCALE=$(echo "$MONITOR_INFO" | jq -r '.scale')

# Determine target refresh
TARGET_REFRESH="$HIGH_REFRESH"

if [[ "$BATTERY_STATUS" == "Discharging" && "$POWER_PROFILE" == "power-saver" ]]; then
    TARGET_REFRESH="$LOW_REFRESH"
fi

# Switch if different
if [[ "$CURRENT_REFRESH" -ne "$TARGET_REFRESH" ]]; then
    printf "⚙️  Changing refresh rate to %sHz...\n" "$TARGET_REFRESH"
    switch_refresh "$TARGET_REFRESH" "$RESOLUTION" "$POSITION" "$SCALE"
else
    printf "ℹ️  Already at %sHz — no change needed.\n" "$TARGET_REFRESH"
fi

printf "✅ Done.\n"
exit 0
