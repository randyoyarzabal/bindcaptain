# BindCaptain

> **Containerized BIND DNS Server with Smart Management**

Modern, containerized BIND DNS solution with automated management and inline reverse DNS generation, perfect for homelab and enterprise environments.

## Quick Start

### 1. Clone & Configure
```bash
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# Add your DNS zones
mkdir -p config/yourdomain.com
# Copy your zone files to config/yourdomain.com/
# Copy config-examples/named.conf.template to config/named.conf and customize
```

### 2. Launch Container
```bash
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run
```

### 3. Verify & Manage
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

Detailed guides available in [`docs/`](docs/):

- **[docs/cheat-sheet.md](docs/cheat-sheet.md)** - Complete management reference
- **[docs/setup-system.md](docs/setup-system.md)** - System prerequisites  
- **[docs/example-add-record.md](docs/example-add-record.md)** - Step-by-step examples
- **[docs/systemd-service.md](docs/systemd-service.md)** - Systemd service setup guide

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
# Rocky Linux 9 / CentOS Stream 9 / AlmaLinux 9
    sudo ./tools/setup.sh  # Installs Podman, git, bind-utils
```

See [docs/setup-system.md](docs/setup-system.md) for detailed system setup.

## Contributing

Issues and pull requests welcome! See our [GitHub repository](https://github.com/randyoyarzabal/bindcaptain).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**BindCaptain** - *Navigate your DNS with confidence*