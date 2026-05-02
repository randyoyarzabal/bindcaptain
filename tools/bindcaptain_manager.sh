#!/bin/bash

# ⚓BindCaptain DNS Manager
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
#   bc.refresh           - Refresh and validate DNS configuration
#   bc.sync_ptr_from_forwards - Rebuild PTR zones from forward A records
#   bc.show_environment  - Show environment information
#   bc.help              - Show help
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
#   - PTR records for lab subnets derived from forward A records (sync on refresh/delete/create)
#   - Zone file validation and backup
#   - Interactive record management
#   - BIND reload and validation
#   - Comprehensive logging
#
# REQUIREMENTS:
#   - Root privileges (sudo)
#   - BindCaptain container running (for some operations)
#   - Valid DNS configuration

# Only enable exit-on-error when run as a script. When sourced (e.g. root login,
# bc.ssh, or chief.plugin), a failing command would exit the caller's shell.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    set -e
fi

# Resolve script path so sourcing works when invoked via symlink (e.g. chief.plugin).
# Otherwise SCRIPT_DIR points to the symlink's directory and source of common.sh fails, exiting the shell.
__resolve_script_path() {
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
SCRIPT_SOURCE="$(__resolve_script_path "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Manager-specific configuration
LOG_FILE="$LOG_DIR/bind_manager.log"
BACKUP_DIR="$CONTAINER_DATA_DIR/backups"

# Backup control - disabled by default
ENABLE_BACKUPS="${BINDCAPTAIN_ENABLE_BACKUPS:-false}"

# Manager-specific variables (safe when sourced: discover_domains may fail if config not ready)
domains_output=$(discover_domains 2>/dev/null) && DOMAINS=($domains_output) || DOMAINS=()
DEFAULT_TTL="86400"

# Manager-specific logging function
__log_action() {
    log_message "$1" "$LOG_FILE"
}

# Parse FQDN to extract hostname and domain
# Usage: __parse_fqdn "webserver.example.com" 
# Returns: hostname domain (space separated)
__parse_fqdn() {
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

# Lowercase and strip trailing dots for FQDN comparison
__dns_normalize() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\.*$//'
}

# Build zone file without matching RRs; list removed lines in match_ref file.
# Args: zone_file apex_domain target_fqdn (normalized or not) rrtype_filter keep_varname match_varname (namerefs).
# Returns 1 if no RR matched (temp files removed).
__zone_fqdn_delete_prepare() {
    local zone_file="$1"
    local d="$2"
    local target_fqdn
    target_fqdn=$(__dns_normalize "$3")
    local rrtype_filter="${4:-}"
    local -n keep_ref="$5"
    local -n match_ref="$6"

    keep_ref=$(mktemp) || return 1
    match_ref=$(mktemp) || return 1

    local current_origin="${d}."
    local in_multiline=false
    local removed=0

    while IFS= read -r line || [ -n "$line" ]; do
        local original_line="$line"
        [[ "$line" =~ ^[[:space:]]*# ]] && { printf '%s\n' "$original_line" >>"$keep_ref"; continue; }
        [[ "$line" =~ ^[[:space:]]*\; ]] && { printf '%s\n' "$original_line" >>"$keep_ref"; continue; }
        [[ -z "${line// }" ]] && { printf '%s\n' "$original_line" >>"$keep_ref"; continue; }

        if [[ "$in_multiline" == true ]]; then
            printf '%s\n' "$original_line" >>"$keep_ref"
            [[ "$line" =~ \) ]] && in_multiline=false
            continue
        fi

        if [[ "$line" =~ ^\$ORIGIN[[:space:]]+(.+) ]]; then
            current_origin="${BASH_REMATCH[1]}"
            [[ ! "$current_origin" =~ \.$ ]] && current_origin="${current_origin}."
            printf '%s\n' "$original_line" >>"$keep_ref"
            continue
        fi

        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        local name type value
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+IN[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        else
            printf '%s\n' "$original_line" >>"$keep_ref"
            continue
        fi

        if [ "$type" == "SOA" ]; then
            printf '%s\n' "$original_line" >>"$keep_ref"
            [[ "$value" =~ \( ]] && in_multiline=true
            continue
        fi

        if [ "$type" == "NS" ] && { [ "$name" == "@" ] || [ "$name" == "$d" ]; }; then
            printf '%s\n' "$original_line" >>"$keep_ref"
            continue
        fi

        if [ -n "$rrtype_filter" ] && [ "$type" != "$rrtype_filter" ]; then
            printf '%s\n' "$original_line" >>"$keep_ref"
            continue
        fi

        local fqdn
        if [[ "$name" == "@" ]]; then
            fqdn="$d"
        elif [[ "$name" =~ \.$ ]]; then
            fqdn="${name%.}"
        elif [[ "$current_origin" == "$d." ]]; then
            fqdn="${name}.${d}"
        else
            fqdn="${name}.${current_origin%.}"
        fi
        fqdn=$(__dns_normalize "$fqdn")

        if [[ "$fqdn" == "$target_fqdn" ]]; then
            printf '%s\n' "$original_line" >>"$match_ref"
            removed=$((removed + 1))
            continue
        fi
        printf '%s\n' "$original_line" >>"$keep_ref"
    done <"$zone_file"

    if [ "$removed" -eq 0 ]; then
        rm -f "$keep_ref" "$match_ref"
        return 1
    fi
    return 0
}

# Custom header for this script
__print_manager_header() {
    print_header "⚓BindCaptain ${BINDCAPTAIN_VERSION}" "(Container-aware DNS Management)"
}

# Manager-specific domain validation (checks against discovered domains)
__validate_domain_in_config() {
    local domain=$1
    for valid_domain in "${DOMAINS[@]}"; do
        if [ "$domain" = "$valid_domain" ]; then
            return 0
        fi
    done
    return 1
}

# Backup zone file
__backup_zone() {
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
        __log_action "Backed up zone $domain"
        return 0
    else
        print_status "error" "Failed to backup $domain"
        return 1
    fi
}

# Append under the zone apex. Files may end inside another $ORIGIN (e.g. lab.zone under
# the same db); a bare hostname there would be relative to that origin, not $domain.
__append_zone_record() {
    local zone_file="$1"
    local domain="$2"
    local record_line="$3"
    {
        echo ""
        echo "\$ORIGIN ${domain}."
        echo "$record_line"
    } >> "$zone_file"
}

# Increment serial number
__increment_serial() {
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

# Flush block cache after zone file edits (NFS, slow disks) so named reads current data.
__sync_bind_mount_writes() {
    if command -v sync &>/dev/null; then
        sync
    fi
}

# Zone edits run as root; BIND reads zones as named (UID 25). Without this, rndc reload may
# leave stale in-memory data because named cannot open updated master files (errno=EACCES).
#
# Note: `find -L` is required because BIND_DIR may be a symlink (e.g. /opt/bindcaptain/config
# -> /opt/chief_plugins/project_data/bindcaptain/ on hosts that store zones in the shared
# Chief plugins repo). Without -L, `find` treats the top-level argument as a non-directory
# symlink and walks nothing — chown silently no-ops, leaving zone files 0600 root:root and
# unreadable by named.
__chown_zone_files_for_named() {
    if [ ! -d "$BIND_DIR" ]; then
        return 0
    fi
    if is_container; then
        find -L "$BIND_DIR" -name '*.db' -exec chown named:named {} + 2>/dev/null || true
        find -L "$BIND_DIR" -name '*.db' -exec chmod 644 {} + 2>/dev/null || true
    else
        find -L "$BIND_DIR" -name '*.db' -exec chown 25:25 {} + 2>/dev/null || true
        find -L "$BIND_DIR" -name '*.db' -exec chmod 644 {} + 2>/dev/null || true
    fi
}

# Reload BIND after zone changes; require success so callers do not report "created" when
# nothing was reloaded (or when the container restart fallback still failed).
# Always use full "rndc reload" (all zones) — the reliable path for bind-mounted volume
# updates. Per-zone-only reload is not used: it can return success without refreshing
# mounted files the same way a full reload does.
__reload_bind_required() {
    __sync_bind_mount_writes
    __chown_zone_files_for_named
    if ! __reload_bind; then
        print_status "error" "Zone files were updated on disk, but BIND reload failed (rndc and SIGHUP). Check: podman ps, podman logs $CONTAINER_NAME. Manual recovery: podman kill -s HUP $CONTAINER_NAME, or as last resort: podman restart $CONTAINER_NAME"
        return 1
    fi
    __notify_slaves_after_reload
    return 0
}

# Best-effort: tell BIND to (re-)issue NOTIFY for every authoritative primary
# zone after a successful reload. Belt-and-suspenders — BIND already sends
# NOTIFY automatically on serial change, but explicit `rndc notify` covers
# edge cases (e.g. in-container source-IP binding hiccups, NS/MNAME pairing
# quirks, reload races). Failures here do not fail the calling operation —
# the reload already succeeded; this just nudges the slaves.
__notify_slaves_after_reload() {
    [ ${#DOMAINS[@]} -eq 0 ] && return 0
    local rndc_cmd
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        rndc_cmd=(/usr/sbin/rndc)
    elif command -v podman >/dev/null 2>&1 && is_container_running 2>/dev/null; then
        rndc_cmd=(podman exec "$CONTAINER_NAME" /usr/sbin/rndc)
    else
        return 0
    fi
    local d
    for d in "${DOMAINS[@]}"; do
        "${rndc_cmd[@]}" notify "$d" >/dev/null 2>&1 || true
    done
    __log_action "Issued rndc notify for: ${DOMAINS[*]}"
}

# Reload BIND (container-aware): full rndc reload, then SIGHUP fallback.
__reload_bind() {
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        # Running inside container
        if systemctl reload named 2>/dev/null || /usr/sbin/rndc reload 2>/dev/null; then
            print_status "success" "BIND reloaded successfully"
            __log_action "BIND reloaded"
            return 0
        fi
        if [ -f /run/named/named.pid ]; then
            if kill -HUP "$(cat /run/named/named.pid)" 2>/dev/null; then
                print_status "success" "BIND reloaded via SIGHUP (named pid)"
                __log_action "BIND reloaded via SIGHUP (named)"
                return 0
            fi
        fi
        print_status "error" "Failed to reload BIND (rndc and SIGHUP)"
        return 1
    else
        # Running on host - reload via container: full rndc, else SIGHUP to container (named)
        if command -v podman &> /dev/null; then
            if ! is_container_running 2>/dev/null; then
                print_status "error" "Cannot reload BIND - container not running"
                return 1
            fi
            if podman exec "$CONTAINER_NAME" /usr/sbin/rndc reload 2>/dev/null; then
                print_status "success" "BIND reloaded successfully (via container)"
                __log_action "BIND reloaded via container (rndc)"
                return 0
            fi
            print_status "info" "rndc reload failed; trying SIGHUP to named in container (no full restart)"
            if podman kill -s HUP "$CONTAINER_NAME" 2>/dev/null; then
                sleep 1
                print_status "success" "BIND reloaded via SIGHUP (container main process)"
                __log_action "BIND reloaded via container (SIGHUP)"
                return 0
            fi
            print_status "error" "rndc reload and SIGHUP both failed for $CONTAINER_NAME"
            __log_action "ERROR: rndc and SIGHUP reload failed for $CONTAINER_NAME"
            return 1
        else
            print_status "error" "Cannot reload BIND - not in container and podman not available"
            return 1
        fi
    fi
}

# Validate zone file at an explicit path (zone apex name + file path).
__validate_zone_at_path() {
    local zone_name=$1
    local zone_file=$2

    if [ ! -f "$zone_file" ]; then
        print_status "error" "Zone file not found: $zone_file"
        return 1
    fi

    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        if named-checkzone "$zone_name" "$zone_file" >/dev/null 2>&1; then
            print_status "success" "Zone $zone_name validation passed"
            return 0
        else
            print_status "error" "Zone $zone_name validation failed"
            named-checkzone "$zone_name" "$zone_file"
            return 1
        fi
    else
        if command -v podman &> /dev/null; then
            local container_zone_file
            container_zone_file=$(echo "$zone_file" | sed "s|$BIND_DIR|/var/named|")
            if podman exec "$CONTAINER_NAME" named-checkzone "$zone_name" "$container_zone_file" >/dev/null 2>&1; then
                print_status "success" "Zone $zone_name validation passed (via container)"
                return 0
            else
                print_status "error" "Zone $zone_name validation failed (via container)"
                podman exec "$CONTAINER_NAME" named-checkzone "$zone_name" "$container_zone_file"
                return 1
            fi
        else
            print_status "warning" "Cannot validate zone - not in container and podman not available"
            return 0
        fi
    fi
}

# Validate zone file (forward zones: apex = domain name).
__validate_zone() {
    local domain=$1
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    __validate_zone_at_path "$domain" "$zone_file"
}

# Reverse zones BindCaptain rewrites from forward A records.
#
# Auto-discovered from named.conf: every `zone "X.X.X.in-addr.arpa"` block of
# `type primary` (a.k.a. master) is included. The subnet prefix is derived
# from the reverse zone name (e.g. 1.0.10.in-addr.arpa -> 10.0.1). The
# zone-file directory (last field) is read from the `file` directive in the
# zone block; if the file path includes a parent directory, that directory is
# the value (matching the BindCaptain convention of grouping reverse zones
# under their related forward-zone directory). Otherwise the value is empty
# (callers fall back to BIND_DIR/<zone>.db).
#
# Static override: set BINDCAPTAIN_PTR_NETWORKS to a colon-separated list of
# the same subnet:reverse-zone:dir lines and that takes precedence.
#
# Output: one line per managed reverse zone in the form
#   <subnet-prefix>:<reverse-zone-name>:<zone-dir>
# where <subnet-prefix> is the dotted prefix matching the first three octets
# (e.g. 10.0.1). Reverse zones for class-B or class-A coverage are not
# auto-detected; users with non-/24 reverse zones should use the static
# override env var.
__ptr_managed_network_lines() {
    if [ -n "${BINDCAPTAIN_PTR_NETWORKS:-}" ]; then
        local ifs_save="$IFS"
        IFS=$' \n,'
        local entry
        for entry in $BINDCAPTAIN_PTR_NETWORKS; do
            [ -n "$entry" ] && echo "$entry"
        done
        IFS="$ifs_save"
        return 0
    fi

    if [ ! -f "$NAMED_CONF" ]; then
        return 0
    fi

    awk '
        # Emit one parsed zone (helper).
        function emit_zone(   n, parts, prefix, zdir, slash) {
            if (ztype != "primary" || zname == "") return
            n = split(zname, parts, ".")
            if (n < 5 || parts[n-1] != "in-addr" || parts[n] != "arpa") return
            prefix = parts[3] "." parts[2] "." parts[1]
            zdir = ""
            if (zfile != "") {
                slash = index(zfile, "/")
                if (slash > 0) zdir = substr(zfile, 1, slash - 1)
            }
            print prefix ":" zname ":" zdir
        }
        # Open of a reverse zone block. Handle both multi-line (next; rest comes
        # on subsequent lines) and single-line (everything between { and };).
        /^[[:space:]]*zone[[:space:]]+"[0-9]+\.[0-9]+\.[0-9]+\.in-addr\.arpa"[[:space:]]*(IN[[:space:]]*)?\{/ {
            match($0, /"[^"]+"/)
            zname = substr($0, RSTART+1, RLENGTH-2)
            ztype = ""
            zfile = ""
            inblock = 1
            line = $0
            # Single-line zone block?
            if (line ~ /\}[[:space:]]*;/) {
                if (line ~ /type[[:space:]]+(primary|master)[[:space:]]*;/) ztype = "primary"
                if (match(line, /file[[:space:]]+"[^"]+"/)) {
                    fdecl = substr(line, RSTART, RLENGTH)
                    match(fdecl, /"[^"]+"/)
                    zfile = substr(fdecl, RSTART+1, RLENGTH-2)
                }
                emit_zone()
                inblock = 0
                zname = ""; ztype = ""; zfile = ""
            }
            next
        }
        inblock && /type[[:space:]]+(primary|master)[[:space:]]*;/ { ztype = "primary" }
        inblock && /file[[:space:]]+"[^"]+"/ {
            match($0, /"[^"]+"/)
            zfile = substr($0, RSTART+1, RLENGTH-2)
        }
        inblock && /^[[:space:]]*\}[[:space:]]*;/ {
            emit_zone()
            inblock = 0
            zname = ""; ztype = ""; zfile = ""
        }
    ' "$NAMED_CONF"
}

# Emit IPv4 A records as ip<TAB>fqdn (last duplicate IP wins), one per discovered forward zone.
__emit_forward_a_map() {
    local d zone_file current_origin line name type value fqdn in_multiline
    for d in "${DOMAINS[@]}"; do
        zone_file="$BIND_DIR/${d}/${d}.db"
        if [ ! -f "$zone_file" ]; then
            zone_file="$BIND_DIR/${d}.db"
        fi
        if [ ! -f "$zone_file" ]; then
            continue
        fi
        current_origin="${d}."
        in_multiline=false
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*\; ]] && continue
            [[ -z "${line// }" ]] && continue
            if [[ "$in_multiline" == true ]]; then
                [[ "$line" =~ \) ]] && in_multiline=false
                continue
            fi
            if [[ "$line" =~ ^\$ORIGIN[[:space:]]+(.+) ]]; then
                current_origin="${BASH_REMATCH[1]}"
                [[ ! "$current_origin" =~ \.$ ]] && current_origin="${current_origin}."
                continue
            fi
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+IN[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                type="${BASH_REMATCH[2]}"
                value="${BASH_REMATCH[3]}"
            elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                type="${BASH_REMATCH[2]}"
                value="${BASH_REMATCH[3]}"
            else
                continue
            fi
            if [ "$type" == "SOA" ]; then
                [[ "$value" =~ \( ]] && in_multiline=true
                continue
            fi
            if [ "$type" == "NS" ] && { [ "$name" == "@" ] || [ "$name" == "$d" ]; }; then
                continue
            fi
            if [ "$type" != "A" ]; then
                continue
            fi
            value="${value%%;*}"
            value=$(echo "$value" | sed 's/[[:space:]]*$//')
            [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || continue
            if [[ "$name" == "@" ]]; then
                fqdn="$d"
            elif [[ "$name" =~ \.$ ]]; then
                fqdn="${name%.}"
            elif [[ "$current_origin" == "$d." ]]; then
                fqdn="${name}.${d}"
            else
                fqdn="${name}.${current_origin%.}"
            fi
            fqdn=$(__dns_normalize "$fqdn")
            printf '%s\t%s\n' "$value" "$fqdn"
        done <"$zone_file"
    done
}

# Rewrite managed reverse zones so PTR RRs match forward A records (orphan PTR lines removed).
# Optional: --no-reload — skip rndc reload (caller reloads once).
__sync_ptr_zones_from_forwards() {
    local no_reload=false
    if [[ "${1:-}" == "--no-reload" ]]; then
        no_reload=true
    fi

    if [ ${#DOMAINS[@]} -eq 0 ]; then
        print_status "warning" "No domains discovered; PTR sync skipped"
        return 0
    fi

    local map_file
    map_file=$(mktemp) || return 1
    __emit_forward_a_map | awk -F'\t' '{map[$1]=$2} END {for (ip in map) print ip "\t" map[ip]}' >"$map_file"

    local any_changed=false
    local network subnet reverse_zone reverse_domain reverse_file tmp_new ptr_block bak
    while IFS= read -r network; do
        [ -z "$network" ] && continue
        subnet=$(echo "$network" | cut -d: -f1)
        reverse_zone=$(echo "$network" | cut -d: -f2)
        reverse_domain=$(echo "$network" | cut -d: -f3)
        reverse_file="$BIND_DIR/${reverse_domain}/${reverse_zone}.db"
        if [ ! -f "$reverse_file" ]; then
            continue
        fi

        tmp_new=$(mktemp) || {
            rm -f "$map_file"
            return 1
        }
        awk '$0 ~ /^[[:space:]]*[0-9]{1,3}[[:space:]]+IN[[:space:]]+PTR[[:space:]]/ {next} {print}' "$reverse_file" >"$tmp_new"

        ptr_block=$(mktemp) || {
            rm -f "$tmp_new" "$map_file"
            return 1
        }
        awk -F'\t' -v pref="$subnet." '$1 ~ "^" pref {
            split($1, a, ".")
            oct = a[4]
            fqdn = $2
            if (fqdn !~ /\.$/) fqdn = fqdn "."
            printf "%s\t\tIN\tPTR\t%s\n", oct, fqdn
        }' "$map_file" | sort -n >"$ptr_block"

        if [ -s "$ptr_block" ]; then
            echo "" >>"$tmp_new"
            cat "$ptr_block" >>"$tmp_new"
        fi
        rm -f "$ptr_block"

        if cmp -s "$reverse_file" "$tmp_new"; then
            rm -f "$tmp_new"
            continue
        fi

        bak="${reverse_file}.bak.ptr_sync.$$"
        cp "$reverse_file" "$bak"
        if ! mv "$tmp_new" "$reverse_file"; then
            rm -f "$bak"
            rm -f "$map_file"
            return 1
        fi
        __increment_serial "$reverse_file"
        if ! __validate_zone_at_path "$reverse_zone" "$reverse_file"; then
            mv "$bak" "$reverse_file"
            rm -f "$map_file"
            print_status "error" "PTR sync rolled back for $reverse_zone (zone invalid)"
            return 1
        fi
        rm -f "$bak"
        any_changed=true
        print_status "success" "PTR zone synced from forward A records: $reverse_zone"
        __log_action "PTR sync rewrote $reverse_file from forward A records"
    done < <(__ptr_managed_network_lines)

    rm -f "$map_file"

    if [ "$any_changed" = true ] && [ "$no_reload" = false ]; then
        __reload_bind_required || return 1
    fi
    return 0
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
        echo -e "  ${GREEN}fqdn${NC}       - Fully qualified domain name (e.g., webserver.example.com)"
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
        echo "  bc.create_record webserver.${DOMAINS[0]:-example.com} 192.0.2.100"
        echo "  bc.create_record webserver ${DOMAINS[0]:-example.com} 192.0.2.100"
        echo "  bc.create_record --backup webserver ${DOMAINS[0]:-example.com} 192.0.2.100"
        return 0
    fi
    
    # Parse arguments - support both FQDN and hostname+domain formats
    local hostname domain ip_address ttl
    if [ $# -eq 2 ] || [ $# -eq 3 ]; then
        # FQDN format: <fqdn> <ip> [ttl]
        read hostname domain <<< $(__parse_fqdn "$1")
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
    
    __print_manager_header
    echo -e "${WHITE}Creating A Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Hostname: $hostname"
    echo "Domain: $domain"
    echo "IP: $ip_address"
    echo "TTL: $ttl"
    echo
    
    # Validations
    if ! validate_relative_dns_name "$hostname"; then
        print_status "error" "Invalid hostname: $hostname"
        return 1
    fi
    
    if ! __validate_domain_in_config "$domain"; then
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
    
    # Match RR owner: first field equals hostname (zone-relative label chain)
    if grep -qE "^${hostname//./\\.}[[:space:]]" "$zone_file"; then
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
        # Remove existing record (escape . for sed)
        local _hn_esc="${hostname//./\\.}"
        sed -i "/^${_hn_esc}[[:space:]]/d" "$zone_file"
    fi
    
    # Backup zone file
    __backup_zone "$domain"
    
    # Add new record
    local record_line="${hostname}                 IN      A       ${ip_address}"
    
    # Find the right place to insert (after A Records comment, before CNAME Records)
    if grep -q "; CNAME Records" "$zone_file"; then
        sed -i "/; CNAME Records/i\\$record_line" "$zone_file"
    elif grep -q "; A Records" "$zone_file"; then
        sed -i "/; A Records/a\\$record_line" "$zone_file"
    else
        __append_zone_record "$zone_file" "$domain" "$record_line"
    fi
    
    # Increment serial and validate
    __increment_serial "$zone_file"
    
    if __validate_zone "$domain"; then
        if ! __sync_ptr_zones_from_forwards --no-reload; then
            print_status "error" "PTR sync failed after create (fix zones and run: bc.sync_ptr_from_forwards)"
            return 1
        fi
        if ! __reload_bind_required; then
            return 1
        fi
        
        print_status "success" "A record created: $hostname.$domain -> $ip_address"
        __log_action "Created A record: $hostname.$domain -> $ip_address"
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
        echo -e "  ${GREEN}fqdn${NC}       - Fully qualified domain name for alias (e.g., www.example.com)"
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
        read alias domain <<< $(__parse_fqdn "$1")
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
    
    __print_manager_header
    echo -e "${WHITE}Creating CNAME Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Alias: $alias"
    echo "Domain: $domain"
    echo "Target: $target"
    echo
    
    # Validations
    if ! validate_relative_dns_name "$alias"; then
        print_status "error" "Invalid alias: $alias"
        return 1
    fi
    
    if ! __validate_domain_in_config "$domain"; then
        print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
        return 1
    fi
    
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
    if grep -qE "^${alias//./\\.}[[:space:]]" "$zone_file"; then
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
        local _al_esc="${alias//./\\.}"
        sed -i "/^${_al_esc}[[:space:]]/d" "$zone_file"
    fi
    
    # Backup zone file
    __backup_zone "$domain"
    
    # Add new CNAME record
    local record_line="${alias}                 IN      CNAME   ${target}"
    
    # Find the right place to insert (after CNAME Records comment, before other sections)
    if grep -q "; CNAME Records" "$zone_file"; then
        sed -i "/; CNAME Records/a\\$record_line" "$zone_file"
    elif grep -q "; A Records" "$zone_file"; then
        # Insert after A Records section
        sed -i "/; A Records/,/^$/a\\$record_line" "$zone_file"
    else
        __append_zone_record "$zone_file" "$domain" "$record_line"
    fi
    
    # Increment serial and validate
    __increment_serial "$zone_file"
    
    if __validate_zone "$domain"; then
        if ! __reload_bind_required; then
            return 1
        fi
        print_status "success" "CNAME record created: $alias.$domain -> $target"
        __log_action "Created CNAME record: $alias.$domain -> $target"
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
    
    __print_manager_header
    echo -e "${WHITE}Creating TXT Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Name: $name"
    echo "Domain: $domain"
    echo "Text: $text_value"
    echo
    
    # Validations
    if [ "$name" != "@" ] && ! validate_relative_dns_name "$name"; then
        print_status "error" "Invalid name: $name"
        return 1
    fi
    
    if ! __validate_domain_in_config "$domain"; then
        print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
        return 1
    fi
    
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
    # Backup zone file
    __backup_zone "$domain"
    
    # Add new TXT record
    local record_line="${name}                 IN      TXT     \"${text_value}\""
    
    # Append under zone apex (zone file may end inside a delegated $ORIGIN)
    __append_zone_record "$zone_file" "$domain" "$record_line"
    
    # Increment serial and validate
    __increment_serial "$zone_file"
    
    if __validate_zone "$domain"; then
        if ! __reload_bind_required; then
            return 1
        fi
        print_status "success" "TXT record created: $name.$domain -> \"$text_value\""
        __log_action "Created TXT record: $name.$domain -> \"$text_value\""
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
        echo -e "  ${GREEN}fqdn${NC}        - Fully qualified domain name (e.g., webserver.example.com)"
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
        echo "  bc.delete_record host.lab.${DOMAINS[0]:-example.com}   # multi-label names under \$ORIGIN"
        return 0
    fi
    
    # Parse arguments - support both FQDN and name+domain formats
    local name domain record_type
    # Chief (and some shells) pass a second empty argument for optional type; treat as single-arg FQDN.
    if [ $# -eq 1 ] || ( [ $# -eq 2 ] && [[ -z "$2" ]] ) || ( [ $# -eq 2 ] && [[ "$2" =~ ^[A-Z]+$ ]] ); then
        # FQDN format: <fqdn> [record_type]
        read name domain <<< $(__parse_fqdn "$1")
        record_type=${2:-""}
        
        # If domain wasn't extracted, treat first arg as name and fail
        if [ -z "$domain" ]; then
            print_status "error" "Could not parse domain from '$1'. Available domains: ${DOMAINS[*]}"
            return 1
        fi
    elif [ $# -ge 2 ] && [[ -n "$2" ]]; then
        # Traditional format: <name> <domain> [record_type]
        name=$1
        domain=$2
        record_type=${3:-""}
    else
        print_status "error" "Invalid arguments. Use --help for usage."
        return 1
    fi
    
    __print_manager_header
    echo -e "${WHITE}Deleting DNS Record${NC}"
    echo -e "${CYAN}Compatible with BIND 9.16+ modern syntax${NC}"
    echo "Name: $name"
    echo "Domain: $domain"
    [ -n "$record_type" ] && echo "Type: $record_type"
    echo
    
    # Validations (multi-label relative names allowed, e.g. mactest.lab under an apex domain)
    if ! validate_relative_dns_name "$name"; then
        print_status "error" "Invalid name: $name"
        return 1
    fi
    
    if ! __validate_domain_in_config "$domain"; then
        print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
        return 1
    fi
    
    local zone_file="$BIND_DIR/${domain}/${domain}.db"
    if [ ! -f "$zone_file" ]; then
        zone_file="$BIND_DIR/${domain}.db"
    fi
    
    local target_fqdn
    if [[ "$name" == "@" ]]; then
        target_fqdn=$(__dns_normalize "$domain")
    else
        target_fqdn=$(__dns_normalize "${name}.${domain}")
    fi
    
    local keep_tmp match_tmp
    if ! __zone_fqdn_delete_prepare "$zone_file" "$domain" "$target_fqdn" "$record_type" keep_tmp match_tmp; then
        print_status "error" "Record not found: ${target_fqdn} (in zone $domain)"
        return 1
    fi
    
    # Show what will be deleted
    echo -e "${YELLOW}Records to be deleted:${NC}"
    cat "$match_tmp"
    echo
    
    # In non-interactive mode, delete without prompting (delete is explicit action)
    if [ "${BIND_NONINTERACTIVE:-0}" = "1" ]; then
        print_status "info" "Non-interactive mode: deleting records"
    else
        read -p "Delete these records? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$keep_tmp" "$match_tmp"
            print_status "info" "Operation cancelled"
            return 0
        fi
    fi
    
    # Backup zone file
    __backup_zone "$domain"
    
    # Apply zone without matched lines
    mv "$keep_tmp" "$zone_file"
    local did_delete_a=false
    if grep -qE '[[:space:]]IN[[:space:]]+A[[:space:]]+' "$match_tmp" 2>/dev/null; then
        did_delete_a=true
    fi
    rm -f "$match_tmp"

    # Increment serial and validate
    __increment_serial "$zone_file"

    if [ "$did_delete_a" = true ]; then
        __sync_ptr_zones_from_forwards --no-reload || {
            print_status "error" "PTR sync failed after delete (fix zones and run: bc.sync_ptr_from_forwards)"
            return 1
        }
    fi

    if __validate_zone "$domain"; then
        if ! __reload_bind_required; then
            return 1
        fi
        print_status "success" "Record(s) deleted: $target_fqdn"
        __log_action "Deleted record: $target_fqdn"
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

# Escape a string for use inside JSON double quotes (minimal DNS-safe set).
__json_escape_str() {
    local s="$1"
    local out="" i c
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            '"') out+='\"' ;;
            \\) out+='\\\\' ;;
            $'\n') out+='\n' ;;
            $'\r') out+='\r' ;;
            $'\t') out+='\t' ;;
            *) out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

# Function: bc.list_records
bc.list_records() {
    local show_help=false
    local json_output=false
    local positional=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help | -h | '-?')
                show_help=true
                shift
                ;;
            --json | -j)
                json_output=true
                shift
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    set -- "${positional[@]}"

    if [ "$show_help" = true ]; then
        echo -e "${WHITE}bc.list_records${NC} - List DNS records"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bc.list_records [--json|-j] [domain] [record_type]"
        echo
        echo -e "${YELLOW}Parameters:${NC}"
        echo -e "  ${GREEN}--json${NC} / ${GREEN}-j${NC} - Print one JSON array of records (zone, name, fqdn, type, rdata, ttl)"
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
        echo "  bc.list_records --json ${DOMAINS[0]:-example.com}"
        return 0
    fi

    local domain=${1:-""}
    local record_type=${2:-""}

    if [ "$json_output" != true ]; then
        __print_manager_header
        echo -e "${WHITE}DNS Records${NC}"
        echo
    fi

    if [ -n "$domain" ]; then
        if ! __validate_domain_in_config "$domain"; then
            print_status "error" "Invalid domain: $domain (available: ${DOMAINS[*]})"
            return 1
        fi
        domains=("$domain")
    else
        domains=("${DOMAINS[@]}")
    fi

    local json_first=true
    if [ "$json_output" = true ]; then
        echo '['
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

        if [ "$json_output" != true ]; then
            echo -e "${CYAN}=== $d ===${NC}"
            printf "%-45s %-8s %s\n" "FQDN" "TYPE" "VALUE"
            printf "%-45s %-8s %s\n" "----" "----" "-----"
        fi

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

            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            local name type value ttl=""

            # name TTL IN TYPE rdata
            if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([0-9]+)[[:space:]]+IN[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                ttl="${BASH_REMATCH[2]}"
                type="${BASH_REMATCH[3]}"
                value="${BASH_REMATCH[4]}"
            # name IN TYPE rdata (most common)
            elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+IN[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                type="${BASH_REMATCH[2]}"
                value="${BASH_REMATCH[3]}"
            # name TTL TYPE rdata (no IN)
            elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([0-9]+)[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                ttl="${BASH_REMATCH[2]}"
                type="${BASH_REMATCH[3]}"
                value="${BASH_REMATCH[4]}"
            # name TYPE rdata (no IN keyword)
            elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
                name="${BASH_REMATCH[1]}"
                type="${BASH_REMATCH[2]}"
                value="${BASH_REMATCH[3]}"
            else
                continue
            fi

            if [ "$type" == "SOA" ]; then
                [[ "$value" =~ \( ]] && in_multiline=true
                continue
            fi

            if [ "$type" == "NS" ] && { [ "$name" == "@" ] || [ "$name" == "$d" ]; }; then
                continue
            fi

            if [ -n "$record_type" ] && [ "$type" != "$record_type" ]; then
                continue
            fi

            local fqdn
            if [[ "$name" == "@" ]]; then
                fqdn="$d"
            elif [[ "$name" =~ \.$ ]]; then
                fqdn="${name%.}"
            elif [[ "$current_origin" == "$d." ]]; then
                fqdn="${name}.${d}"
            else
                fqdn="${name}.${current_origin%.}"
            fi

            value="${value%;}"
            value="${value%.}"

            if [ "$json_output" = true ]; then
                local ttl_json
                if [ -n "$ttl" ]; then
                    ttl_json="$ttl"
                else
                    ttl_json="null"
                fi
                if [ "$json_first" = true ]; then
                    json_first=false
                else
                    printf ',\n'
                fi
                printf '  {"zone": "%s", "name": "%s", "fqdn": "%s", "type": "%s", "rdata": "%s", "ttl": %s}' \
                    "$(__json_escape_str "$d")" \
                    "$(__json_escape_str "$name")" \
                    "$(__json_escape_str "$fqdn")" \
                    "$(__json_escape_str "$type")" \
                    "$(__json_escape_str "$value")" \
                    "$ttl_json"
            else
                printf "%-45s ${GREEN}%-8s${NC} %s\n" "$fqdn" "$type" "$value"
            fi
            count=$((count + 1))
        done <"$zone_file"

        if [ "$json_output" != true ]; then
            echo
            echo -e "${GREEN}Total: $count records${NC}"
            echo
        fi
    done

    if [ "$json_output" = true ]; then
        echo
        echo ']'
    fi
}
# Show environment info (internal)
__show_environment() {
    __print_manager_header
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

# Function: bc.help
bc.help() {
    __print_manager_header
    echo -e "${WHITE}Available Commands (same API on host and via Chief plugin):${NC}"
    echo
    echo -e "  ${GREEN}bc.create${NC} / ${GREEN}bc.create_record${NC}  - Create DNS record (A default)"
    echo -e "  ${GREEN}bc.create_cname${NC}   - Create CNAME record"
    echo -e "  ${GREEN}bc.create_txt${NC}     - Create TXT record"
    echo -e "  ${GREEN}bc.delete${NC} / ${GREEN}bc.delete_record${NC}  - Delete DNS record"
    echo -e "  ${GREEN}bc.list${NC} / ${GREEN}bc.list_records${NC}   - List records (optional ${CYAN}--json|-j${NC})"
    echo -e "  ${GREEN}bc.refresh${NC}         - Validate zones and reload BIND"
    echo -e "  ${GREEN}bc.sync_ptr_from_forwards${NC} - Rebuild lab PTR zones from forward A records"
    echo -e "  ${GREEN}bc.git_refresh${NC}     - Update ⚓BindCaptain from Git"
    echo -e "  ${GREEN}bc.status${NC}          - Show service and container status"
    echo -e "  ${GREEN}bc.start${NC} / ${GREEN}bc.stop${NC} / ${GREEN}bc.restart${NC} - Service control"
    echo -e "  ${GREEN}bc.show_environment${NC} - Show paths and domains"
    echo -e "  ${GREEN}bc.ssh${NC}             - (Remote only: open SSH; on host: no-op)"
    echo -e "  ${GREEN}bc.help${NC}             - Show this help"
    echo
    echo -e "  Aliases: ${CYAN}bc.a${NC}=bc.create ${CYAN}bc.ls${NC}=bc.list ${CYAN}bc.rm${NC}=bc.delete ${CYAN}bc.cname${NC}=bc.create_cname ${CYAN}bc.txt${NC}=bc.create_txt"
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo "  bc.create [A|CNAME|TXT] ...   or   bc.create_record --help"
    echo "  bc.refresh              (or: $0 refresh when run as script)"
    echo
    echo -e "${YELLOW}Example:${NC}"
    if [ ${#DOMAINS[@]} -gt 0 ]; then
        echo "  bc.create webserver.${DOMAINS[0]} 192.0.2.100"
        echo "  bc.create CNAME www.${DOMAINS[0]} webserver"
        echo "  bc.create TXT @ ${DOMAINS[0]} 'v=spf1 -all'"
    else
        echo "  bc.create webserver.example.com 192.0.2.100"
    fi
    echo
}

# Wrappers so all entry points use the bc. prefix (bc.refresh goes through __main for check_root)
bc.sync_ptr_from_forwards() {
    __main "$@"
}

bc.refresh() {
    __main "$@"
}
bc.show_environment() {
    __show_environment "$@"
}

# Short names (same as Chief plugin) so host and remote have identical bc.* API
bc.create() {
    local record_type="A"
    if [[ "${1:-}" == "-?" ]] || [[ "${1:-}" == "--help" ]]; then
        echo -e "${WHITE}bc.create${NC} - Unified create command"
        echo
        echo -e "${YELLOW}Usage:${NC}"
        echo "  bc.create [A] <fqdn> <ip>"
        echo "  bc.create [A] <hostname> <domain> <ip>"
        echo "  bc.create CNAME <fqdn> <target>"
        echo "  bc.create CNAME <alias> <domain> <target>"
        echo "  bc.create TXT <name> <domain> <value>"
        echo
        echo "Record type defaults to A when omitted."
        echo "Supported types: A, CNAME, TXT"
        return 0
    fi

    case "${1^^}" in
        A|CNAME|TXT)
            record_type="${1^^}"
            shift
            ;;
    esac

    case "$record_type" in
        A) bc.create_record "$@" ;;
        CNAME) bc.create_cname "$@" ;;
        TXT) bc.create_txt "$@" ;;
        *)
            print_status "error" "Unsupported record type: $record_type (supported: A, CNAME, TXT)"
            return 1
            ;;
    esac
}
bc.list() {
    bc.list_records "$@"
}
bc.delete() {
    bc.delete_record "$@"
}

# Service control (parity with Chief plugin; run on host)
bc.status() {
    echo -e "${CYAN}⚓BindCaptain status:${NC}"
    echo "=========================================="
    systemctl status bindcaptain --no-pager -l 2>/dev/null || true
    echo ""
    echo "Container:"
    podman ps -a --filter name="$CONTAINER_NAME" 2>/dev/null || true
}
bc.start() {
    check_root
    echo "Starting ⚓BindCaptain service..."
    systemctl start bindcaptain
    echo -e "${GREEN}✓ ⚓BindCaptain service started${NC}"
    sleep 2
    bc.status
}
bc.stop() {
    check_root
    echo "Stopping ⚓BindCaptain service..."
    systemctl stop bindcaptain
    echo -e "${GREEN}✓ ⚓BindCaptain service stopped${NC}"
}
bc.restart() {
    check_root
    echo "Restarting ⚓BindCaptain service..."
    systemctl restart bindcaptain
    echo -e "${GREEN}✓ ⚓BindCaptain service restarted${NC}"
    sleep 2
    bc.status
}
bc.git_refresh() {
    check_root
    echo "Updating ⚓BindCaptain from Git..."
    (cd "$SCRIPT_DIR/.." && git pull) || {
        print_status "error" "git pull failed"
        return 1
    }
    echo -e "${GREEN}✓ ⚓BindCaptain updated${NC}"
    if command -v podman &>/dev/null && is_container_running; then
        print_status "info" "Reloading BIND so any pulled zone/config changes take effect…"
        __reload_bind_required || print_status "warning" "Reload failed; run bc.refresh after fixing rndc/container"
    fi
}
# No-op when already on host (plugin uses this to open SSH)
bc.ssh() {
    echo -e "${CYAN}Already on BindCaptain host. Use bc.help for commands.${NC}"
}

# Internal dispatcher for bc.* entry points (root check and routing)
__main() {
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
        bc.help)
            bc.help "$@"
            ;;
        bc.show_environment)
            __show_environment "$@"
            ;;
        bc.refresh)
            __refresh_dns "$@"
            ;;
        bc.sync_ptr_from_forwards)
            __print_manager_header
            echo -e "${WHITE}PTR sync (from forward A records)${NC}"
            echo
            __sync_ptr_zones_from_forwards
            ;;
            show_environment)
                __show_environment "$@"
                ;;
            refresh)
                __refresh_dns "$@"
                ;;
        *)
            __print_manager_header
            echo -e "${WHITE}Available Commands:${NC} (bc.help for full list)"
            echo
            echo -e "  DNS: bc.create, bc.create_cname, bc.create_txt, bc.delete, bc.list"
            echo -e "  Service: bc.refresh, bc.status, bc.start, bc.stop, bc.restart, bc.git_refresh"
            echo -e "  Other: bc.show_environment, bc.ssh, bc.help"
            echo
            echo "  source $0   then   bc.help"
            ;;
    esac
}

