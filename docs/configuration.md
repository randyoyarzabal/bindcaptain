# Configuration Management

Complete guide to configuring BindCaptain DNS zones and settings.

## Configuration Overview

BindCaptain uses a template-driven configuration system that makes it easy to set up and manage DNS zones without manual BIND configuration editing.

## Configuration Files Structure

```
/opt/bindcaptain/
├── config/
│   ├── named.conf              # Main BIND configuration
│   └── named.conf.template     # Configuration template
├── zones/
│   ├── example.com.db          # Zone files
│   └── 1.168.192.in-addr.arpa.db  # Reverse zones
├── logs/
│   └── named.log              # BIND logs
└── data/
    └── managed-keys.bind      # DNSSEC keys
```

## Initial Configuration

### Interactive Configuration Wizard

```bash
# Run the configuration wizard
sudo ./tools/config-setup.sh wizard
```

The wizard will guide you through:

1. **Domain Setup**
   - Primary domain name
   - Admin email address
   - Primary nameserver

2. **Network Configuration**
   - IP address ranges
   - Reverse DNS zones
   - Subnet configuration

3. **BIND Settings**
   - Debug level
   - Logging options
   - Security settings

4. **Zone Generation**
   - Create initial zone files
   - Set up reverse zones
   - Configure zone transfers

### Manual Configuration

```bash
# Copy template configuration
sudo cp config-examples/named.conf.template /opt/bindcaptain/config/named.conf

# Edit configuration
sudo nano /opt/bindcaptain/config/named.conf

# Create zone files
sudo ./tools/config-setup.sh create-zone example.com
```

## Zone Configuration

### Creating Zones

#### Forward Zones

```bash
# Create basic forward zone
sudo ./tools/config-setup.sh create-zone example.com

# Create zone with custom settings
sudo ./tools/config-setup.sh create-zone example.com \
    --primary-ns ns1.example.com \
    --admin-email admin@example.com \
    --refresh 3600 \
    --retry 1800 \
    --expire 1209600 \
    --minimum 3600
```

#### Reverse Zones

```bash
# Create reverse zone for 192.168.1.0/24
sudo ./tools/config-setup.sh create-reverse-zone 1.168.192.in-addr.arpa

# Create reverse zone with custom settings
sudo ./tools/config-setup.sh create-reverse-zone 1.168.192.in-addr.arpa \
    --primary-ns ns1.example.com \
    --admin-email admin@example.com
```

### Zone File Templates

#### Forward Zone Template

```bind
$TTL 3600
@   IN  SOA ns1.example.com. admin.example.com. (
    2024011501  ; Serial
    3600        ; Refresh
    1800        ; Retry
    1209600     ; Expire
    3600        ; Minimum TTL
)

; Name servers
@   IN  NS  ns1.example.com.
@   IN  NS  ns2.example.com.

; A records
@   IN  A   192.168.1.10
ns1 IN  A   192.168.1.10
ns2 IN  A   192.168.1.11

; CNAME records
www IN  CNAME   @
```

#### Reverse Zone Template

```bind
$TTL 3600
@   IN  SOA ns1.example.com. admin.example.com. (
    2024011501  ; Serial
    3600        ; Refresh
    1800        ; Retry
    1209600     ; Expire
    3600        ; Minimum TTL
)

; Name servers
@   IN  NS  ns1.example.com.
@   IN  NS  ns2.example.com.

; PTR records
10  IN  PTR ns1.example.com.
11  IN  PTR ns2.example.com.
```

## BIND Configuration

### Main Configuration File

The main BIND configuration is located at `/opt/bindcaptain/config/named.conf`:

```bind
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    allow-query { any; };
    recursion yes;
    dnssec-enable yes;
    dnssec-validation yes;
    bindkeys-file "/etc/named.isc-dlv.key";
    managed-keys-directory "/var/named/dynamic";
    pid-file "/run/named/named.pid";
    session-keyfile "/run/named/session.key";
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

zone "example.com" IN {
    type master;
    file "example.com.db";
    allow-update { none; };
};

zone "1.168.192.in-addr.arpa" IN {
    type master;
    file "1.168.192.in-addr.arpa.db";
    allow-update { none; };
};
```

### Configuration Options

#### Global Options

```bind
options {
    // Network settings
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    
    // Directory settings
    directory "/var/named";
    
    // Security settings
    allow-query { any; };
    allow-recursion { localhost; };
    allow-transfer { none; };
    
    // Performance settings
    recursion yes;
    dnssec-enable yes;
    dnssec-validation yes;
    
    // Logging settings
    version "BindCaptain DNS Server";
};
```

#### Zone Options

```bind
zone "example.com" IN {
    type master;
    file "example.com.db";
    allow-update { none; };
    allow-transfer { 192.168.1.0/24; };
    notify yes;
    also-notify { 192.168.1.11; };
};
```

