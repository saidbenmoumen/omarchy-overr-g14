#!/bin/bash
set -euo pipefail

# AC adapter event handler for ACPI with refresh rate switching
# This script handles AC adapter plug/unplug events and automatically
# switches between 120Hz (plugged) and 60Hz (battery) for power saving

# Source the hypr-utils for all the functions we need
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/hypr-utils.sh" ]; then
  # Create a temporary version of hypr-utils.sh without the lock file mechanism
  temp_utils="/tmp/hypr-utils-ac-handler-$$.sh"

  # Remove the problematic lock file lines and flock dependency
  sed -e 's/^exec 9>.*$/# exec 9> (disabled for ac-adapter-handler)/' \
      -e 's/^if command -v flock.*$/# if command -v flock (disabled); then/' \
      -e 's/^  flock -n 9.*$/  # flock -n 9 (disabled)/' \
      -e '/Another lid handler instance running/d' \
      -e '/^fi$/d' \
      "$SCRIPT_DIR/hypr-utils.sh" > "$temp_utils"

  # Add the closing fi back only if needed
  echo "# fi (disabled lock section)" >> "$temp_utils"

  # Source the modified version
  . "$temp_utils"

  # Clean up
  rm -f "$temp_utils"
else
  echo "Error: hypr-utils.sh not found in $SCRIPT_DIR"
  exit 1
fi

# Function to detect current AC adapter status
detect_ac_status() {
  local ac_online_file="/sys/class/power_supply/ACAD/online"

  if [ ! -r "$ac_online_file" ]; then
    # Try alternative AC adapter names
    for ac_path in /sys/class/power_supply/A{C,D}A{D,C}*/online /sys/class/power_supply/ADP*/online; do
      if [ -r "$ac_path" ]; then
        ac_online_file="$ac_path"
        break
      fi
    done

    if [ ! -r "$ac_online_file" ]; then
      log "AC adapter status file not found"
      return 2
    fi
  fi

  local status
  status=$(cat "$ac_online_file" 2>/dev/null)

  case "$status" in
    1) echo "plugged"; return 0 ;;
    0) echo "unplugged"; return 1 ;;
    *) log "Unexpected AC status: $status"; return 2 ;;
  esac
}

# Main handler function
handle_ac_event() {
  local event="$1"
  local current_status

  log "AC adapter event: $event"

  # Verify the event matches the actual status
  current_status=$(detect_ac_status) || true
  if [ "$current_status" != "$event" ]; then
    log "Event '$event' doesn't match detected status '$current_status', using detected status"
    event="$current_status"
  fi

  # Initialize Hyprland environment
  if ! export_hypr_env; then
    log "Failed to export Hyprland environment, skipping refresh rate change"
    return 1
  fi

  case "$event" in
    "plugged")
      log "AC adapter plugged in - switching to high refresh rate (${LAPTOP_HIGH_REFRESH}Hz)"
      notify "Power" "AC connected - switching to ${LAPTOP_HIGH_REFRESH}Hz" -i battery-charging

      # Switch to high refresh rate
      set_high_refresh
      ;;

    "unplugged")
      log "AC adapter unplugged - switching to battery saving mode (${LAPTOP_LOW_REFRESH}Hz)"
      notify "Power" "Battery mode - switching to ${LAPTOP_LOW_REFRESH}Hz" -i battery

      # Switch to low refresh rate for battery saving
      set_low_refresh
      ;;

    *)
      log "Unknown AC adapter event: $event"
      ;;
  esac
}

# Parse command line arguments
if [ $# -eq 0 ]; then
  # If no arguments provided, detect current status and auto-adjust
  log "No event specified, auto-adjusting refresh rate based on current power state"
  if export_hypr_env; then
    auto_adjust_refresh
  else
    log "Failed to export Hyprland environment, cannot auto-adjust refresh rate"
  fi
elif [ $# -eq 1 ]; then
  # Handle the provided event
  handle_ac_event "$1"
else
  echo "Usage: $0 [plugged|unplugged]"
  echo "If no argument is provided, the current AC status will be detected and refresh rate adjusted accordingly."
  exit 1
fi
