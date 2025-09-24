#!/bin/bash 

# ⚓ BindCaptain DNS Refresh
# Automated DNS refresh and maintenance for BindCaptain

# Container configuration
CONTAINER_NAME="bindcaptain"
CONTAINER_DATA_DIR="/opt/bindcaptain"
DOMAIN_CONFIG_BASE="/var/named"

# Use container paths if running in container, host paths if running on host
if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
    # Running inside container
    BIND_DIR="/var/named"
    LOG_FILE="/var/log/dns_refresh.log"
    NAMED_CONF="/etc/named.conf"
else
    # Running on host - target the same config the container uses
    BIND_DIR="$CONTAINER_DATA_DIR/config"
    LOG_FILE="$CONTAINER_DATA_DIR/logs/dns_refresh.log"
    NAMED_CONF="$CONTAINER_DATA_DIR/config/named.conf"
fi

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    logger "DNS-REFRESH: $1"
}

# Check if named configuration is valid
check_config() {
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        # Running inside container
        if named-checkconf "$NAMED_CONF"; then
            log_message "Named configuration is valid"
            return 0
        else
            log_message "ERROR: Named configuration is invalid"
            return 1
        fi
    else
        # Running on host - check via container
        if command -v podman &> /dev/null; then
            if podman exec "$CONTAINER_NAME" named-checkconf /etc/named.conf; then
                log_message "Named configuration is valid"
                return 0
            else
                log_message "ERROR: Named configuration is invalid"
                return 1
            fi
        else
            log_message "Cannot validate config - not in container and podman not available"
            return 1
        fi
    fi
}

# Auto-discover zones from configuration
discover_zones() {
    local zones=()
    if [ -f "$NAMED_CONF" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q '^[[:space:]]*zone[[:space:]]\+'; then
                local zone_name=$(echo "$line" | sed 's/.*zone[[:space:]]*"\([^"]*\)".*/\1/')
                # Skip special zones
                if [[ ! "$zone_name" =~ ^(\.|\.|localhost)$ ]] && [[ ! "$zone_name" =~ \.arpa$ ]]; then
                    zones+=("$zone_name")
                fi
            fi
        done < "$NAMED_CONF"
    fi
    printf '%s\n' "${zones[@]}"
}

# Check individual zone files
check_zones() {
    local errors=0
    local zones=($(discover_zones))
    
    for zone in "${zones[@]}"; do
        # Find zone file in domain-specific subdirectories
        local zone_file=""
        if [ -f "$BIND_DIR/${zone}/${zone}.db" ]; then
            zone_file="$BIND_DIR/${zone}/${zone}.db"
        elif [ -f "$BIND_DIR/${zone}.db" ]; then
            zone_file="$BIND_DIR/${zone}.db"
        fi
        
        if [ -z "$zone_file" ]; then
            log_message "WARNING: Zone file for $zone not found"
            continue
        fi
        
        if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
            # Running inside container
            if named-checkzone "$zone" "$zone_file" >/dev/null 2>&1; then
                log_message "Zone $zone is valid"
            else
                log_message "ERROR: Zone $zone has errors"
                ((errors++))
            fi
        else
            # Running on host - check via container
            if command -v podman &> /dev/null; then
                # Convert host path to container path
                local container_zone_file=$(echo "$zone_file" | sed "s|$BIND_DIR|/var/named|")
                if podman exec "$CONTAINER_NAME" named-checkzone "$zone" "$container_zone_file" >/dev/null 2>&1; then
                    log_message "Zone $zone is valid"
                else
                    log_message "ERROR: Zone $zone has errors"
                    ((errors++))
                fi
            else
                log_message "Cannot validate zone $zone - not in container and podman not available"
            fi
        fi
    done
    
    return $errors
}

# Note: Reverse DNS generation moved to inline creation in bindcaptain_manager.sh
# PTR records are now created automatically when A records are added

# Reload BIND
reload_bind() {
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        # Running inside container
        if /usr/sbin/rndc reload 2>/dev/null; then
            log_message "BIND reloaded successfully"
            return 0
        else
            log_message "ERROR: Failed to reload BIND"
            return 1
        fi
    else
        # Running on host - reload via container
        if command -v podman &> /dev/null; then
            if podman exec "$CONTAINER_NAME" /usr/sbin/rndc reload 2>/dev/null; then
                log_message "BIND reloaded successfully (via container)"
                return 0
            else
                log_message "ERROR: Failed to reload BIND via container"
                return 1
            fi
        else
            log_message "Cannot reload BIND - not in container and podman not available"
            return 1
        fi
    fi
}

# Main execution
log_message "Starting DNS refresh process (container-aware)"

# Ensure proper ownership of zone files
log_message "Ensuring proper ownership of zone files in $BIND_DIR"
if [ -d "$BIND_DIR" ]; then
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        # Running inside container
        chown named:named "$BIND_DIR"/*.db 2>/dev/null || true
        chmod 644 "$BIND_DIR"/*.db 2>/dev/null || true
    else
        # Running on host
        chown 25:25 "$BIND_DIR"/*.db 2>/dev/null || true
        chmod 644 "$BIND_DIR"/*.db 2>/dev/null || true
    fi
fi

# Note: PTR records now created inline with A records - no separate generation needed

# Check configuration and zones
if check_config && check_zones; then
    log_message "Configuration and zone validation passed"
    # Note: BIND reloading now handled by bindcaptain_manager.sh when records are added
    log_message "No changes detected, BIND service not reloaded"
else
    log_message "ERROR: Configuration or zone validation failed, not reloading BIND"
fi

log_message "DNS refresh process completed"
