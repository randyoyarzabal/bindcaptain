# ⚓ BindCaptain Configuration Examples

This directory contains **template configurations** for BindCaptain. Copy these to your `config/` directory and customize for your domains.

## 📁 Directory Structure

```
config-examples/
├── README.md                 # This file
├── named.conf.template       # Main BIND configuration template
└── example.com/              # Template domain configuration
    ├── example.com.db        # Forward zone template
    ├── reverse-example.md    # Reverse zone documentation
    └── README.md             # Domain setup instructions
```

## 🚀 Quick Setup

### **1. Copy Templates to Your Config Directory**

```bash
# Create your config directory
mkdir -p config

# Copy main configuration template
cp config-examples/named.conf.template config/named.conf

# Copy example domain for your first domain
cp -r config-examples/example.com config/yourdomain.com

# Edit for your domain
nano config/yourdomain.com/yourdomain.com.db
nano config/named.conf
```

### **2. Domain-Based Organization**

For each domain you manage, create a directory structure like:

```bash
config/
├── named.conf              # Your main BIND configuration
├── yourdomain.com/         # Your domain
│   └── yourdomain.com.db   # Zone file
├── anotherdomain.org/      # Another domain
│   └── anotherdomain.org.db
└── authority-domain.net/   # Network authority domain
    ├── authority-domain.net.db
    ├── 10.0.1.in-addr.arpa.db     # Reverse zones
    └── 10.0.2.in-addr.arpa.db
```

### **3. Reverse Zone Strategy**

- **Forward zones**: Each domain in its own directory
- **Reverse zones**: Consolidated under the **network authority domain**
- **Authority domain**: The domain that owns your network infrastructure

## 📝 Configuration Steps

### **Step 1: Main Configuration**

```bash
# Edit main configuration
nano config/named.conf

# Update these sections:
# - listen-on port 53 { YOUR_IP; };
# - allow-query { YOUR_NETWORKS; };
# - Add your zone declarations
```

### **Step 2: Forward Zones**

```bash
# For each domain, create directory and zone file
mkdir -p config/yourdomain.com
cp config-examples/example.com/example.com.db config/yourdomain.com/yourdomain.com.db

# Edit zone file:
# - Update $ORIGIN
# - Update SOA record
# - Add your A records
# - Add your CNAME records
```

### **Step 3: Reverse Zones**

```bash
# Create reverse zones in your network authority domain
mkdir -p config/your-authority-domain.com

# Create reverse zone files:
# - subnet.in-addr.arpa.db files
# - PTR records pointing to your domains
```

### **Step 4: Validation**

```bash
# Test configuration syntax
sudo ./bindcaptain.sh validate

# Test individual zones
named-checkzone yourdomain.com config/yourdomain.com/yourdomain.com.db
```

## 🎯 Example Scenarios

### **Single Domain Setup**
- Copy `example.com/` → `yourdomain.com/`
- Update `named.conf.template` → `named.conf`
- Simple forward DNS only

### **Multi-Domain Setup**  
- Multiple domain directories
- Shared reverse zones in authority domain
- Complex network topology

### **Production Infrastructure**
- Separate development/staging/production domains
- Network segmentation with multiple reverse zones
- Master/slave configuration with multiple DNS servers

## 🔧 Template Customization

### **named.conf.template Features:**
- Modern BIND 9.16+ syntax
- Security best practices
- Performance optimizations
- Master/slave ready
- DNSSEC enabled

### **example.com.db Features:**
- Proper SOA record structure
- Common record types (A, CNAME, TXT)
- Professional formatting
- Documentation comments

## 📚 Documentation References

- **Main README**: [../README.md](../README.md)
- **System Setup**: [../SETUP-SYSTEM.md](../SETUP-SYSTEM.md)
- **Native BIND**: [../SETUP-NATIVE.md](../SETUP-NATIVE.md)
- **Podman Setup**: [../PODMAN-SETUP.md](../PODMAN-SETUP.md)

## ⚠️ Important Notes

### **Security:**
- **Never commit real configurations** to public repositories
- **Use .gitignore** to exclude your `config/` directory
- **Review zone files** for sensitive information before sharing

### **Testing:**
- **Always validate** configuration before deployment
- **Test DNS resolution** from multiple clients
- **Monitor logs** for errors and warnings
- **Use staging environment** for testing changes

## 🎯 Next Steps

1. **Copy templates** to your `config/` directory
2. **Customize configurations** for your domains and network
3. **Validate syntax** with BindCaptain tools
4. **Deploy container** with your configuration
5. **Test DNS resolution** and functionality

---

*These templates provide a solid foundation for professional DNS infrastructure management with BindCaptain.*
