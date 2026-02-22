#!/bin/bash
set -Euo pipefail

# Uninstaller for Super Shift S Gaming Mode Installer
# Reverses changes made by Super_shift_S_release.sh

info() { echo "[*] $*"; }
warn() { echo "[!] $*"; }
err() { echo "[!] $*" >&2; }

REMOVED=0
SKIPPED=0
FAILED=0

remove_file() {
  local file="$1"
  local description="${2:-}"
  if sudo test -f "$file" 2>/dev/null; then
    if sudo rm -f "$file"; then
      info "Removed: $file${description:+ ($description)}"
      ((REMOVED++)) || true
    else
      err "Failed to remove: $file"
      ((FAILED++)) || true
    fi
  else
    ((SKIPPED++)) || true
  fi
}

remove_dir_if_empty() {
  local dir="$1"
  if sudo test -d "$dir" 2>/dev/null; then
    if sudo rmdir "$dir" 2>/dev/null; then
      info "Removed empty directory: $dir"
    fi
  fi
}

echo ""
echo "================================================================"
echo "  SUPER SHIFT S GAMING MODE UNINSTALLER"
echo "================================================================"
echo ""
echo "  This will remove all files and configurations created by"
echo "  the Super Shift S Gaming Mode installer."
echo ""
echo "  The following will NOT be removed (too risky / shared):"
echo "    - Installed packages (steam, gamescope, drivers, etc.)"
echo "    - Bootloader changes (nvidia-drm.modeset=1)"
echo "    - User group memberships (video, input, wheel)"
echo ""
read -p "Proceed with uninstall? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Uninstall cancelled."
  exit 0
fi

sudo -v || {
  err "sudo authentication required"
  exit 1
}

# --- Kill any running gaming mode processes ---
echo ""
info "Stopping any running gaming mode processes..."
pkill -f steam-library-mount 2>/dev/null || true
pkill -f gaming-keybind-monitor 2>/dev/null || true
pkill -f gamescope-session-nm-wrapper 2>/dev/null || true

# --- Scripts in /usr/local/bin ---
echo ""
info "Removing scripts from /usr/local/bin..."
remove_file "/usr/local/bin/gamescope-session-nm-wrapper" "ChimeraOS session wrapper"
remove_file "/usr/local/bin/gaming-session-switch" "Session switching helper"
remove_file "/usr/local/bin/switch-to-gaming" "Hyprland to Gaming Mode switcher"
remove_file "/usr/local/bin/switch-to-desktop" "Gaming Mode to Desktop switcher"
remove_file "/usr/local/bin/gaming-keybind-monitor" "Super+Shift+R keybind monitor"
remove_file "/usr/local/bin/gamescope-nm-start" "NetworkManager start script"
remove_file "/usr/local/bin/gamescope-nm-stop" "NetworkManager stop script"
remove_file "/usr/local/bin/steam-library-mount" "Steam library drive mount script"

# --- NVIDIA gamescope wrapper ---
echo ""
info "Removing NVIDIA gamescope wrapper..."
remove_file "/usr/local/lib/gamescope-nvidia/gamescope" "NVIDIA gamescope wrapper"
remove_dir_if_empty "/usr/local/lib/gamescope-nvidia"

# --- Session / system files ---
echo ""
info "Removing session and system files..."
remove_file "/usr/share/wayland-sessions/gamescope-session-steam-nm.desktop" "SDDM session entry"
remove_file "/usr/lib/os-session-select" "Steam Exit to Desktop handler"

# --- /etc config files ---
echo ""
info "Removing system configuration files..."
remove_file "/etc/sddm.conf.d/zz-gaming-session.conf" "SDDM session switching config"
remove_file "/etc/polkit-1/rules.d/50-gamescope-networkmanager.rules" "Polkit NM rules"
remove_file "/etc/polkit-1/rules.d/50-udisks-gaming.rules" "Polkit udisks2 rules"
remove_file "/etc/sudoers.d/gaming-session-switch" "Session switching sudoers"
remove_file "/etc/sudoers.d/gaming-mode-sysctl" "Performance sudoers"
remove_file "/etc/udev/rules.d/99-gaming-performance.rules" "Udev performance rules"
remove_file "/etc/security/limits.d/99-gaming-memlock.conf" "Memlock limits"
remove_file "/etc/pipewire/pipewire.conf.d/10-gaming-latency.conf" "PipeWire low-latency"
remove_file "/etc/environment.d/99-shader-cache.conf" "Shader cache config"
remove_file "/etc/environment.d/90-nvidia-gamescope.conf" "NVIDIA gamescope env"
remove_file "/etc/NetworkManager/conf.d/10-iwd-backend.conf" "NM iwd backend config"
remove_file "/etc/NetworkManager/conf.d/20-unmanaged-systemd.conf" "NM systemd coexistence"

# Clean up empty parent dirs that the installer may have created
remove_dir_if_empty "/etc/pipewire/pipewire.conf.d"
remove_dir_if_empty "/etc/environment.d"
remove_dir_if_empty "/etc/NetworkManager/conf.d"

# --- Reload udev rules after removing them ---
if ! sudo test -f /etc/udev/rules.d/99-gaming-performance.rules 2>/dev/null; then
  sudo udevadm control --reload-rules 2>/dev/null || true
