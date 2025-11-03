#!/bin/bash

# Configuration
MONITOR="eDP-1"
LOW_REFRESH=60
HIGH_REFRESH=120

# Get battery status
BATTERY_STATUS=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1)

# Get current power profile
POWER_PROFILE=$(powerprofilesctl get 2>/dev/null)

# Determine if we should use low refresh rate
USE_LOW_REFRESH=false

if [ "$BATTERY_STATUS" = "Discharging" ] && [ "$POWER_PROFILE" = "power-saver" ]; then
    USE_LOW_REFRESH=true
fi

# Get current monitor state dynamically
MONITOR_INFO=$(hyprctl monitors -j | jq -r ".[] | select(.name==\"$MONITOR\")")
CURRENT_REFRESH=$(echo "$MONITOR_INFO" | jq -r '.refreshRate' | cut -d'.' -f1)
RESOLUTION=$(echo "$MONITOR_INFO" | jq -r '"\(.width)x\(.height)"')
POSITION=$(echo "$MONITOR_INFO" | jq -r '"\(.x)x\(.y)"')
SCALE=$(echo "$MONITOR_INFO" | jq -r '.scale')

# Switch refresh rate if needed while preserving all other settings
if [ "$USE_LOW_REFRESH" = true ] && [ "$CURRENT_REFRESH" != "$LOW_REFRESH" ]; then
    hyprctl keyword monitor "$MONITOR,$RESOLUTION@$LOW_REFRESH,$POSITION,$SCALE" >/dev/null 2>&1
    # Uncomment to get notifications:
    notify-send -u low "Display" "Switched to ${LOW_REFRESH}Hz (Battery + Power Saver)"

elif [ "$USE_LOW_REFRESH" = false ] && [ "$CURRENT_REFRESH" != "$HIGH_REFRESH" ]; then
    hyprctl keyword monitor "$MONITOR,$RESOLUTION@$HIGH_REFRESH,$POSITION,$SCALE" >/dev/null 2>&1
    # Uncomment to get notifications:
    notify-send -u low "Display" "Switched to ${HIGH_REFRESH}Hz"
fi

exit 0