# DNS Refresh and Maintenance Functions
__refresh_dns() {
    __print_manager_header
    __log_action "Starting DNS refresh process (container-aware)"
    
    # Ensure proper ownership of zone files (including domain subdirs, e.g. example.com/example.com.db)
    __log_action "Ensuring proper ownership of zone files under $BIND_DIR"
    if [ -d "$BIND_DIR" ]; then
        # -L required: BIND_DIR may be a symlink (see __chown_zone_files_for_named comment).
        if is_container; then
            find -L "$BIND_DIR" -name '*.db' -exec chown named:named {} + 2>/dev/null || true
            find -L "$BIND_DIR" -name '*.db' -exec chmod 644 {} + 2>/dev/null || true
        else
            find -L "$BIND_DIR" -name '*.db' -exec chown 25:25 {} + 2>/dev/null || true
            find -L "$BIND_DIR" -name '*.db' -exec chmod 644 {} + 2>/dev/null || true
        fi
        if [ -f "$NAMED_CONF" ]; then
            if is_container; then
                chown root:named "$NAMED_CONF" 2>/dev/null || chown root:root "$NAMED_CONF" 2>/dev/null || true
            else
                chown 25:25 "$NAMED_CONF" 2>/dev/null || true
            fi
            chmod 644 "$NAMED_CONF" 2>/dev/null || true
        fi
    fi

    __log_action "Syncing PTR reverse zones from forward A records"
    if ! __sync_ptr_zones_from_forwards --no-reload; then
        __log_action "ERROR: PTR sync during refresh failed"
        print_status "error" "PTR sync failed — fix zones or run bc.sync_ptr_from_forwards"
        return 1
    fi

    # Check configuration and zones, then full rndc reload so in-memory data matches disk and
    # NOTIFY is sent to secondaries (same path as after bc.create_record / bc.delete_record).
    if validate_bind_config && __check_zones; then
        __log_action "Configuration and zone validation passed"
        if ! __reload_bind_required; then
            __log_action "ERROR: BIND reload after refresh failed"
            print_status "error" "Configuration is valid but BIND reload failed (check rndc and container)"
            return 1
        fi
        print_status "success" "DNS refresh completed (BIND reloaded; slaves notified per named.conf)"
    else
        __log_action "ERROR: Configuration or zone validation failed"
        print_status "error" "DNS refresh failed - check configuration"
        return 1
    fi
    
    __log_action "DNS refresh process completed"
}

