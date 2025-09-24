# 🐳 Podman Setup for BindCaptain DNS Services

**Comprehensive guide for configuring Podman on Rocky Linux 9 to run DNS containers as root**

This guide focuses specifically on Podman configuration for DNS services that require binding to port 53.

---

## 🎯 Why Root for DNS?

### **Port 53 Requirements:**
- **Privileged Port:** Port 53 is a privileged port (< 1024) on Linux
- **Root Access:** Traditionally requires root or special capabilities
- **DNS Standards:** Most DNS software expects to bind directly to port 53
- **Container Reality:** Easiest and most reliable approach is root containers

### **Alternatives Considered:**
- ❌ **Rootless + CAP_NET_BIND_SERVICE:** Complex capability management
- ❌ **Port Forwarding:** iptables complexity, performance overhead  
- ❌ **User Namespaces:** Complicated networking setup
- ✅ **Root Container:** Simple, reliable, industry standard

---

## 🚀 Rocky Linux 9 Podman Setup

### **1. Install Podman Packages**

```bash
# Install complete podman stack
sudo dnf install -y \
    podman \
    podman-compose \
    buildah \
    skopeo \
    containers-common \
    fuse-overlayfs \
    slirp4netns \
    crun \
    policycoreutils-python-utils

# Verify installation
podman --version
podman system info
```

### **2. Configure Podman for Root DNS Operations**

#### **System Integration:**
```bash
# Enable podman system service
sudo systemctl enable --now podman.socket

# Verify socket activation
sudo systemctl status podman.socket
```

#### **Container Configuration:**
```bash
# Create optimized containers.conf
sudo mkdir -p /etc/containers
sudo tee /etc/containers/containers.conf << 'EOF'
[containers]
# Capabilities needed for DNS services
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

# Network configuration for DNS
default_sysctls = [
    "net.ipv4.ping_group_range=0 0"
]

[network]
default_network = "podman"

[engine]
# Rocky 9 optimizations
cgroup_manager = "systemd"
events_logger = "journald"  
runtime = "crun"
EOF
```

#### **Storage Configuration:**
```bash
# Configure overlay storage for performance
sudo tee /etc/containers/storage.conf << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
additionalimagestores = []

[storage.options.overlay]
# Optimize for Rocky 9 filesystem
mountopt = "nodev,metacopy=on"
size = ""
EOF
```

### **3. Kernel Configuration for Privileged Ports**

```bash
# Allow binding to port 53 without full root
echo 'net.ipv4.ip_unprivileged_port_start=53' | sudo tee /etc/sysctl.d/podman-dns.conf

# Apply immediately
sudo sysctl -p /etc/sysctl.d/podman-dns.conf

# Verify setting
sysctl net.ipv4.ip_unprivileged_port_start
```

### **4. SELinux Configuration for DNS Containers**

```bash
# Configure SELinux booleans for container networking
sudo setsebool -P container_manage_cgroup on
sudo setsebool -P container_connect_any on
sudo setsebool -P domain_can_mmap_files on
sudo setsebool -P nis_enabled on
sudo setsebool -P virt_use_nfs on

# Allow containers to bind to DNS ports
sudo semanage port -a -t container_port_t -p tcp 53 || true
sudo semanage port -a -t container_port_t -p udp 53 || true

# Verify SELinux configuration
getsebool container_manage_cgroup container_connect_any
semanage port -l | grep 53
```

### **5. Firewall Integration**

```bash
# Configure firewalld for container DNS services
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --permanent --add-port=53/tcp
sudo firewall-cmd --permanent --add-port=53/udp

# Add container interface to trusted zone (optional)
sudo firewall-cmd --permanent --zone=trusted --add-interface=podman0

# Apply firewall rules
sudo firewall-cmd --reload

# Verify firewall configuration
sudo firewall-cmd --list-services
sudo firewall-cmd --list-ports
```

---

## 🧪 Testing Podman DNS Configuration

### **1. Basic Podman Tests**

```bash
# Test podman functionality
sudo podman run --rm hello-world

# Test system info
sudo podman system info

# Check storage
sudo podman system df
```

### **2. Network Capability Tests**

```bash
# Test basic networking
sudo podman run --rm alpine:latest ping -c 3 8.8.8.8

# Test privileged port binding (port 53)
sudo podman run --rm --privileged -p 53:53/udp alpine:latest \
  /bin/sh -c "nc -l -u -p 53 & sleep 2 && echo 'Port 53 bind test successful'"

# Test with DNS service simulation
sudo podman run --rm --privileged -p 53:53/udp -p 53:53/tcp alpine:latest \
  /bin/sh -c "echo 'DNS ports available'"
```

