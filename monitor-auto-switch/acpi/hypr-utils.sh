#!/bin/bash
set -euo pipefail

umask 022
PATH=/usr/local/bin:/usr/bin:/bin

log() {
  logger -t lid-events "[$0] $*"
}

# ========== CONFIGURATION SECTION ==========
# Customize these values based on your hardware
LAPTOP_MONITOR="eDP-1"                    # Your laptop display name
EXTERNAL_MONITOR="DP-5"                   # Your external display name
EXTERNAL_RESOLUTION="5120x2160@60"        # External monitor resolution@refresh
EXTERNAL_SCALE="1.67"                     # External monitor scaling factor
LAPTOP_SCALE="2"                           # Laptop monitor scaling factor
EXTERNAL_POSITION="0x0"                   # External monitor position
LAPTOP_POSITION_DUAL="3072x0"            # Laptop position in dual mode
LAPTOP_POSITION_SOLO="0x0"               # Laptop position when alone
# Workspace distribution
EXTERNAL_WS="${EXTERNAL_WS:-1 2 3 4 5}"  # Workspaces for external monitor
LAPTOP_WS="${LAPTOP_WS:-6 7 8 9 10}"     # Workspaces for laptop monitor
# Refresh rate settings for power management
LAPTOP_LOW_REFRESH="60"                   # Battery saving refresh rate
LAPTOP_HIGH_REFRESH="120"                 # AC power refresh rate
LAPTOP_BASE_RESOLUTION="2880x1800"       # Base resolution without refresh rate
# ========== END CONFIGURATION SECTION ==========

# Debounce: single instance at a time
exec 9>/run/lid-switch.lock || true
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { log "Another lid handler instance running, exiting."; exit 0; }
fi

require_cmd() { command -v "$1" >/dev/null 2>&1 || { log "Missing command: $1"; exit 1; }; }
require_cmd hyprctl
require_cmd logger

get_hypr_user() {
  local u
  u=$(ps -o user= -C Hyprland | head -n1 || true)
  if [ -z "$u" ]; then
    u=$(ps aux | grep -E '[Hh]yprland' | awk '{print $1}' | head -n1 || true)
  fi
  echo "$u"
}

