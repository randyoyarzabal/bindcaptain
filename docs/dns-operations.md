# DNS Operations

Complete guide to managing DNS records and zones with BindCaptain.

## DNS Management Overview

BindCaptain provides comprehensive DNS management through the `bindcaptain_manager.sh` script, offering both interactive and command-line interfaces.

## Loading Management Functions

### Source the Script

```bash
# Load all DNS management functions
source ./tools/bindcaptain_manager.sh
```

### Available Functions

After sourcing, you get access to:

- `bc.create_record` - Create DNS records
- `bc.delete_record` - Delete DNS records
- `bc.list_records` - List DNS records
- `bind.list_zones` - List all zones
- `bind.refresh` - Reload BIND configuration
- `bind.validate` - Validate DNS configuration

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

```bash
# Create PTR record
bind.create_ptr 100 1.168.192.in-addr.arpa webserver.example.com

# Create PTR with TTL
bind.create_ptr 101 1.168.192.in-addr.arpa mail.example.com 3600
```

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

## Zone Management

### Listing Zones

```bash
# List all configured zones
bind.list_zones

# List zones with details
bind.list_zones --verbose
```

### Creating New Zones

```bash
# Create forward zone
bind.create_zone example.com

# Create reverse zone
bind.create_zone 1.168.192.in-addr.arpa

# Create zone with specific settings
bind.create_zone test.com --primary-ns ns1.test.com --admin-email admin@test.com
```

### Zone Validation

```bash
# Validate specific zone
bind.validate_zone example.com

# Validate all zones
bind.validate_all_zones

# Check zone syntax
bind.check_zone example.com
```

## BIND Configuration Management

### Reloading Configuration

```bash
# Reload BIND configuration
bind.refresh

# Reload specific zone
bind.reload_zone example.com

# Check configuration before reload
bind.validate_config
```

### Configuration Validation

```bash
# Validate main configuration
bind.validate_config

# Validate specific zone
bind.validate_zone example.com

# Check all zones
bind.check_all_zones
```

## Interactive Management

### Launch Interactive Mode

```bash
# Start interactive DNS management
./tools/bindcaptain_manager.sh
```

Interactive menu options:

```
1. Create A Record
2. Create CNAME Record
3. Create TXT Record
4. Create PTR Record
5. List Records
6. Delete Record
7. List Zones
8. Refresh DNS
9. Validate Configuration
10. Exit
```

### Command Line Interface

```bash
# Direct command execution
./tools/bindcaptain_manager.sh create-record webserver example.com 192.168.1.100
./tools/bindcaptain_manager.sh list-records example.com
./tools/bindcaptain_manager.sh refresh
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

#### Backup and Restore

```bash
# Backup zone files
bind.backup_zones

# Restore from backup
bind.restore_zones backup-2024-01-15
```

### Zone File Management

#### Direct Zone File Editing

```bash
# Edit zone file directly
sudo nano /opt/bindcaptain/zones/example.com.db

# Reload after editing
bind.reload_zone example.com
```

#### Zone File Validation

```bash
# Check zone file syntax
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db

# Check all zone files
bind.check_all_zones
```

## Monitoring and Logging

### DNS Query Logging

```bash
# Enable query logging
bind.enable_query_logging

# Disable query logging
bind.disable_query_logging

# View query logs
bind.view_query_logs
```

### Performance Monitoring

```bash
# Check DNS response times
bind.test_response_time example.com

# Monitor query statistics
bind.show_statistics

# Check zone transfer status
bind.check_zone_transfers
```

## Troubleshooting DNS Issues

### Common Problems

#### DNS Not Resolving

```bash
# Check BIND status
sudo ./bindcaptain.sh status

# Check zone configuration
bind.validate_zone example.com

# Test DNS resolution
dig @localhost example.com
```

#### Zone Transfer Issues

```bash
# Check zone transfer permissions
bind.check_zone_transfers

# Validate zone file
bind.validate_zone example.com

# Check BIND logs
sudo tail -f /opt/bindcaptain/logs/named.log
```

#### Configuration Errors

```bash
# Validate configuration
bind.validate_config

# Check syntax
sudo named-checkconf /opt/bindcaptain/config/named.conf

# Reload configuration
bind.refresh
```

### Debug Commands

```bash
# Enable debug logging
bind.enable_debug_logging 3

# Check BIND processes
sudo podman exec bindcaptain ps aux | grep named

# Monitor DNS queries
sudo podman exec bindcaptain tcpdump -i any port 53
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

# Create TXT records
bc.create_txt example.com example.com "v=spf1 mx a ip4:192.168.1.0/24 ~all"
bc.create_txt _dmarc example.com "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"

# Create PTR records
bind.create_ptr 10 1.168.192.in-addr.arpa ns1.example.com
bind.create_ptr 11 1.168.192.in-addr.arpa ns2.example.com
bind.create_ptr 20 1.168.192.in-addr.arpa mail.example.com
bind.create_ptr 30 1.168.192.in-addr.arpa web.example.com

# Refresh configuration
bind.refresh
```

---

**Need help?** Check the [Troubleshooting Guide](troubleshooting.md) or [Configuration Reference](config-reference.md).
