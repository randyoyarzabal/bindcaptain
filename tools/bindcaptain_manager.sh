#!/bin/bash

# ⚓ BindCaptain DNS Manager
# Container-aware DNS management for modern BIND infrastructure
# Take command of your DNS records with confidence

# Container configuration
CONTAINER_NAME="bindcaptain"
CONTAINER_DATA_DIR="/opt/bindcaptain"
DOMAIN_CONFIG_BASE="/var/named"

# Use container paths if running in container, host paths if running on host
if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
    # Running inside container
    BIND_DIR="/var/named"
    NAMED_CONF="/etc/named.conf"
    LOG_FILE="/var/log/bind_manager.log"
    BACKUP_DIR="/var/backups/bind"
else
    # Running on host - target the same config the container uses
    BIND_DIR="$CONTAINER_DATA_DIR/config"
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
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
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
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
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
            # Try subdirectory structure first, then fallback to direct path
            local container_zone_file="/var/named/${domain}/${domain}.db"
            if ! podman exec "$CONTAINER_NAME" test -f "$container_zone_file" 2>/dev/null; then
                container_zone_file="/var/named/${domain}.db"
            fi
            
            if podman exec "$CONTAINER_NAME" named-checkzone "$domain" "$container_zone_file" >/dev/null 2>&1; then
                print_status "success" "Zone $domain validation passed (via container)"
                return 0
            else
                print_status "error" "Zone $domain validation failed (via container)"
                podman exec "$CONTAINER_NAME" named-checkzone "$domain" "$container_zone_file"
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
    
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
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

# Function: bind.create_cname
bind.create_cname() {
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
        echo -e "${WHITE}bind.create_cname${NC} - Create DNS CNAME record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bind.create_cname <alias> <domain> <target>"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}alias${NC}      - Alias name (without domain)"
        echo -e "  ${GREEN}domain${NC}     - Domain name (from: ${DOMAINS[*]:-auto-discovered})"
        echo -e "  ${GREEN}target${NC}     - Target hostname (can include domain)"
        echo
        echo -e "${YELLOW}Available Domains:${NC}"
        for domain in "${DOMAINS[@]}"; do
            echo "  - $domain"
        done
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  bind.create_cname www ${DOMAINS[0]:-example.com} webserver"
        echo "  bind.create_cname ftp ${DOMAINS[0]:-example.com} webserver.${DOMAINS[0]:-example.com}."
        return 0
    fi
    
    local alias=$1
    local domain=$2
    local target=$3
    
    print_header
    echo -e "${WHITE}Creating CNAME Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Alias: $alias"
    echo "Domain: $domain"
    echo "Target: $target"
    echo
    
    # Validations
    if ! validate_hostname "$alias"; then
        print_status "error" "Invalid alias: $alias"
        return 1
    fi
    
    if ! validate_domain "$domain"; then
        print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
        return 1
    fi
    
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
    # Check if record already exists
    if grep -q "^${alias}\s" "$zone_file"; then
        print_status "warning" "Record $alias already exists in $domain"
        read -p "Overwrite existing record? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "info" "Operation cancelled"
            return 0
        fi
        # Remove existing record
        sed -i "/^${alias}\s/d" "$zone_file"
    fi
    
    # Backup zone file
    backup_zone "$domain"
    
    # Add new CNAME record
    local record_line="${alias}                 IN      CNAME   ${target}"
    
    # Find the right place to insert (after CNAME Records comment, before other sections)
    if grep -q "; CNAME Records" "$zone_file"; then
        sed -i "/; CNAME Records/a\\$record_line" "$zone_file"
    elif grep -q "; A Records" "$zone_file"; then
        # Insert after A Records section
        sed -i "/; A Records/,/^$/a\\$record_line" "$zone_file"
    else
        echo "$record_line" >> "$zone_file"
    fi
    
    # Increment serial and validate
    increment_serial "$zone_file"
    
    if validate_zone "$domain"; then
        reload_bind
        print_status "success" "CNAME record created: $alias.$domain -> $target"
        log_action "Created CNAME record: $alias.$domain -> $target"
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

