# BindCaptain Management Cheat Sheet

## 🚀 Quick Reference for Your Production BindCaptain Setup

**Production Directory:** `/opt/bindcaptain`  
**Container Name:** `bindcaptain`  
**DNS IP:** `172.25.50.156:53`

---

## 📁 Directory Layout
```
/opt/bindcaptain/
├── config/                          # ← YOUR DNS CONFIGS (mounted in container)
│   ├── named.conf                   # Main BIND configuration
│   ├── example.com/example.com.db   # example.com zone file
│   ├── mydomain.net/                # mydomain.net domain
│   │   ├── mydomain.net.db          # Forward zone
│   │   ├── 40.25.172.in-addr.arpa.db # Reverse zones
│   │   ├── 42.25.172.in-addr.arpa.db
│   │   └── 50.25.172.in-addr.arpa.db
│   └── named.ca                     # Root hints file
├── logs/                            # Log files
├── bindcaptain.sh                   # Container management script
├── bindcaptain_manager.sh           # DNS record management
└── bindcaptain_refresh.sh           # Auto-refresh script (cron)
```

---

## 🔧 Container Management

### Basic Operations
```bash
# Container status
sudo podman ps --filter name=bindcaptain

# Start container
sudo podman start bindcaptain

# Stop container  
sudo podman stop bindcaptain

# Restart container
sudo podman restart bindcaptain

# View logs (live)
sudo podman logs -f bindcaptain

# View recent logs
sudo podman logs --tail 20 bindcaptain
```

### Using BindCaptain Script
```bash
cd /opt/bindcaptain

# Container status and info
sudo ./bindcaptain.sh status

# View logs
sudo ./bindcaptain.sh logs

# Force rebuild (if needed)
sudo ./bindcaptain.sh build
```

---

## 📝 Managing DNS Records (Using BindCaptain Manager)

**⚠️ IMPORTANT:** Always use the BindCaptain manager functions - never edit zone files manually!

### Using the Manager
```bash
# First, source the manager script
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh"

# Or call functions directly
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && bind.create_record --help"
```

### Adding A Records
```bash
# Syntax: bind.create_record <hostname> <domain> <ip_address> [ttl]
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.create_record newserver example.com 192.168.1.100"

# With custom TTL
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.create_record webserver example.com 192.168.1.200 3600"
```

### Adding CNAME Records
```bash
# Syntax: bind.create_cname <alias> <domain> <target>
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.create_cname www example.com newserver"

# Point to external domain
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.create_cname ftp example.com newserver.example.com."
```

### Adding TXT Records
```bash
# Syntax: bind.create_txt <name> <domain> <text_value>
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.create_txt @ example.com 'v=spf1 include:_spf.google.com ~all'"

# DMARC record
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.create_txt _dmarc example.com 'v=DMARC1; p=none'"
```

### Deleting Records
```bash
# Syntax: bind.delete_record <name> <domain> [record_type]
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.delete_record oldserver example.com"

# Delete specific record type
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.delete_record www example.com CNAME"
```

### Viewing Records
```bash
# List all records for all domains
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.list_records"

# List records for specific domain
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.list_records example.com"

# List specific record type
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh && \
    bind.list_records example.com A"
```

### ⚡ **Auto-Management Features**
- **✅ Serial numbers** automatically incremented
- **✅ Zone validation** before applying changes  
- **✅ Automatic backups** before modifications
- **✅ BIND reload** after successful changes
- **✅ Rollback** on validation failures

### Zone File Template
```dns
$ORIGIN .
$TTL 86400
domain.com         IN SOA   ns1.domain.com. admin.domain.com. (
                            2025092401  ; serial (YYYYMMDDNN)
                            43200       ; refresh (12 hours)
                            180         ; retry (3 minutes)  
                            1209600     ; expire (2 weeks)
                            10800       ; minimum (3 hours)
                            )
                   NS      ns1.domain.com.

$ORIGIN domain.com.
; A Records
hostname           IN      A       192.168.1.100
ns1                IN      A       192.168.1.1

; CNAME Records  
www                IN      CNAME   hostname
```

---

## 🔄 Configuration Updates

### Modify BIND Configuration
```bash
# Edit main config
sudo vi /opt/bindcaptain/config/named.conf

# Validate configuration
sudo podman exec bindcaptain named-checkconf

# Restart container to apply
sudo podman restart bindcaptain
```

### Add New Domain/Zone
```bash
# 1. Create directory and zone file
sudo mkdir -p /opt/bindcaptain/config/newdomain.com
sudo cp /opt/bindcaptain/config-examples/example.com/example.com.db \
        /opt/bindcaptain/config/newdomain.com/newdomain.com.db

# 2. Edit zone file
sudo vi /opt/bindcaptain/config/newdomain.com/newdomain.com.db

# 3. Add zone to named.conf
sudo vi /opt/bindcaptain/config/named.conf
# Add:
# zone "newdomain.com" IN {
#     type primary;
#     file "newdomain.com/newdomain.com.db";
#     check-names warn;
#     notify primary-only;
#     also-notify { 172.25.50.122; 172.25.50.123; };
#     allow-transfer { 172.25.50.122; 172.25.50.123; };
#     allow-query { any; };
# };

# 4. Restart container
sudo podman restart bindcaptain
```

