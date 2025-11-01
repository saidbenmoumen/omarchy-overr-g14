#!/usr/bin/env bash
set -euo pipefail

# Monitor Auto-Switch Installer (generalized)
# - Copies ACPI lid/monitor scripts into a destination (default /etc/acpi)
# - Creates ACPI event files (default /etc/acpi/events)
# - Optionally restarts acpid
# Works on any system with acpid + systemd (service name: acpid)

# Defaults (can be overridden by flags)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ACPI_DIR="${REPO_ROOT}/acpi"
DEST_DIR="/etc/acpi"
EVENTS_DIR="/etc/acpi/events"
LOG_FILE="/var/log/lid-events.log"
NO_RESTART=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [options]

Options:
  -s, --src DIR            Source directory containing ACPI scripts (default: "+auto detect+" -> "+script_dir+/../acpi")
  -d, --dest DIR           Destination directory for scripts (default: /etc/acpi)
      --events-dir DIR     Destination directory for ACPI events (default: /etc/acpi/events)
  -n, --dry-run            Print what would be done, do not write
      --no-restart         Do not restart acpid after installing
  -h, --help               Show this help and exit

Expected files in --src:
  hypr-utils.sh, lid-open.sh, lid-close.sh, check-lid-on-startup.sh

Examples:
  sudo $(basename "$0")
  sudo $(basename "$0") --src /path/to/your/acpi --no-restart
  sudo $(basename "$0") -n   # dry-run
EOF
}

# Parse args early (before sudo checks so --help works without root)
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -s|--src)
        REPO_ACPI_DIR="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      -d|--dest)
        DEST_DIR="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      --events-dir)
        EVENTS_DIR="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      -n|--dry-run)
        DRY_RUN=1; shift ;;
      --no-restart)
        NO_RESTART=1; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 2
        ;;
    esac
  done
}

need_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root: sudo $0 [options]" >&2
    exit 1
  fi
}

say() { printf '%s\n' "$*"; }

run_as_user() {
  local user="$1"; shift
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  else
    sudo -u "$user" "$@"
  fi
}

backup_if_changed() {
  local src="$1" dest="$2"
  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    if [ "$DRY_RUN" = 1 ]; then
      say "Would back up $dest -> ${dest}.backup"
    else
      cp -av "$dest" "${dest}.backup"
    fi
  fi
}

install_file() {
  local src="$1" dest="$2" mode="$3"
  if [ "$DRY_RUN" = 1 ]; then
    say "Would install $src -> $dest (mode $mode)"
  else
    install -m "$mode" -o root -g root "$src" "$dest"
  fi
}

install_from_repo() {
  mkdir -p "$DEST_DIR" "$EVENTS_DIR"

  backup_if_changed "$REPO_ACPI_DIR/hypr-utils.sh" "$DEST_DIR/hypr-utils.sh"
  install_file      "$REPO_ACPI_DIR/hypr-utils.sh" "$DEST_DIR/hypr-utils.sh" 0755

  backup_if_changed "$REPO_ACPI_DIR/lid-open.sh" "$DEST_DIR/lid-open.sh"
  install_file      "$REPO_ACPI_DIR/lid-open.sh"  "$DEST_DIR/lid-open.sh"  0755

  backup_if_changed "$REPO_ACPI_DIR/lid-close.sh" "$DEST_DIR/lid-close.sh"
  install_file      "$REPO_ACPI_DIR/lid-close.sh" "$DEST_DIR/lid-close.sh" 0755

  backup_if_changed "$REPO_ACPI_DIR/check-lid-on-startup.sh" "$DEST_DIR/check-lid-on-startup.sh"
  install_file      "$REPO_ACPI_DIR/check-lid-on-startup.sh" "$DEST_DIR/check-lid-on-startup.sh" 0755
}

update_events() {
  if [ "$DRY_RUN" = 1 ]; then
    say "Would write $EVENTS_DIR/lid-close with regex event"
    say "Would write $EVENTS_DIR/lid-open with regex event"
  else
    install -m 0644 -o root -g root /dev/stdin "$EVENTS_DIR/lid-close" <<'EOF'
event=button/lid.*close
action=/etc/acpi/lid-close.sh
EOF
    install -m 0644 -o root -g root /dev/stdin "$EVENTS_DIR/lid-open" <<'EOF'
event=button/lid.*open
action=/etc/acpi/lid-open.sh
EOF
  fi
}