# Function: bind.create_txt
bind.create_txt() {
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
        echo -e "${WHITE}bind.create_txt${NC} - Create DNS TXT record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bind.create_txt <name> <domain> <text_value>"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}name${NC}       - Record name (without domain, use @ for domain root)"
        echo -e "  ${GREEN}domain${NC}     - Domain name (from: ${DOMAINS[*]:-auto-discovered})"
        echo -e "  ${GREEN}text_value${NC} - Text value (will be quoted automatically)"
        echo
        echo -e "${YELLOW}Available Domains:${NC}"
        for domain in "${DOMAINS[@]}"; do
            echo "  - $domain"
        done
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  bind.create_txt @ ${DOMAINS[0]:-example.com} 'v=spf1 include:_spf.google.com ~all'"
        echo "  bind.create_txt _dmarc ${DOMAINS[0]:-example.com} 'v=DMARC1; p=none'"
        return 0
    fi
    
    local name=$1
    local domain=$2
    local text_value="$3"
    
    print_header
    echo -e "${WHITE}Creating TXT Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Name: $name"
    echo "Domain: $domain"
    echo "Text: $text_value"
    echo
    
    # Validations
    if [ "$name" != "@" ] && ! validate_hostname "$name"; then
        print_status "error" "Invalid name: $name"
        return 1
    fi
    
    if ! validate_domain "$domain"; then
        print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
        return 1
    fi
    
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
    # Backup zone file
    backup_zone "$domain"
    
    # Add new TXT record
    local record_line="${name}                 IN      TXT     \"${text_value}\""
    
    # Find the right place to insert (append to end of file)
    echo "$record_line" >> "$zone_file"
    
    # Increment serial and validate
    increment_serial "$zone_file"
    
    if validate_zone "$domain"; then
        reload_bind
        print_status "success" "TXT record created: $name.$domain -> \"$text_value\""
        log_action "Created TXT record: $name.$domain -> \"$text_value\""
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