export_hypr_env() {
  HYPR_USER="${HYPR_USER:-$(get_hypr_user)}"
  if [ -z "$HYPR_USER" ]; then
    log "Hyprland user not found."
    return 1
  fi
  local pid
  pid=$(pgrep -u "$HYPR_USER" -x Hyprland | head -n1 || true)
  if [ -z "$pid" ]; then
    pid=$(pgrep -u "$HYPR_USER" -f '[Hh]yprland' | head -n1 || true)
  fi
  if [ -z "$pid" ]; then
    log "Hyprland PID not found for user $HYPR_USER."
    return 1
  fi
  
  # Get XDG_RUNTIME_DIR from the process environment
  XDG_RUNTIME_DIR=$(cat /proc/"$pid"/environ | tr '\0' '\n' | awk -F= '$1=="XDG_RUNTIME_DIR"{print $2}')
  if [ -z "$XDG_RUNTIME_DIR" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u "$HYPR_USER")"
  fi
  
  # Try to get HYPRLAND_INSTANCE_SIGNATURE from the process environment
  HYPR_SIG=$(cat /proc/"$pid"/environ | tr '\0' '\n' | awk -F= '$1=="HYPRLAND_INSTANCE_SIGNATURE"{print $2}')
  
  # If not found (e.g., UWSM managed), try to find the most recent socket directory
  if [ -z "$HYPR_SIG" ]; then
    # Look for the most recent Hyprland socket directory
    local latest_socket=""
    local latest_time=0
    for socket_dir in "$XDG_RUNTIME_DIR"/hypr/*/; do
      if [ -d "$socket_dir" ] && [ -S "${socket_dir}/.socket.sock" ]; then
        local mtime=$(stat -c %Y "$socket_dir" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$latest_time" ]; then
          latest_time="$mtime"
          latest_socket="$socket_dir"
        fi
      fi
    done
    if [ -n "$latest_socket" ]; then
      HYPR_SIG=$(basename "$latest_socket")
    fi
  fi
  
  if [ -z "$XDG_RUNTIME_DIR" ]; then
    log "Could not determine XDG_RUNTIME_DIR for user $HYPR_USER."
    return 1
  fi
  
  # We can proceed even without HYPR_SIG as hyprctl might work without it
  export HYPR_USER HYPR_SIG XDG_RUNTIME_DIR
  log "Hyprland env: user=$HYPR_USER, XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR, sig=${HYPR_SIG:-'(auto-detect)'}"
}

run_as_hypr() {
  if [ -n "$HYPR_SIG" ]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$HYPR_USER" -- env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    else
      sudo -u "$HYPR_USER" env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    fi
  else
    # Try without HYPR_SIG, let hyprctl auto-detect
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$HYPR_USER" -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    else
      sudo -u "$HYPR_USER" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    fi
  fi
}

hypr() {
  run_as_hypr hyprctl "$@"
}

monitor_connected_sysfs() {
  local connector="$1" path
  for path in /sys/class/drm/card*-"$connector"/status; do
    [ -r "$path" ] && grep -q '^connected' "$path" && return 0
  done
  return 1
}

monitor_connected_hypr() {
  local connector="$1"
  hypr monitors 2>/dev/null | awk -v name="$connector" '$1=="Monitor" && $2==name {found=1} END {exit !found}'
}

monitor_connected() {
  local connector="$1"
  monitor_connected_sysfs "$connector" || monitor_connected_hypr "$connector"
}

detect_external_monitor() {
  # Keep configured monitor if already connected
  if [ -n "${EXTERNAL_MONITOR:-}" ] && monitor_connected "$EXTERNAL_MONITOR"; then
    log "Using configured external monitor: ${EXTERNAL_MONITOR}"
    return 0
  fi

  local path connector
  for path in /sys/class/drm/card*-DP-*/status; do
    [ -r "$path" ] || continue
    if grep -q '^connected' "$path"; then
      connector=$(basename "$(dirname "$path")")
      connector="${connector#*-}"
      EXTERNAL_MONITOR="$connector"
      export EXTERNAL_MONITOR
      log "Auto-detected external monitor via sysfs: ${EXTERNAL_MONITOR}"
      return 0
    fi
  done

  for path in /sys/class/drm/card*-HDMI-*/status; do
    [ -r "$path" ] || continue
    if grep -q '^connected' "$path"; then
      connector=$(basename "$(dirname "$path")")
      connector="${connector#*-}"
      EXTERNAL_MONITOR="$connector"
      export EXTERNAL_MONITOR
      log "Auto-detected external monitor via HDMI sysfs: ${EXTERNAL_MONITOR}"
      return 0
    fi
  done

  local hypr_candidate
  hypr_candidate=$(hypr monitors 2>/dev/null | awk -v skip="$LAPTOP_MONITOR" '$1=="Monitor" && $2!=skip {print $2; exit}')
  if [ -n "$hypr_candidate" ]; then
    EXTERNAL_MONITOR="$hypr_candidate"
    export EXTERNAL_MONITOR
    log "Auto-detected external monitor via hyprctl: ${EXTERNAL_MONITOR}"
    return 0
  fi

  log "Auto-detect failed: no connected external monitor found."
  return 1
}

external_connected() {
  [ -n "${EXTERNAL_MONITOR:-}" ] || detect_external_monitor
  monitor_connected "${EXTERNAL_MONITOR:-}"
}

# Retry wrapper: wait for external to enumerate (docks/cables can be slow)
external_connected_retry() {
  local attempts="${1:-30}"
  local delay="${2:-0.15}"
  local i=0
  detect_external_monitor || true
  while [ "$i" -lt "$attempts" ]; do
    if external_connected; then
      return 0
    fi
    detect_external_monitor || true
    sleep "$delay"
    i=$((i+1))
  done
  return 1
}

move_ws_to_monitor() {
  local dest="$1"
  shift
  local ws
  for ws in "$@"; do
    hypr dispatch moveworkspacetomonitor "$ws" "$dest" >/dev/null 2>&1 || true
    sleep 0.05
  done
}

