# BindCaptain

Welcome to **BindCaptain** - Take command of your DNS infrastructure with captain-grade precision.

## Table of Contents

### Getting Started

- [Quick Start Guide](quick-start.md) - Get up and running in minutes
- [System Requirements](system-requirements.md) - Supported distributions and manual setup
- [Installation Guide](installation.md) - Complete setup and configuration
- [Manual Setup](manual-setup.md) - Setup for unsupported Linux distributions

### User Guides

- [Configuration Management](configuration.md) - DNS zone and record management
- [Container Management](container-management.md) - Building, running, and managing containers
- [DNS Operations](dns-operations.md) - Creating, updating, and managing DNS records
- [Systemd Integration](systemd-service.md) - Service management and automation
- [Chief Remote Plugin](chief-remote-plugin.md) - Optional: control BindCaptain remotely via Chief over SSH
- [Troubleshooting](troubleshooting.md) - Common issues and solutions

### Advanced Topics

- [Architecture](architecture.md) - How BindCaptain works internally
- [Security](security.md) - Security best practices and hardening
- [Backup & Restore](backup-restore.md) - Data protection and recovery
- [Performance Tuning](performance.md) - Optimization and monitoring
- [Integration](integration.md) - Working with other tools and systems

### Reference

- [Script Reference](script-reference.md) - Complete command reference for all scripts
- [Configuration Reference](config-reference.md) - All configuration options
- [API Reference](api-reference.md) - Container and service APIs
- [Changelog](changelog.md) - Version history and changes

### Development

- [Contributing](contributing.md) - How to contribute to BindCaptain
- [Development Setup](development.md) - Setting up development environment
- [Testing](testing.md) - Running tests and validation
- [Code Style](code-style.md) - Coding standards and guidelines

## Quick Start

New to BindCaptain? Start here:

1. **[System Requirements](system-requirements.md)** - Check compatibility and prerequisites
2. **[Installation Guide](installation.md)** - Complete setup and configuration
3. **[Quick Start Guide](quick-start.md)** - Get your first DNS zone running
4. **[DNS Operations](dns-operations.md)** - Learn to manage DNS records

## Quick Examples

### Complete Setup (Supported Distributions)

```bash
# 1. Clone BindCaptain
git clone https://github.com/yourusername/bindcaptain.git
cd bindcaptain

# 2. System setup (one-time)
sudo ./tools/system-setup.sh

# 3. Configure DNS zones
sudo ./tools/config-setup.sh wizard

# 4. Build and run container
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run

# 5. Manage DNS records
source ./tools/bindcaptain_manager.sh
bc.create_record webserver example.com 192.168.1.100
```

### Manual Setup (Unsupported Distributions)

```bash
# 1. Install prerequisites manually
# See manual-setup.md for your distribution

# 2. Configure DNS zones
sudo ./tools/config-setup.sh wizard

# 3. Build and run container
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run
```

### DNS Management

```bash
# Load management functions
source ./tools/bindcaptain_manager.sh

# Create DNS records
bc.create_record webserver example.com 192.168.1.100
bc.create_record mail example.com 192.168.1.101
bc.create_cname www example.com webserver.example.com

# List and manage records
bc.list_records example.com
bc.delete_record webserver example.com

# Refresh DNS
./tools/bindcaptain_manager.sh refresh
```

## Supported Distributions

| Distribution | Support | Setup Method |
|-------------|---------|--------------|
| **RHEL 8/9** | ✅ Full | `system-setup.sh` |
| **CentOS 8/9** | ✅ Full | `system-setup.sh` |
| **Rocky Linux 8/9** | ✅ Full | `system-setup.sh` |
| **AlmaLinux 8/9** | ✅ Full | `system-setup.sh` |
| **Fedora 35+** | ✅ Full | `system-setup.sh` |
| **Ubuntu/Debian** | ⚠️ Manual | See [Manual Setup](manual-setup.md) |
| **Arch Linux** | ⚠️ Manual | See [Manual Setup](manual-setup.md) |
| **Others** | ⚠️ Manual | See [Manual Setup](manual-setup.md) |

## Core Features

- **🎯 Container-First** - Runs BIND in Podman containers for isolation
- **⚡ Quick Setup** - Automated system setup for supported distributions
- **🔧 Easy Management** - Interactive DNS record management
- **🛡️ Security Focused** - SELinux, firewalld, and security best practices
- **📊 Monitoring Ready** - Built-in logging and health checks
- **🔄 Auto-Reload** - Automatic BIND configuration reload on changes
- **📝 Template Driven** - Easy zone file generation from templates

## Project Structure

```text
bindcaptain/
├── bindcaptain.sh              # Main container management script
├── chief-plugin/               # Optional Chief plugin for remote control
│   ├── bc_chief-plugin.sh     # Source in Chief to control remote BindCaptain
│   └── README.md
├── tools/                      # Management and setup tools
│   ├── common.sh              # Shared utilities library
│   ├── system-setup.sh        # System preparation (supported distros)
│   ├── config-setup.sh        # DNS configuration management
│   └── bindcaptain_manager.sh # DNS management (bc.*); run 'refresh' or source for bc.help
├── config-examples/            # Configuration templates
├── docs/                      # Comprehensive documentation
└── tests/                     # Test suite
```

## Common Operations

```bash
# Container lifecycle
sudo ./bindcaptain.sh build     # Build container image
sudo ./bindcaptain.sh run       # Start container
sudo ./bindcaptain.sh stop      # Stop container
sudo ./bindcaptain.sh status    # Check status

# DNS management
source ./tools/bindcaptain_manager.sh
bc.create_record --help       # Show help
bc.list_records               # List records
./tools/bindcaptain_manager.sh refresh   # Reload BIND configuration

# System management
sudo ./tools/system-setup.sh    # One-time system setup
sudo ./tools/config-setup.sh    # Configure DNS zones
```

## Prerequisites

**Essential requirements:**

- **Linux** with Podman support
- **Root access** for system setup and container management
- **Network access** for DNS resolution
- **Storage** for configuration and zone files

**[Complete Prerequisites Guide](system-requirements.md)**

## How It Works

BindCaptain uses:

- **Container isolation** - BIND runs in Podman containers
- **Template-driven config** - Easy zone file generation
- **Interactive management** - User-friendly DNS record operations
- **Auto-reload** - Configuration changes applied automatically
- **Security hardening** - SELinux, firewalld, and best practices

---

**BindCaptain** - Take command of your DNS infrastructure

**GitHub:** [https://github.com/yourusername/bindcaptain](https://github.com/yourusername/bindcaptain)
