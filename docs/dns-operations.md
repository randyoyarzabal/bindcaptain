# DNS Operations

Complete guide to managing DNS records and zones with BindCaptain.

## DNS Management Overview

BindCaptain provides DNS management through the `tools/bindcaptain_manager.sh` script. Use the `bc.*` functions after sourcing the script.

## Loading Management Functions

### Source the Script

```bash
# Load all DNS management functions (from repo root or /opt/bindcaptain)
source ./tools/bindcaptain_manager.sh
# Or when installed: source /opt/bindcaptain/tools/bindcaptain_manager.sh
```

### Available Commands (bc.*)

After sourcing, you get access to:

- `bc.create_record` - Create A records (PTR created automatically for configured networks)
- `bc.create_cname` - Create CNAME records
- `bc.create_txt` - Create TXT records
- `bc.delete_record` - Delete DNS records
- `bc.list_records` - List records (all zones or by domain/type)
- `bc.refresh` - Validate zones and reload BIND
- `bc.show_environment` - Show paths, domains, and container status
- `bc.help` - Show usage and examples

## Creating DNS Records

### A Records (IPv4 Addresses)

```bash
# Create A record
bc.create_record webserver example.com 192.168.1.100

# Create A record with TTL
bc.create_record mail example.com 192.168.1.101 3600

# Create multiple A records
bc.create_record web1 example.com 192.168.1.100
bc.create_record web2 example.com 192.168.1.101
```

### CNAME Records (Aliases)

```bash
# Create CNAME record
bc.create_cname www example.com webserver.example.com

# Create CNAME with TTL
bc.create_cname ftp example.com fileserver.example.com 7200
```

### TXT Records (Text Records)

```bash
# Create TXT record
bc.create_txt _dmarc example.com "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"

# Create SPF record
bc.create_txt example.com example.com "v=spf1 mx a ip4:192.168.1.0/24 ~all"
```

### PTR Records (Reverse DNS)

PTR records are created **automatically** when you add A records with `bc.create_record`, for networks configured in the manager (e.g. 172.25.40.0/24, 172.25.42.0/24, 172.25.50.0/24). No separate PTR command is needed.

## Managing DNS Records

### Listing Records

```bash
# List all records in a zone
bc.list_records example.com

# List specific record type
bc.list_records example.com A
bc.list_records example.com CNAME
bc.list_records example.com TXT
```

### Deleting Records

```bash
# Delete A record
bc.delete_record webserver example.com

# Delete CNAME record
bc.delete_record www example.com

# Delete TXT record
bc.delete_record _dmarc example.com
```

### Updating Records

```bash
# Update A record (delete and recreate)
bc.delete_record webserver example.com
bc.create_record webserver example.com 192.168.1.200

# Update with new TTL
bc.delete_record mail example.com
bc.create_record mail example.com 192.168.1.201 7200
```

## Zone and BIND Management

### Refresh and Validate

```bash
# Validate all zones and reload BIND (run after sourcing the manager)
bc.refresh
```

When run as a script (e.g. from cron), use:

```bash
./tools/bindcaptain_manager.sh refresh
# Or: /opt/bindcaptain/tools/bindcaptain_manager.sh refresh
```

### Environment and Help

```bash
bc.show_environment   # Show BIND paths, domains, container status
bc.help               # Show all bc.* commands and usage
```

## Advanced Operations

### Bulk Operations

#### Create Multiple Records

```bash
# Create multiple A records from file
while read -r hostname ip; do
    bc.create_record "$hostname" example.com "$ip"
done < hosts.txt
```

#### Backup

Zone backups are created automatically by the manager when `BINDCAPTAIN_ENABLE_BACKUPS=true` and you use `bc.create_record` (or other record commands) with the `--backup` flag. Backup location: `$CONTAINER_DATA_DIR/backups` (e.g. `/opt/bindcaptain/backups` on the host).

### Zone File Paths

When installed under `/opt/bindcaptain`, zone files live under `/opt/bindcaptain/config/` (e.g. `config/example.com/example.com.db`). The manager uses these paths; use `bc.show_environment` to see the exact `BIND_DIR` and domains.

## Troubleshooting DNS Issues

### Common Problems

#### DNS Not Resolving

```bash
# Check container status
sudo ./bindcaptain.sh status

# Validate and reload (after sourcing the manager)
source ./tools/bindcaptain_manager.sh
bc.refresh

# Test DNS resolution
dig @localhost example.com
```

#### Configuration Errors

```bash
# Validate and reload
source ./tools/bindcaptain_manager.sh
bc.refresh

# Check BIND config syntax (when paths known)
sudo named-checkconf /opt/bindcaptain/config/named.conf
```

### Debug Commands

```bash
# Check BIND processes in container
sudo podman exec bindcaptain ps aux | grep named

# View logs
sudo ./bindcaptain.sh logs
# Or: sudo podman logs bindcaptain
```

## Best Practices

### Record Management

- ✅ Use descriptive hostnames
- ✅ Set appropriate TTL values
- ✅ Keep records organized
- ✅ Regular validation and testing

### Security

- ✅ Limit zone transfers
- ✅ Use TSIG for secure transfers
- ✅ Regular security updates
- ✅ Monitor for suspicious activity

### Performance

- ✅ Optimize TTL values
- ✅ Use CNAME records efficiently
- ✅ Monitor query patterns
- ✅ Regular maintenance

## Examples

### Complete Domain Setup

```bash
# Load management functions
source ./tools/bindcaptain_manager.sh

# Create main A records
bc.create_record ns1 example.com 192.168.1.10
bc.create_record ns2 example.com 192.168.1.11
bc.create_record mail example.com 192.168.1.20
bc.create_record web example.com 192.168.1.30

# Create CNAME records
bc.create_cname www example.com web.example.com
bc.create_cname ftp example.com web.example.com

# Create TXT records (name, domain, value)
bc.create_txt @ example.com "v=spf1 mx a ip4:192.168.1.0/24 ~all"
bc.create_txt _dmarc example.com "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"

# PTR records are created automatically when adding A records (for configured networks)

# Refresh and validate configuration
bc.refresh
```

---

**Need help?** Check the [Troubleshooting Guide](troubleshooting.md) or [Configuration](configuration.md).