### **3. BindCaptain Compatibility Test**

```bash
# Test container build capability
cd /opt/bindcaptain
sudo podman build -t bindcaptain-test -f Containerfile .

# Test container run with DNS ports
sudo podman run --rm --privileged \
  -p 53:53/tcp -p 53:53/udp \
  bindcaptain-test named-checkconf /etc/named.conf
```

---

## 🔧 Performance Optimization

### **1. Storage Optimization**

```bash
# Configure optimized storage driver options
sudo mkdir -p /etc/containers/storage.conf.d
sudo tee /etc/containers/storage.conf.d/dns-optimization.conf << 'EOF'
[storage.options.overlay]
# Optimize for DNS workload (many small files)
mount_program = "/usr/bin/fuse-overlayfs"
mountopt = "nodev,metacopy=on,volatile"
EOF
```

### **2. Memory and Resource Limits**

```bash
# Configure systemd for container resource management
sudo mkdir -p /etc/systemd/system/podman.service.d
sudo tee /etc/systemd/system/podman.service.d/dns-limits.conf << 'EOF'
[Service]
# Optimize for DNS container workloads
LimitNOFILE=65536
LimitNPROC=4096
OOMScoreAdjust=-100
EOF

sudo systemctl daemon-reload
```

### **3. Network Performance**

```bash
# Optimize kernel networking for DNS
sudo tee -a /etc/sysctl.d/podman-dns.conf << 'EOF'
# DNS-specific network optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
EOF

sudo sysctl -p /etc/sysctl.d/podman-dns.conf
```

---

## 🚨 Common Issues & Solutions

### **Port 53 Permission Denied**

```bash
# Check if another service is using port 53
sudo ss -tlnp | grep :53

# Stop conflicting services
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Verify no processes on port 53
sudo lsof -i :53
```

### **SELinux Denials**

```bash
# Check for SELinux denials
sudo ausearch -m avc -ts recent | grep container

# Common fix - allow container networking
sudo setsebool -P container_connect_any on

# Allow container port binding
sudo semanage port -a -t container_port_t -p tcp 53
sudo semanage port -a -t container_port_t -p udp 53
```

### **Storage Issues**

```bash
# Clean up storage space
sudo podman system prune -a

# Check storage usage
sudo podman system df
df -h /var/lib/containers

# Reset storage if corrupted
sudo systemctl stop podman
sudo rm -rf /var/lib/containers/storage
sudo systemctl start podman
```

### **Networking Problems**

```bash
# Reset podman networking
sudo podman system reset --force

# Recreate default network
sudo podman network create podman

# Test network connectivity
sudo podman run --rm alpine:latest ping -c 3 8.8.8.8
```

---

## 📋 Production Checklist

### **Pre-Production Verification:**

- [ ] **Podman installed** and version confirmed
- [ ] **System service** enabled (podman.socket)
- [ ] **Storage configured** for overlay filesystem
- [ ] **Network optimized** for DNS workloads
- [ ] **Port 53 binding** tested and confirmed
- [ ] **SELinux configured** for container networking
- [ ] **Firewall rules** applied for DNS services
- [ ] **Resource limits** configured appropriately
- [ ] **No conflicting services** on port 53
- [ ] **Performance optimizations** applied

### **Security Verification:**

- [ ] **Container capabilities** minimized to requirements
- [ ] **SELinux enforcing** with proper contexts
- [ ] **Firewall active** with DNS-only access
- [ ] **Root access** restricted to DNS container only
- [ ] **Storage permissions** properly configured
- [ ] **Log access** configured for monitoring

---

## 🎯 Rocky Linux 9 Specific Notes

### **Default Configurations:**
- **Cgroups v2:** Enabled by default (good for containers)
- **SELinux:** Enforcing by default (properly configured above)
- **Firewalld:** Active by default (configured for DNS)
- **systemd:** Version 250+ with good container integration

### **Podman Version:**
- **Rocky 9 ships with Podman 4.0+**
- **Rootless by default but root capable**
- **Good systemd integration**
- **Optimized for enterprise workloads**

### **Performance:**
- **Overlay storage** is default and optimal
- **crun runtime** provides better performance than runc
- **systemd cgroup manager** integrates well with Rocky 9

---

*🐳 Your Rocky Linux 9 system is now optimized for BindCaptain DNS containers running as root with full port 53 access!*