---

## 🔍 Validation & Testing

### Validate Before Changes
```bash
# Check configuration
sudo podman exec bindcaptain named-checkconf

# Check specific zone
sudo podman exec bindcaptain named-checkzone example.com /var/named/example.com/example.com.db
sudo podman exec bindcaptain named-checkzone mydomain.net /var/named/mydomain.net/mydomain.net.db

# Or validate from host
sudo named-checkzone example.com /opt/bindcaptain/config/example.com/example.com.db
```

### Test DNS Resolution  
```bash
# Test forward DNS
dig @172.25.50.156 hostname.homelab.io
dig @172.25.50.156 hostname.reonetlabs.us

# Test reverse DNS  
dig @172.25.50.156 -x 172.25.50.156

# Test from external
dig @172.25.50.156 wolfman.homelab.io +short

# Check NS records
dig @172.25.50.156 homelab.io NS
```

---

## 📊 Monitoring & Logs

### View Logs
```bash
# Container logs
sudo podman logs bindcaptain | tail -20

# DNS refresh automation logs
sudo tail -f /opt/bindcaptain/logs/dns_refresh.log

# Cron logs  
sudo tail -f /opt/bindcaptain/logs/cron.log

# System cron logs
sudo journalctl -u crond -f
```

### Monitor Performance
```bash
# Container resource usage
sudo podman stats bindcaptain

# Check if container is responding
dig @172.25.50.156 . +short

# View active queries (if logging enabled)
sudo podman exec bindcaptain tail -f /var/log/named/named.log
```

---

## 🔧 Automation & Maintenance

### Reverse DNS Automation
**Note**: As of BindCaptain v2.1+, PTR records are created automatically when A records are added. No cron jobs or external tools required.

```bash
# PTR records are created inline - no separate commands needed
bind.create_record hostname domain.com 192.168.1.100
# ↑ Creates both A record AND PTR record automatically

# Legacy refresh script still available for manual validation
sudo /opt/bindcaptain/tools/bindcaptain_refresh.sh
```

### Backup Configuration
```bash
# Backup entire config
sudo tar -czf /opt/bindcaptain-backup-$(date +%Y%m%d).tar.gz /opt/bindcaptain/config/

# Backup specific zone
sudo cp /opt/bindcaptain/config/example.com/example.com.db \
        /opt/bindcaptain/config/example.com/example.com.db.backup.$(date +%Y%m%d)
```

---

## 🚨 Troubleshooting

### Common Issues

**Container Won't Start:**
```bash
# Check logs for errors
sudo podman logs bindcaptain

# Check if port is in use
sudo ss -tlnp | grep :53

# Check configuration
sudo podman exec bindcaptain named-checkconf
```

**DNS Not Resolving:**
```bash
# Check if BIND is listening
sudo podman exec bindcaptain ss -tlnp | grep :53

# Check container ports
sudo podman port bindcaptain

# Test locally first
dig @127.0.0.1 hostname.domain.com
```

**Zone File Errors:**
```bash
# Always validate after editing
sudo named-checkzone domain.com /opt/bindcaptain/config/domain.com/domain.com.db

# Common issues:
# - Missing trailing dots in CNAMEs  
# - Forgot to increment serial number
# - Missing newline at end of file
# - Incorrect file permissions
```

**Permission Issues:**
```bash
# Fix file ownership
sudo chown -R named:named /opt/bindcaptain/config/

# Fix permissions
sudo find /opt/bindcaptain/config/ -name "*.db" -exec chmod 644 {} \;
sudo chmod 640 /opt/bindcaptain/config/named.conf
```

### Emergency Recovery
```bash
# Stop container
sudo podman stop bindcaptain

# Restore from backup
sudo tar -xzf /opt/bindcaptain-backup-YYYYMMDD.tar.gz -C /

# Start container
sudo podman start bindcaptain
```

---

## 📋 Quick Commands Summary

| Task | Command |
|------|---------|
| **Container Status** | `sudo podman ps --filter name=bindcaptain` |
| **Restart DNS** | `sudo podman restart bindcaptain` |
| **View Logs** | `sudo podman logs bindcaptain \| tail -20` |
| **Edit Zone** | `sudo vi /opt/bindcaptain/config/domain/domain.db` |
| **Validate Zone** | `sudo named-checkzone domain /opt/bindcaptain/config/domain/domain.db` |
| **Test DNS** | `dig @172.25.50.156 hostname.domain.com` |
| **Manual Refresh** | `sudo /opt/bindcaptain/tools/bindcaptain_refresh.sh` |
| **Backup Config** | `sudo tar -czf backup.tar.gz /opt/bindcaptain/config/` |

---

## 🎯 Pro Tips

1. **Always increment serial numbers** after zone changes
2. **Validate before restarting** - use `named-checkzone` and `named-checkconf`  
3. **Edit files directly** on host - no need to go into container
4. **Monitor logs** - especially after changes
5. **Backup before major changes** - zone files are small
6. **Use meaningful serial numbers** - YYYYMMDDNN format recommended
7. **Test locally first** - use `dig @172.25.50.156` for testing
8. **Let cron handle reverse DNS** - it runs every 5 minutes automatically

---

**Need Help?** Check logs first: `sudo podman logs bindcaptain | tail -20`
