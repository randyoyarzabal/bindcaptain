# ⚓ BindCaptain

**Navigate DNS complexity with captain-grade precision**

A production-ready, containerized BIND DNS server solution that puts you in complete control of your DNS infrastructure. **Updated for BIND 9.16+ compatibility** with modern configuration syntax and security best practices.

> *"Navigate the complex waters of DNS management with the confidence of a seasoned captain"*

## 🚀 Features

- **Multi-stage optimized container** - ~60-70% smaller than traditional builds
- **Modern BIND compatible** - Works with BIND 9.16, 9.18, and 9.20+
- **Updated configuration syntax** - Uses modern `primary/primaries` terminology
- **Enhanced security** - DNSSEC auto-validation, rate limiting, version hiding
- **Domain-based organization** - Clean directory structure for multiple domains
- **Container-aware management** - Scripts work both inside and outside container
- **Auto-discovery** - Automatically discovers domains from your configuration
- **Production-ready** - Includes backup, validation, and monitoring

## ⚠️ BIND Version Compatibility

BindCaptain is designed for **BIND 9.16+** and includes:

### **✅ Modern BIND Features:**
- **Updated terminology:** `type primary` instead of `type master`
- **RFC 8499 compliance:** `primaries` instead of `masters`
- **DNSSEC auto-validation:** Enabled by default for security
- **Rate limiting:** Protection against DNS amplification attacks
- **Enhanced logging:** Structured logging with categories
- **Deprecated option warnings:** Container startup checks for outdated syntax

### **🔧 Automatic Compatibility:**
- Detects BIND version at startup
- Warns about deprecated configuration options
- Supports both old and new syntax during transition
- Forward-compatible with BIND 9.20+

## 📁 Directory Structure

```
bindcaptain/
├── Containerfile              # Multi-stage container build (BIND 9.16+)
├── container_start.sh         # Enhanced startup with version detection
├── bindcaptain.sh             # Main container management script
├── bindcaptain_manager.sh     # Container-aware DNS management
├── bindcaptain_refresh.sh     # Container-aware automation
├── setup.sh                  # Interactive setup wizard
├── README.md                 # This file
├── LICENSE                   # MIT license
├── .gitignore                # Proper git exclusions
├── .github/                  # GitHub Actions CI/CD
│   └── workflows/
│       └── ci.yml            # Comprehensive CI pipeline
├── tests/                    # Comprehensive test suite
│   ├── run-tests.sh          # Main test runner
│   ├── test-configs/         # Test configuration files
│   └── results/              # Test results and logs
├── scripts/                  # System setup scripts
│   └── setup-rocky9.sh      # Automated Rocky Linux 9 setup
├── config/                   # YOUR DNS configuration (gitignored)
│   ├── .gitkeep              # Ensures directory exists
│   └── (your domains here)   # Copy from config-examples/
├── config-examples/          # Template configurations
│   ├── README.md             # Configuration guide
│   ├── named.conf.template   # Main BIND configuration template
│   └── example.com/          # Example domain template
│       ├── example.com.db    # Zone file template
│       ├── reverse-example.md # Reverse zone documentation
│       └── README.md         # Domain setup instructions
└── .gitignore                # Protects your personal configs
```

## ⚓ Quick Start

### 1. System Setup (New Linux Box)

**🐳 For Containerized BindCaptain (Recommended):**

```bash
# Automated containerized DNS setup for Rocky Linux 9/AlmaLinux 9/CentOS Stream 9
curl -fsSL https://raw.githubusercontent.com/randyoyarzabal/bindcaptain/main/scripts/setup-rocky9.sh | bash
```

**📦 For Traditional Native BIND:**
```bash
# Alternative: Traditional BIND installation (not containerized)
sudo dnf install -y bind bind-utils
# See SETUP-NATIVE.md for complete native installation guide
```

> **Recommendation:** Use the containerized approach for modern, portable, and scalable DNS infrastructure.

*For detailed setup guides: [Containerized Setup](SETUP-SYSTEM.md) | [Native BIND Setup](SETUP-NATIVE.md)*

### 2. BindCaptain Configuration

```bash
# Clone BindCaptain (if not done by automated setup)
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# Copy template configurations to your config directory
cp config-examples/named.conf.template config/named.conf
cp -r config-examples/example.com config/yourdomain.com

# Customize for your domains
nano config/named.conf
nano config/yourdomain.com/yourdomain.com.db

# Or use the interactive setup wizard
sudo ./setup.sh wizard
```

### 2. Modern Configuration Structure

BindCaptain organizes DNS configuration by **domain** for better management:

#### **Domain Directory Structure:**
```bash
config/
├── named.conf              # Main configuration
├── example.com/            # Template domain
│   ├── example.com.db      # Zone file
│   └── README.md           # Documentation
├── homelab.io/             # Homelab domain
│   └── homelab.io.db       # Zone file
└── reonetlabs.us/          # Network authority domain
    ├── reonetlabs.us.db    # Forward zone file
    ├── 40.25.172.in-addr.arpa.db  # Reverse zones
    ├── 42.25.172.in-addr.arpa.db  # (consolidated)
    └── 50.25.172.in-addr.arpa.db  # by authority
```

