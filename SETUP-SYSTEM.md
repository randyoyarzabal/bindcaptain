# ⚓ BindCaptain System Setup Guide

**Complete guide for preparing a fresh Linux system to run BindCaptain DNS containers**

> **🐳 CONTAINERIZED APPROACH:** This guide is specifically for setting up **containerized DNS infrastructure** using BindCaptain and Podman. This is **NOT** for traditional native BIND package installation.

This guide walks you through setting up a clean Linux system (Rocky Linux 9, AlmaLinux 9, CentOS Stream 9) to run **containerized** BindCaptain DNS infrastructure using Podman.

---

## 🎯 Target Systems & Approach

### **📦 Container vs. Native BIND:**

| Approach | Use Case | This Guide |
|----------|----------|------------|
| **🐳 Containerized (BindCaptain)** | Modern, portable, isolated DNS infrastructure | ✅ **This Guide** |
| **📦 Native BIND packages** | Traditional system-level BIND installation | ❌ Not covered |

> **This guide is for containerized BindCaptain only.** For native BIND installation, use your distribution's package manager and follow traditional BIND documentation.

### **Tested Container-Ready Distributions:**
- ✅ **Rocky Linux 9** (Recommended)
- ✅ **AlmaLinux 9**
- ✅ **CentOS Stream 9**
- ✅ **RHEL 9** (with subscription)

### **Prerequisites:**
- **✅ Rocky Linux 9** system already installed and running
- **✅ Network configured** (static IP, hostname, basic connectivity)
- **✅ SSH access** and sudo privileges
- **❌ Container Runtime:** Will be installed by this guide

---

## 🚀 Quick Start Commands

### **🐳 For Containerized BindCaptain (This Guide):**
```bash
# For Rocky Linux 9 - prepares system for DNS containers
curl -fsSL https://raw.githubusercontent.com/randyoyarzabal/bindcaptain/main/scripts/setup-rocky9.sh | bash
```

### **📦 For Native BIND Installation (Alternative):**
```bash
# Traditional approach - NOT covered by this guide
sudo dnf install -y bind bind-utils
sudo systemctl enable --now named
# Follow traditional BIND documentation
```

> **Choose your approach:** This guide focuses on the **containerized method** which provides better isolation, portability, and modern DevOps practices.

*Follow the detailed manual steps below for better understanding and customization of the containerized approach.*

---

## 📋 Container Setup Steps

### **1. System Preparation**

#### **Install Container Prerequisites:**
```bash
# Update packages
sudo dnf update -y

# Install only what's needed for container DNS operations
sudo dnf install -y \
    git \
    bind-utils
```

> **Why these packages?**
> - **git:** Clone BindCaptain repository
> - **bind-utils:** Test DNS from host (dig, nslookup)
> - **Everything else:** Already in the container or pre-configured on running system

### **2. Firewall Configuration for DNS**

#### **Configure FirewallD for DNS Container:**
```bash
# Ensure firewalld is running (should already be on Rocky 9)
sudo systemctl enable --now firewalld

# Allow DNS services (port 53 TCP/UDP)
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload

# Verify DNS service is allowed
sudo firewall-cmd --list-services | grep dns
```

> **Note:** We only configure DNS ports. SSH and other services should already be configured on your running system.

### **3. Container Runtime Installation**

#### **Install Podman:**
```bash
# Install podman and related tools for DNS container operations
sudo dnf install -y \
    podman \
    podman-compose \
    buildah \
    skopeo \
    containers-common \
    fuse-overlayfs \
    slirp4netns

# Verify podman installation
podman --version
podman info
```

#### **Configure Podman for DNS Container (Root Operation):**

Since DNS services need to bind to port 53 (privileged port), we'll configure Podman for root container operation:

```bash
# Enable podman socket for systemd integration
sudo systemctl enable --now podman.socket

# Create optimized containers.conf for DNS operations
sudo mkdir -p /etc/containers
sudo tee /etc/containers/containers.conf << 'EOF'
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

[network]
default_network = "podman"

[engine]
cgroup_manager = "systemd"
events_logger = "journald"
runtime = "crun"
EOF

# Configure storage for root podman
sudo tee /etc/containers/storage.conf << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options.overlay]
mountopt = "nodev,metacopy=on"
EOF

# Allow binding to privileged ports
echo 'net.ipv4.ip_unprivileged_port_start=53' | sudo tee /etc/sysctl.d/podman-dns.conf
sudo sysctl -p /etc/sysctl.d/podman-dns.conf

# Test privileged port binding
sudo podman run --rm --privileged -p 53:53/udp alpine:latest echo "DNS port test successful"
```

### **4. DNS Service Preparation**

#### **Disable Conflicting DNS Services:**
```bash
# Check for systemd-resolved conflicts
systemctl status systemd-resolved

# If active, disable it to avoid port 53 conflicts
sudo systemctl disable --now systemd-resolved

# Check for existing BIND installation
systemctl status named 2>/dev/null && sudo systemctl stop named || true
```

