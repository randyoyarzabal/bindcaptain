# BindCaptain Management Cheat Sheet

Quick reference for day-to-day BindCaptain operations. Substitute the
`<PLACEHOLDERS>` below with your own values.

**Install dir:** `/opt/bindcaptain` (default for systemd installs)
**Container name:** `bindcaptain`
**DNS IP:** `<PRIMARY-IP>:53` — whatever your `listen-on` advertises

---

## Directory Layout
```
/opt/bindcaptain/
├── config/                          # ← YOUR DNS CONFIGS (mounted in container)
│   ├── named.conf                   # Main BIND configuration
│   ├── example.com/example.com.db   # example.com zone file
│   ├── mydomain.net/                # mydomain.net domain
│   │   ├── mydomain.net.db          # Forward zone
│   │   ├── 1.0.10.in-addr.arpa.db   # Reverse zones (one per /24)
│   │   ├── 2.0.10.in-addr.arpa.db
│   │   └── 3.0.10.in-addr.arpa.db
│   └── named.ca                     # Root hints file
├── logs/                            # Log files
├── bindcaptain.sh                   # Container management script
├── tools/
│   ├── bindcaptain_manager.sh       # DNS record management (bc.*)
│   └── bindcaptain_refresh.sh       # Auto-refresh script (cron)
```

---

## Container Management

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

## Managing DNS Records

**⚠ IMPORTANT:** Always use the `bc.*` commands - never edit zone files manually!

BindCaptain ships **two distinct `bc.*` command surfaces**. Pick the right one:

