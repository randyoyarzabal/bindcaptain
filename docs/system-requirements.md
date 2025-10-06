# System Requirements

BindCaptain system requirements and compatibility information.

## Supported Distributions

### Fully Supported (Automated Setup)

| Distribution | Version | Package Manager | Status |
|-------------|---------|----------------|--------|
| **RHEL** | 8.x, 9.x | dnf/yum | ✅ Full |
| **CentOS** | 8.x, 9.x | dnf/yum | ✅ Full |
| **Rocky Linux** | 8.x, 9.x | dnf/yum | ✅ Full |
| **AlmaLinux** | 8.x, 9.x | dnf/yum | ✅ Full |
| **Fedora** | 35+ | dnf | ✅ Full |

### Manual Setup Required

| Distribution | Version | Package Manager | Status |
|-------------|---------|----------------|--------|
| **Ubuntu** | 20.04+ | apt | ⚠️ Manual |
| **Debian** | 11+ | apt | ⚠️ Manual |
| **Arch Linux** | Latest | pacman | ⚠️ Manual |
| **openSUSE** | 15+ | zypper | ⚠️ Manual |

## Hardware Requirements

### Minimum Requirements

- **CPU**: 1 core, 1.0 GHz
- **RAM**: 512 MB
- **Storage**: 1 GB free space
- **Network**: Ethernet connection

### Recommended Requirements

- **CPU**: 2 cores, 2.0 GHz
- **RAM**: 2 GB
- **Storage**: 5 GB free space
- **Network**: Gigabit Ethernet

## Software Prerequisites

### Required Packages

#### DNF/YUM Distributions (Automated)
```bash
# These are automatically installed by system-setup.sh
podman
bind
bind-utils
bind-chroot
firewalld
policycoreutils-python-utils
```

#### APT Distributions (Manual)
```bash
# Install manually on Ubuntu/Debian
sudo apt update
sudo apt install -y podman bind9 bind9utils firewalld
```

#### Pacman Distributions (Manual)
```bash
# Install manually on Arch Linux
sudo pacman -S podman bind firewalld
```

### Optional Packages

- **dig/nslookup**: For DNS testing
- **tcpdump**: For network debugging
- **htop**: For system monitoring

## Network Requirements

### Ports

| Port | Protocol | Purpose | Required |
|------|----------|---------|----------|
| **53** | TCP/UDP | DNS queries | ✅ Yes |
| **953** | TCP | BIND control | ✅ Yes |

### Firewall Configuration

BindCaptain automatically configures firewalld:

```bash
# DNS service
firewall-cmd --add-service=dns --permanent
firewall-cmd --reload
```

## Security Requirements

### SELinux

SELinux is automatically configured for container operations:

```bash
# Container file contexts
setsebool -P container_manage_cgroup on
setsebool -P container_use_cephfs on
```

### User Permissions

- **Root access** required for system setup
- **Container runtime** access for Podman operations
- **Network binding** privileges for port 53

## Container Runtime

### Podman Requirements

- **Version**: 3.0+ recommended
- **Rootless**: Not supported (requires port 53)
- **Storage**: Local storage driver

### Container Image

- **Base**: Rocky Linux 9
- **BIND Version**: 9.16+
- **Size**: ~200 MB compressed

## Storage Requirements

### Configuration Directory

```text
/opt/bindcaptain/
├── config/           # DNS configuration files
├── zones/            # Zone files
├── logs/             # BIND logs
└── data/             # BIND data files
```

### Disk Space

- **Base installation**: 100 MB
- **Container image**: 200 MB
- **Zone files**: Variable (depends on DNS zones)
- **Logs**: Variable (depends on query volume)

## Performance Considerations

### DNS Query Load

| Queries/Second | CPU Usage | Memory Usage |
|---------------|-----------|--------------|
| **100** | < 5% | < 100 MB |
| **1,000** | < 15% | < 200 MB |
| **10,000** | < 50% | < 500 MB |

### Zone File Size

| Zones | Records | Memory Usage |
|-------|---------|--------------|
| **10** | 1,000 | ~ 50 MB |
| **100** | 10,000 | ~ 200 MB |
| **1,000** | 100,000 | ~ 1 GB |

## Compatibility Matrix

### BIND Versions

| BIND Version | Status | Notes |
|-------------|--------|-------|
| **9.16** | ✅ Supported | Minimum required |
| **9.18** | ✅ Supported | Recommended |
| **9.20** | ✅ Supported | Latest stable |

### Container Runtimes

| Runtime | Status | Notes |
|---------|--------|-------|
| **Podman 3.0+** | ✅ Supported | Primary runtime |
| **Docker** | ⚠️ Limited | Not officially supported |

## Unsupported Configurations

### Not Supported

- **Rootless containers** (requires port 53)
- **Docker runtime** (use Podman)
- **IPv6-only** networks (IPv4 required)
- **Windows/macOS** hosts (Linux only)

### Limited Support

- **Custom BIND configurations** (use templates)
- **Multiple BIND instances** (single instance only)
- **Cluster deployments** (single node only)

## Manual Setup

For unsupported distributions, see the [Manual Setup Guide](manual-setup.md) for detailed installation instructions.

---

**Need help?** Check the [Troubleshooting Guide](troubleshooting.md) or [Installation Guide](installation.md).
