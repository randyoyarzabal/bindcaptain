# DNS Operations

Complete guide to managing DNS records and zones with BindCaptain.

## Two `bc.*` command surfaces

BindCaptain exposes the same DNS functionality through two shells:

| Surface | Where sourced | Commands |
|---|---|---|
| **Chief plugin** (`chief-plugin/bc_chief-plugin.sh`) | Operator / workstation shell via [Chief](https://github.com/randyoyarzabal/chief), or directly on the DNS host with `BC_HOST` unset. | High-level wrappers — `bc.create`, `bc.update`, `bc.delete`, `bc.list`, `bc.refresh`, `bc.sync_ptr`, plus `bc.create_cname` / `bc.create_txt` shortcuts. Output normalized; supports `--json`. |
| **In-container manager** (`tools/bindcaptain_manager.sh`) | Sourced **inside the container scope** on the DNS host (or via `sudo bash -c 'source $BC_MANAGER && …'`). | Low-level primitives — `bc.create_record`, `bc.create_cname`, `bc.create_txt`, `bc.delete_record`, `bc.list_records`. The manager **also** defines `bc.create` / `bc.list` / `bc.delete` aliases that dispatch to those primitives. |

For most operations, use the **Chief plugin wrappers** — they work both locally and remotely via SSH and produce structured output. See [Chief Remote Plugin](chief-remote-plugin.md) for setup.

> **Important:** Write operations (`bc.create` / `bc.update`) only support **A, CNAME, and TXT** record types — anything else is rejected with `Unsupported record type`. The Chief plugin does not implement `bc.create_record` / `bc.delete_record` / `bc.list_records`; those names exist only when the in-container manager is sourced directly on the host.

## Loading the commands

### Chief plugin (recommended)

```bash
# On a workstation or operator host
chief.plugin bc                                        # see chief-plugin/README.md
# Or source directly (BC_HOST unset = local mode):
source /opt/bindcaptain/chief-plugin/bc_chief-plugin.sh
```

### In-container manager (low-level, on the DNS host)

```bash
source /opt/bindcaptain/tools/bindcaptain_manager.sh   # production install
source ./tools/bindcaptain_manager.sh                   # from repo root
```

After loading, `bc.help` lists what is available in that surface; per-command `--help` works on every `bc.*` function.

---

## Chief plugin wrappers (primary user-facing API)

### A records — `bc.create [A] <fqdn> <ip> [ttl]`

```bash
bc.create webserver.example.com 192.168.1.100             # FQDN form
bc.create webserver example.com 192.168.1.100             # hostname + domain form
bc.create webserver.example.com 192.168.1.100 3600        # with TTL
bc.create A webserver.example.com 192.168.1.100 --json    # explicit type, JSON output
```

PTR records are created **automatically** for A records whose IP falls inside a managed reverse network (configured in `config/named.conf`). No separate PTR command is needed.

### CNAME records — `bc.create CNAME <fqdn> <target>`

`bc.create CNAME` does not take a TTL argument.

```bash
bc.create CNAME www.example.com webserver
bc.create CNAME www example.com webserver                  # alias + domain form
bc.create CNAME ftp.example.com fileserver.example.com.    # external target (trailing dot)
bc.create_cname www.example.com webserver                  # shortcut wrapper
```

### TXT records — `bc.create TXT <name> <domain> <value>`

```bash
bc.create TXT _dmarc example.com "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"
bc.create TXT @      example.com "v=spf1 mx a ip4:192.168.1.0/24 ~all"
bc.create_txt @      example.com "v=spf1 -all"             # shortcut wrapper
```

Use `@` for the zone apex.

### Updating records — `bc.update [TYPE] <fqdn> <new_value> [ttl]`

Implemented on the remote host as `delete + create` inside one SSH session, so BIND only reloads at the end. JSON input is accepted.

```bash
bc.update webserver.example.com 192.168.1.200            # change A IP
bc.update webserver.example.com 192.168.1.200 3600        # also change TTL
bc.update CNAME www.example.com newtarget                 # change CNAME target
bc.update TXT @ example.com "v=spf1 -all"                 # change TXT value

# JSON input form
bc.update --json '{"type":"A","fqdn":"web.example.com","rdata":"192.0.2.200","ttl":3600}'
```

### Deleting records — `bc.delete <fqdn> [TYPE]`

```bash
bc.delete webserver.example.com               # any matching record
bc.delete webserver example.com               # hostname + domain form
bc.delete www.example.com CNAME               # restrict to a record type
bc.delete www.example.com CNAME --json        # JSON output
```

### Listing records — `bc.list [domain] [--json|-j]`

```bash
bc.list                       # all zones
bc.list example.com           # one zone
bc.list example.com --json    # machine-readable JSON array
```

### Maintenance

```bash
bc.refresh           # validate all zones and reload BIND (--json supported)
bc.sync_ptr          # rebuild managed reverse zones from forward A records
bc.git_refresh       # git pull on the BindCaptain repo on the host
bc.status            # show systemd + container status
bc.start | bc.stop | bc.restart    # service control
bc.ssh               # interactive SSH session to BC_HOST (no-op when local)
bc.help              # full command list + current BC_HOST/BC_MANAGER
```

Aliases: `bc.a`=`bc.create`, `bc.up`=`bc.update`, `bc.cname`=`bc.create_cname`, `bc.txt`=`bc.create_txt`, `bc.rm`=`bc.delete`, `bc.ls`=`bc.list`.

---

## In-container manager primitives (low-level)

Sourced directly on the DNS host (`tools/bindcaptain_manager.sh`). Every primitive accepts `--help`/`-?` and an optional `--backup` flag (creates a zone backup before mutating).

```bash
# A records
#   bc.create_record [--backup] <fqdn> <ip> [ttl]
#   bc.create_record [--backup] <hostname> <domain> <ip> [ttl]
bc.create_record webserver example.com 192.168.1.100
bc.create_record mail      example.com 192.168.1.101 3600

# CNAME (no TTL arg)
#   bc.create_cname [--backup] <fqdn> <target>
#   bc.create_cname [--backup] <alias> <domain> <target>
bc.create_cname www example.com webserver
bc.create_cname ftp.example.com fileserver.example.com.

# TXT
#   bc.create_txt [--backup] <name> <domain> <text_value>
bc.create_txt _dmarc example.com "v=DMARC1; p=quarantine"
bc.create_txt @      example.com "v=spf1 mx a ip4:192.168.1.0/24 ~all"

# Delete
#   bc.delete_record [--backup] <fqdn> [record_type]
#   bc.delete_record [--backup] <name> <domain> [record_type]
bc.delete_record webserver example.com
bc.delete_record www.example.com CNAME

# List (--json|-j supported; same JSON shape as the Chief plugin)
#   bc.list_records [--json|-j] [domain] [record_type]
bc.list_records
bc.list_records example.com
bc.list_records example.com A
bc.list_records --json example.com

# Refresh (also runs PTR sync as part of validation)
bc.refresh
bc.sync_ptr_from_forwards     # manager-side name; the Chief plugin wraps this as bc.sync_ptr

# Diagnostics
bc.show_environment           # show BIND paths, domains, container status
bc.help                       # list all bc.* commands and usage
```

The manager also defines short-name dispatchers `bc.create` / `bc.list` / `bc.delete` so the **same `bc.create webserver.example.com 192.0.2.100` syntax works on the host** as well as via the Chief plugin. Updating records on the host requires the manual `bc.delete_record` + `bc.create_record` sequence shown below — the in-container manager has no `bc.update` equivalent (use the Chief plugin if you need single-reload updates).

```bash
# Update A record on the host (manual delete + recreate; BIND reloads twice)
bc.delete_record webserver example.com
bc.create_record webserver example.com 192.168.1.200
```

When run **as a script** (cron, systemd timers, etc.) — i.e. not sourced — only the `refresh` subcommand is supported:

```bash
sudo /opt/bindcaptain/tools/bindcaptain_manager.sh refresh
```

## Advanced Operations

### Bulk Operations

#### Create Multiple Records

```bash
# Create multiple A records from file (Chief plugin form)
while read -r host ip; do
    bc.create "$host.example.com" "$ip"
done < hosts.txt

# Or directly on the host with the in-container manager
while read -r host ip; do
    bc.create_record "$host" example.com "$ip"
done < hosts.txt
```

#### Backup

Zone backups are created automatically by the in-container manager when `BINDCAPTAIN_ENABLE_BACKUPS=true` and the low-level primitives (`bc.create_record`, `bc.create_cname`, `bc.create_txt`, `bc.delete_record`) are called with the `--backup` flag. Backup location: `$CONTAINER_DATA_DIR/backups` (e.g. `/opt/bindcaptain/backups` on the host).

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

### Complete Domain Setup (Chief plugin)

```bash
# Load the plugin (locally or on a workstation)
source /opt/bindcaptain/chief-plugin/bc_chief-plugin.sh

# Create main A records
bc.create ns1.example.com  192.168.1.10
bc.create ns2.example.com  192.168.1.11
bc.create mail.example.com 192.168.1.20
bc.create web.example.com  192.168.1.30

# Create CNAME records
bc.create CNAME www.example.com web
bc.create CNAME ftp.example.com web

# Create TXT records
bc.create TXT @      example.com "v=spf1 mx a ip4:192.168.1.0/24 ~all"
bc.create TXT _dmarc example.com "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"

# PTR records are created automatically when adding A records (for managed networks)

# Validate and reload BIND
bc.refresh
```

---

**Need help?** Check the [Troubleshooting Guide](troubleshooting.md) or [Configuration](configuration.md).