fi

# --- Restart polkit if rules were removed ---
sudo systemctl restart polkit.service 2>/dev/null || true

# --- User config files ---
echo ""
info "Removing user configuration files..."
remove_file "$HOME/.config/environment.d/gamescope-session-plus.conf" "Gamescope session config"
remove_file "$HOME/.config/environment.d/90-fcitx-wayland.conf" "Fcitx Wayland silence"

# --- Hyprland bindings.conf: remove the gaming mode keybind ---
echo ""
info "Cleaning up Hyprland config..."
HYPR_BINDINGS="$HOME/.config/hypr/bindings.conf"
if [[ -f "$HYPR_BINDINGS" ]]; then
  if grep -q "switch-to-gaming" "$HYPR_BINDINGS" 2>/dev/null; then
    # Remove the keybind line and any blank line immediately before it
    sed -i '/^$/N;/\n.*switch-to-gaming/d' "$HYPR_BINDINGS"
    # If the simple approach missed it, remove the line directly
    sed -i '/switch-to-gaming/d' "$HYPR_BINDINGS"
    info "Removed Gaming Mode keybind from $HYPR_BINDINGS"
    ((REMOVED++)) || true
  else
    ((SKIPPED++)) || true
  fi
fi

# --- Hyprland hyprland.conf: remove fcitx env line added by installer ---
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [[ -f "$HYPR_CONF" ]]; then
  if grep -q "FCITX_NO_WAYLAND_DIAGNOSE" "$HYPR_CONF" 2>/dev/null; then
    sed -i '/# Silence fcitx5 Wayland diagnose warning (gaming-mode installer)/d' "$HYPR_CONF"
    sed -i '/env = FCITX_NO_WAYLAND_DIAGNOSE,1/d' "$HYPR_CONF"
    info "Removed FCITX_NO_WAYLAND_DIAGNOSE from $HYPR_CONF"
    ((REMOVED++)) || true
  else
    ((SKIPPED++)) || true
  fi
fi

# --- Elephant launcher config: remove uwsm-app launch_prefix ---
ELEPHANT_CFG="$HOME/.config/elephant/desktopapplications.toml"
if [[ -f "$ELEPHANT_CFG" ]]; then
  if grep -q '^launch_prefix[[:space:]]*=[[:space:]]*"uwsm-app --"' "$ELEPHANT_CFG" 2>/dev/null; then
    sed -i '/^launch_prefix[[:space:]]*=[[:space:]]*"uwsm-app --"/d' "$ELEPHANT_CFG"
    info "Removed uwsm-app launch_prefix from $ELEPHANT_CFG"
    ((REMOVED++)) || true
  else
    ((SKIPPED++)) || true
  fi
fi

# --- Remove gamescope cap_sys_nice capability ---
if command -v gamescope >/dev/null 2>&1; then
  if getcap "$(command -v gamescope)" 2>/dev/null | grep -q 'cap_sys_nice'; then
    if sudo setcap -r "$(command -v gamescope)" 2>/dev/null; then
      info "Removed cap_sys_nice from gamescope"
      ((REMOVED++)) || true
    else
      warn "Failed to remove capability from gamescope"
      ((FAILED++)) || true
    fi
  fi
fi

# --- Remove temporary runtime files ---
rm -f /tmp/.gaming-session-active 2>/dev/null || true

# --- Offer to remove AUR gaming session packages ---
echo ""
echo "================================================================"
echo "  AUR PACKAGE REMOVAL (OPTIONAL)"
echo "================================================================"
echo ""

aur_packages_installed=()
for pkg in gamescope-session-git gamescope-session gamescope-session-steam-git gamescope-session-steam; do
  if pacman -Qi "$pkg" &>/dev/null; then
    aur_packages_installed+=("$pkg")
  fi
done

if ((${#aur_packages_installed[@]})); then
  echo "  The following AUR gaming session packages are still installed:"
  for pkg in "${aur_packages_installed[@]}"; do
    echo "    - $pkg"
  done
  echo ""
  read -p "Remove these packages? [y/N]: " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    if sudo pacman -Rns --noconfirm "${aur_packages_installed[@]}"; then
      info "Removed AUR gaming session packages"
    else
      warn "Failed to remove some packages"
    fi
  else
    info "Keeping AUR packages"
  fi
else
  info "No AUR gaming session packages found"
fi

# --- Reload Hyprland if running ---
if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 && info "Hyprland config reloaded" || true
fi

# --- Summary ---
echo ""
echo "================================================================"
echo "  UNINSTALL COMPLETE"
echo "================================================================"
echo ""
echo "  Removed:  $REMOVED items"
echo "  Skipped:  $SKIPPED items (not found / already clean)"
echo "  Failed:   $FAILED items"
echo ""
echo "  NOT removed (manual action if desired):"
echo "    - Installed packages (steam, gamescope, drivers, libs, etc.)"
echo "    - Bootloader changes (nvidia-drm.modeset=1)"
echo "    - User group memberships (video, input, wheel)"
echo ""
if ((FAILED > 0)); then
  echo "  Some items failed to remove. Check errors above."
  echo ""
fi
echo "  A reboot or re-login is recommended to fully clear all changes."
echo "================================================================"
echo ""
