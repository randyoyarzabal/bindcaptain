# Example: Adding a New DNS Record

## Scenario: add `newserver.example.com` → `192.168.1.200`

### Step 1 — Load a `bc.*` command surface

Pick whichever fits your workflow (both produce the same result; see [DNS Operations](dns-operations.md) for the full surface comparison):

```bash
# Chief plugin (recommended; works locally on the DNS host or remotely with BC_HOST set)
source /opt/bindcaptain/chief-plugin/bc_chief-plugin.sh

# Or, on the DNS host directly, the in-container manager
source /opt/bindcaptain/tools/bindcaptain_manager.sh
```

### Step 2 — Create the A record

Chief plugin (recommended):

```bash
bc.create newserver.example.com 192.168.1.200
# or hostname + domain form:
bc.create newserver example.com 192.168.1.200
# explicit TTL:
bc.create newserver.example.com 192.168.1.200 3600
```

In-container manager (low-level equivalent):

```bash
bc.create_record newserver example.com 192.168.1.200
```

Output (Chief plugin form, summary mode):

```text
✓ Create A record: success
  Host:    local
  Record:  newserver.example.com A 192.168.1.200
  Message: A record created: newserver.example.com -> 192.168.1.200
  Reload:  BIND reloaded
```

Add `--json` to either form (`bc.create … --json`) for machine-readable output.

### Step 3 — Verify

```bash
# Forward lookup
dig @192.168.1.1 newserver.example.com +short
# → 192.168.1.200

# Reverse lookup (PTR is created automatically for managed networks)
dig @192.168.1.1 -x 192.168.1.200 +short
# → newserver.example.com.

# List the zone
bc.list example.com           # Chief plugin
# bc.list_records example.com # In-container manager
```

## What just happened

- ✓ Serial number incremented automatically
- ✓ Zone validated before applying
- ✓ PTR record auto-created (for IPs in a managed reverse network)
- ✓ BIND reloaded
- ✓ Configured secondaries automatically notified

---

## Adding a CNAME record

`bc.create CNAME` does **not** take a TTL argument.

```bash
# Chief plugin — FQDN form
bc.create CNAME web.example.com newserver

# Chief plugin — alias + domain form
bc.create CNAME web example.com newserver

# Shortcut wrapper
bc.create_cname web.example.com newserver

# In-container manager (low-level)
bc.create_cname web example.com newserver
```

Verify:

```bash
dig @192.168.1.1 web.example.com +short
# → newserver.example.com.
#   192.168.1.200
```

## Updating or deleting

```bash
# Change the IP (delete + recreate in one BIND reload — Chief plugin only)
bc.update newserver.example.com 192.168.1.201

# Delete the record (any matching type, or restrict)
bc.delete newserver.example.com
bc.delete web.example.com CNAME
```

> The in-container manager has no `bc.update`. To update from the host with the manager, run `bc.delete_record` then `bc.create_record` (BIND reloads twice).

**Remember:** Always use `bc.*` rather than editing zone files by hand — the manager handles serial increments, validation, backups, and BIND reload for you.
