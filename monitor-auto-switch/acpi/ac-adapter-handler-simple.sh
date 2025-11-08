#!/bin/bash
set -euo pipefail

# Simple AC adapter event handler for refresh rate switching
# This script handles AC adapter plug/unplug events and automatically
# switches between 120Hz (plugged) and 60Hz (battery) for power saving

# Configuration
LAPTOP_MONITOR="eDP-1"
LAPTOP_LOW_REFRESH="60"
LAPTOP_HIGH_REFRESH="120"
LAPTOP_BASE_RESOLUTION="2880x1800"
LAPTOP_SCALE="2"
LAPTOP_POSITION_SOLO="0x0"
LAPTOP_POSITION_DUAL="auto-left"

# Logging function
log() {
  logger -t ac-adapter-handler "[$0] $*"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Notification function
notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@" 2>/dev/null || true
  fi
}

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
      echo "unknown"
      return 2
    fi
  fi

  local status
  status=$(cat "$ac_online_file" 2>/dev/null)

  case "$status" in
    1) echo "plugged"; return 0 ;;
    0) echo "unplugged"; return 0 ;;  # Changed return code to 0 for success
    *) log "Unexpected AC status: $status"; echo "unknown"; return 2 ;;
  esac
}

# Check if AC adapter is plugged in
ac_adapter_plugged() {
  local ac_online_file="/sys/class/power_supply/ACAD/online"
  
  if [ ! -r "$ac_online_file" ]; then
    for ac_path in /sys/class/power_supply/A{C,D}A{D,C}*/online /sys/class/power_supply/ADP*/online; do
      if [ -r "$ac_path" ]; then
        ac_online_file="$ac_path"
        break
      fi
    done
    
    if [ ! -r "$ac_online_file" ]; then
      return 2
    fi
  fi
  
  local status
  status=$(cat "$ac_online_file" 2>/dev/null)
  
  case "$status" in
    1) return 0 ;;  # Plugged in
    0) return 1 ;;  # Unplugged
    *) return 2 ;;  # Error
  esac
}

# Function to check if external monitor is connected
external_connected() {
  # Check via sysfs first
  for path in /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-*/status; do
    [ -r "$path" ] || continue
    if grep -q '^connected' "$path" 2>/dev/null; then
      return 0
    fi
  done

  # Check via hyprctl if available
  if command -v hyprctl >/dev/null 2>&1; then
    if run_hyprctl_as_user monitors 2>/dev/null | awk -v skip="$LAPTOP_MONITOR" '$1=="Monitor" && $2!=skip {found=1} END {exit !found}'; then
      return 0
    fi
  fi

  return 1
}

