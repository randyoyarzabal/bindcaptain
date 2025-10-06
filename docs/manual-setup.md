# Manual System Setup

This guide covers manual system setup for distributions not supported by the automated `system-setup.sh` script.

## Supported vs Unsupported Distributions

### Automated Setup (system-setup.sh)
- RHEL 8+
- CentOS 8+ (CentOS Stream)
- Rocky Linux 8+
- AlmaLinux 8+
- Fedora 30+

### Manual Setup Required
- Ubuntu/Debian
- Arch Linux
- openSUSE
- Other distributions

## Manual Setup Instructions

### 1. Install Container Runtime

#### Ubuntu/Debian
```bash
# Update package list
sudo apt update

# Install Podman and related tools
sudo apt install -y \
    podman \
    podman-compose \
    buildah \
    skopeo \
    containers-common

# Enable Podman socket
sudo systemctl enable --now podman.socket
```

#### Arch Linux
```bash
# Install Podman and related tools
sudo pacman -S \
    podman \
    podman-compose \
    buildah \
    skopeo

# Enable Podman socket
sudo systemctl enable --now podman.socket
```

#### openSUSE
```bash
# Install Podman and related tools
sudo zypper install -y \
    podman \
    podman-compose \
    buildah \
    skopeo

# Enable Podman socket
sudo systemctl enable --now podman.socket
```

### 2. Install Required Tools

#### All Distributions
```bash
# Install Git (for cloning repository)
# Ubuntu/Debian:
sudo apt install -y git bind-utils

# Arch Linux:
sudo pacman -S git bind

# openSUSE:
sudo zypper install -y git bind-utils
```

### 3. Configure Podman for Root Operations

Since BindCaptain needs to bind to port 53 (privileged port), configure Podman for root operations:

```bash
# Create containers configuration directory
sudo mkdir -p /etc/containers

# Create containers.conf for DNS operations
sudo tee /etc/containers/containers.conf > /dev/null << 'EOF'
[containers]
# DNS containers need network access and port binding
default_capabilities = [
    "CHOWN",
    "DAC_OVERRIDE", 
    "FOWNER",
    "FSETID",
    "KILL",
    "NET_BIND_SERVICE",
    "SETFCAP",
    "SETGID",
    "SETPCAP",
    "SETUID",
    "SYS_CHROOT"
]

# Allow binding to privileged ports (like 53)
default_sysctls = [
    "net.ipv4.ping_group_range=0 0"
]

[network]
# Configure networking for DNS services
default_network = "podman"

[engine]
# Optimize for system containers
cgroup_manager = "systemd"
events_logger = "journald"
runtime = "crun"
EOF

# Create storage configuration
sudo tee /etc/containers/storage.conf > /dev/null << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
additionalimagestores = []

[storage.options.overlay]
mountopt = "nodev,metacopy=on"
EOF
```

### 4. Configure Firewall

#### Ubuntu/Debian (ufw)
```bash
# Allow DNS services
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Allow SSH (if not already allowed)
sudo ufw allow ssh

# Enable firewall
sudo ufw --force enable
```

#### Arch Linux (iptables)
```bash
# Allow DNS services
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT

# Save rules (method varies by distribution)
sudo iptables-save > /etc/iptables/iptables.rules
```

#### openSUSE (firewalld)
```bash
# Allow DNS services
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --permanent --add-port=53/tcp
sudo firewall-cmd --permanent --add-port=53/udp

# Apply rules
sudo firewall-cmd --reload
```

### 5. Disable Conflicting Services

```bash
# Stop and disable systemd-resolved (if present)
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Stop any existing BIND/named services
sudo systemctl stop named 2>/dev/null || true
sudo systemctl disable named 2>/dev/null || true

# Stop any other DNS services that might conflict
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true
```

### 6. Test Podman Installation

```bash
# Test Podman installation
podman --version
podman info

# Test privileged port binding (optional)
sudo podman run --rm --privileged -p 53:53/udp alpine:latest /bin/sh -c "echo 'Port 53 test successful'"
```

### 7. Clone and Configure BindCaptain

```bash
# Clone BindCaptain repository
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# Make scripts executable
chmod +x *.sh tools/*.sh tests/*.sh

# Configure DNS zones
sudo ./tools/config-setup.sh wizard
```

### 8. Build and Run BindCaptain

```bash
# Build container image
sudo ./bindcaptain.sh build

# Run BindCaptain
sudo ./bindcaptain.sh run

# Check status
sudo ./bindcaptain.sh status
```

## Troubleshooting

### Port 53 Already in Use
```bash
# Check what's using port 53
sudo netstat -tulpn | grep :53
sudo lsof -i :53

# Stop conflicting services
sudo systemctl stop systemd-resolved
sudo systemctl stop named
```

### Podman Permission Issues
```bash
# Ensure Podman socket is running
sudo systemctl status podman.socket

# Restart Podman socket if needed
sudo systemctl restart podman.socket
```

### Firewall Issues
```bash
# Check firewall status
sudo ufw status          # Ubuntu/Debian
sudo firewall-cmd --list-all  # openSUSE/RHEL-based

# Test DNS connectivity
dig @localhost google.com
```

### Container Build Issues
```bash
# Check Podman logs
sudo journalctl -u podman -f

# Test with a simple container
sudo podman run --rm hello-world
```

## Next Steps

After completing manual setup:

1. **Configure DNS zones**: `sudo ./tools/config-setup.sh wizard`
2. **Build container**: `sudo ./bindcaptain.sh build`
3. **Run BindCaptain**: `sudo ./bindcaptain.sh run`
4. **Test DNS**: `dig @localhost yourdomain.com`
5. **Manage records**: Use `bindcaptain_manager.sh` for DNS record management

## Support

If you encounter issues with manual setup:

1. Check the [Troubleshooting Guide](troubleshooting.md)
2. Review Podman documentation for your distribution
3. Ensure all prerequisites are properly installed
4. Verify firewall and network configuration

For supported distributions, consider using the automated `system-setup.sh` script instead.
