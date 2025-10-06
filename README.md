# BindCaptain

> **Containerized BIND DNS Server with Smart Management**

Modern, containerized BIND DNS solution with automated management and inline reverse DNS generation, perfect for homelab and enterprise environments.

## System Requirements

### Supported Distributions
BindCaptain includes an automated system setup script for the following distributions:

- **RHEL 8+** (Red Hat Enterprise Linux)
- **CentOS 8+** (CentOS Stream)
- **Rocky Linux 8+**
- **AlmaLinux 8+**
- **Fedora 30+**

### Manual Setup for Other Distributions
If you're using an unsupported distribution (Ubuntu, Debian, Arch, etc.), you'll need to manually install the prerequisites before running BindCaptain:

#### Required Packages
```bash
# Install container runtime (Podman recommended)
# Ubuntu/Debian:
sudo apt update
sudo apt install podman podman-compose buildah skopeo

# Arch Linux:
sudo pacman -S podman podman-compose buildah skopeo

# Other distributions: Install Podman from your package manager
```

#### Required Tools
- **Podman** (container runtime)
- **Git** (for cloning repository)
- **bind-utils** (for DNS testing with `dig`, `nslookup`)

#### System Configuration
- **Port 53** must be available (stop any existing DNS services)
- **Root privileges** required for container operations
- **Firewall** configured to allow ports 53/tcp and 53/udp

## Quick Start

### 1. System Setup (First Time)

#### For Supported Distributions (RHEL/CentOS/Rocky/AlmaLinux/Fedora)
```bash
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# Automated system setup (installs Podman, configures system)
# This script will detect your distribution and install prerequisites
sudo ./tools/system-setup.sh
```

> **Note**: The automated setup script will check your distribution and provide helpful error messages if you're on an unsupported system.

#### For Other Distributions (Ubuntu/Debian/Arch/etc.)
```bash
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# Manual setup required - see detailed instructions below
# Install Podman, bind-utils, and configure system manually
```

**📖 Detailed Manual Setup Guide**: See [Manual Setup Guide](docs/manual-setup.md) for step-by-step instructions for Ubuntu, Debian, Arch Linux, and other distributions.

### 2. Configure DNS Zones
```bash
# Interactive configuration wizard
sudo ./tools/config-setup.sh wizard

# Or manual setup
mkdir -p config/yourdomain.com
# Copy your zone files to config/yourdomain.com/
# Copy config-examples/named.conf.template to config/named.conf and customize
```

### 3. Launch Container
```bash
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run
```

### 4. Verify & Manage
```bash
# Test DNS resolution
dig @your-server-ip yourdomain.com

# Manage DNS records
sudo bash -c "source ./bindcaptain_manager.sh && bind.create_record webserver yourdomain.com 192.168.1.100"
```

## Systemd Service Setup (Recommended)

For production use, BindCaptain can be installed as a systemd service for automatic startup:

### Automatic First-Time Setup
The script will offer to install the systemd service when `run` is executed and the service is not found:

```bash
# First time setup (will prompt for service installation)
sudo ./bindcaptain.sh run
```

### Manual Service Installation
```bash
# Install systemd service
sudo ./bindcaptain.sh install

# Enable and start
sudo ./bindcaptain.sh enable
sudo ./bindcaptain.sh start

# Check status
sudo ./bindcaptain.sh service-status
```

### Service Management
```bash
# Using BindCaptain script
sudo ./bindcaptain.sh start         # Start service
sudo ./bindcaptain.sh stop-service  # Stop service
sudo ./bindcaptain.sh restart       # Restart service
sudo ./bindcaptain.sh service-status # Show status

# Using systemctl directly
sudo systemctl start bindcaptain
sudo systemctl stop bindcaptain
sudo systemctl restart bindcaptain
sudo systemctl status bindcaptain
sudo journalctl -u bindcaptain -f   # View logs
```

For detailed systemd setup instructions, see [Systemd Service Guide](docs/systemd-service.md).

