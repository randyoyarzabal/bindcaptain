#!/bin/bash

# Container startup script for BIND DNS
# Works with any user configuration - no hardcoded domains
# Updated for BIND 9.16+ compatibility and modern security practices
set -e

echo "[*] Starting BindCaptain - Navigate DNS complexity with captain-grade precision"
echo "Container started at: $(date)"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [CONTAINER] $1" | tee -a /var/log/named/container.log
}

# Check BIND version compatibility
check_bind_version() {
    if [ "${BIND_VERSION_CHECK:-true}" = "true" ]; then
        local bind_version=$(named -v 2>&1 | head -1 || echo "unknown")
        log_message "BIND Version: $bind_version"
        
        # Extract major.minor version
        local version_num=$(echo "$bind_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -n "$version_num" ]; then
            log_message "Detected BIND version: $version_num"
            
            # Check for modern BIND features
            if echo "$version_num" | awk -F. '{exit !($1 > 9 || ($1 == 9 && $2 >= 16))}'; then
                log_message "Modern BIND detected (9.16+) - enhanced features available"
            else
                log_message "WARNING: Older BIND version detected - some features may not be available"
            fi
        fi
    fi
}

# Validate mounted configuration with modern syntax awareness
validate_config() {
    log_message "Validating BIND configuration..."
    
    if [ ! -f "${BIND_CONFIG:-/etc/named.conf}" ]; then
        log_message "ERROR: Configuration file not found at ${BIND_CONFIG:-/etc/named.conf}"
        log_message "Please mount your named.conf to /etc/named.conf"
        log_message "Example: -v /path/to/your/named.conf:/etc/named.conf:ro"
        exit 1
    fi
    
    # Check for deprecated options and warn
    local config_file="${BIND_CONFIG:-/etc/named.conf}"
    
    if grep -q "Masterfile-Format" "$config_file"; then
        log_message "WARNING: 'Masterfile-Format' option is deprecated in BIND 9.18+"
    fi
    
    if grep -q "dnssec-enable" "$config_file"; then
        log_message "WARNING: 'dnssec-enable' option is deprecated in BIND 9.16+ (DNSSEC is enabled by default)"
    fi
    
    if grep -q "type master" "$config_file"; then
        log_message "INFO: Consider updating 'type master' to 'type primary' for RFC 8499 compliance"
    fi
    
    if grep -q "notify master-only" "$config_file"; then
        log_message "INFO: Consider updating 'notify master-only' to 'notify primary-only'"
    fi
    
    # Validate configuration syntax
    if ! named-checkconf "${BIND_CONFIG:-/etc/named.conf}"; then
        log_message "ERROR: Invalid BIND configuration"
        exit 1
    fi
    
    log_message "Configuration validation passed"
}

# Enhanced zone validation with modern BIND compatibility
validate_zones() {
    log_message "Discovering and validating zone files..."
    
    # Extract zones from named.conf (support both master/primary syntax)
    local zones_found=0
    local zones_valid=0
    local zones_invalid=0
    
    if [ -f "${BIND_CONFIG:-/etc/named.conf}" ]; then
        # Parse zone definitions from named.conf (support both old and new syntax)
        while IFS= read -r line; do
            if echo "$line" | grep -q '^[[:space:]]*zone[[:space:]]\+'; then
                zone_name=$(echo "$line" | sed 's/.*zone[[:space:]]*"\([^"]*\)".*/\1/')
                ((zones_found++))
                
                # Skip special zones
                if [[ "$zone_name" == "." || "$zone_name" == "localhost" || "$zone_name" =~ \.arpa$ ]]; then
                    log_message "Skipping validation for system zone: $zone_name"
                    continue
                fi
                
                # Find zone file for this zone
                zone_block=""
                found_zone=false
                while IFS= read -r zone_line; do
                    if echo "$zone_line" | grep -q "zone[[:space:]]*\"$zone_name\""; then
                        found_zone=true
                    fi
                    if [ "$found_zone" = true ]; then
                        zone_block="$zone_block$zone_line"$'\n'
                        if echo "$zone_line" | grep -q '}'; then
                            break
                        fi
                    fi
                done < "${BIND_CONFIG:-/etc/named.conf}"
                
                # Check if this is a primary/master zone
                if echo "$zone_block" | grep -qE 'type[[:space:]]+(master|primary)'; then
                    # Extract file path
                    if echo "$zone_block" | grep -q 'file[[:space:]]\+'; then
                        zone_file=$(echo "$zone_block" | grep 'file[[:space:]]\+' | sed 's/.*file[[:space:]]*"\([^"]*\)".*/\1/')
                        
                        # Make path absolute if not already
                        if [[ ! "$zone_file" =~ ^/ ]]; then
                            zone_file="${BIND_ZONES:-/var/named}/$zone_file"
                        fi
                        
                        if [ -f "$zone_file" ]; then
                            if named-checkzone "$zone_name" "$zone_file" >/dev/null 2>&1; then
                                log_message "Zone $zone_name validation passed ($zone_file)"
                                ((zones_valid++))
                            else
                                log_message "ERROR: Zone $zone_name validation failed ($zone_file)"
                                named-checkzone "$zone_name" "$zone_file"
                                ((zones_invalid++))
                            fi
                        else
                            log_message "WARNING: Zone file $zone_file not found for zone $zone_name"
                        fi
                    fi
                else
                    log_message "Skipping non-primary zone: $zone_name"
                fi
            fi
        done < "${BIND_CONFIG:-/etc/named.conf}"
    fi
    
    log_message "Zone discovery complete: $zones_found total, $zones_valid valid, $zones_invalid invalid"
    
    if [ $zones_invalid -gt 0 ]; then
        log_message "ERROR: Some zones failed validation"
        exit 1
    fi
    
    if [ $zones_found -eq 0 ]; then
        log_message "WARNING: No zones found in configuration"
    fi
}

# Set proper permissions with security considerations
set_permissions() {
    log_message "Setting proper file permissions..."
    
    # Ensure named user owns necessary directories
    chown -R ${BIND_USER:-named}:${BIND_USER:-named} \
        "${BIND_ZONES:-/var/named}" \
        "${BIND_LOGS:-/var/log/named}" \
        /var/run/named \
        /var/backups/bind 2>/dev/null || true
    
    # Set proper permissions on zone files
    if [ -d "${BIND_ZONES:-/var/named}" ]; then
        find "${BIND_ZONES:-/var/named}" -name "*.db" -exec chown ${BIND_USER:-named}:${BIND_USER:-named} {} \; 2>/dev/null || true
        find "${BIND_ZONES:-/var/named}" -name "*.db" -exec chmod 644 {} \; 2>/dev/null || true
    fi
    
    # Set permissions on configuration (more restrictive for security)
    if [ -f "${BIND_CONFIG:-/etc/named.conf}" ]; then
        chown root:${BIND_USER:-named} "${BIND_CONFIG:-/etc/named.conf}"
        chmod 640 "${BIND_CONFIG:-/etc/named.conf}"
    fi
    
    # Secure log directory
    chmod 750 "${BIND_LOGS:-/var/log/named}"
    chmod 644 "${BIND_LOGS:-/var/log/named}"/*.log 2>/dev/null || true
}

# Start BIND with enhanced options
start_bind() {
    log_message "Starting BIND DNS server with modern configuration..."
    
    # Determine debug level
    local debug_level=${BIND_DEBUG_LEVEL:-1}
    
    # Check for modern BIND command-line options
    local bind_args=()
    bind_args+=("-g")  # foreground
    bind_args+=("-c" "${BIND_CONFIG:-/etc/named.conf}")
    bind_args+=("-u" "${BIND_USER:-named}")
    
    # Add debug level if specified
    if [ "$debug_level" -gt 0 ]; then
        bind_args+=("-d" "$debug_level")
    fi
    
    # Force foreground and disable syslog for container
    bind_args+=("-f")
    
    log_message "Starting BIND with args: ${bind_args[*]}"
    
    # Start BIND in foreground mode for container
    exec /usr/sbin/named "${bind_args[@]}" 2>&1 | tee -a "${BIND_LOGS:-/var/log/named}/named.log"
}

# Signal handlers for graceful shutdown
shutdown_bind() {
    log_message "Received shutdown signal, stopping BIND..."
    if [ -f "/var/run/named/named.pid" ]; then
        kill -TERM $(cat /var/run/named/named.pid) 2>/dev/null || true
        wait
    fi
    log_message "BIND stopped"
    exit 0
}

# Trap signals for graceful shutdown
trap shutdown_bind SIGTERM SIGINT

# Display environment variables and modern configuration info
display_config() {
    log_message "=== Container Configuration ==="
    log_message "BIND User: ${BIND_USER:-named}"
    log_message "Config File: ${BIND_CONFIG:-/etc/named.conf}"
    log_message "Zones Directory: ${BIND_ZONES:-/var/named}"
    log_message "Logs Directory: ${BIND_LOGS:-/var/log/named}"
    log_message "Debug Level: ${BIND_DEBUG_LEVEL:-1}"
    log_message "Version Check: ${BIND_VERSION_CHECK:-true}"
    log_message "Container hostname: $(hostname)"
    log_message "Container IP: $(hostname -I 2>/dev/null || echo 'unknown')"
    log_message "=============================="
}

# Main execution
log_message "BindCaptain initialization starting..."

# Check BIND version compatibility
check_bind_version

# Display configuration
display_config

# Run validation and setup
validate_config
set_permissions
validate_zones

# Check if running as root (needed for port 53)
if [ "$(id -u)" -eq 0 ]; then
    log_message "Running as root (required for port 53 binding)"
else
    log_message "WARNING: Not running as root - may not be able to bind to port 53"
fi

# Display mount points and configuration status
log_message "=== Volume Mounts ==="
log_message "Configuration: $(if [ -f "${BIND_CONFIG:-/etc/named.conf}" ]; then echo "mounted"; else echo "missing"; fi)"
log_message "Zone files: $(if [ -d "${BIND_ZONES:-/var/named}" ]; then echo "$(find ${BIND_ZONES:-/var/named} -name '*.db' | wc -l) zone files found"; else echo "directory not found"; fi)"
log_message "===================="

log_message "Starting BIND DNS server with modern compatibility..."

# Start BIND
start_bind