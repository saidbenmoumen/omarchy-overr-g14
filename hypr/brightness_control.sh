#!/bin/bash

# Configuration
DEVICE="amdgpu_bl2"  # Change this to your device name
MONITOR="eDP-1"  # Change this to your monitor name
STEP=10  # Percentage step for brightness change

# Get current and max brightness
get_brightness() {
    brightnessctl -d "$DEVICE" get
}

get_max_brightness() {
    brightnessctl -d "$DEVICE" max
}

# Check if display is off
is_display_off() {
    # Check if monitor is disabled in Hyprland
    hyprctl monitors | grep -A 5 "$MONITOR" | grep -q "disabled: yes"
}

# Turn display on/off
display_on() {
    hyprctl keyword monitor "$MONITOR, preferred, auto, 1"
}

display_off() {
    hyprctl keyword monitor "$MONITOR, disable"
}

# Main function
brightness_control() {
    local action=$1
    
    if [ "$action" = "up" ]; then
        # Check if display is off
        if is_display_off; then
            display_on
            echo "Display turned on"
            exit 0
        fi
        
        # Increase brightness by 5%
        brightnessctl -d "$DEVICE" set +${STEP}%
        echo "Brightness increased to $(get_brightness)"
        
    elif [ "$action" = "down" ]; then
        # Check if display is off - do nothing
        if is_display_off; then
            echo "Display is off - cannot decrease further"
            exit 0
        fi
        
        current=$(get_brightness)
        max=$(get_max_brightness)
        
        # Calculate what 5% would be
        step_value=$((max * STEP / 100))
        
        # If current brightness minus step would be <= 0, turn off display
        if [ $((current - step_value)) -le 0 ]; then
            brightnessctl -d "$DEVICE" set 0
            display_off
            echo "Brightness at minimum - Display turned off"
        else
            # Normal decrease
            brightnessctl -d "$DEVICE" set ${STEP}%-
            echo "Brightness decreased to $(get_brightness)"
        fi
    else
        echo "Usage: $0 {up|down}"
        exit 1
    fi
}

# Run the script
brightness_control "$1"
