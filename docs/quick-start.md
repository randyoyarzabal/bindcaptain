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

Load the Chief plugin (works locally on the DNS host with `BC_HOST` unset, and remotely from a workstation when `BC_HOST` is set):

```bash
source ./chief-plugin/bc_chief-plugin.sh
# or, when installed: source /opt/bindcaptain/chief-plugin/bc_chief-plugin.sh
```

Create your first DNS record:

```bash
bc.create webserver.example.com 192.168.1.100
```

> See [DNS Operations](dns-operations.md) for the full command reference, including the in-container manager primitives (`bc.create_record`, etc.) for direct host-local use.

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

# DNS management — Chief plugin (recommended; works local + remote)
source ./chief-plugin/bc_chief-plugin.sh
bc.create host.domain.com 192.168.1.100
bc.list   domain.com
bc.delete host.domain.com
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
