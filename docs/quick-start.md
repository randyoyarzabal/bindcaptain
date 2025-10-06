# Quick Start Guide

Get BindCaptain up and running in minutes with this step-by-step guide.

## Prerequisites

- **Supported Linux distribution** (RHEL, CentOS, Rocky, AlmaLinux, Fedora)
- **Root access** for system setup
- **Network connectivity** for DNS resolution

## Step 1: Clone BindCaptain

```bash
git clone https://github.com/yourusername/bindcaptain.git
cd bindcaptain
```

## Step 2: System Setup

Run the automated system setup script:

```bash
sudo ./tools/system-setup.sh
```

This script will:
- ✅ Detect your Linux distribution
- ✅ Install Podman and required packages
- ✅ Configure firewall and SELinux
- ✅ Install BindCaptain system-wide
- ✅ Set up systemd service

## Step 3: Configure DNS Zones

Set up your DNS configuration:

```bash
sudo ./tools/config-setup.sh wizard
```

Follow the interactive wizard to:
- ✅ Create your domain zone
- ✅ Set up reverse DNS zones
- ✅ Configure BIND settings
- ✅ Generate zone files

## Step 4: Build and Run Container

Build the BindCaptain container:

```bash
sudo ./bindcaptain.sh build
```

Start the DNS service:

```bash
sudo ./bindcaptain.sh run
```

## Step 5: Verify Installation

Check that everything is running:

```bash
# Check container status
sudo ./bindcaptain.sh status

# Test DNS resolution
dig @localhost example.com
nslookup example.com localhost
```

## Step 6: Manage DNS Records

Load the management functions:

```bash
source ./tools/bindcaptain_manager.sh
```

Create your first DNS record:

```bash
bind.create_record webserver example.com 192.168.1.100
```

## Next Steps

- **[DNS Operations](dns-operations.md)** - Learn advanced DNS management
- **[Configuration Management](configuration.md)** - Customize your setup
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions

## Quick Commands Reference

```bash
# Container management
sudo ./bindcaptain.sh build    # Build container
sudo ./bindcaptain.sh run      # Start service
sudo ./bindcaptain.sh stop     # Stop service
sudo ./bindcaptain.sh status   # Check status

# DNS management
source ./tools/bindcaptain_manager.sh
bind.create_record host domain.com 192.168.1.100
bind.list_records domain.com
bind.delete_record host domain.com
```

## Troubleshooting

### Container won't start
```bash
# Check logs
sudo podman logs bindcaptain

# Check configuration
sudo ./bindcaptain.sh validate
```

### DNS not resolving
```bash
# Check BIND status
sudo ./bindcaptain.sh status

# Test configuration
sudo named-checkconf /path/to/your/named.conf
```

### Permission issues
```bash
# Ensure proper ownership
sudo chown -R root:root /opt/bindcaptain
sudo chmod +x /opt/bindcaptain/tools/*.sh
```

---

**Need help?** Check the [Troubleshooting Guide](troubleshooting.md) or [Manual Setup](manual-setup.md) for unsupported distributions.
