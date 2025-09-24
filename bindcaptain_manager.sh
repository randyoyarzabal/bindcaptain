#!/bin/bash

# ⚓ BindCaptain DNS Manager
# Container-aware DNS management for modern BIND infrastructure
# Take command of your DNS records with confidence

# Container configuration
CONTAINER_NAME="bind-dns"
CONTAINER_DATA_DIR="/opt/bind-dns"
DOMAIN_CONFIG_BASE="/var/named"

# Use container paths if running in container, host paths if running on host
if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
    # Running inside container
    BIND_DIR="/var/named"
    NAMED_CONF="/etc/named.conf"
    LOG_FILE="/var/log/bind_manager.log"
    BACKUP_DIR="/var/backups/bind"
else
    # Running on host - target container volumes
    BIND_DIR="$CONTAINER_DATA_DIR/zones"
    NAMED_CONF="$CONTAINER_DATA_DIR/config/named.conf"
    LOG_FILE="$CONTAINER_DATA_DIR/logs/bind_manager.log"
    BACKUP_DIR="$CONTAINER_DATA_DIR/backups"
fi

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

# Auto-discover domains from named.conf
discover_domains() {
    local domains=()
    if [ -f "$NAMED_CONF" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q '^[[:space:]]*zone[[:space:]]\+'; then
                local zone_name=$(echo "$line" | sed 's/.*zone[[:space:]]*"\([^"]*\)".*/\1/')
                # Skip special zones
                if [[ ! "$zone_name" =~ ^(\.|\.|localhost|.*\.arpa)$ ]]; then
                    domains+=("$zone_name")
                fi
            fi
        done < "$NAMED_CONF"
    fi
    printf '%s\n' "${domains[@]}"
}

DOMAINS=($(discover_domains))
DEFAULT_TTL="86400"

# Logging function
log_action() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Print colored output
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "success" ]; then
        echo -e "${GREEN}${CHECK}${NC} $message"
    elif [ "$status" = "error" ]; then
        echo -e "${RED}${CROSS}${NC} $message"
    elif [ "$status" = "warning" ]; then
        echo -e "${YELLOW}${CROSS}${NC} $message"
    elif [ "$status" = "info" ]; then
        echo -e "${BLUE}${CHECK}${NC} $message"
    fi
}

# Header function
print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}  BIND DNS Management Tool${NC}"
    echo -e "${CYAN}  (Container-aware)${NC}"
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

# Validate domain
validate_domain() {
    local domain=$1
    for valid_domain in "${DOMAINS[@]}"; do
        if [ "$domain" = "$valid_domain" ]; then
            return 0
        fi
    done
    return 1
}