| Surface | Where to source | What you get | When to use |
|---|---|---|---|
| **Chief plugin** (`chief-plugin/bc_chief-plugin.sh`) | Operator/workstation shell, via [Chief](https://github.com/randyoyarzabal/chief). Or directly on the DNS host with `BC_HOST` unset. | High-level wrappers: `bc.create`, `bc.update`, `bc.delete`, `bc.list`, `bc.refresh`, `bc.sync_ptr`, plus `bc.create_cname` / `bc.create_txt` shortcuts. Output is normalized; `--json` is supported. | **Default for day-to-day DNS edits**, local or remote. |
| **In-container manager** (`tools/bindcaptain_manager.sh`) | Sourced **inside the container scope** on the DNS host (or via `sudo bash -c 'source $BC_MANAGER && …'`). | Low-level primitives: `bc.create_record`, `bc.create_cname`, `bc.create_txt`, `bc.delete_record`, `bc.list_records`. | Direct host-local debugging or scripted automation that already runs on the DNS host. |

> **Important:** The `_record`-suffixed names (`bc.create_record`, `bc.delete_record`, `bc.list_records`) **do not exist** in a Chief-plugin operator shell — only the high-level wrappers are present. Tab-complete `bc.<TAB>` to confirm what’s loaded.

### Loading the commands

```bash
# Operator / remote workstation — Chief plugin (recommended)
chief.plugin bc            # see chief-plugin/README.md for install
# Or, on the DNS host directly, just source the plugin file with BC_HOST unset:
source /opt/bindcaptain/chief-plugin/bc_chief-plugin.sh

# Direct on the DNS host — in-container manager (low-level)
source /opt/bindcaptain/tools/bindcaptain_manager.sh

bc.help                   # list all commands available in the loaded surface
bc.create --help          # per-command help (Chief plugin)
bc.create_record --help   # per-command help (in-container manager)
```

---

### Chief plugin wrappers (primary user-facing API)

Signatures are taken verbatim from `chief-plugin/bc_chief-plugin.sh`. **Write operations only support `A`, `CNAME`, and `TXT`** — anything else returns `Unsupported record type`.

#### Adding A records — `bc.create [A] <fqdn> <ip> [ttl]`
```bash
# Either FQDN form…
bc.create newserver.example.com 192.168.1.100

# …or hostname + domain form
bc.create newserver example.com 192.168.1.100

# With explicit TTL and JSON output
bc.create webserver.example.com 192.168.1.200 3600 --json

# Explicit type (A is the default)
bc.create A webserver.example.com 192.168.1.200
```

#### Adding CNAME records — `bc.create CNAME <fqdn> <target>`
```bash
# FQDN form
bc.create CNAME www.example.com webserver

# alias + domain form
bc.create CNAME www example.com webserver

# Point at an external target (trailing dot makes it absolute)
bc.create CNAME ftp.example.com newserver.example.com.

# Shortcut wrapper
bc.create_cname www.example.com webserver
```

#### Adding TXT records — `bc.create TXT <name> <domain> <value>`
```bash
bc.create TXT @       example.com 'v=spf1 include:_spf.google.com ~all'
bc.create TXT _dmarc  example.com 'v=DMARC1; p=none'

# Shortcut wrapper
bc.create_txt @ example.com 'v=spf1 -all'
```

#### Updating records — `bc.update [TYPE] <fqdn> <new_value> [ttl]`

Implemented as a delete-then-create on the remote host inside one SSH session, so BIND only reloads at the end.

```bash
bc.update webserver.example.com 192.168.1.200            # change A IP
bc.update webserver.example.com 192.168.1.200 3600        # also update TTL
bc.update CNAME www.example.com newtarget                 # change CNAME target
bc.update TXT   @   example.com 'v=spf1 -all'             # change TXT value

# JSON input (useful for IPAM / Igor-style integrations)
bc.update --json '{"type":"A","fqdn":"web.example.com","rdata":"192.0.2.200","ttl":3600}'
```

#### Deleting records — `bc.delete <fqdn> [TYPE]`
```bash
bc.delete oldserver.example.com               # deletes any matching record
bc.delete oldserver example.com               # hostname + domain form
bc.delete www.example.com CNAME               # restrict to a record type
bc.delete www.example.com CNAME --json        # JSON output
```

#### Listing records — `bc.list [domain] [--json|-j]`
```bash
bc.list                       # all records, all domains
bc.list example.com           # one domain
bc.list example.com --json    # machine-readable JSON
```

#### Other Chief-plugin commands
```bash
bc.refresh           # validate all zones + reload BIND (--json supported)
bc.sync_ptr          # rebuild managed PTR zones from forward A records
bc.status / bc.start / bc.stop / bc.restart   # service control on the host
bc.ssh               # open an SSH session to BC_HOST
bc.git_refresh       # git-pull BindCaptain on the host
```

Aliases: `bc.a`=`bc.create`, `bc.up`=`bc.update`, `bc.cname`=`bc.create_cname`, `bc.txt`=`bc.create_txt`, `bc.rm`=`bc.delete`, `bc.ls`=`bc.list`.

---

### Low-level / direct-on-host (in-container manager)

Only callable when `tools/bindcaptain_manager.sh` is sourced inside the container scope (or invoked via `sudo bash -c 'source $BC_MANAGER && …'`). The Chief-plugin wrappers above dispatch to these under the hood.

```bash
# A record
#   bc.create_record [--backup] <fqdn> <ip> [ttl]
#   bc.create_record [--backup] <hostname> <domain> <ip> [ttl]
bc.create_record newserver example.com 192.168.1.100
bc.create_record webserver.example.com 192.168.1.200 3600

# CNAME
#   bc.create_cname [--backup] <fqdn> <target>
#   bc.create_cname [--backup] <alias> <domain> <target>
bc.create_cname www example.com newserver
bc.create_cname ftp.example.com newserver.example.com.

# TXT
#   bc.create_txt [--backup] <name> <domain> <text_value>
bc.create_txt @       example.com 'v=spf1 include:_spf.google.com ~all'
bc.create_txt _dmarc  example.com 'v=DMARC1; p=none'

# Delete
#   bc.delete_record [--backup] <fqdn> [record_type]
#   bc.delete_record [--backup] <name> <domain> [record_type]
bc.delete_record oldserver example.com
bc.delete_record www.example.com CNAME

# List
#   bc.list_records [domain] [type]
bc.list_records
bc.list_records example.com
bc.list_records example.com A
```

### **Auto-Management Features**
- **✓ Serial numbers** automatically incremented
- **✓ Zone validation** before applying changes  
- **✓ Automatic backups** before modifications
- **✓ BIND reload** after successful changes
- **✓ Rollback** on validation failures

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

## Configuration Updates

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
#     also-notify { <SECONDARY-IP>; <SECONDARY-IP-2>; };
#     allow-transfer { <SECONDARY-IP>; <SECONDARY-IP-2>; };
#     allow-query { any; };
# };

# 4. Restart container
sudo podman restart bindcaptain
```

---

## Validation & Testing

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
dig @<PRIMARY-IP> host.example.com
dig @<PRIMARY-IP> host.example.net

# Test reverse DNS  
dig @<PRIMARY-IP> -x <PRIMARY-IP>

# Test from external
dig @<PRIMARY-IP> primary.example.com +short

# Check NS records
dig @<PRIMARY-IP> example.com NS
```

---

## Monitoring & Logs

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
dig @<PRIMARY-IP> . +short

# View active queries (if logging enabled)
sudo podman exec bindcaptain tail -f /var/log/named/named.log
```

---

## Automation & Maintenance

### Reverse DNS Automation
**Note**: PTR records are created automatically when A records are added (for IPs in managed reverse networks). No cron jobs or external tools required.

```bash
# Chief plugin — creates A record AND PTR record automatically
bc.create hostname.domain.com 192.168.1.100

# In-container manager (low-level, on the host) — same automatic PTR
bc.create_record hostname domain.com 192.168.1.100

# Force a full revalidation + reload
bc.refresh
# Or rebuild PTR zones from forward A records
bc.sync_ptr        # Chief plugin
# bc.sync_ptr_from_forwards   # in-container manager name
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

## Troubleshooting

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

## Quick Commands Summary

| Task | Command |
|------|---------|
| **Container Status** | `sudo podman ps --filter name=bindcaptain` |
| **Restart DNS** | `sudo podman restart bindcaptain` |
| **View Logs** | `sudo podman logs bindcaptain \| tail -20` |
| **Edit Zone** | `sudo vi /opt/bindcaptain/config/domain/domain.db` |
| **Validate Zone** | `sudo named-checkzone domain /opt/bindcaptain/config/domain/domain.db` |
| **Test DNS** | `dig @<PRIMARY-IP> hostname.domain.com` |
| **Manual Refresh** | `sudo /opt/bindcaptain/tools/bindcaptain_refresh.sh` |
| **Backup Config** | `sudo tar -czf backup.tar.gz /opt/bindcaptain/config/` |

---

## Pro Tips

1. **Always increment serial numbers** after zone changes
2. **Validate before restarting** - use `named-checkzone` and `named-checkconf`  
3. **Edit files directly** on host - no need to go into container
4. **Monitor logs** - especially after changes
5. **Backup before major changes** - zone files are small
6. **Use meaningful serial numbers** - YYYYMMDDNN format recommended
7. **Test locally first** - use `dig @<PRIMARY-IP>` for testing
8. **Let cron handle reverse DNS** - it runs every 5 minutes automatically

---

**Need Help?** Check logs first: `sudo podman logs bindcaptain | tail -20`
