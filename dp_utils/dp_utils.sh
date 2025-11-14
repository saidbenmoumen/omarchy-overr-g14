#!/bin/bash

# Display Manager for Hyprland
# A utility script to manage display configurations on Arch Linux with Hyprland
# Author: Display Utils Script
# Version: 1.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if hyprctl is available
check_hyprland() {
    if ! command -v hyprctl &> /dev/null; then
        error "hyprctl command not found. Make sure Hyprland is installed and running."
        exit 1
    fi
}

# Get all available monitors
get_all_monitors() {
    hyprctl monitors -j | jq -r '.[].name' 2>/dev/null || {
        # Fallback if jq is not available
        hyprctl monitors | grep -E "^Monitor" | awk '{print $2}'
    }
}

# Get all eDP monitors (laptop screens)
get_edp_monitors() {
    get_all_monitors | grep -E "^eDP"
}

# Get all non-eDP monitors (external displays)
get_external_monitors() {
    get_all_monitors | grep -v -E "^eDP"
}

# Disable all monitors
disable_all_monitors() {
    log "Disabling all monitors..."
    local monitors
    monitors=$(get_all_monitors)
    
    if [ -z "$monitors" ]; then
        warning "No monitors found"
        return 1
    fi
    
    while IFS= read -r monitor; do
        if [ -n "$monitor" ]; then
            log "Disabling monitor: $monitor"
            hyprctl keyword monitor "$monitor,disable"
        fi
    done <<< "$monitors"
}

# Enable eDP monitors with auto-detection
enable_edp_monitors() {
    log "Enabling eDP monitors with auto-detection..."
    local edp_monitors
    edp_monitors=$(get_edp_monitors)
    
    if [ -z "$edp_monitors" ]; then
        warning "No eDP monitors found"
        return 1
    fi
    
    while IFS= read -r monitor; do
        if [ -n "$monitor" ]; then
            log "Enabling eDP monitor: $monitor"
            hyprctl keyword monitor "$monitor,preferred,auto,auto"
        fi
    done <<< "$edp_monitors"
    
    success "eDP monitors enabled successfully"
}

# Main function: dp_laptop - Enable only laptop screen (eDP monitors)
dp_laptop() {
    log "Starting dp_laptop: Switching to laptop-only display mode"
    
    # Check if Hyprland is running
    check_hyprland
    
    # Get current monitors for logging
    local all_monitors
    all_monitors=$(get_all_monitors)
    log "Current monitors detected: $(echo "$all_monitors" | tr '\n' ' ')"
    
    # Get eDP monitors
    local edp_monitors
    edp_monitors=$(get_edp_monitors)
    
    if [ -z "$edp_monitors" ]; then
        error "No eDP monitors found. Cannot switch to laptop mode."
        return 1
    fi
    
    log "eDP monitors found: $(echo "$edp_monitors" | tr '\n' ' ')"
    
    # Disable all monitors first
    disable_all_monitors
    
    # Small delay to ensure monitors are disabled
    sleep 1
    
    # Enable only eDP monitors
    enable_edp_monitors
    
    success "Successfully switched to laptop-only display mode"
    
    # Show final monitor status
    log "Final monitor configuration:"
    hyprctl monitors | grep -E "(Monitor|disabled)" || true
}

# Help function
show_help() {
    echo "Display Manager for Hyprland - dp_utils.sh"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  dp_laptop    Enable only laptop screen (eDP monitors)"
    echo "  help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dp_laptop    # Switch to laptop-only display mode"
    echo ""
    echo "Notes:"
    echo "  - This script uses hyprctl commands for Hyprland"
    echo "  - Auto-detection is used for resolution, refresh rate, scale, and position"
    echo "  - eDP monitors are considered laptop screens"
}

# Main script logic
main() {
    case "${1:-}" in
        "dp_laptop")
            dp_laptop
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            error "No command specified. Use 'help' for usage information."
            exit 1
            ;;
        *)
            error "Unknown command: $1. Use 'help' for usage information."
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