## DNS Management

```bash
    # Source the manager
    sudo bash -c "source /opt/bindcaptain/tools/bindcaptain_manager.sh"

# Add DNS records
bind.create_record webserver yourdomain.com 192.168.1.100
bind.create_cname www yourdomain.com webserver
bind.create_txt @ yourdomain.com "v=spf1 -all"

# List records
bind.list_records yourdomain.com

# Update codebase
bind.git_refresh
```

## Management Commands

BindCaptain provides several management commands for DNS operations:

```bash
# Container Management
sudo ./bindcaptain.sh build    # Build container image
sudo ./bindcaptain.sh run      # Start DNS container
sudo ./bindcaptain.sh stop     # Stop container
sudo ./bindcaptain.sh restart  # Restart container
sudo ./bindcaptain.sh logs     # View container logs
sudo ./bindcaptain.sh status   # Check container status

# Service Management (systemd)
sudo ./bindcaptain.sh install       # Install systemd service
sudo ./bindcaptain.sh uninstall     # Uninstall systemd service
sudo ./bindcaptain.sh enable        # Enable service at boot
sudo ./bindcaptain.sh disable       # Disable service at boot
sudo ./bindcaptain.sh start         # Start service
sudo ./bindcaptain.sh stop-service  # Stop service
sudo ./bindcaptain.sh restart       # Restart service
sudo ./bindcaptain.sh service-status # Show service status

# DNS Record Management (via bindcaptain_manager.sh)
bind.create_record <hostname> <domain> <ip>     # Add A record + PTR (automatic)
bind.create_cname <alias> <domain> <target>     # Add CNAME record  
bind.create_txt <name> <domain> <text>          # Add TXT record
bind.delete_record <name> <domain> [type]       # Delete record
bind.list_records [domain] [type]               # List records

# System Updates
bind.git_refresh [--force]                      # Update codebase from GitHub
```

## Features

- **Containerized** - Clean, isolated BIND installation
- **Auto-Updates** - Built-in git refresh functionality  
- **Smart Management** - CLI tools for DNS record management
- **Secure** - Modern BIND 9.16+ with security best practices
- **Zero-Config** - Works out of the box with example configs
- **Auto-Reverse** - Automatic reverse DNS generation
- **Production-Ready** - Used in real production environments


## Documentation

Comprehensive documentation is available in the [`docs/`](docs/) directory:

### Quick Start
- **[Installation Guide](docs/installation.md)** - Complete setup and configuration
- **[Quick Start Guide](docs/quick-start.md)** - Get up and running in minutes
- **[System Requirements](docs/system-requirements.md)** - Supported distributions and prerequisites

### User Guides
- **[DNS Operations](docs/dns-operations.md)** - Managing DNS records and zones
- **[Configuration Management](docs/configuration.md)** - Customizing your DNS setup
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

### Reference
- **[Complete Documentation Index](docs/index.md)** - Full table of contents and navigation
- **[Cheat Sheet](docs/cheat-sheet.md)** - Quick command reference
- **[Systemd Service](docs/systemd-service.md)** - Service management guide

**📚 [View All Documentation](docs/index.md)**

## Architecture

```
BindCaptain/
├── bindcaptain.sh          # Container management + systemd service
├── bindcaptain.service     # Systemd service file
├── config-examples/        # Example configurations
└── docs/                   # Documentation
```

## Requirements

- **Podman** (container runtime)
- **Git** (for cloning repository)

### First-Time Container Setup (Optional)

If you need to install Podman and container tools:

```bash
# RHEL/CentOS/Rocky/AlmaLinux/Fedora
    sudo ./tools/system-setup.sh  # Installs Podman, git, bind-utils
```

See [docs/setup-system.md](docs/setup-system.md) for detailed system setup.

## Contributing

Issues and pull requests welcome! See our [GitHub repository](https://github.com/randyoyarzabal/bindcaptain).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**BindCaptain** - *Navigate your DNS with confidence*