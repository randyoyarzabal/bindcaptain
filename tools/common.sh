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

# BindCaptain version (read from VERSION file at the repo root). Sourced into
# every tool that includes common.sh; surfaced in headers, help text, and
# the chief plugin so users see the same version everywhere.
__bc_resolve_version() {
    local here version_file v
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for version_file in "$here/../VERSION" "$here/VERSION"; do
        if [ -r "$version_file" ]; then
            v="$(head -n1 "$version_file" 2>/dev/null | tr -d '[:space:]')"
            if [ -n "$v" ]; then
                printf 'v%s' "${v#v}"
                return 0
            fi
        fi
    done
    printf 'v0.0.0-unknown'
}
BINDCAPTAIN_VERSION="$(__bc_resolve_version)"

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

# Log a message to the system logger (syslog/journald) and, optionally, to
# a shadow log file kept at its current on-disk location for at-a-glance
# review.
#
#   log_message "<msg>" [<shadow_file>]
#
# - System logger: tagged "bindcaptain", facility user, priority derived
#   from a leading "ERROR:" / "WARNING:" prefix in <msg> (default info).
#   Reachable via: journalctl -t bindcaptain    (RHEL: /var/log/messages)
# - Shadow file: only written when a <shadow_file> path is passed in
#   (callers like __log_action pass $LOG_FILE). Rotation is handled by
#   the logrotate config shipped in config-examples/bindcaptain.logrotate.
#
# Nothing is echoed to stdout — callers that want to surface a status line
# already do so via print_status. This avoids the historical double-print
# in tools that capture stdout for parsing.
log_message() {
    local message="$1"
    local shadow_file="${2:-}"

    local prio="info"
    case "$message" in
        ERROR:*|*"ERROR:"*)     prio="err" ;;
        WARNING:*|*"WARNING:"*) prio="warning" ;;
    esac

    if command -v logger >/dev/null 2>&1; then
        logger -t bindcaptain -p "user.$prio" -- "$message"
    fi

    if [[ -n "$shadow_file" ]]; then
        mkdir -p "$(dirname "$shadow_file")" 2>/dev/null
        printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$shadow_file" 2>/dev/null
    fi
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

# Validate a relative owner name (one or more DNS labels), e.g. mactest or mactest.lab or @
validate_relative_dns_name() {
    local n="$1"
    [[ "$n" == "@" ]] && return 0
    [[ -z "$n" ]] && return 1
    local IFS='.'
    local -a parts
    read -ra parts <<< "$n"
    local p
    for p in "${parts[@]}"; do
        [[ "$p" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$ ]] || return 1
    done
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

# Reload BIND in the podman container: try rndc first, then SIGHUP to the container’s
# main process (named). HUP is safe: it reloads zones without stopping the container
# (unlike podman restart). Use when rndc is misconfigured (e.g. no controls channel).
__reload_bind_podman() {
    if ! is_container_running; then
        return 1
    fi
    if podman exec "$CONTAINER_NAME" /usr/sbin/rndc reload 2>/dev/null; then
        return 0
    fi
    if podman kill -s HUP "$CONTAINER_NAME" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Reload BIND configuration
reload_bind() {
    if is_container_running; then
        if __reload_bind_podman; then
            print_status "success" "BIND reloaded successfully"
            return 0
        fi
        print_status "error" "rndc reload and SIGHUP both failed (container not restarted)"
        return 1
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

    # Container context: validate directly against the container-visible path.
    if is_container; then
        if named-checkconf "$config_file"; then
            print_status "success" "BIND configuration is valid"
            return 0
        fi
        print_status "error" "BIND configuration is invalid"
        return 1
    fi

    # Host with running container: execute named-checkconf inside that container.
    if is_container_running; then
        local check_path="${CONTAINER_NAMED_CONF:-/etc/named.conf}"
        if podman exec "$CONTAINER_NAME" named-checkconf "$check_path"; then
            print_status "success" "BIND configuration is valid"
            return 0
        fi
        print_status "error" "BIND configuration is invalid"
        return 1
    fi

    # Host with container stopped: validate using the bindcaptain image, so we don't
    # require bind-utils on the host.
    if command -v podman >/dev/null 2>&1 && podman image exists "localhost/bindcaptain:latest" >/dev/null 2>&1; then
        if podman run --rm \
            --entrypoint /usr/sbin/named-checkconf \
            -v "$config_file:/etc/named.conf:ro,Z" \
            localhost/bindcaptain:latest /etc/named.conf; then
            print_status "success" "BIND configuration is valid"
            return 0
        fi
        print_status "error" "BIND configuration is invalid"
        return 1
    fi

    # Last-resort fallback if bind-utils is installed on host.
    if command -v named-checkconf >/dev/null 2>&1 && named-checkconf "$config_file"; then
        print_status "success" "BIND configuration is valid"
        return 0
    fi

    print_status "error" "BIND configuration is invalid (no validation runtime available)"
    return 1
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