#### **Zone File References:**
```bash
zone "example.com" IN {
    type primary;
    file "example.com/example.com.db";  # Domain-specific path
    ...
};

zone "1.168.192.in-addr.arpa" IN {
    type primary;
    file "reonetlabs.us/1.168.192.in-addr.arpa.db";  # Consolidated in authority domain
    ...
};
```

### 3. Deploy Your DNS Fleet

```bash
# Build and deploy your DNS infrastructure
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run

# Check your fleet status
sudo ./bindcaptain.sh status

# View the ship's logs
sudo ./bindcaptain.sh logs | grep "BIND Version"
```

## 🧭 Navigation Commands

### ⚓ Fleet Management

```bash
# Build your DNS fleet
sudo ./bindcaptain.sh build

# Deploy and take command
sudo ./bindcaptain.sh run

# Check fleet status
sudo ./bindcaptain.sh status

# Monitor the bridge
sudo ./bindcaptain.sh logs
```

### 🗺️ DNS Record Management

```bash
# Take command of DNS records
source bindcaptain_manager.sh

# Chart new territories (create records)
bind.create_record webserver yourdomain.com 172.25.50.200

# Survey your domain
bind.list_records yourdomain.com

# Show navigation status
show_environment
```

## 🧪 Testing & Quality Assurance

BindCaptain includes a comprehensive test suite to ensure captain-grade reliability:

### **Run Test Suite**

```bash
# Run all tests
./tests/run-tests.sh

# Run with verbose output
./tests/run-tests.sh --verbose

# Skip container tests (if no podman/docker)
SKIP_CONTAINER_TESTS=1 ./tests/run-tests.sh

# Skip BIND validation tests (if no bind-utils)
SKIP_BIND_TESTS=1 ./tests/run-tests.sh
```

### **Test Coverage**

The test suite validates:
- ✅ **Project Structure** - All required files and directories
- ✅ **Script Syntax** - Shell script validation
- ✅ **Configuration** - BIND syntax validation
- ✅ **Container Build** - Multi-stage container build
- ✅ **Container Startup** - Basic functionality test
- ✅ **Documentation** - README and link validation
- ✅ **Security** - License and security best practices
- ✅ **Compatibility** - BIND version compatibility

### **GitHub Actions CI**

Continuous Integration runs automatically on:
- **Push to main/develop** - Full test suite
- **Pull Requests** - Complete validation
- **Weekly Schedule** - Regular health checks

The CI pipeline includes:
- 🧪 **Multi-platform builds** (amd64, arm64)
- 🔒 **Security scanning** (Trivy)
- 🧭 **BIND version compatibility** (9.16, 9.18)
- 📚 **Documentation validation**
- 🔍 **Script linting** (ShellCheck)
- 🚢 **Container publishing** (GitHub Registry)

## 🗺️ Domain Management

### **Adding New Domains**

1. **Create domain directory:**
   ```bash
   mkdir -p config/yourdomain.com
   ```

2. **Copy template zone file:**
   ```bash
   cp config/example.com/example.com.db config/yourdomain.com/yourdomain.com.db
   ```

3. **Edit zone file:**
   ```bash
   # Update domain name, SOA, and records
   nano config/yourdomain.com/yourdomain.com.db
   ```

4. **Update named.conf:**
   ```bash
   # Add zone declaration
   zone "yourdomain.com" IN {
       type primary;
       file "yourdomain.com/yourdomain.com.db";
       check-names warn;
       also-notify { 172.25.50.122; 172.25.50.123; };
       allow-transfer { 172.25.50.122; 172.25.50.123; };
       allow-query { any; };
   };
   ```

5. **Validate and deploy:**
   ```bash
   sudo ./bindcaptain.sh validate
   sudo ./bindcaptain.sh restart
   ```

### **Domain-Specific Features**

#### **homelab.io** - OpenShift Integration:
- Multiple OpenShift clusters
- Container infrastructure
- Development environments

#### **reonetlabs.us** - Production Infrastructure:
- Proxmox VE clusters
- Network management
- Production services

#### **example.com** - Template Domain:
- Starting point for new domains
- Well-documented structure
- Best practices implementation

## 🌊 Environment Variables

Configure your DNS fleet:

```bash
# Fleet configuration
export USER_CONFIG_DIR="/path/to/your/dns-config"
export CONTAINER_DATA_DIR="/opt/your-dns"

# Navigation settings
export BIND_VERSION_CHECK="true"    # Check compatibility
export BIND_DEBUG_LEVEL="1"         # Bridge verbosity
export TZ="America/New_York"         # Fleet timezone

# Set sail!
sudo ./bindcaptain.sh run
```

## 🔍 Bridge Monitoring

BindCaptain provides intelligent monitoring:

### **Ship Status Reports:**
```bash
[CONTAINER] ⚓ BindCaptain - BIND Version: BIND 9.16.23-RH
[CONTAINER] Detected BIND version: 9.16
[CONTAINER] Modern BIND detected (9.16+) - enhanced features available
[CONTAINER] WARNING: 'Masterfile-Format' option is deprecated in BIND 9.18+
[CONTAINER] INFO: Consider updating 'type master' to 'type primary'
```

### **Navigation Health:**
- Supports both `master` and `primary` zone types
- Auto-detects configured zones
- Compatible with modern BIND security features

## 🔒 Fleet Security

### **Modern BIND Security Features:**

1. **DNSSEC Auto-Validation:**
   ```bash
   dnssec-validation auto;  # Automatic DNSSEC validation
   ```

2. **Rate Limiting (Anti-DDoS):**
   ```bash
   rate-limit {
       responses-per-second 10;
       window 5;
   };
   ```

3. **Information Hiding:**
   ```bash
   version none;    # Hide BIND version
   hostname none;   # Hide server hostname
   ```

4. **Enhanced Logging:**
   ```bash
   logging {
       channel security_file {
           file "/var/log/named/security.log";
           severity info;
       };
   };
   ```

## ⚓ Fleet Compatibility

### **Tested Waters:**
- ✅ **BIND 9.16.x** - Full compatibility
- ✅ **BIND 9.18.x** - Enhanced features
- ✅ **BIND 9.20.x** - Latest features

### **Supported Ports:**
- **Rocky Linux 9** - BIND 9.16.x (primary target)
- **AlmaLinux 9** - BIND 9.16.x
- **Ubuntu 22.04** - BIND 9.18.x
- **Debian 12** - BIND 9.18.x

## 🚢 Advanced Fleet Operations

### **Multi-Ship Deployment:**
```bash
# Deploy multiple DNS fleets
USER_CONFIG_DIR="/etc/dns1" CONTAINER_DATA_DIR="/opt/dns1" sudo ./bindcaptain.sh run
USER_CONFIG_DIR="/etc/dns2" CONTAINER_DATA_DIR="/opt/dns2" sudo ./bindcaptain.sh run
```

### **Custom Fleet Configuration:**
```bash
# Deploy with specific settings
BIND_VERSION_CHECK=false sudo ./bindcaptain.sh run
```

## 🗺️ Migration from Legacy Systems

### **Upgrading Old Fleet (BIND 9.11 and older):**

1. **Update navigation charts:**
   ```bash
   # Copy your old config
   cp /etc/named.conf config/named.conf
   
   # Organize by domains
   mkdir -p config/yourdomain.com
   mv /var/named/yourdomain.com.db config/yourdomain.com/
   
   # Update file paths in named.conf
   sed -i 's|file "yourdomain.com.db"|file "yourdomain.com/yourdomain.com.db"|g' config/named.conf
   
   # Modernize the fleet
   sed -i 's/type master/type primary/g' config/named.conf
   sed -i 's/notify master-only/notify primary-only/g' config/named.conf
   sed -i '/Masterfile-Format/d' config/named.conf
   sed -i '/dnssec-enable/d' config/named.conf
   ```

2. **Deploy modern security:**
   ```bash
   echo "dnssec-validation auto;" >> config/named.conf
   echo "version none;" >> config/named.conf
   ```

3. **Set sail with new fleet:**
   ```bash
   sudo ./bindcaptain.sh validate
   sudo ./bindcaptain.sh run
   ```

## 🆘 Troubleshooting

### **Fleet Diagnostics:**

```bash
# Check ship's engine
sudo podman exec bindcaptain named -v

# Monitor bridge warnings
sudo ./bindcaptain.sh logs | grep WARNING

# Emergency navigation mode
BIND_VERSION_CHECK=false sudo ./bindcaptain.sh run
```

### **Common Issues:**

```bash
# View navigation warnings
sudo ./bindcaptain.sh logs | grep "deprecated"

# Common fixes:
# Remove: Masterfile-Format Text;
# Remove: dnssec-enable no;
# Add: dnssec-validation auto;
# Change: type master → type primary
```

## 🤝 Join the Crew

BindCaptain maintains compatibility with:
- **BIND 9.16+** (minimum supported)
- **Modern DNS standards** (RFC 8499, etc.)
- **Container security best practices**
- **Multi-architecture support**

## 📜 Ship's License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚓ Captain's Log

*"In the vast ocean of network infrastructure, a reliable DNS service is your North Star. BindCaptain ensures you never lose your way."*

- ⚓ **Captain-grade reliability** for production deployments
- 🧭 **Modern navigation** with BIND 9.16+ compatibility
- 🔒 **Fortress-level security** with enhanced protection
- 🚢 **Fleet-ready** for enterprise deployment
- 🗺️ **Domain-organized** for scalable management

---

*Set sail with BindCaptain - Where DNS Infrastructure Meets Naval Precision* ⚓