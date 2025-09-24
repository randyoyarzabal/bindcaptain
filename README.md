# BindCaptain 🌊⚓

> **Containerized BIND DNS Server with Smart Management**

Modern, containerized BIND DNS solution with automated management, perfect for homelab and enterprise environments.

## 🚀 Quick Start

### 1. Clone & Setup
```bash
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain
sudo ./setup.sh
```

### 2. Configure Your Zones
```bash
# Copy your DNS zones to config/
mkdir -p config/yourdomain.com
# Add your zone files to config/yourdomain.com/
```

### 3. Launch
```bash
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run
```

## 📝 DNS Management

```bash
# Source the manager
sudo bash -c "source /opt/bindcaptain/bindcaptain_manager.sh"

# Add DNS records
bind.create_record webserver yourdomain.com 192.168.1.100
bind.create_cname www yourdomain.com webserver
bind.create_txt @ yourdomain.com "v=spf1 -all"

# List records
bind.list_records yourdomain.com

# Update codebase
bind.git_refresh
```

## ✨ Features

- **🐳 Containerized** - Clean, isolated BIND installation
- **🔄 Auto-Updates** - Built-in git refresh functionality  
- **📊 Smart Management** - CLI tools for DNS record management
- **🔒 Secure** - Modern BIND 9.16+ with security best practices
- **🔧 Zero-Config** - Works out of the box with example configs
- **📈 Auto-Reverse** - Automatic reverse DNS generation
- **🎯 Production-Ready** - Used in real production environments

## 📚 Documentation

Detailed guides available in [`docs/`](docs/):

- **[docs/cheat-sheet.md](docs/cheat-sheet.md)** - Complete management reference
- **[docs/setup-system.md](docs/setup-system.md)** - System prerequisites  
- **[docs/example-add-record.md](docs/example-add-record.md)** - Step-by-step examples

## 🌐 Architecture

```
BindCaptain/
├── bindcaptain.sh          # Container management
├── bindcaptain_manager.sh  # DNS record management  
├── config/                 # Your DNS zones
│   ├── yourdomain.com/
│   │   ├── yourdomain.com.db
│   │   └── reverse zones
│   └── named.conf
└── docs/                   # Documentation
```

## 🛠️ Requirements

- **Rocky Linux 9 / CentOS Stream 9 / AlmaLinux 9** (recommended)
- **Podman** (auto-installed by setup script)
- **Git & bind-utils** (auto-installed)

## 🤝 Contributing

Issues and pull requests welcome! See our [GitHub repository](https://github.com/randyoyarzabal/bindcaptain).

---

**BindCaptain** - *Navigate your DNS with confidence* 🌊⚓