set_external_only() {
  # Enable external and disable laptop using configured values
  hypr keyword monitor "${EXTERNAL_MONITOR},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE}"
  sleep 0.25
  hypr keyword monitor "${LAPTOP_MONITOR},disable"
  sleep 0.25
}

set_dual_layout() {
  # External and laptop both enabled, positions/scales from config
  hypr keyword monitor "${EXTERNAL_MONITOR},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE}"
  sleep 0.25

  # Set laptop monitor with appropriate refresh rate based on power state
  local laptop_refresh="${LAPTOP_HIGH_REFRESH}"
  if ac_adapter_plugged; then
    laptop_refresh="${LAPTOP_HIGH_REFRESH}"
    log "AC power detected, using high refresh rate for laptop in dual layout"
  else
    laptop_refresh="${LAPTOP_LOW_REFRESH}"
    log "Battery power detected, using low refresh rate for laptop in dual layout"
  fi

  hypr keyword monitor "${LAPTOP_MONITOR},${LAPTOP_BASE_RESOLUTION}@${laptop_refresh},${LAPTOP_POSITION_DUAL},${LAPTOP_SCALE}"
  sleep 0.25
}

set_laptop_only() {
  hypr keyword monitor "${EXTERNAL_MONITOR},disable"
  sleep 0.25

  # Set laptop monitor with appropriate refresh rate based on power state
  local laptop_refresh="${LAPTOP_HIGH_REFRESH}"
  if ac_adapter_plugged; then
    laptop_refresh="${LAPTOP_HIGH_REFRESH}"
    log "AC power detected, using high refresh rate for laptop-only mode"
  else
    laptop_refresh="${LAPTOP_LOW_REFRESH}"
    log "Battery power detected, using low refresh rate for laptop-only mode"
  fi

  hypr keyword monitor "${LAPTOP_MONITOR},${LAPTOP_BASE_RESOLUTION}@${laptop_refresh},${LAPTOP_POSITION_SOLO},${LAPTOP_SCALE}"
  sleep 0.25
}

reassert_primary_external() {
  sleep 0.60
  hypr dispatch focusmonitor "${EXTERNAL_MONITOR}"
  hypr dispatch workspace 1
  sleep 0.10
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    run_as_hypr notify-send "$@"
  fi
}

# ========== AC ADAPTER DETECTION FUNCTIONS ==========

# Check if AC adapter is plugged in
# Returns: 0 if plugged in, 1 if unplugged, 2 if unable to determine
ac_adapter_plugged() {
  local ac_online_file="/sys/class/power_supply/ACAD/online"

  # Check if the AC adapter online file exists and is readable
  if [ ! -r "$ac_online_file" ]; then
    # Try alternative AC adapter names
    for ac_path in /sys/class/power_supply/A{C,D}A{D,C}*/online /sys/class/power_supply/ADP*/online; do
      if [ -r "$ac_path" ]; then
        ac_online_file="$ac_path"
        break
      fi
    done

    # If still not found, return error
    if [ ! -r "$ac_online_file" ]; then
      log "AC adapter status file not found or not readable"
      return 2
    fi
  fi

  # Read the online status (1 = plugged in, 0 = unplugged)
  local status
  status=$(cat "$ac_online_file" 2>/dev/null)

  case "$status" in
    1) return 0 ;;  # Plugged in
    0) return 1 ;;  # Unplugged
    *)
      log "Unexpected AC adapter status: $status"
      return 2
      ;;
  esac
}

# Get human-readable AC adapter status
get_ac_adapter_status() {
  if ac_adapter_plugged; then
    echo "plugged"
  elif [ $? -eq 1 ]; then
    echo "unplugged"
  else
    echo "unknown"
  fi
}

# Check if running on battery power
on_battery() {
  ! ac_adapter_plugged
}

# ========== REFRESH RATE MANAGEMENT ==========

# Switch laptop monitor refresh rate based on power state
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
  hypr keyword monitor "${LAPTOP_MONITOR},${resolution}@${refresh},${position},${scale}" >/dev/null 2>&1
  notify "Display" "Switched to ${refresh}Hz" -u low
  log "✅ Laptop monitor switched to ${refresh}Hz"
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