post_install() {
  # Ensure log file exists and is writable by both root and user sessions
  if [ "$DRY_RUN" = 1 ]; then
    say "Would touch $LOG_FILE and chmod 666"
  else
    touch "$LOG_FILE"
    chmod 666 "$LOG_FILE" || true
  fi

  if [ "$NO_RESTART" = 1 ]; then
    say "Skipping acpid restart (--no-restart)"
  else
    if [ "$DRY_RUN" = 1 ]; then
      say "Would restart acpid"
    else
      if command -v systemctl >/dev/null 2>&1; then
        systemctl restart acpid || {
          echo "Warning: could not restart acpid. Ensure it is installed and running." >&2
        }
      else
        echo "Note: systemctl not found; please restart acpid manually if needed." >&2
      fi
    fi
  fi
}

ensure_hyprland_hooks() {
  local target_user
  target_user="${SUDO_USER:-$(logname 2>/dev/null || echo "${USER:-}")}"
  if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
    say "Skipping Hyprland hook: unable to determine non-root user context"
    return
  fi

  local target_home
  target_home=$(getent passwd "$target_user" | cut -d: -f6 2>/dev/null || true)
  if [ -z "$target_home" ]; then
    target_home=$(eval echo "~$target_user")
  fi
  if [ -z "$target_home" ]; then
    say "Skipping Hyprland hook: could not resolve home for $target_user"
    return
  fi

  local candidates=(
    "$target_home/.config/hypr/hyprland.conf"
    "$target_home/.config/omarchy/current/theme/hyprland.conf"
  )

  local updated=0
  for conf in "${candidates[@]}"; do
    [ -f "$conf" ] || continue
    if grep -Fq '/etc/acpi/check-lid-on-startup.sh' "$conf"; then
      say "Hyprland hook already present in $conf"
      continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
      say "Would append Hyprland auto-switch hook to $conf"
    else
      say "Appending Hyprland auto-switch hook to $conf"
      run_as_user "$target_user" bash -c "cat <<'EOF' >> '$conf'

# Monitor auto-switch startup hook (managed by install-monitor-auto-switch.sh)
exec-once = /etc/acpi/check-lid-on-startup.sh
exec = /etc/acpi/check-lid-on-startup.sh
EOF"
    fi
    updated=1
  done

  if [ "$updated" -eq 0 ]; then
    say "Note: No Hyprland config files were updated automatically; add the exec hooks manually if needed."
  fi
}

invoke_startup_check() {
  if [ "$DRY_RUN" = 1 ]; then
    say "Would run ${DEST_DIR}/check-lid-on-startup.sh to synchronise layout immediately"
    return
  fi

  if ! command -v pgrep >/dev/null 2>&1; then
    say "pgrep not available; skipping immediate startup lid check"
    return
  fi

  if pgrep -x Hyprland >/dev/null 2>&1; then
    say "Hyprland detected; running ${DEST_DIR}/check-lid-on-startup.sh for immediate layout sync"
    if ! "${DEST_DIR}/check-lid-on-startup.sh"; then
      echo "Warning: ${DEST_DIR}/check-lid-on-startup.sh exited with a non-zero status." >&2
    fi
  else
    say "Hyprland not running; skipping immediate startup lid check"
  fi
}

validate_src() {
  local missing=0
  for f in hypr-utils.sh lid-open.sh lid-close.sh check-lid-on-startup.sh; do
    if [ ! -f "$REPO_ACPI_DIR/$f" ]; then
      echo "Missing: $REPO_ACPI_DIR/$f" >&2
      missing=1
    fi
  done
  if [ "$missing" = 1 ]; then
    echo "Source directory invalid. Use --src DIR to point at the directory containing the ACPI scripts." >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  # Allow --help without root
  if [ "$DRY_RUN" != 1 ]; then
    need_sudo
  fi

  validate_src
  install_from_repo
  update_events
  post_install
  ensure_hyprland_hooks
  invoke_startup_check

  say "Install complete. You can test with:"
  say "  sudo ${DEST_DIR}/lid-close.sh"
  say "  sudo ${DEST_DIR}/lid-open.sh"
}

main "$@"
