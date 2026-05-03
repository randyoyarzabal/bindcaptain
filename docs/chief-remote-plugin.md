# Chief Remote Plugin for BindCaptain

Optional **Chief** plugin that lets you control a **remote** BindCaptain installation from your local machine. All DNS and service commands are executed on the remote host over SSH.

Use case: BindCaptain runs on a server (e.g. `primary.example.com`); you use Chief on your laptop and run `bc.create`, `bc.list`, etc.; the plugin runs the corresponding commands on the server via SSH.

**Chief is a separate project.** If you are not familiar with it, see the Chief GitHub project for what it is, how to install it, and how to use plugins:  
[https://github.com/randyoyarzabal/chief](https://github.com/randyoyarzabal/chief)

## Overview

- **Plugin name:** `bc` (BindCaptain)
- **Location in repo:** `chief-plugin/bc_chief-plugin.sh`
- **Requirements:** Chief (or any shell that sources Chief plugins), SSH access to the BindCaptain host, BindCaptain installed on that host.

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Chief** | Separate shell framework that loads user plugins. See [Chief on GitHub](https://github.com/randyoyarzabal/chief) for more info. |
| **SSH** | Access to the remote host as a user that can run `sudo` (typically `root`). |
| **Remote host** | BindCaptain installed (e.g. under `/opt/bindcaptain`) with `tools/bindcaptain_manager.sh` and, if you use service commands, the systemd unit `bindcaptain`. |
| **SSH auth** | Key-based authentication is recommended so commands run without a password prompt. |

## Configuration variables

Set these **before** sourcing the plugin, or edit the defaults inside `bc_chief-plugin.sh`.

| Variable | Description | Default |
|----------|-------------|---------|
| **`BC_HOST`** | If set, SSH target `user@host` (must be able to `sudo` there). If unset, commands run **on the current machine** (for Chief on the DNS host). | *(unset — local)* |
| **`BC_MANAGER`** | Absolute path to `bindcaptain_manager.sh` on the **remote** host. | `/opt/bindcaptain/tools/bindcaptain_manager.sh` |

### Overriding without editing the file

```bash
# Only when Chief runs on another machine than BindCaptain:
export BC_HOST="root@dns.example.com"
export BC_MANAGER="/opt/bindcaptain/tools/bindcaptain_manager.sh"
# Then load the plugin (e.g. Chief does this automatically for the bc plugin)
source /path/to/bc_chief-plugin.sh
```

When Chief runs **on** the BindCaptain host (e.g. root on the primary), do **not** set `BC_HOST` so `bc.list` / `bc.status` run locally without SSH.

## Installation

1. **Copy the plugin into Chief’s user plugins** so Chief loads it as the `bc` plugin. The exact path depends on your Chief setup (e.g. `chief_plugins/user_plugins/bc_chief-plugin.sh` or equivalent). You can copy from the BindCaptain repo:
   ```bash
   cp bindcaptain/chief-plugin/bc_chief-plugin.sh /path/to/chief/user_plugins/
   ```
2. **Set `BC_HOST` and `BC_MANAGER`** for your BindCaptain server (see above).
3. **Load the plugin** (e.g. start a new Chief shell or run `chief.plugin bc` if your Chief supports it).
4. Run `bc.help` to confirm and see usage.

### Reloading plugins in an existing shell

Chief keeps sourced plugins in the **current** shell. If you change `bc_chief-plugin.sh` on disk, or you open a session that started before the plugin was available, `bc.status` and other `bc.*` names may be undefined until you reload:

```text
chief.reload
```

If your Chief build uses a different command for the same action, use that instead of starting a subshell that never loaded the plugin.

## Commands (summary)

After loading the plugin. Signatures match `chief-plugin/bc_chief-plugin.sh` verbatim. **Write operations only support `A`, `CNAME`, and `TXT`** — anything else is rejected with `Unsupported record type`.

| Command | Description |
|---------|-------------|
| `bc.create [A] <fqdn> <ip> [ttl] [--json]` | Create A record (PTR auto-created for managed networks). Hostname+domain form also supported. `A` is the default type when omitted. |
| `bc.create CNAME <fqdn> <target> [--json]` | Create CNAME record. |
| `bc.create TXT <name> <domain> <value> [--json]` | Create TXT record (use `@` for zone apex). |
| `bc.create_cname <fqdn> <target> [--json]` | Shortcut for `bc.create CNAME …`. |
| `bc.create_txt <name> <domain> <value> [--json]` | Shortcut for `bc.create TXT …`. |
| `bc.update [A\|CNAME\|TXT] <fqdn> <new_value> [ttl] [--json]` | Update a record (delete + recreate in one SSH session, single BIND reload). Also accepts `--json '<json-object>'` input. |
| `bc.delete <fqdn> [type] [--json]` | Delete a DNS record (optionally restricted to `type`). |
| `bc.list [domain] [--json\|-j]` | List records (all zones or one domain); JSON array on `--json`. |
| `bc.refresh [--json]` | Validate zones and reload BIND on the remote. |
| `bc.sync_ptr [--json]` | Rewrite managed reverse zones so PTRs match forward A records. |
| `bc.git_refresh` | Run `git pull` in the BindCaptain repo on the remote. |
| `bc.status` | Show BindCaptain service and container status. |
| `bc.start` / `bc.stop` / `bc.restart` | Control the BindCaptain systemd service. |
| `bc.ssh` | Open an interactive SSH session to the BindCaptain host. |
| `bc.help` | Show full usage and current `BC_HOST` / `BC_MANAGER`. |

**Aliases:** `bc.a`=`bc.create`, `bc.up`=`bc.update`, `bc.cname`=`bc.create_cname`, `bc.txt`=`bc.create_txt`, `bc.rm`=`bc.delete`, `bc.ls`=`bc.list`.

## Examples

```bash
# Create A record (FQDN form; hostname+domain form also accepted)
bc.create webserver.example.com 192.0.2.100
bc.create webserver example.com 192.0.2.100 3600        # explicit TTL
bc.create webserver.example.com 192.0.2.100 --json       # JSON output

# Create CNAME / TXT
bc.create CNAME www.example.com webserver
bc.create TXT   @   example.com "v=spf1 -all"
bc.create_cname www.example.com webserver                # shortcut form
bc.create_txt   @   example.com "v=spf1 -all"            # shortcut form

# Update an existing record (delete+create in one session, one BIND reload)
bc.update webserver.example.com 192.0.2.200
bc.update CNAME www.example.com newtarget
bc.update --json '{"type":"A","fqdn":"web.example.com","rdata":"192.0.2.200","ttl":3600}'

# List / delete
bc.list example.com
bc.list example.com --json
bc.delete webserver.example.com
bc.delete www.example.com CNAME --json

# Maintenance
bc.refresh           # validate + reload BIND on the remote
bc.sync_ptr          # rebuild managed PTR zones from forward A records
bc.git_refresh       # update BindCaptain on the remote
bc.ssh               # interactive SSH session to BC_HOST
```

## How it works

- The plugin is **sourced** in your local shell (never run as `./bc_chief-plugin.sh`).
- Each `bc.*` command uses `ssh $BC_HOST` to run the corresponding operation on the remote host (or runs locally when `BC_HOST` is unset).
- DNS record operations run `sudo bash -c 'source $BC_MANAGER && bc.create_record …'` (and similar low-level primitives) on the remote, so the same logic as [bindcaptain_manager.sh](dns-operations.md) is used there.
- `bc.update` issues a single `delete + create` script over one SSH session so BIND reloads only at the end.
- Service commands run `systemctl` and `podman` on the remote.

## Troubleshooting

- **`bc.status`, `bc.list`, or `bc.*` not found** (interactive Chief session)  
  The `bc` plugin may not be loaded in that shell yet, or you updated the plugin file after Chief started. Run **`chief.reload`** (or open a new Chief login session), then `bc.help`.

- **“Cannot connect to $BC_HOST”**  
  Check SSH from your machine: `ssh $BC_HOST`. Ensure key-based auth or agent is set up so the plugin can connect without a password.

- **“Permission denied” or sudo errors on remote**  
  The user in `BC_HOST` must be able to run `sudo` without a password for the paths and commands the plugin uses (e.g. `sudo source $BC_MANAGER`, `sudo systemctl`, `sudo podman`).

- **Manager not found on remote**  
  Confirm BindCaptain is installed and `BC_MANAGER` points to the real path on the **remote** host (e.g. `/opt/bindcaptain/tools/bindcaptain_manager.sh`). See [Installation](installation.md) for where BindCaptain lives on the server.

## See also

- [DNS Operations](dns-operations.md) — same `bc.*`-style commands when run **on** the server (sourcing `bindcaptain_manager.sh`).
- [Installation](installation.md) — how to install BindCaptain on the remote host.
- [Cheat Sheet](cheat-sheet.md) — quick reference for BindCaptain commands.