# Validate hostname
validate_hostname() {
    local hostname=$1
    if [[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Backup zone file
backup_zone() {
    local domain=$1
    local zone_file="$BIND_DIR/${domain}.db"
    
    if [ ! -f "$zone_file" ]; then
        print_status "error" "Zone file for $domain not found"
        return 1
    fi
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/${domain}.db.backup.$(date +%Y%m%d_%H%M%S)"
    
    if cp "$zone_file" "$backup_file"; then
        print_status "success" "Backed up $domain to $backup_file"
        log_action "Backed up zone $domain"
        return 0
    else
        print_status "error" "Failed to backup $domain"
        return 1
    fi
}

# Increment serial number
increment_serial() {
    local zone_file=$1
    local current_serial=$(grep -E "^\s*[0-9]+\s*;\s*serial" "$zone_file" | awk '{print $1}')
    local new_serial
    
    if [ -z "$current_serial" ]; then
        new_serial=$(date +%Y%m%d01)
    else
        local date_part=${current_serial:0:8}
        local seq_part=${current_serial:8:2}
        local today=$(date +%Y%m%d)
        
        if [ "$date_part" = "$today" ]; then
            new_serial=$((current_serial + 1))
        else
            new_serial="${today}01"
        fi
    fi
    
    sed -i "s/$current_serial\s*;\s*serial/$new_serial         ; serial/" "$zone_file"
    print_status "info" "Updated serial number to $new_serial"
}

# Reload BIND (container-aware)
reload_bind() {
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        # Running inside container
        if systemctl reload named 2>/dev/null || /usr/sbin/rndc reload 2>/dev/null; then
            print_status "success" "BIND reloaded successfully"
            log_action "BIND reloaded"
            return 0
        else
            print_status "error" "Failed to reload BIND"
            return 1
        fi
    else
        # Running on host - reload via container
        if command -v podman &> /dev/null; then
            if podman exec "$CONTAINER_NAME" /usr/sbin/rndc reload 2>/dev/null; then
                print_status "success" "BIND reloaded successfully (via container)"
                log_action "BIND reloaded via container"
                return 0
            else
                print_status "error" "Failed to reload BIND via container"
                return 1
            fi
        else
            print_status "error" "Cannot reload BIND - not in container and podman not available"
            return 1
        fi
    fi
}

# Validate zone file
validate_zone() {
    local domain=$1
    local zone_file="$BIND_DIR/${domain}.db"
    
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        # Running inside container
        if named-checkzone "$domain" "$zone_file" >/dev/null 2>&1; then
            print_status "success" "Zone $domain validation passed"
            return 0
        else
            print_status "error" "Zone $domain validation failed"
            named-checkzone "$domain" "$zone_file"
            return 1
        fi
    else
        # Running on host - validate via container
        if command -v podman &> /dev/null; then
            if podman exec "$CONTAINER_NAME" named-checkzone "$domain" "/var/named/$(basename "$zone_file")" >/dev/null 2>&1; then
                print_status "success" "Zone $domain validation passed (via container)"
                return 0
            else
                print_status "error" "Zone $domain validation failed (via container)"
                podman exec "$CONTAINER_NAME" named-checkzone "$domain" "/var/named/$(basename "$zone_file")"
                return 1
            fi
        else
            print_status "warning" "Cannot validate zone - not in container and podman not available"
            return 0
        fi
    fi
}

# Function: bind.create_record
bind.create_record() {
    local show_help=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -?|--help)
                show_help=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [ "$show_help" = true ] || [ $# -lt 3 ]; then
        echo -e "${WHITE}bind.create_record${NC} - Create DNS A record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bind.create_record <hostname> <domain> <ip_address> [ttl]"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}hostname${NC}   - Host name (without domain)"
        echo -e "  ${GREEN}domain${NC}     - Domain name (from: ${DOMAINS[*]:-auto-discovered})"
        echo -e "  ${GREEN}ip_address${NC} - IPv4 address"
        echo -e "  ${GREEN}ttl${NC}        - Time to live (optional, default: $DEFAULT_TTL)"
        echo
        echo -e "${YELLOW}Available Domains:${NC}"
        for domain in "${DOMAINS[@]}"; do
            echo "  - $domain"
        done
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  bind.create_record webserver ${DOMAINS[0]:-example.com} 172.25.50.100"
        return 0
    fi
    
    local hostname=$1
    local domain=$2
    local ip_address=$3
    local ttl=${4:-$DEFAULT_TTL}
    
    print_header
    echo -e "${WHITE}Creating A Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Hostname: $hostname"
    echo "Domain: $domain"
    echo "IP: $ip_address"
    echo "TTL: $ttl"
    echo
    
    # Validations
    if ! validate_hostname "$hostname"; then
        print_status "error" "Invalid hostname: $hostname"
        return 1
    fi
    
    if ! validate_domain "$domain"; then
        print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
        return 1
    fi
    
    if ! validate_ip "$ip_address"; then
        print_status "error" "Invalid IP address: $ip_address"
        return 1
    fi
    
    local zone_file="$BIND_DIR/${domain}.db"
    
    # Check if record already exists
    if grep -q "^${hostname}\s" "$zone_file"; then
        print_status "warning" "Record $hostname already exists in $domain"
        read -p "Overwrite existing record? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "info" "Operation cancelled"
            return 0
        fi
        # Remove existing record
        sed -i "/^${hostname}\s/d" "$zone_file"
    fi
    
    # Backup zone file
    backup_zone "$domain"
    
    # Add new record
    local record_line="${hostname}                 IN      A       ${ip_address}"
    
    # Find the right place to insert (after A Records comment, before CNAME Records)
    if grep -q "; CNAME Records" "$zone_file"; then
        sed -i "/; CNAME Records/i\\$record_line" "$zone_file"
    elif grep -q "; A Records" "$zone_file"; then
        sed -i "/; A Records/a\\$record_line" "$zone_file"
    else
        echo "$record_line" >> "$zone_file"
    fi
    
    # Increment serial and validate
    increment_serial "$zone_file"
    
    if validate_zone "$domain"; then
        reload_bind
        print_status "success" "A record created: $hostname.$domain -> $ip_address"
        log_action "Created A record: $hostname.$domain -> $ip_address"
    else
        print_status "error" "Zone validation failed, restoring backup"
        # Restore from backup
        local latest_backup=$(ls -t "$BACKUP_DIR/${domain}.db.backup."* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$zone_file"
            print_status "info" "Backup restored"
        fi
        return 1
    fi
}

# Function: bind.list_records
bind.list_records() {
    local show_help=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -?|--help)
                show_help=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [ "$show_help" = true ]; then
        echo -e "${WHITE}bind.list_records${NC} - List DNS records"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bind.list_records [domain] [record_type]"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}domain${NC}      - Domain name (optional, shows all if not specified)"
        echo -e "  ${GREEN}record_type${NC} - Record type filter (A, CNAME, TXT, etc.)"
        echo
        echo -e "${YELLOW}Available Domains:${NC}"
        for domain in "${DOMAINS[@]}"; do
            echo "  - $domain"
        done
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  bind.list_records"
        echo "  bind.list_records ${DOMAINS[0]:-example.com}"
        echo "  bind.list_records ${DOMAINS[0]:-example.com} A"
        return 0
    fi
    
    local domain=${1:-""}
    local record_type=${2:-""}
    
    print_header
    echo -e "${WHITE}DNS Records${NC}"
    echo
    
    if [ -n "$domain" ]; then
        if ! validate_domain "$domain"; then
            print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
            return 1
        fi
        domains=("$domain")
    else
        domains=("${DOMAINS[@]}")
    fi
    
    for d in "${domains[@]}"; do
        local zone_file="$BIND_DIR/${d}.db"
        if [ ! -f "$zone_file" ]; then
            print_status "warning" "Zone file not found for $d"
            continue
        fi
        
        echo -e "${CYAN}=== $d ===${NC}"
        
        if [ -n "$record_type" ]; then
            grep "IN\s*$record_type\s" "$zone_file" | grep -v "^;" | head -20
        else
            grep "IN\s*[A-Z]" "$zone_file" | grep -v "^;" | head -20
        fi
        echo
    done
}

# Show environment info
show_environment() {
    print_header
    echo -e "${WHITE}Environment Information${NC}"
    echo
    echo "Mode: $(if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then echo "Container"; else echo "Host"; fi)"
    echo "BIND Directory: $BIND_DIR"
    echo "Configuration: $NAMED_CONF"
    echo "Log File: $LOG_FILE"
    echo "Backup Directory: $BACKUP_DIR"
    echo "Container Name: $CONTAINER_NAME"
    echo
    echo "Discovered Domains:"
    for domain in "${DOMAINS[@]}"; do
        echo "  - $domain"
    done
    echo
}

# Main function to handle command routing
main() {
    # Create log file if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Check for root privileges
    check_root
    
    # Route to appropriate function
    case "${FUNCNAME[1]}" in
        bind.create_record)
            bind.create_record "$@"
            ;;
        bind.list_records)
            bind.list_records "$@"
            ;;
        show_environment)
            show_environment "$@"
            ;;
        *)
            print_header
            echo -e "${WHITE}Available Commands:${NC}"
            echo
            echo -e "  ${GREEN}bind.create_record${NC}  - Create DNS A record"
            echo -e "  ${GREEN}bind.list_records${NC}   - List DNS records"
            echo -e "  ${GREEN}show_environment${NC}    - Show environment information"
            echo
            echo -e "${YELLOW}Usage:${NC}"
            echo "  source $0"
            echo "  bind.create_record --help"
            echo "  show_environment"
            echo
            echo -e "${YELLOW}Example:${NC}"
            if [ ${#DOMAINS[@]} -gt 0 ]; then
                echo "  bind.create_record webserver ${DOMAINS[0]} 172.25.50.100"
            else
                echo "  bind.create_record webserver example.com 172.25.50.100"
            fi
            ;;
    esac
}

# Only run main if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
