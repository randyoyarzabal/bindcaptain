#!/bin/bash

# ⚓ BindCaptain DNS Manager
# Container-aware DNS management for modern BIND infrastructure
# Take command of your DNS records with confidence
#
# USAGE:
#   # As a library (recommended for interactive use)
#   source ./tools/bindcaptain_manager.sh
#   bc.create_record webserver example.com 192.168.1.100
#
#   # As a direct command
#   sudo ./tools/bindcaptain_manager.sh refresh
#
# FUNCTIONS:
#   bc.create_record    - Create DNS A record
#   bc.create_cname     - Create DNS CNAME record
#   bc.create_txt       - Create DNS TXT record
#   bc.delete_record    - Delete DNS record
#   bc.list_records     - List DNS records
#   refresh               - Refresh and validate DNS configuration
#   show_environment      - Show environment information
#
# EXAMPLES:
#   # Create A record
#   bc.create_record webserver example.com 192.168.1.100
#
#   # Create CNAME record
#   bc.create_cname www example.com webserver
#
#   # Create TXT record
#   bc.create_txt @ example.com "v=spf1 -all"
#
#   # List all records
#   bc.list_records
#
#   # Refresh DNS configuration
#   ./tools/bindcaptain_manager.sh refresh
#
# FEATURES:
#   - Container-aware (works inside and outside containers)
#   - Automatic PTR record creation for A records
#   - Zone file validation and backup
#   - Interactive record management
#   - BIND reload and validation
#   - Comprehensive logging
#
# REQUIREMENTS:
#   - Root privileges (sudo)
#   - BindCaptain container running (for some operations)
#   - Valid DNS configuration

set -e