### **5. Container Security Configuration**

#### **SELinux Configuration:**
```bash
# Check SELinux status
sestatus

# Configure SELinux for DNS container operations
sudo setsebool -P container_manage_cgroup on
sudo setsebool -P virt_use_nfs on
sudo setsebool -P nis_enabled on
sudo setsebool -P container_connect_any on
sudo setsebool -P domain_can_mmap_files on

# Install SELinux management tools (if not present)
sudo dnf install -y policycoreutils-python-utils

# Allow containers to bind to DNS ports (53)
sudo semanage port -a -t container_port_t -p tcp 53 || true
sudo semanage port -a -t container_port_t -p udp 53 || true

# Verify SELinux configuration
getsebool -a | grep container
semanage port -l | grep 53
```

### **6. BindCaptain Installation**

#### **Clone BindCaptain Repository:**
```bash
# Clone to your preferred location
cd /opt
sudo git clone https://github.com/randyoyarzabal/bindcaptain.git
sudo chown -R $USER:$USER bindcaptain

# Make scripts executable
cd bindcaptain
chmod +x *.sh tests/*.sh

# Verify installation
./bindcaptain.sh --help
```

#### **Initial Configuration Setup:**
```bash
# Run the setup wizard
sudo ./setup.sh wizard

# Or manual setup
sudo ./setup.sh setup

# Test container build
sudo ./bindcaptain.sh build
```

### **7. Testing and Validation**

#### **Container System Check:**
```bash
# Verify container readiness
echo "=== Container System Check ==="

# Check podman installation
echo "Podman Version:"
podman --version

# Test container functionality
echo -e "\nTesting container functionality:"
sudo podman run --rm hello-world

# Check DNS port availability
echo -e "\nChecking port 53 availability:"
sudo ss -tlnp | grep :53 || echo "Port 53 available"

# Check firewall
echo -e "\nFirewall Status:"
sudo firewall-cmd --list-services | grep dns

# Test privileged port binding
echo -e "\nTesting DNS port binding:"
sudo podman run --rm --privileged -p 53:53/udp alpine:latest echo "Port 53 test OK"
```

#### **BindCaptain Test:**
```bash
# Test BindCaptain build
cd /opt/bindcaptain
sudo ./tests/run-tests.sh

# Build container
sudo ./bindcaptain.sh build

# Test run (dry run)
sudo ./bindcaptain.sh validate
```

---

## 🔧 Troubleshooting

### **Common Issues:**

#### **Port 53 Permission Denied:**
```bash
# Check if another DNS service is running
sudo ss -tlnp | grep :53
sudo systemctl status systemd-resolved
sudo systemctl status named

# Stop conflicting services
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

#### **Container Build Failures:**
```bash
# Check available space
df -h

# Clear podman cache
podman system prune -a

# Check SELinux logs
sudo ausearch -m avc -ts recent
```

#### **Network Connectivity Issues:**
```bash
# Check routing
ip route show

# Test external connectivity
ping -c 3 8.8.8.8

# Check firewall rules
sudo firewall-cmd --list-all-zones
```

#### **DNS Resolution Problems:**
```bash
# Check system DNS
cat /etc/resolv.conf

# Test DNS queries
dig @8.8.8.8 google.com
nslookup google.com 1.1.1.1

# Check systemd-resolved conflicts
systemctl status systemd-resolved
```

---

## 📋 Production Checklist

### **Container-Ready Verification:**

- [ ] **Podman installed** and tested
- [ ] **Port 53 available** (no conflicts)
- [ ] **Firewall configured** for DNS services
- [ ] **SELinux configured** for containers
- [ ] **BindCaptain cloned** and built
- [ ] **Container build** successful
- [ ] **Container run test** completed
- [ ] **DNS port binding** confirmed

---

## 🎯 Next Steps

After completing this system setup:

1. **Configure DNS Zones**: Follow the main [README.md](README.md) for BindCaptain configuration
2. **Deploy Containers**: Use `./bindcaptain.sh run` to start DNS services
3. **Monitor System**: Set up monitoring and alerting
4. **Plan Backups**: Implement configuration and data backup procedures
5. **Document Changes**: Keep records of customizations for your environment

---

## 🆘 Support

### **System-Level Support:**
- **Rocky Linux**: https://docs.rockylinux.org/
- **Podman**: https://docs.podman.io/
- **FirewallD**: https://firewalld.org/documentation/

### **BindCaptain Support:**
- **GitHub Issues**: https://github.com/randyoyarzabal/bindcaptain/issues
- **Documentation**: [README.md](README.md)
- **Testing**: [tests/run-tests.sh](tests/run-tests.sh)

---

*⚓ This system is now ready to set sail with BindCaptain DNS infrastructure!*
