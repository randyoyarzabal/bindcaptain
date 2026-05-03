# ⚓ BindCaptain

> **Containerized BIND DNS Server — Deploy in Minutes**

[![Version](https://img.shields.io/badge/version-1.2.0-blue)](VERSION) [![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![BIND](https://img.shields.io/badge/BIND-9.16%2B-orange)](https://www.isc.org/bind/)

**Repository:** <https://github.com/randyoyarzabal/bindcaptain>

A modern, containerized BIND DNS solution with automated record management,
auto-generated reverse PTR zones, and a clean `bc.*` CLI for day-to-day
operations. Suitable for homelabs, small businesses, and enterprise
environments. Runs as a Podman container, manages everything via systemd,
and integrates with your system logger for free rotation and shipping.

## TL;DR (RHEL family)

```bash
git clone https://github.com/randyoyarzabal/bindcaptain.git /opt/bindcaptain
cd /opt/bindcaptain
sudo ./tools/system-setup.sh         # installs Podman + deps
sudo ./tools/config-setup.sh wizard  # interactive zone setup
sudo ./bindcaptain.sh install        # systemd service
sudo systemctl enable --now bindcaptain
dig @<your-dns-ip> SOA <your-zone>   # verify
```

For Ubuntu/Debian/Arch, install Podman first (`sudo apt install podman`
or `sudo pacman -S podman`), then run the same `config-setup.sh`,
`install`, and `enable --now` steps above.

If your server must NOTIFY external secondaries (slaves), set
`BINDCAPTAIN_NETWORK_MODE=host` — see [docs/networking.md](docs/networking.md).

## Tracking `config/` in a separate (private) repo

BindCaptain intentionally **gitignores `config/`** so site-specific
zones, IPs, and secrets never land in the public repo. A common
pattern is to keep `config/` under version control in a **separate
private repo** (e.g. an internal Gitea/GitLab) and symlink it into
place:

```bash
ln -s /opt/ops/dns/bindcaptain /opt/bindcaptain/config
# or
export BINDCAPTAIN_CONFIG_PATH=/opt/ops/dns/bindcaptain
```

See [docs/config-tracked-separately.md](docs/config-tracked-separately.md)
for the full pattern, deploy alternatives, and the v1.2.0 fixes that
make symlinked configs work cleanly with chown/chmod across reloads.

## Quick Start (detailed, 3 steps)

### 1. Clone & Setup

```bash
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# Auto-install Podman and dependencies (RHEL/CentOS/Rocky/AlmaLinux/Fedora)
sudo ./tools/system-setup.sh

# For Ubuntu/Debian/Arch: Install Podman manually first
# Ubuntu: sudo apt install podman podman-compose buildah skopeo
# Arch: sudo pacman -S podman podman-compose buildah skopeo
```

### 2. Configure DNS

```bash
# Interactive wizard (recommended)
sudo ./tools/config-setup.sh wizard

# Or manual: Copy your zone files to config/yourdomain.com/
```

### 3. Launch & Test

```bash
# Build and run
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run

# Test DNS resolution
dig @localhost yourdomain.com
```

**That's it!** Your DNS server is running. See [Complete Documentation](docs/index.md) for advanced features.

## System Requirements

- **Podman** (container runtime)
- **Git** (for cloning)
- **Port 53** available
- **Root privileges**

**Supported OS**: RHEL 8+, CentOS 8+, Rocky Linux 8+, AlmaLinux 8+, Fedora 30+, Ubuntu, Debian, Arch Linux

### Environment Variables

- **`BINDCAPTAIN_CONFIG_PATH`** - Path to your DNS configuration directory (default: `./config`)
- **`TZ`** - Timezone setting (default: `UTC`)

```bash
# Use custom configuration directory
BINDCAPTAIN_CONFIG_PATH=/path/to/my/dns-config sudo ./bindcaptain.sh run
```

> **Need detailed setup instructions?** See [System Requirements](docs/system-requirements.md) and [Manual Setup Guide](docs/manual-setup.md) for comprehensive installation steps.

## Production Setup

### Systemd Service (Auto-start)

```bash
# Install as systemd service (one-time)
sudo ./bindcaptain.sh install
sudo ./bindcaptain.sh enable

# Service management
sudo ./bindcaptain.sh start|stop|restart|service-status
```

> **Detailed service setup?** See [Systemd Service Guide](docs/systemd-service.md) for complete service management instructions.

### DNS Record Management

BindCaptain exposes **two distinct `bc.*` command surfaces**. Most users only ever touch the first one:

| Surface | Where it’s sourced | Primary use case | Commands |
|---|---|---|---|
| **Chief plugin (`bc_chief-plugin.sh`)** | Operator/workstation shell, via [Chief](https://github.com/randyoyarzabal/chief) — or directly on the DNS host with `BC_HOST` unset | **Day-to-day DNS edits** (local or remote). Wraps the in-container manager over SSH, normalizes output, and supports `--json`. | `bc.create`, `bc.update`, `bc.delete`, `bc.list`, `bc.refresh`, `bc.sync_ptr`, plus `bc.create_cname` / `bc.create_txt` shortcuts |
| **In-container manager (`bindcaptain_manager.sh`)** | Sourced **inside the container scope** (or via `sudo bash -c 'source $BC_MANAGER && …'`) on the DNS host | Low-level direct calls — what the Chief wrappers dispatch to under the hood. Useful for debugging or scripted host-local automation. | `bc.create_record`, `bc.create_cname`, `bc.create_txt`, `bc.delete_record`, `bc.list_records` |

> **Important:** `bc.create_record` / `bc.delete_record` / `bc.list_records` (the `_record`-suffixed names) **only exist** when the in-container manager is sourced. From a normal operator shell with the Chief plugin loaded, only the high-level wrappers (`bc.create`, `bc.delete`, `bc.list`, …) are present — verify with `bc.<TAB>` completion.

**Recommended usage — Chief plugin wrappers** (load the plugin, then run the same commands locally on the DNS host or remotely from your workstation; see [Chief bc plugin](chief-plugin/README.md)):

```bash
# Add records (TYPE defaults to A; CNAME / TXT supported)
bc.create webserver.yourdomain.com 192.168.1.100
bc.create CNAME www.yourdomain.com webserver
bc.create TXT @ yourdomain.com "v=spf1 -all"

# Update / delete
bc.update webserver.yourdomain.com 192.168.1.200
bc.delete webserver.yourdomain.com

# List (machine-readable with --json)
bc.list yourdomain.com
bc.list yourdomain.com --json
```

Write operations (`bc.create` / `bc.update`) accept **only `A`, `CNAME`, and `TXT`** — anything else is rejected with `Unsupported record type`.

<details>
<summary>Low-level / direct-on-host (in-container manager)</summary>

These are only callable when the manager is sourced inside the container scope:

```bash
# On the DNS host, as root:
sudo bash -c 'source /opt/bindcaptain/tools/bindcaptain_manager.sh && \
  bc.create_record webserver yourdomain.com 192.168.1.100'

# Or load it into your root shell for repeated use:
source /opt/bindcaptain/tools/bindcaptain_manager.sh

bc.create_record webserver yourdomain.com 192.168.1.100   # A
bc.create_cname  www       yourdomain.com webserver        # CNAME
bc.create_txt    @         yourdomain.com "v=spf1 -all"    # TXT
bc.delete_record webserver.yourdomain.com [TYPE]
bc.list_records  yourdomain.com
```

To auto-load on root login on the DNS host, add the `source …/bindcaptain_manager.sh` line to root’s `~/.bashrc` or `~/.profile`.

</details>

> **Advanced DNS operations?** See [DNS Operations Guide](docs/dns-operations.md) for comprehensive record management and zone configuration.

## Key Commands

```bash
# Container Management
sudo ./bindcaptain.sh build|run|stop|restart|logs|status

# Service Management
sudo ./bindcaptain.sh install|uninstall|enable|disable|start|stop-service

# DNS Management — Chief plugin wrappers (operator/remote shell)
bc.create | bc.update | bc.delete | bc.list | bc.refresh | bc.sync_ptr

# DNS Management — in-container manager (sourced on the DNS host)
bc.create_record | bc.create_cname | bc.create_txt | bc.delete_record | bc.list_records
```

> **Complete command reference?** See [Cheat Sheet](docs/cheat-sheet.md) for all available commands and examples.

### Git: GitHub + private mirror (optional)

To push and fetch both **this GitHub repository** and a **separate, private Git remote** (self-hosted, team, etc.), do not store that mirror’s URL in the public tree. Choose one way to point at it, then run:

```bash
export BINDCAPTAIN_GIT_MIRROR_URL='ssh://…'   # or: copy local/git-mirror.url.example → local/git-mirror.url
./tools/setup-git-dual-push.sh
```

- **`local/git-mirror.url`** (gitignored) can hold a single `ssh://…` or `git@…` line (see **local/git-mirror.url.example**). If a second remote is already in your local `.git/config`, the script can reuse that URL.
- **`git push origin`** goes to both GitHub and the mirror; **`git fetch --all`** updates both. On a **deploy host** that only has SSH to the private mirror, use **`BINDCAPTAIN_PREFER_MIRROR_FOR_PULL=1`** so **`git pull`** fast-forwards from the mirror; add a [GitHub deploy key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#deploy-keys) (or a key for `git@github.com`) so **`git fetch origin`** and the GitHub leg of **`git push origin`** work.

## Features

- **Deploy in Minutes** - 3-step setup process
- **Containerized** - Clean, isolated BIND installation  
- **Smart Management** - CLI tools for DNS record management
- **Secure** - Modern BIND 9.16+ with security best practices
- **Auto-Reverse DNS** - Automatic reverse DNS generation
- **Auto-Updates** - Built-in git refresh functionality
- **Production-Ready** - Used in real production environments

## Documentation

- **[Complete Guide](docs/index.md)** — Full documentation index
- **[Installation](docs/installation.md)** — Detailed setup instructions
- **[DNS Operations](docs/dns-operations.md)** — Managing DNS records
- **[Networking](docs/networking.md)** — `BINDCAPTAIN_NETWORK_MODE` (bridge vs host) and slave-NOTIFY notes
- **[Tracking config/ separately](docs/config-tracked-separately.md)** — keep your zones in a private repo, symlinked into place
- **[Secondaries / NOTIFY / rndc](docs/secondary-notify-and-rndc.md)** — primary/secondary plumbing
- **[Troubleshooting](docs/troubleshooting.md)** — Common issues and solutions
- **[Cheat Sheet](docs/cheat-sheet.md)** — Quick command reference
- **[Changelog](CHANGELOG.md)** — Release history

## Contributing

Issues and pull requests welcome! See our [GitHub repository](https://github.com/randyoyarzabal/bindcaptain).

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**BindCaptain** - *Navigate your DNS with confidence*