# Resolve script path so sourcing works when invoked via symlink (e.g. chief.plugin).
# Otherwise SCRIPT_DIR points to the symlink's directory and source of common.sh fails, exiting the shell.
_resolve_script_path() {
    local path="$1"
    while [ -L "$path" ]; do
        local dir
        dir="$(dirname "$path")"
        local link
        link="$(readlink "$path")"
        if [[ "$link" = /* ]]; then
            path="$link"
        else
            path="$dir/$link"
        fi
    done
    echo "$path"
}

# Load common utilities (use resolved path so symlinked source finds common.sh)
SCRIPT_SOURCE="$(_resolve_script_path "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Manager-specific configuration
LOG_FILE="$LOG_DIR/bind_manager.log"
BACKUP_DIR="$CONTAINER_DATA_DIR/backups"

# Backup control - disabled by default
ENABLE_BACKUPS="${BINDCAPTAIN_ENABLE_BACKUPS:-false}"

# Manager-specific variables
DOMAINS=($(discover_domains))
DEFAULT_TTL="86400"

# Manager-specific logging function
log_action() {
    log_message "$1" "$LOG_FILE"
}

# Parse FQDN to extract hostname and domain
# Usage: parse_fqdn "webserver.homelab.io" 
# Returns: hostname domain (space separated)
parse_fqdn() {
    local input="$1"
    
    # If no dot, return as-is (just hostname)
    if [[ ! "$input" =~ \. ]]; then
        echo "$input"
        return 0
    fi
    
    # Try to match against configured domains
    for domain in "${DOMAINS[@]}"; do
        if [[ "$input" == *".$domain" ]]; then
            local hostname="${input%.$domain}"
            echo "$hostname $domain"
            return 0
        fi
    done
    
    # If no match, try to split on first dot
    local hostname="${input%%.*}"
    local domain="${input#*.}"
    echo "$hostname $domain"
    return 0
}

# Custom header for this script
print_manager_header() {
    print_header "BIND DNS Management Tool" "(Container-aware)"
}

# Manager-specific domain validation (checks against discovered domains)
validate_domain_in_config() {
    local domain=$1
    for valid_domain in "${DOMAINS[@]}"; do
        if [ "$domain" = "$valid_domain" ]; then
            return 0
        fi
    done
    return 1
}

# Backup zone file
backup_zone() {
    # Skip backup if disabled
    if [[ "$ENABLE_BACKUPS" != "true" ]]; then
        return 0
    fi
    
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
                print_status "warning" "rndc reload failed, attempting container restart..."
                if podman restart "$CONTAINER_NAME" >/dev/null 2>&1; then
                    sleep 3  # Give container time to start
                    print_status "success" "BIND reloaded via container restart"
                    log_action "BIND reloaded via container restart"
                    return 0
                else
                    print_status "error" "Failed to reload BIND via container"
                    return 1
                fi
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

# Create PTR record for given IP and hostname
create_ptr_record() {
    local ip_address=$1
    local hostname=$2
    local domain=$3
    
    # Define networks and their reverse zones
    local networks=(
        "172.25.40:40.25.172.in-addr.arpa:reonetlabs.us"
        "172.25.42:42.25.172.in-addr.arpa:reonetlabs.us" 
        "172.25.50:50.25.172.in-addr.arpa:reonetlabs.us"
    )
    
    # Determine which reverse zone this IP belongs to
    for network in "${networks[@]}"; do
        local subnet=$(echo "$network" | cut -d: -f1)
        local reverse_zone=$(echo "$network" | cut -d: -f2)
        local reverse_domain=$(echo "$network" | cut -d: -f3)
        
        if [[ "$ip_address" == ${subnet}.* ]]; then
            local last_octet=$(echo "$ip_address" | cut -d. -f4)
            local ptr_record="${last_octet}			IN	PTR	${hostname}.${domain}."
            local reverse_file="$BIND_DIR/${reverse_domain}/${reverse_zone}.db"
            
            if [ -f "$reverse_file" ]; then
                # Check if PTR record already exists for this IP
                if grep -q "^${last_octet}.*PTR" "$reverse_file"; then
                    # Remove existing PTR record for this IP
                    sed -i "/^${last_octet}.*PTR/d" "$reverse_file"
                    print_status "info" "Removed existing PTR record for $ip_address"
                fi
                
                # Add new PTR record
                echo "$ptr_record" >> "$reverse_file"
                
                # Increment serial number in reverse zone
                increment_serial "$reverse_file"
                
                print_status "success" "PTR record created: $ip_address -> ${hostname}.${domain}"
                log_action "Created PTR record: $ip_address -> ${hostname}.${domain}"
                return 0
            else
                print_status "warning" "Reverse zone file not found: $reverse_file"
                return 1
            fi
        fi
    done
    
    print_status "warning" "No matching reverse zone found for IP: $ip_address"
    return 1
}

# Function: bc.create_record
bc.create_record() {
    local show_help=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -?|--help)
                show_help=true
                shift
                ;;
            --backup)
                ENABLE_BACKUPS=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [ "$show_help" = true ] || [ $# -lt 2 ]; then
        echo -e "${WHITE}bc.create_record${NC} - Create DNS A record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bc.create_record [--backup] <fqdn> <ip_address> [ttl]"
        echo "  bc.create_record [--backup] <hostname> <domain> <ip_address> [ttl]"
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo -e "  ${GREEN}--backup${NC}   - Create backup before modification (disabled by default)"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}fqdn${NC}       - Fully qualified domain name (e.g., webserver.homelab.io)"
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
        echo "  bc.create_record webserver.${DOMAINS[0]:-example.com} 172.25.50.100"
        echo "  bc.create_record webserver ${DOMAINS[0]:-example.com} 172.25.50.100"
        echo "  bc.create_record --backup webserver ${DOMAINS[0]:-example.com} 172.25.50.100"
        return 0
    fi
    
    # Parse arguments - support both FQDN and hostname+domain formats
    local hostname domain ip_address ttl
    if [ $# -eq 2 ] || [ $# -eq 3 ]; then
        # FQDN format: <fqdn> <ip> [ttl]
        read hostname domain <<< $(parse_fqdn "$1")
        ip_address=$2
        ttl=${3:-$DEFAULT_TTL}
        
        # If domain wasn't extracted, treat first arg as hostname and fail
        if [ -z "$domain" ]; then
            print_status "error" "Could not parse domain from '$1'. Available domains: ${DOMAINS[*]}"
            return 1
        fi
    elif [ $# -ge 3 ]; then
        # Traditional format: <hostname> <domain> <ip> [ttl]
        hostname=$1
        domain=$2
        ip_address=$3
        ttl=${4:-$DEFAULT_TTL}
    else
        print_status "error" "Invalid arguments. Use --help for usage."
        return 1
    fi
    
    print_manager_header
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
    
    if ! validate_domain_in_config "$domain"; then
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
        
        # In non-interactive mode, fail rather than overwrite
        if [ "${BIND_NONINTERACTIVE:-0}" = "1" ]; then
            print_status "error" "Record already exists (use delete first, or run interactively to overwrite)"
            return 1
        else
            read -p "Overwrite existing record? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "info" "Operation cancelled"
                return 0
            fi
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
        # Create corresponding PTR record before reload
        create_ptr_record "$ip_address" "$hostname" "$domain"
        
        # Reload BIND to pick up both forward and reverse zone changes
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

# Function: bc.create_cname
bc.create_cname() {
    local show_help=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -?|--help)
                show_help=true
                shift
                ;;
            --backup)
                ENABLE_BACKUPS=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [ "$show_help" = true ] || [ $# -lt 2 ]; then
        echo -e "${WHITE}bc.create_cname${NC} - Create DNS CNAME record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bc.create_cname [--backup] <fqdn> <target>"
        echo "  bc.create_cname [--backup] <alias> <domain> <target>"
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo -e "  ${GREEN}--backup${NC}   - Create backup before modification (disabled by default)"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}fqdn${NC}       - Fully qualified domain name for alias (e.g., www.homelab.io)"
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
        echo "  bc.create_cname www.${DOMAINS[0]:-example.com} webserver"
        echo "  bc.create_cname www ${DOMAINS[0]:-example.com} webserver"
        echo "  bc.create_cname --backup www ${DOMAINS[0]:-example.com} webserver"
        return 0
    fi
    
    # Parse arguments - support both FQDN and alias+domain formats
    local alias domain target
    if [ $# -eq 2 ]; then
        # FQDN format: <fqdn> <target>
        read alias domain <<< $(parse_fqdn "$1")
        target=$2
        
        # If domain wasn't extracted, treat first arg as alias and fail
        if [ -z "$domain" ]; then
            print_status "error" "Could not parse domain from '$1'. Available domains: ${DOMAINS[*]}"
            return 1
        fi
    elif [ $# -eq 3 ]; then
        # Traditional format: <alias> <domain> <target>
        alias=$1
        domain=$2
        target=$3
    else
        print_status "error" "Invalid arguments. Use --help for usage."
        return 1
    fi
    
    print_manager_header
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
    
    if ! validate_domain_in_config "$domain"; then
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
        
        # In non-interactive mode, fail rather than overwrite
        if [ "${BIND_NONINTERACTIVE:-0}" = "1" ]; then
            print_status "error" "Record already exists (use delete first, or run interactively to overwrite)"
            return 1
        else
            read -p "Overwrite existing record? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "info" "Operation cancelled"
                return 0
            fi
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

# Function: bc.create_txt
bc.create_txt() {
    local show_help=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -?|--help)
                show_help=true
                shift
                ;;
            --backup)
                ENABLE_BACKUPS=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [ "$show_help" = true ] || [ $# -lt 3 ]; then
        echo -e "${WHITE}bc.create_txt${NC} - Create DNS TXT record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bc.create_txt [--backup] <name> <domain> <text_value>"
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo -e "  ${GREEN}--backup${NC}   - Create backup before modification (disabled by default)"
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
        echo "  bc.create_txt @ ${DOMAINS[0]:-example.com} 'v=spf1 include:_spf.google.com ~all'"
        echo "  bc.create_txt _dmarc ${DOMAINS[0]:-example.com} 'v=DMARC1; p=none'"
        echo "  bc.create_txt --backup @ ${DOMAINS[0]:-example.com} 'v=spf1 include:_spf.google.com ~all'"
        return 0
    fi
    
    local name=$1
    local domain=$2
    local text_value="$3"
    
    print_manager_header
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
    
    if ! validate_domain_in_config "$domain"; then
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

# Function: bc.delete_record
bc.delete_record() {
    local show_help=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -?|--help)
                show_help=true
                shift
                ;;
            --backup)
                ENABLE_BACKUPS=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [ "$show_help" = true ] || [ $# -lt 1 ]; then
        echo -e "${WHITE}bc.delete_record${NC} - Delete DNS record"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bc.delete_record [--backup] <fqdn> [record_type]"
        echo "  bc.delete_record [--backup] <name> <domain> [record_type]"
        echo
        echo -e "${YELLOW}Options:${NC}"
        echo -e "  ${GREEN}--backup${NC}   - Create backup before modification (disabled by default)"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}fqdn${NC}        - Fully qualified domain name (e.g., webserver.homelab.io)"
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
        echo "  bc.delete_record webserver.${DOMAINS[0]:-example.com}"
        echo "  bc.delete_record webserver ${DOMAINS[0]:-example.com}"
        echo "  bc.delete_record www.${DOMAINS[0]:-example.com} CNAME"
        echo "  bc.delete_record --backup webserver ${DOMAINS[0]:-example.com}"
        return 0
    fi
    
    # Parse arguments - support both FQDN and name+domain formats
    local name domain record_type
    if [ $# -eq 1 ] || ( [ $# -eq 2 ] && [[ "$2" =~ ^[A-Z]+$ ]] ); then
        # FQDN format: <fqdn> [record_type]
        read name domain <<< $(parse_fqdn "$1")
        record_type=${2:-""}
        
        # If domain wasn't extracted, treat first arg as name and fail
        if [ -z "$domain" ]; then
            print_status "error" "Could not parse domain from '$1'. Available domains: ${DOMAINS[*]}"
            return 1
        fi
    elif [ $# -ge 2 ]; then
        # Traditional format: <name> <domain> [record_type]
        name=$1
        domain=$2
        record_type=${3:-""}
    else
        print_status "error" "Invalid arguments. Use --help for usage."
        return 1
    fi
    
    print_manager_header
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
    
    if ! validate_domain_in_config "$domain"; then
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
    
    # In non-interactive mode, delete without prompting (delete is explicit action)
    if [ "${BIND_NONINTERACTIVE:-0}" = "1" ]; then
        print_status "info" "Non-interactive mode: deleting records"
    else
        read -p "Delete these records? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "info" "Operation cancelled"
            return 0
        fi
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

# Function: bc.list_records
bc.list_records() {
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
        echo -e "${WHITE}bc.list_records${NC} - List DNS records"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bc.list_records [domain] [record_type]"
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
        echo "  bc.list_records"
        echo "  bc.list_records ${DOMAINS[0]:-example.com}"
        echo "  bc.list_records ${DOMAINS[0]:-example.com} A"
        return 0
    fi
    
    local domain=${1:-""}
    local record_type=${2:-""}
    
    print_manager_header
    echo -e "${WHITE}DNS Records${NC}"
    echo
    
    if [ -n "$domain" ]; then
        if ! validate_domain_in_config "$domain"; then
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
        printf "%-45s %-8s %s\n" "FQDN" "TYPE" "VALUE"
        printf "%-45s %-8s %s\n" "----" "----" "-----"
        
        # Parse zone file and track $ORIGIN
        local current_origin="$d."
        local count=0
        local in_multiline=false
        
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*\; ]] && continue
            [[ -z "$line" ]] && continue
            
            # Skip continuation lines (indented lines from multi-line records like SOA)
            if [[ "$in_multiline" == true ]]; then
                # Check if this is the closing parenthesis
                if [[ "$line" =~ \) ]]; then
                    in_multiline=false
                fi
                continue
            fi
            
            # Track $ORIGIN changes
            if [[ "$line" =~ ^\$ORIGIN[[:space:]]+(.+) ]]; then
                current_origin="${BASH_REMATCH[1]}"
                [[ ! "$current_origin" =~ \.$ ]] && current_origin="${current_origin}."
                continue
            fi
            
            # Trim leading/trailing whitespace for easier parsing
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Parse DNS records with multiple pattern attempts
            local name type value
            
            # Try pattern 1: name IN TYPE value (most common)
            if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+IN[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                type="${BASH_REMATCH[2]}"
                value="${BASH_REMATCH[3]}"
            # Try pattern 2: name TYPE value (no IN keyword)
            elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                type="${BASH_REMATCH[2]}"
                value="${BASH_REMATCH[3]}"
            else
                # Doesn't match any pattern, skip
                continue
            fi
            
            # Skip SOA and NS records at zone level (zone metadata)
            if [ "$type" == "SOA" ]; then
                [[ "$value" =~ \( ]] && in_multiline=true
                continue
            fi
            
            # Skip zone-level NS records (no name or @ name)
            if [ "$type" == "NS" ] && { [ "$name" == "@" ] || [ "$name" == "$d" ]; }; then
                continue
            fi
            
            # Filter by record type if specified
            if [ -n "$record_type" ] && [ "$type" != "$record_type" ]; then
                continue
            fi
            
            # Build FQDN
            local fqdn
            if [[ "$name" == "@" ]]; then
                fqdn="$d"
            elif [[ "$name" =~ \.$ ]]; then
                # Already absolute
                fqdn="${name%.}"
            elif [[ "$current_origin" == "$d." ]]; then
                # At main domain origin
                fqdn="${name}.${d}"
            else
                # At subdomain origin
                fqdn="${name}.${current_origin%.}"
            fi
            
            # Clean up value - remove trailing dots for display
            value="${value%;}"
            value="${value%.}"
            
            printf "%-45s ${GREEN}%-8s${NC} %s\n" "$fqdn" "$type" "$value"
            count=$((count + 1))
        done < "$zone_file"
        
        echo
        echo -e "${GREEN}Total: $count records${NC}"
        echo
    done
}
# Show environment info
show_environment() {
    print_manager_header
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
        bc.create_record)
            bc.create_record "$@"
            ;;
        bc.create_cname)
            bc.create_cname "$@"
            ;;
        bc.create_txt)
            bc.create_txt "$@"
            ;;
            bc.delete_record)
                bc.delete_record "$@"
                ;;
            bc.list_records)
                bc.list_records "$@"
                ;;
            show_environment)
                show_environment "$@"
                ;;
            refresh)
                refresh_dns "$@"
                ;;
        *)
            print_manager_header
            echo -e "${WHITE}Available Commands:${NC}"
            echo
                echo -e "  ${GREEN}bc.create_record${NC}  - Create DNS A record"
                echo -e "  ${GREEN}bc.create_cname${NC}   - Create DNS CNAME record"
                echo -e "  ${GREEN}bc.create_txt${NC}     - Create DNS TXT record"
                echo -e "  ${GREEN}bc.delete_record${NC}  - Delete DNS record"
                echo -e "  ${GREEN}bc.list_records${NC}   - List DNS records"
                echo -e "  ${GREEN}refresh${NC}             - Refresh and validate DNS configuration"
                echo -e "  ${GREEN}show_environment${NC}    - Show environment information"
            echo
            echo -e "${YELLOW}Usage:${NC}"
            echo "  source $0"
            echo "  bc.create_record --help"
            echo "  show_environment"
            echo
            echo -e "${YELLOW}Example:${NC}"
            if [ ${#DOMAINS[@]} -gt 0 ]; then
                echo "  bc.create_record webserver ${DOMAINS[0]} 172.25.50.100"
            else
                echo "  bc.create_record webserver example.com 172.25.50.100"
            fi
            ;;
    esac
}

# DNS Refresh and Maintenance Functions
refresh_dns() {
    print_manager_header
    log_action "Starting DNS refresh process (container-aware)"
    
    # Ensure proper ownership of zone files
    log_action "Ensuring proper ownership of zone files in $BIND_DIR"
    if [ -d "$BIND_DIR" ]; then
        if is_container; then
            # Running inside container
            chown named:named "$BIND_DIR"/*.db 2>/dev/null || true
            chmod 644 "$BIND_DIR"/*.db 2>/dev/null || true
        else
            # Running on host
            chown 25:25 "$BIND_DIR"/*.db 2>/dev/null || true
            chmod 644 "$BIND_DIR"/*.db 2>/dev/null || true
        fi
    fi
    
    # Check configuration and zones
    if validate_bind_config && check_zones; then
        log_action "Configuration and zone validation passed"
        print_status "success" "DNS refresh completed successfully"
    else
        log_action "ERROR: Configuration or zone validation failed"
        print_status "error" "DNS refresh failed - check configuration"
        return 1
    fi
    
    log_action "DNS refresh process completed"
}

# Check individual zone files
check_zones() {
    local errors=0
    local zones=($(discover_domains))
    
    for zone in "${zones[@]}"; do
        # Find zone file in domain-specific subdirectories
        local zone_file=""
        if [ -f "$BIND_DIR/${zone}/${zone}.db" ]; then
            zone_file="$BIND_DIR/${zone}/${zone}.db"
        elif [ -f "$BIND_DIR/${zone}.db" ]; then
            zone_file="$BIND_DIR/${zone}.db"
        fi
        
        if [ -z "$zone_file" ]; then
            log_action "WARNING: Zone file for $zone not found"
            continue
        fi
        
        if is_container; then
            # Running inside container
            if named-checkzone "$zone" "$zone_file" >/dev/null 2>&1; then
                log_action "Zone $zone is valid"
            else
                log_action "ERROR: Zone $zone has errors"
                ((errors++))
            fi
        else
            # Running on host - check via container
            if is_container_running; then
                # Convert host path to container path
                local container_zone_file=$(echo "$zone_file" | sed "s|$BIND_DIR|/var/named|")
                if podman exec "$CONTAINER_NAME" named-checkzone "$zone" "$container_zone_file" >/dev/null 2>&1; then
                    log_action "Zone $zone is valid"
                else
                    log_action "ERROR: Zone $zone has errors"
                    ((errors++))
                fi
            else
                log_action "Cannot validate zone $zone - container not running"
            fi
        fi
    done
    
    return $errors
}

# Direct command line interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        "refresh")
            refresh_dns
            ;;
        "help"|"-h"|"--help")
            print_manager_header
            echo "BindCaptain DNS Manager - Direct Commands"
            echo
            echo "Usage: $0 [COMMAND]"
            echo
            echo "Commands:"
            echo "  refresh  - Refresh and validate DNS configuration"
            echo "  help     - Show this help"
            echo
            echo "For interactive DNS management, source this script:"
            echo "  source $0"
            echo "  bc.create_record --help"
            ;;
        *)
            print_manager_header
            echo "Unknown command: $1"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
fi
