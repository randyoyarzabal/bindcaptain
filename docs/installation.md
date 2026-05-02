# Installation Guide

Complete installation and configuration guide for BindCaptain.

## Installation Methods

### Method 1: Automated Setup (Recommended)

For supported distributions (RHEL, CentOS, Rocky, AlmaLinux, Fedora):

```bash
# 1. Clone repository
git clone https://github.com/yourusername/bindcaptain.git
cd bindcaptain

# 2. Run automated setup
sudo ./tools/system-setup.sh

# 3. Configure DNS zones
sudo ./tools/config-setup.sh wizard

# 4. Build and start container
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run
```

### Method 2: Manual Setup

For unsupported distributions or custom installations:

See [Manual Setup Guide](manual-setup.md) for detailed instructions.

## Detailed Installation Steps

### Step 1: System Preparation

#### Automated (Supported Distributions)

```bash
sudo ./tools/system-setup.sh
```

The script will:
- ✅ Detect your Linux distribution
- ✅ Install Podman and BIND packages
- ✅ Configure firewall rules
- ✅ Set up SELinux policies
- ✅ Install BindCaptain system-wide
- ✅ Create systemd service

#### Manual (Unsupported Distributions)

```bash
# Install Podman
sudo apt install podman  # Ubuntu/Debian
sudo pacman -S podman    # Arch Linux

# Install BIND
sudo apt install bind9 bind9utils  # Ubuntu/Debian
sudo pacman -S bind                 # Arch Linux

# Configure firewall
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Install BindCaptain
sudo cp -r . /opt/bindcaptain
sudo chmod +x /opt/bindcaptain/tools/*.sh
```

### Step 2: DNS Configuration

#### Interactive Configuration

```bash
sudo ./tools/config-setup.sh wizard
```

Follow the prompts to:
- ✅ Set your domain name
- ✅ Configure IP addresses
- ✅ Set up reverse DNS zones
- ✅ Choose BIND settings
- ✅ Generate zone files

#### Manual Configuration

```bash
# Copy example configuration
sudo cp config-examples/named.conf.template /opt/bindcaptain/config/named.conf

# Edit configuration
sudo nano /opt/bindcaptain/config/named.conf

# Create zone files
sudo ./tools/config-setup.sh create-zone example.com
```

### Step 3: Container Setup

#### Build Container Image

```bash
sudo ./bindcaptain.sh build
```

This creates a container image with:
- Rocky Linux 9 base
- BIND 9.16+ DNS server
- BindCaptain management tools
- Security hardening

#### Start DNS Service

```bash
sudo ./bindcaptain.sh run
```

The container will:
- ✅ Start BIND DNS server
- ✅ Mount configuration files
- ✅ Bind to port 53
- ✅ Enable auto-restart

### Step 4: Verification

#### Check Container Status

```bash
sudo ./bindcaptain.sh status
```

Expected output:
```
Container Status: Running
BIND Status: Active
Port 53: Listening
Configuration: Valid
```

#### Test DNS Resolution

```bash
# Test forward lookup
dig @localhost example.com

# Test reverse lookup
dig @localhost -x 192.168.1.100

# Test with nslookup
nslookup example.com localhost
```

#### Check Logs

```bash
# Container logs
sudo podman logs bindcaptain

# BIND logs
sudo tail -f /opt/bindcaptain/logs/named.log
```

## Configuration Options

### Environment Variables

```bash
# Timezone
export TZ="America/New_York"

# BIND debug level
export BIND_DEBUG_LEVEL="3"

# Container restart policy
export RESTART_POLICY="unless-stopped"
```

### Configuration Files

#### Main Configuration

```bash
# BIND main configuration
/opt/bindcaptain/config/named.conf

# Zone files directory
/opt/bindcaptain/zones/

# Log files directory
/opt/bindcaptain/logs/
```

#### Systemd Service

```bash
# Service file
/etc/systemd/system/bindcaptain.service

# Enable auto-start
sudo systemctl enable bindcaptain
```

## Post-Installation Setup

### DNS Management

Load management functions:

```bash
source ./tools/bindcaptain_manager.sh
```

Create your first DNS record:

```bash
bc.create_record webserver example.com 192.168.1.100
```

### Monitoring Setup

#### Enable Logging

```bash
# Configure BIND logging
sudo nano /opt/bindcaptain/config/named.conf
```

Add logging configuration:
```bind
logging {
    channel default_log {
        file "/var/log/named/named.log" versions 3 size 5m;
        severity info;
    };
    category default { default_log; };
};
```

#### Health Checks

```bash
# Check BIND status
sudo ./bindcaptain.sh status

# Validate configuration
sudo ./bindcaptain.sh validate

# Test DNS resolution (after container is running)
./tools/bindcaptain_manager.sh help
dig @localhost example.com
```

## Troubleshooting Installation

### Common Issues

#### Container Won't Start

```bash
# Check Podman status
sudo systemctl status podman

# Check container logs
sudo podman logs bindcaptain

# Check port conflicts
sudo netstat -tlnp | grep :53
```

#### Permission Denied

```bash
# Fix ownership
sudo chown -R root:root /opt/bindcaptain
sudo chmod +x /opt/bindcaptain/tools/*.sh

# Check SELinux
sudo setsebool -P container_manage_cgroup on
```

#### DNS Not Resolving

```bash
# Check BIND status
sudo ./bindcaptain.sh status

# Validate configuration
sudo named-checkconf /opt/bindcaptain/config/named.conf

# Check zone files
sudo named-checkzone example.com /opt/bindcaptain/zones/example.com.db
```

### Log Locations

```bash
# Container logs
sudo podman logs bindcaptain

# BIND logs
sudo tail -f /opt/bindcaptain/logs/named.log

# System logs
sudo journalctl -u bindcaptain
```

## Uninstallation

### Remove BindCaptain

```bash
# Stop and remove container
sudo ./bindcaptain.sh stop
sudo podman rm bindcaptain

# Remove container image
sudo podman rmi bindcaptain:latest

# Remove systemd service
sudo systemctl disable bindcaptain
sudo rm /etc/systemd/system/bindcaptain.service

# Remove configuration
sudo rm -rf /opt/bindcaptain
```

### Clean Up System

```bash
# Remove firewall rules
sudo firewall-cmd --remove-service=dns --permanent
sudo firewall-cmd --reload

# Remove SELinux policies
sudo setsebool -P container_manage_cgroup off
```

## Next Steps

After successful installation:

1. **[DNS Operations](dns-operations.md)** - Learn to manage DNS records
2. **[Configuration Management](configuration.md)** - Customize your setup
3. **[Security](security.md)** - Harden your DNS server
4. **[Monitoring](monitoring.md)** - Set up logging and alerts

---

**Need help?** Check the [Troubleshooting Guide](troubleshooting.md) or [Manual Setup](manual-setup.md) for unsupported distributions.