## Security Configuration

### Access Control

#### Query Restrictions

```bind
options {
    // Allow queries from specific networks
    allow-query { 
        192.168.1.0/24;
        10.0.0.0/8;
    };
    
    // Allow recursion only for local networks
    allow-recursion {
        192.168.1.0/24;
        127.0.0.1;
    };
};
```

#### Zone Transfer Security

```bind
zone "example.com" IN {
    type master;
    file "example.com.db";
    
    // Restrict zone transfers
    allow-transfer {
        192.168.1.11;  // Secondary nameserver
        192.168.1.12;  // Backup nameserver
    };
    
    // Enable notifications
    notify yes;
    also-notify { 192.168.1.11; 192.168.1.12; };
};
```

### DNSSEC Configuration

```bind
options {
    // Enable DNSSEC
    dnssec-enable yes;
    dnssec-validation yes;
    
    // DNSSEC key files
    bindkeys-file "/etc/named.isc-dlv.key";
    managed-keys-directory "/var/named/dynamic";
    
    // DNSSEC policy
    dnssec-policy "default";
};
```

## Logging Configuration

### Query Logging

```bind
logging {
    channel query_log {
        file "/var/log/named/queries.log" versions 3 size 5m;
        severity info;
        print-time yes;
        print-category yes;
    };
    
    category queries { query_log; };
};
```

### Debug Logging

```bind
logging {
    channel debug_log {
        file "/var/log/named/debug.log" versions 3 size 10m;
        severity dynamic;
        print-time yes;
    };
    
    category default { debug_log; };
};
```

## Performance Tuning

### Cache Configuration

```bind
options {
    // Cache settings
    max-cache-size 256m;
    max-cache-ttl 3600;
    max-ncache-ttl 3600;
    
    // Memory settings
    max-memory-usage 512m;
    max-memory-usage 75%;
};
```

### Zone Settings

```bind
zone "example.com" IN {
    type master;
    file "example.com.db";
    
    // Zone refresh settings
    refresh 3600;
    retry 1800;
    expire 1209600;
    minimum 3600;
    
    // Performance settings
    max-zone-ttl 86400;
};
```

## Configuration Validation

### Syntax Checking

```bash
# Check main configuration
sudo named-checkconf /opt/bindcaptain/config/named.conf

# Check specific zone
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db

# Check all zones
sudo ./bindcaptain.sh validate
```

### Testing Configuration

```bash
# Test DNS resolution
dig @localhost example.com
nslookup example.com localhost

# Test reverse DNS
dig @localhost -x 192.168.1.100
nslookup 192.168.1.100 localhost
```

## Configuration Management

### Backup Configuration

```bash
# Backup all configuration
sudo ./tools/config-setup.sh backup

# Backup specific zone
sudo ./tools/config-setup.sh backup-zone example.com

# List backups
sudo ./tools/config-setup.sh list-backups
```

### Restore Configuration

```bash
# Restore from backup
sudo ./tools/config-setup.sh restore backup-2024-01-15

# Restore specific zone
sudo ./tools/config-setup.sh restore-zone example.com backup-2024-01-15
```

### Configuration Updates

```bash
# Update configuration
sudo ./tools/config-setup.sh update

# Reload configuration
sudo ./bindcaptain.sh reload

# Restart service
sudo ./bindcaptain.sh restart
```

## Troubleshooting Configuration

### Common Issues

#### Configuration Syntax Errors

```bash
# Check syntax
sudo named-checkconf /opt/bindcaptain/config/named.conf

# Check specific zone
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db
```

#### Zone File Issues

```bash
# Load the manager, then validate and reload (or use Chief bc.refresh remotely)
source /opt/bindcaptain/tools/bindcaptain_manager.sh
bc.refresh

# Check zone syntax
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db
```

#### Permission Issues

```bash
# Fix ownership
sudo chown -R root:named /opt/bindcaptain/zones/
sudo chmod 640 /opt/bindcaptain/zones/*.db

# Fix SELinux contexts
sudo restorecon -R /opt/bindcaptain/
```

## Best Practices

### Configuration Management

- ✅ Use templates for consistency
- ✅ Regular configuration backups
- ✅ Test changes before applying
- ✅ Document custom configurations

### Security

- ✅ Restrict zone transfers
- ✅ Use DNSSEC when possible
- ✅ Regular security updates
- ✅ Monitor access logs

### Performance

- ✅ Optimize TTL values
- ✅ Configure appropriate cache sizes
- ✅ Monitor memory usage
- ✅ Regular performance testing

---

**Need help?** Check the [Troubleshooting Guide](troubleshooting.md) or [DNS Operations](dns-operations.md).