# Check individual zone files
__check_zones() {
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
            __log_action "WARNING: Zone file for $zone not found"
            continue
        fi
        
        if is_container; then
            # Running inside container
            if named-checkzone "$zone" "$zone_file" >/dev/null 2>&1; then
                __log_action "Zone $zone is valid"
            else
                __log_action "ERROR: Zone $zone has errors"
                ((errors++))
            fi
        else
            # Running on host - check via container
            if is_container_running; then
                # Convert host path to container path
                local container_zone_file=$(echo "$zone_file" | sed "s|$BIND_DIR|/var/named|")
                if podman exec "$CONTAINER_NAME" named-checkzone "$zone" "$container_zone_file" >/dev/null 2>&1; then
                    __log_action "Zone $zone is valid"
                else
                    __log_action "ERROR: Zone $zone has errors"
                    ((errors++))
                fi
            else
                __log_action "Cannot validate zone $zone - container not running"
            fi
        fi
    done

    local ptr_net rz rd zf_ptr
    while IFS= read -r ptr_net; do
        [ -z "$ptr_net" ] && continue
        rz=$(echo "$ptr_net" | cut -d: -f2)
        rd=$(echo "$ptr_net" | cut -d: -f3)
        zf_ptr="$BIND_DIR/${rd}/${rz}.db"
        if [ ! -f "$zf_ptr" ]; then
            continue
        fi
        if is_container; then
            if named-checkzone "$rz" "$zf_ptr" >/dev/null 2>&1; then
                __log_action "Zone $rz is valid"
            else
                __log_action "ERROR: Zone $rz has errors"
                ((errors++)) || true
            fi
        else
            if is_container_running; then
                local container_zf_ptr
                container_zf_ptr=$(echo "$zf_ptr" | sed "s|$BIND_DIR|/var/named|")
                if podman exec "$CONTAINER_NAME" named-checkzone "$rz" "$container_zf_ptr" >/dev/null 2>&1; then
                    __log_action "Zone $rz is valid"
                else
                    __log_action "ERROR: Zone $rz has errors"
                    ((errors++)) || true
                fi
            else
                __log_action "Cannot validate zone $rz - container not running"
            fi
        fi
    done < <(__ptr_managed_network_lines)

    return $errors
}

# When sourced, show load message and set aliases (skip when run as script)
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    echo "⚓BindCaptain loaded. Type 'bc.help' for usage." >&2
    alias bc.a='bc.create'
    alias bc.ls='bc.list'
    alias bc.rm='bc.delete'
    alias bc.cname='bc.create_cname'
    alias bc.txt='bc.create_txt'
fi

# Direct command line interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        "refresh")
            __refresh_dns
            ;;
        "help"|"-h"|"--help")
            __print_manager_header
            echo "⚓BindCaptain - Direct Commands"
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
            __print_manager_header
            echo "Unknown command: $1"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
fi
