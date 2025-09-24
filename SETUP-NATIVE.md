# 📦 Native BIND Setup Guide for Rocky Linux 9

**Traditional system-level BIND installation (alternative to containerized BindCaptain)**

> **📦 NATIVE APPROACH:** This guide covers traditional **native BIND package installation** directly on the host system. This is **NOT** for containerized BindCaptain.

If you prefer the traditional approach of installing BIND directly on your Rocky Linux 9 system, follow this guide instead of the containerized BindCaptain setup.

---

## 🎯 When to Choose Native BIND

### **✅ Native BIND is good for:**
- **Traditional environments** with existing BIND expertise
- **Simple single-server** DNS setups
- **Integration** with existing system management tools
- **Direct file system access** for zone files
- **Lower resource overhead** (no container layer)

### **❌ Native BIND limitations:**
- **System dependency** - tied to host OS
- **Harder migration** between systems
- **Manual dependency management**
- **Less isolation** from host system
- **Traditional backup/restore** procedures

---

## 🚀 Rocky Linux 9 Native BIND Installation

### **1. Install BIND Packages**

```bash
# Install BIND and utilities
sudo dnf install -y \
    bind \
    bind-utils \
    bind-chroot

# Verify installation
named -v
dig -v
```

### **2. Configure BIND Service**

```bash
# Enable and start BIND service
sudo systemctl enable named
sudo systemctl start named

# Check service status
sudo systemctl status named

# Verify BIND is listening on port 53
sudo ss -tlnp | grep :53
```

### **3. Configure Firewall**

```bash
# Allow DNS service through firewall
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload

# Verify firewall rules
sudo firewall-cmd --list-services
```

### **4. Basic Configuration**

```bash
# Edit main configuration file
sudo nano /etc/named.conf

# Test configuration syntax
sudo named-checkconf

# Reload configuration
sudo systemctl reload named
```

### **5. Zone File Management**

```bash
# Zone files location
ls -la /var/named/

# Create a zone file
sudo nano /var/named/example.com.db

# Check zone file syntax
sudo named-checkzone example.com /var/named/example.com.db

# Reload zones
sudo rndc reload
```

---

## 🔧 Comparison: Native vs Containerized

| Feature | Native BIND | Containerized BindCaptain |
|---------|-------------|---------------------------|
| **Installation** | `dnf install bind` | Podman container |
| **Configuration** | `/etc/named.conf` | Mounted config directory |
| **Zone Files** | `/var/named/` | Mounted volume |
| **Service Management** | `systemctl` | `podman run` |
| **Updates** | `dnf update bind` | `podman pull` new image |
| **Backup** | File system copy | Container volume backup |
| **Migration** | Manual config transfer | Container image + volumes |
| **Isolation** | Host system | Container sandbox |
| **Dependencies** | System packages | Container includes all |
| **Resource Usage** | Lower overhead | Container overhead |
| **Portability** | OS-specific | Runs anywhere |

---

## 📋 Migration Path

### **From Native to Containerized:**

```bash
# 1. Backup existing configuration
sudo cp -r /etc/named.conf /backup/
sudo cp -r /var/named/ /backup/

# 2. Stop native BIND
sudo systemctl stop named
sudo systemctl disable named

# 3. Install BindCaptain
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# 4. Import configuration
cp /backup/named.conf config/
cp /backup/named/* config/example.com/  # Adjust as needed

# 5. Deploy container
sudo ./bindcaptain.sh run
```

### **From Containerized to Native:**

```bash
# 1. Export configuration from container
sudo podman cp bindcaptain:/etc/named.conf /backup/
sudo podman cp bindcaptain:/var/named/ /backup/

# 2. Stop container
sudo ./bindcaptain.sh stop

# 3. Install native BIND
sudo dnf install -y bind bind-utils

# 4. Import configuration
sudo cp /backup/named.conf /etc/
sudo cp -r /backup/named/* /var/named/

# 5. Start native service
sudo systemctl enable --now named
```

---

## 🆘 When to Contact Support

### **Native BIND Support:**
- **Rocky Linux Documentation**: https://docs.rockylinux.org/
- **BIND Documentation**: https://bind9.readthedocs.io/
- **Red Hat Customer Portal**: (if using RHEL)

### **BindCaptain Support:**
- **GitHub Issues**: https://github.com/randyoyarzabal/bindcaptain/issues
- **Container Documentation**: [SETUP-SYSTEM.md](SETUP-SYSTEM.md)

---

## 💡 Recommendation

For **new deployments**, we recommend the **containerized BindCaptain approach** because:

- ✅ **Modern DevOps practices** (Infrastructure as Code)
- ✅ **Easier migration** between systems
- ✅ **Better isolation** and security
- ✅ **Consistent environment** across dev/staging/prod
- ✅ **Automated deployment** and scaling
- ✅ **Version control** for entire DNS infrastructure

Choose **native BIND** only if you have specific requirements that mandate traditional system-level installation.

---

*📦 This covers traditional BIND installation. For the recommended containerized approach, see [SETUP-SYSTEM.md](SETUP-SYSTEM.md)*
