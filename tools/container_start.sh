#!/bin/bash

# Simple BindCaptain startup script
# Just starts BIND without complex validation that was causing crashes

set -e

echo "[*] Starting BindCaptain - Navigate DNS complexity with captain-grade precision"
echo "Container started at: $(date)"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [CONTAINER] $1" | tee -a /var/log/named/container.log
}

log_message "BindCaptain initialization starting..."

# Check BIND version
if command -v named >/dev/null 2>&1; then
    bind_version=$(named -v 2>&1 | head -1 || echo "unknown")
    log_message "BIND Version: $bind_version"
else
    log_message "ERROR: BIND named command not found"
    exit 1
fi

# Display container info
log_message "=== Container Configuration ==="
log_message "BIND User: ${BIND_USER:-named}"
log_message "Config File: ${BIND_CONFIG:-/etc/named.conf}"
log_message "Zones Directory: ${BIND_ZONES:-/var/named}"
log_message "Logs Directory: ${BIND_LOGS:-/var/log/named}"
log_message "Container hostname: $(hostname)"
log_message "Container IP: $(hostname -I | awk '{print $1}' || echo 'unknown')"
log_message "=============================="

# Basic configuration validation
log_message "Validating BIND configuration..."
if [ ! -f "${BIND_CONFIG:-/etc/named.conf}" ]; then
    log_message "ERROR: Configuration file not found at ${BIND_CONFIG:-/etc/named.conf}"
    exit 1
fi

if named-checkconf "${BIND_CONFIG:-/etc/named.conf}"; then
    log_message "Configuration validation passed"
else
    log_message "ERROR: Configuration validation failed"
    exit 1
fi

# Set permissions (handle read-only files gracefully)
log_message "Setting proper file permissions..."

# Ensure named user owns necessary directories
chown -R ${BIND_USER:-named}:${BIND_USER:-named} \
    "${BIND_ZONES:-/var/named}" \
    "${BIND_LOGS:-/var/log/named}" \
    /var/run/named \
    /var/backups/bind 2>/dev/null || true

# Handle read-only config file
if [ -f "${BIND_CONFIG:-/etc/named.conf}" ]; then
    if [ -w "${BIND_CONFIG:-/etc/named.conf}" ]; then
        chown root:${BIND_USER:-named} "${BIND_CONFIG:-/etc/named.conf}" 2>/dev/null || true
        chmod 640 "${BIND_CONFIG:-/etc/named.conf}" 2>/dev/null || true
    else
        log_message "Configuration file is read-only (mounted from host) - skipping permission changes"
    fi
fi

# Set proper directory permissions
chmod 755 "${BIND_ZONES:-/var/named}" "${BIND_LOGS:-/var/log/named}" /var/run/named 2>/dev/null || true
chmod 644 "${BIND_LOGS:-/var/log/named}"/*.log 2>/dev/null || true

log_message "BindCaptain initialization complete - starting BIND DNS server"

# Start BIND DNS server in foreground
log_message "Executing: named -g -u ${BIND_USER:-named}"
exec named -g -u "${BIND_USER:-named}"