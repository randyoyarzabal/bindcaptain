# BindCaptain

> **Containerized BIND DNS Server - Deploy in Minutes**

A modern, containerized BIND DNS solution with automated management and reverse DNS generation. Perfect for homelabs, small businesses, and enterprise environments.

## Quick Start (3 Steps)

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

**Load the manager** in your shell (once per session, or add to your shell profile on the DNS host):

```bash
# From repo directory:
source ./tools/bindcaptain_manager.sh

# When installed under /opt/bindcaptain:
source /opt/bindcaptain/tools/bindcaptain_manager.sh
```

To have it loaded automatically when you log in as root, add one of the lines above to root’s `~/.bashrc` or `~/.profile`. For remote management from your workstation, use the [Chief bc plugin](chief-plugin/README.md).

Then run `bc.*` commands (as root on the DNS host):

```bash
# Add records
bc.create_record webserver yourdomain.com 192.168.1.100
bc.create_cname www yourdomain.com webserver
bc.create_txt @ yourdomain.com "v=spf1 -all"

# List records
bc.list_records yourdomain.com
```

> **Advanced DNS operations?** See [DNS Operations Guide](docs/dns-operations.md) for comprehensive record management and zone configuration.

## Key Commands

```bash
# Container Management
sudo ./bindcaptain.sh build|run|stop|restart|logs|status

# Service Management  
sudo ./bindcaptain.sh install|uninstall|enable|disable|start|stop-service

# DNS Management
bc.create_record|bc.create_cname|bc.create_txt|bc.delete_record|bc.list_records
```

> **Complete command reference?** See [Cheat Sheet](docs/cheat-sheet.md) for all available commands and examples.

### Git: push to GitHub and Fluxmire Gitea

After cloning, run once so **`git push origin`** updates **both** [GitHub](https://github.com/randyoyarzabal/bindcaptain) and Fluxmire Gitea (`ssh://git@git.fluxmire.io:2222/homelab/bindcaptain.git`):

```bash
./tools/setup-git-dual-push.sh
```

The named **`gitea`** remote is unchanged if you use **`git fetch gitea`** separately.

## Features

- **Deploy in Minutes** - 3-step setup process
- **Containerized** - Clean, isolated BIND installation  
- **Smart Management** - CLI tools for DNS record management
- **Secure** - Modern BIND 9.16+ with security best practices
- **Auto-Reverse DNS** - Automatic reverse DNS generation
- **Auto-Updates** - Built-in git refresh functionality
- **Production-Ready** - Used in real production environments

## Documentation

- **[Complete Guide](docs/index.md)** - Full documentation index
- **[Installation](docs/installation.md)** - Detailed setup instructions
- **[DNS Operations](docs/dns-operations.md)** - Managing DNS records
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions
- **[Cheat Sheet](docs/cheat-sheet.md)** - Quick command reference

## Contributing

Issues and pull requests welcome! See our [GitHub repository](https://github.com/randyoyarzabal/bindcaptain).

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**BindCaptain** - *Navigate your DNS with confidence*
