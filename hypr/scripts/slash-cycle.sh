#!/bin/bash

modes=("Static" "Bounce" "Slash" "Loading" "BitStream" "Transmission" "Flow" "Flux" "Phantom" "Spectrum" "Hazard" "Interfacing" "Ramp" "GameOver" "Start" "Buzzer")
state_file="/tmp/slash_mode_index"

# Get current index or start at 0
if [[ -f "$state_file" ]]; then
    index=$(cat "$state_file")
else
    index=0
fi

# Cycle to next
index=$(( (index + 1) % ${#modes[@]} ))
echo "$index" > "$state_file"

mode="${modes[$index]}"
asusctl slash --mode "$mode"
notify-send "Slash Mode" "$mode"
