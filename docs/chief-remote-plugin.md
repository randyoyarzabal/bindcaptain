# Chief Remote Plugin for BindCaptain

Optional **Chief** plugin that lets you control a **remote** BindCaptain installation from your local machine. All DNS and service commands are executed on the remote host over SSH.

Use case: BindCaptain runs on a server (e.g. `wolfman.homelab.io`); you use Chief on your laptop and run `bc.create`, `bc.list`, etc.; the plugin runs the corresponding commands on the server via SSH.

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

When Chief runs **on** the BindCaptain host (e.g. root on `wolfman`), do **not** set `BC_HOST` so `bc.list` / `bc.status` run locally without SSH.

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

After loading the plugin:

| Command | Description |
|---------|-------------|
| `bc.create <fqdn> <ip>` | Create A record (and PTR when applicable). |
| `bc.create_cname <fqdn> <target>` | Create CNAME record. |
| `bc.create_txt <name> <domain> <value>` | Create TXT record. |
| `bc.delete <fqdn> [type]` | Delete a DNS record. |
| `bc.list [domain]` | List records (all zones or one domain). |
| `bc.refresh` | Validate and reload BIND on the remote. |
| `bc.git_refresh` | Run `git pull` in the BindCaptain repo on the remote. |
| `bc.status` | Show BindCaptain service and container status. |
| `bc.start` / `bc.stop` / `bc.restart` | Control the BindCaptain systemd service. |
| `bc.ssh` | Open an interactive SSH session to the BindCaptain host. |
| `bc.help` | Show full usage and current `BC_HOST` / `BC_MANAGER`. |

## Examples

```bash
# Create A record
bc.create webserver.homelab.io 172.25.50.100

# Create CNAME
bc.create_cname www.homelab.io webserver

# TXT record
bc.create_txt @ homelab.io "v=spf1 -all"

# List records
bc.list homelab.io

# Delete record
bc.delete webserver.homelab.io

# Refresh BIND config on remote
bc.refresh

# Update BindCaptain from Git on remote
bc.git_refresh

# SSH to the BindCaptain host
bc.ssh
```

## How it works

- The plugin is **sourced** in your local shell (never run as `./bc_chief-plugin.sh`).
- Each `bc.*` command uses `ssh $BC_HOST` to run the corresponding operation on the remote host.
- DNS record operations run `source $BC_MANAGER && bc.create_record ...` (and similar) on the remote, so the same logic as [bindcaptain_manager.sh](dns-operations.md) is used there.
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