# Function to find the user running Hyprland
find_hyprland_user() {
  # Method 1: Find the user running Hyprland process directly
  local hyprland_user
  hyprland_user=$(ps aux | grep -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+.*[[:space:]]Hyprland$' | head -1 | awk '{print $1}')

  if [ -n "$hyprland_user" ] && [ "$hyprland_user" != "root" ]; then
    echo "$hyprland_user"
    return 0
  fi

  # Method 2: Check who owns the Hyprland socket
  for hypr_socket in /tmp/hypr/*/; do
    if [ -d "$hypr_socket" ]; then
      local socket_owner
      socket_owner=$(stat -c %U "$hypr_socket" 2>/dev/null)
      if [ -n "$socket_owner" ] && [ "$socket_owner" != "root" ]; then
        echo "$socket_owner"
        return 0
      fi
    fi
  done

  # Method 3: Find user from active display session
  local display_user
  display_user=$(who | grep -E '\(:[0-9]+\)' | head -1 | awk '{print $1}')

  if [ -n "$display_user" ]; then
    echo "$display_user"
    return 0
  fi

  # Method 4: Use the owner of /tmp/.X11-unix/X0 if it exists
  if [ -S "/tmp/.X11-unix/X0" ]; then
    local x11_owner
    x11_owner=$(stat -c %U "/tmp/.X11-unix/X0" 2>/dev/null)
    if [ -n "$x11_owner" ] && [ "$x11_owner" != "root" ]; then
      echo "$x11_owner"
      return 0
    fi
  fi

  return 1
}

# Function to run hyprctl command as the correct user
run_hyprctl_as_user() {
  local hyprland_user
  hyprland_user=$(find_hyprland_user)

  if [ -z "$hyprland_user" ]; then
    log "❌ Could not find Hyprland user"
    return 1
  fi

  log "Running hyprctl as user: $hyprland_user"

  # Find the Hyprland socket
  local hyprland_signature=""

  # Check common socket locations
  for socket_dir in "/run/user/$(id -u "$hyprland_user")/hypr" "/tmp/hypr"; do
    if [ -d "$socket_dir" ]; then
      hyprland_signature=$(ls -1 "$socket_dir" 2>/dev/null | head -1)
      if [ -n "$hyprland_signature" ]; then
        break
      fi
    fi
  done

  # Run hyprctl as the Hyprland user with proper environment
  sudo -u "$hyprland_user" \
    HYPRLAND_INSTANCE_SIGNATURE="$hyprland_signature" \
    hyprctl "$@" 2>/dev/null
}

# Switch laptop monitor refresh rate
switch_laptop_refresh() {
  local refresh="$1"
  local resolution="${LAPTOP_BASE_RESOLUTION}"
  local position="${LAPTOP_POSITION_SOLO}"
  local scale="${LAPTOP_SCALE}"

  # Determine position based on current monitor setup
  if external_connected; then
    position="${LAPTOP_POSITION_DUAL}"
  fi

  log "Switching laptop monitor to ${refresh}Hz"

  # Execute the hyprctl command as the correct user
  if command -v hyprctl >/dev/null 2>&1; then
    if run_hyprctl_as_user keyword monitor "${LAPTOP_MONITOR},${resolution}@${refresh},${position},${scale}" >/dev/null 2>&1; then
      # Send notification as the user too
      local hyprland_user
      hyprland_user=$(find_hyprland_user)
      if [ -n "$hyprland_user" ]; then
        sudo -u "$hyprland_user" DISPLAY=:0 notify-send "Display" "Switched to ${refresh}Hz" -u low 2>/dev/null || true
      fi
      log "✅ Laptop monitor switched to ${refresh}Hz"
      return 0
    else
      log "❌ Failed to switch laptop monitor to ${refresh}Hz"
      return 1
    fi
  else
    log "❌ hyprctl command not found"
    return 1
  fi
}

# Set high refresh rate (AC power mode)
set_high_refresh() {
  switch_laptop_refresh "${LAPTOP_HIGH_REFRESH}"
}

# Set low refresh rate (battery mode)
set_low_refresh() {
  switch_laptop_refresh "${LAPTOP_LOW_REFRESH}"
}

# Auto-adjust refresh rate based on AC adapter status
auto_adjust_refresh() {
  if ac_adapter_plugged; then
    log "AC adapter detected, setting high refresh rate"
    set_high_refresh
  else
    log "Battery power detected, setting low refresh rate for power saving"
    set_low_refresh
  fi
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
      return 1
      ;;
  esac
}

# Function to parse ACPI event string
parse_acpi_event() {
  local event_string="$1"

  # Expected format: "ac_adapter ACPI0003:00 00000080 00000000" or "ac_adapter ACPI0003:00 00000080 00000001"
  # Extract the last parameter which indicates plug status (0=unplugged, 1=plugged)
  local status=$(echo "$event_string" | awk '{print $NF}')

  case "$status" in
    "00000000") echo "unplugged" ;;
    "00000001") echo "plugged" ;;
    *)
      log "Unknown ACPI event status: $status from event: $event_string"
      echo "unknown"
      ;;
  esac
}

# Parse command line arguments
if [ $# -eq 0 ]; then
  # If no arguments provided, detect current status and auto-adjust
  log "No event specified, auto-adjusting refresh rate based on current power state"
  auto_adjust_refresh
elif [ $# -eq 1 ]; then
  # Parse the ACPI event string if it looks like an ACPI event
  if [[ "$1" == ac_adapter* ]]; then
    # This is an ACPI event string, parse it
    event=$(parse_acpi_event "$1")
    log "Parsed ACPI event '$1' as: $event"
    handle_ac_event "$event"
  else
    # This is a direct command (plugged/unplugged)
    handle_ac_event "$1"
  fi
elif [ $# -ge 2 ]; then
  # Multiple arguments - likely ACPI passed the event as separate words
  # Reconstruct the event string
  event_string="$*"
  log "Received multiple arguments, reconstructed as: '$event_string'"

  if [[ "$event_string" == ac_adapter* ]]; then
    # This is an ACPI event string, parse it
    event=$(parse_acpi_event "$event_string")
    log "Parsed ACPI event '$event_string' as: $event"
    handle_ac_event "$event"
  else
    log "Unknown multi-argument format: $event_string"
    # Fall back to auto-detect
    log "Falling back to auto-detect current power state"
    auto_adjust_refresh
  fi
else
  echo "Usage: $0 [plugged|unplugged|ACPI_EVENT_STRING]"
  echo "Examples:"
  echo "  $0                                    # Auto-detect current status"
  echo "  $0 plugged                           # Force plugged event"
  echo "  $0 unplugged                         # Force unplugged event"
  echo "  $0 'ac_adapter ACPI0003:00 00000080 00000001'  # Parse ACPI event"
  exit 1
fi
