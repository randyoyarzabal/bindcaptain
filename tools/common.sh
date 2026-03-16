#!/bin/bash

# ⚓ BindCaptain Common Utilities
# Shared functions and configurations for all BindCaptain scripts
# Navigate DNS complexity with captain-grade precision

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Icons
CHECK="✓"
CROSS="✗"
WARNING="⚠"
INFO="ℹ"

# Container configuration
CONTAINER_NAME="bindcaptain"
CONTAINER_DATA_DIR="/opt/bindcaptain"
DOMAIN_CONFIG_BASE="/var/named"

# Detect if running inside container
is_container() {
    [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]
}

# Get appropriate paths based on execution context
# When on host, CONTAINER_NAMED_CONF is the path used inside the container (for podman exec).
get_bind_paths() {
    if is_container; then
        # Running inside container
        BIND_DIR="/var/named"
        NAMED_CONF="/etc/named.conf"
        LOG_DIR="/var/log/named"
        CONTAINER_NAMED_CONF="/etc/named.conf"
    else
        # Running on host - target the same config the container uses (host paths)
        BIND_DIR="$CONTAINER_DATA_DIR/config"
        NAMED_CONF="$CONTAINER_DATA_DIR/config/named.conf"
        LOG_DIR="$CONTAINER_DATA_DIR/logs"
        # Path as seen inside the container (bindcaptain.sh mounts named.conf at /etc/named.conf)
        CONTAINER_NAMED_CONF="/etc/named.conf"
    fi
}

# Print colored status messages
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}${CHECK}${NC} $message" ;;
        "error") echo -e "${RED}${CROSS}${NC} $message" ;;
        "warning") echo -e "${YELLOW}${WARNING}${NC} $message" ;;
        "info") echo -e "${BLUE}${INFO}${NC} $message" ;;
        "debug") echo -e "${PURPLE}[DEBUG]${NC} $message" ;;
        *) echo -e "$message" ;;
    esac
}

# Print header with optional subtitle
print_header() {
    local title="${1:-BindCaptain}"
    local subtitle="${2:-}"
    
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}  $title${NC}"
    if [ -n "$subtitle" ]; then
        echo -e "${CYAN}  $subtitle${NC}"
    fi
    echo -e "${CYAN}================================${NC}"
    echo
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_status "error" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if podman is installed
check_podman() {
    if ! command -v podman &> /dev/null; then
        print_status "error" "Podman is not installed"
        echo "  Install with: dnf install podman"
        exit 1
    fi
    print_status "success" "Podman is available"
}

# Log messages with timestamp
log_message() {
    local message="$1"
    local log_file="${2:-/var/log/bindcaptain.log}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"
    
    # Log with timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$log_file"
}

# Validate domain name
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a ip_parts=($ip)
        for part in "${ip_parts[@]}"; do
            if ((part > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate hostname
validate_hostname() {
    local hostname="$1"
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    return 0
}

# Check if container is running
is_container_running() {
    if command -v podman &> /dev/null; then
        podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
    else
        return 1
    fi
}

# Execute command in container if available, otherwise on host
exec_in_context() {
    local command="$1"
    
    if is_container_running; then
        podman exec "$CONTAINER_NAME" $command
    else
        eval $command
    fi
}

# Reload BIND configuration
reload_bind() {
    if is_container_running; then
        if podman exec "$CONTAINER_NAME" /usr/sbin/rndc reload 2>/dev/null; then
            print_status "success" "BIND reloaded successfully"
            return 0
        else
            print_status "warning" "rndc reload failed, attempting container restart..."
            if podman restart "$CONTAINER_NAME" >/dev/null 2>&1; then
                print_status "success" "BIND reloaded via container restart"
                return 0
            else
                print_status "error" "Failed to reload BIND via container"
                return 1
            fi
        fi
    else
        print_status "error" "Cannot reload BIND - container not running"
        return 1
    fi
}

# Validate BIND configuration
# When on host with container running, uses container path (/etc/named.conf) for named-checkconf.
validate_bind_config() {
    local config_file="${1:-$NAMED_CONF}"
    
    if [ ! -f "$config_file" ]; then
        print_status "error" "Configuration file not found: $config_file"
        return 1
    fi
    
    local check_path="$config_file"
    if ! is_container && is_container_running; then
        # When we exec into the container, use the path inside the container (mount is at /etc/named.conf)
        check_path="${CONTAINER_NAMED_CONF:-/etc/named.conf}"
    fi
    if exec_in_context "named-checkconf $check_path"; then
        print_status "success" "BIND configuration is valid"
        return 0
    else
        print_status "error" "BIND configuration is invalid"
        return 1
    fi
}

# Discover domains from named.conf
discover_domains() {
    local domains=()
    local config_file="${1:-$NAMED_CONF}"
    
    if [ -f "$config_file" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q '^[[:space:]]*zone[[:space:]]\+'; then
                local zone_name=$(echo "$line" | sed 's/.*zone[[:space:]]*"\([^"]*\)".*/\1/')
                # Skip special zones
                if [[ ! "$zone_name" =~ ^(\.|\.|localhost|.*\.arpa)$ ]]; then
                    domains+=("$zone_name")
                fi
            fi
        done < "$config_file"
    fi
    printf '%s\n' "${domains[@]}"
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    local backup_dir="${2:-$(dirname "$file")/backups}"
    
    if [ ! -f "$file" ]; then
        print_status "error" "File not found: $file"
        return 1
    fi
    
    mkdir -p "$backup_dir"
    local backup_file="${backup_dir}/$(basename "$file").$(date +%Y%m%d_%H%M%S).bak"
    
    if cp "$file" "$backup_file"; then
        print_status "success" "Backed up $file to $backup_file"
        echo "$backup_file"
        return 0
    else
        print_status "error" "Failed to backup $file"
        return 1
    fi
}

# Show usage information
show_usage() {
    local script_name="$1"
    local description="$2"
    local usage="$3"
    
    print_header "$script_name" "$description"
    echo "Usage: $usage"
    echo
}

# Initialize common variables
init_common() {
    # Set up paths based on execution context
    get_bind_paths
    
    # Export commonly used variables
    export CONTAINER_NAME
    export CONTAINER_DATA_DIR
    export BIND_DIR
    export NAMED_CONF
    export LOG_DIR
}

# Source this file to initialize common utilities
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    init_common
fi