# Function: bind.delete_record
bind.delete_record() {
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
    
    if [ "$show_help" = true ] || [ $# -lt 2 ]; then
        echo -e "${WHITE}bind.delete_record${NC} - Delete DNS record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bind.delete_record <name> <domain> [record_type]"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}name${NC}        - Record name (without domain)"
        echo -e "  ${GREEN}domain${NC}      - Domain name (from: ${DOMAINS[*]:-auto-discovered})"
        echo -e "  ${GREEN}record_type${NC} - Record type (A, CNAME, TXT, etc) - optional"
        echo
        echo -e "${YELLOW}Available Domains:${NC}"
        for domain in "${DOMAINS[@]}"; do
            echo "  - $domain"
        done
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  bind.delete_record webserver ${DOMAINS[0]:-example.com}"
        echo "  bind.delete_record www ${DOMAINS[0]:-example.com} CNAME"
        return 0
    fi
    
    local name=$1
    local domain=$2
    local record_type=${3:-""}
    
    print_header
    echo -e "${WHITE}Deleting DNS Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Name: $name"
    echo "Domain: $domain"
    [ -n "$record_type" ] && echo "Type: $record_type"
    echo
    
    # Validations
    if ! validate_hostname "$name"; then
        print_status "error" "Invalid name: $name"
        return 1
    fi
    
    if ! validate_domain "$domain"; then
        print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
        return 1
    fi
    
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
    # Check if record exists
    local search_pattern="^${name}\s"
    if [ -n "$record_type" ]; then
        search_pattern="^${name}\s.*IN\s*${record_type}\s"
    fi
    
    if ! grep -q "$search_pattern" "$zone_file"; then
        print_status "error" "Record $name not found in $domain"
        return 1
    fi
    
    # Show what will be deleted
    echo -e "${YELLOW}Records to be deleted:${NC}"
    grep "$search_pattern" "$zone_file"
    echo
    
    read -p "Delete these records? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "info" "Operation cancelled"
        return 0
    fi
    
    # Backup zone file
    backup_zone "$domain"
    
    # Delete records
    sed -i "/$search_pattern/d" "$zone_file"
    
    # Increment serial and validate
    increment_serial "$zone_file"
    
    if validate_zone "$domain"; then
        reload_bind
        print_status "success" "Record(s) deleted: $name from $domain"
        log_action "Deleted record: $name from $domain"
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
        local zone_file="$BIND_DIR/${d}/${d}.db"
        if [ ! -f "$zone_file" ]; then
            zone_file="$BIND_DIR/${d}.db"
        fi
        
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

# Function: bind.git_refresh
bind.git_refresh() {
    if [[ "$1" == "--help" ]] || [[ "$1" == "-?" ]]; then
        print_status "info" "bind.git_refresh - Update BindCaptain codebase from GitHub"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bind.git_refresh [--force]"
        echo
        echo -e "${YELLOW}Description:${NC}"
        echo "  Updates the BindCaptain codebase from the GitHub repository"
        echo "  Preserves your local configuration files"
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo "  --force    Force update even if there are uncommitted changes"
        echo
        echo -e "${YELLOW}Examples:${NC}"
        echo "  bind.git_refresh           # Standard update"
        echo "  bind.git_refresh --force   # Force update"
        return 0
    fi

    print_status "info" "Updating BindCaptain codebase from GitHub..."
    
    local force_update="false"
    if [[ "$1" == "--force" ]]; then
        force_update="true"
    fi
    
    # Determine the correct directory
    local bindcaptain_dir
    if [[ -d "/opt/bindcaptain" ]]; then
        bindcaptain_dir="/opt/bindcaptain"
    elif [[ -d "/home/techno/bind" ]]; then
        bindcaptain_dir="/home/techno/bind"
    else
        print_status "error" "BindCaptain directory not found"
        return 1
    fi
    
    print_status "info" "Working in: $bindcaptain_dir"
    
    # Change to the directory
    cd "$bindcaptain_dir" || {
        print_status "error" "Failed to access $bindcaptain_dir"
        return 1
    }
    
    # Check if it's a git repository
    if [[ ! -d ".git" ]]; then
        print_status "error" "Not a git repository. Initialize with: git clone https://github.com/randyoyarzabal/bindcaptain.git"
        return 1
    fi
    
    # Fix git ownership issues when running as root
    if [[ "$EUID" -eq 0 ]]; then
        print_status "info" "Configuring git safe directory for root access..."
        git config --global --add safe.directory "$bindcaptain_dir" 2>/dev/null || true
    fi
    
    # Backup config if it exists
    if [[ -d "config" ]]; then
        print_status "info" "Backing up local configuration..."
        cp -r config config.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    fi
    
    # Check for uncommitted changes
    if ! $force_update && [[ -n "$(git status --porcelain)" ]]; then
        print_status "warning" "Uncommitted changes detected. Use --force to proceed anyway"
        git status --short
        return 1
    fi
    
    # Fetch and pull latest changes
    print_status "info" "Fetching latest changes from GitHub..."
    git fetch origin || {
        print_status "error" "Failed to fetch from remote repository"
        return 1
    }
    
    # Get current branch
    local current_branch
    current_branch=$(git branch --show-current)
    
    print_status "info" "Updating branch: $current_branch"
    git pull origin "$current_branch" || {
        print_status "error" "Failed to pull changes. You may need to resolve conflicts manually"
        return 1
    }
    
    print_status "success" "BindCaptain codebase updated successfully!"
    print_status "info" "If you have a running container, restart it with: sudo /opt/bindcaptain/bindcaptain.sh restart"
    
    return 0
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
        bind.create_cname)
            bind.create_cname "$@"
            ;;
        bind.create_txt)
            bind.create_txt "$@"
            ;;
            bind.delete_record)
                bind.delete_record "$@"
                ;;
            bind.list_records)
                bind.list_records "$@"
                ;;
            bind.git_refresh)
                bind.git_refresh "$@"
                ;;
            show_environment)
                show_environment "$@"
                ;;
        *)
            print_header
            echo -e "${WHITE}Available Commands:${NC}"
            echo
                echo -e "  ${GREEN}bind.create_record${NC}  - Create DNS A record"
                echo -e "  ${GREEN}bind.create_cname${NC}   - Create DNS CNAME record"
                echo -e "  ${GREEN}bind.create_txt${NC}     - Create DNS TXT record"
                echo -e "  ${GREEN}bind.delete_record${NC}  - Delete DNS record"
                echo -e "  ${GREEN}bind.list_records${NC}   - List DNS records"
                echo -e "  ${GREEN}bind.git_refresh${NC}    - Update codebase from GitHub"
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
