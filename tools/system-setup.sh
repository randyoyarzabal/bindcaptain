#!/bin/bash

# ⚓ BindCaptain System Setup Script
# Automated system preparation for CONTAINERIZED DNS infrastructure
# Supports all DNF/YUM-based Linux distributions (RHEL, CentOS, Rocky, AlmaLinux, Fedora)
# Run as: curl -fsSL https://raw.githubusercontent.com/randyoyarzabal/bindcaptain/main/tools/system-setup.sh | bash
#
# USAGE:
#   sudo ./tools/system-setup.sh
#
# WHAT IT DOES:
#   - Detects your Linux distribution and package manager
#   - Installs Podman container runtime and related tools
#   - Configures Podman for DNS services (port 53 binding)
#   - Sets up firewall rules for DNS (ports 53/tcp, 53/udp)
#   - Configures SELinux for container operations (if available)
#   - Installs BindCaptain from GitHub
#   - Disables conflicting DNS services
#   - Runs basic tests
#
# SUPPORTED DISTRIBUTIONS:
#   - RHEL 8+
#   - CentOS 8+ (CentOS Stream)
#   - Rocky Linux 8+
#   - AlmaLinux 8+
#   - Fedora 30+
#
# FOR OTHER DISTRIBUTIONS:
#   See docs/manual-setup.md for manual setup instructions
#
# REQUIREMENTS:
#   - Root privileges (sudo)
#   - Internet connection
#   - Supported Linux distribution

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Setup-specific configuration
BINDCAPTAIN_DIR="/opt/bindcaptain"
LOG_FILE="/var/log/bindcaptain-setup.log"

# Setup-specific functions
print_system_header() {
    print_header "BindCaptain System Setup" "Navigate DNS complexity with captain-grade precision"
}

log_system_message() {
    log_message "$1" "$LOG_FILE"
}

print_step() {
    local step="$1"
    print_status "info" "$step"
    log_system_message "STEP: $step"
}

print_success() {
    local message="$1"
    print_status "success" "$message"
    log_system_message "SUCCESS: $message"
}

print_error() {
    local message="$1"
    print_status "error" "$message"
    log_system_message "ERROR: $message"
}

# Detect package manager and distribution
detect_package_manager() {
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf update -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum update -y"
    else
        print_error "No supported package manager found (dnf/yum required)"
        exit 1
    fi
    
    print_success "Package manager detected: $PKG_MANAGER"
}

# Check OS compatibility
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    # Check for supported distributions
    case "$ID" in
        "rhel"|"centos"|"rocky"|"almalinux"|"fedora")
            print_success "Supported distribution: $PRETTY_NAME"
            ;;
        "ubuntu"|"debian")
            print_error "This script is for DNF/YUM-based distributions"
            print_error "For Ubuntu/Debian, please install prerequisites manually:"
            print_error "  sudo apt update"
            print_error "  sudo apt install podman podman-compose buildah skopeo bind-utils"
            print_error "  sudo systemctl enable --now podman.socket"
            print_error ""
            print_error "Then proceed with: sudo ./tools/config-setup.sh wizard"
            exit 1
            ;;
        *)
            print_error "Unsupported distribution: $PRETTY_NAME"
            print_error "This script supports: RHEL, CentOS, Rocky Linux, AlmaLinux, Fedora"
            print_error ""
            print_error "For other distributions, please install prerequisites manually:"
            print_error "  - Podman container runtime"
            print_error "  - Git"
            print_error "  - bind-utils (for DNS testing)"
            print_error "  - Configure firewall for ports 53/tcp and 53/udp"
            print_error ""
            print_error "Then proceed with: sudo ./tools/config-setup.sh wizard"
            exit 1
            ;;
    esac
    
    # Check version for RHEL-based systems
    if [[ "$ID" =~ ^(rhel|centos|rocky|almalinux)$ ]]; then
        if [[ "$VERSION_ID" =~ ^[0-9]+$ ]] && [[ "$VERSION_ID" -lt 8 ]]; then
            print_error "This script requires version 8 or higher"
            print_error "Detected version: $VERSION_ID"
            exit 1
        fi
    fi
}

# Update system and install prerequisites
update_system() {
    print_step "Updating system packages"
    
    $PKG_UPDATE >> "$LOG_FILE" 2>&1
    
    print_step "Installing container prerequisites"
    $PKG_INSTALL \
        git \
        bind-utils \
        curl \
        wget >> "$LOG_FILE" 2>&1
    
    print_success "System updated and prerequisites installed"
    log_system_message "Installed: git, bind-utils, curl, wget"
}

# Install Podman container runtime
install_podman() {
    print_step "Installing Podman container runtime"
    
    # Install podman and related tools
    $PKG_INSTALL \
        podman \
        podman-compose \
        buildah \
        skopeo \
        containers-common \
        fuse-overlayfs \
        slirp4netns >> "$LOG_FILE" 2>&1
    
    print_step "Configuring Podman for DNS services"
    
    # Enable podman socket
    systemctl enable --now podman.socket >> "$LOG_FILE" 2>&1
    
    # Configure storage for root podman
    mkdir -p /etc/containers
    
    # Create containers.conf for optimized DNS container operation
    cat > /etc/containers/containers.conf << 'EOF'
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

    # Configure storage.conf for root podman
    cat > /etc/containers/storage.conf << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
additionalimagestores = []

[storage.options.overlay]
mountopt = "nodev,metacopy=on"
EOF

    # Allow binding to privileged ports
    echo 'net.ipv4.ip_unprivileged_port_start=53' > /etc/sysctl.d/podman-dns.conf
    sysctl -p /etc/sysctl.d/podman-dns.conf >> "$LOG_FILE" 2>&1
    
    # Test podman installation
    print_step "Testing Podman installation"
    podman --version >> "$LOG_FILE" 2>&1
    podman info >> "$LOG_FILE" 2>&1
    
    # Test privileged port binding capability
    if timeout 5 podman run --rm --privileged -p 53:53/udp alpine:latest /bin/sh -c "echo 'Port 53 test successful'" >> "$LOG_FILE" 2>&1; then
        print_success "Podman configured for DNS services (port 53 binding confirmed)"
    else
        print_success "Podman installed (port 53 binding will be tested with BindCaptain)"
    fi
    
    log_system_message "Podman version: $(podman --version)"
    log_system_message "Podman storage: $(podman system info --format='{{.Store.GraphRoot}}')"
}

# Configure firewall
configure_firewall() {
    print_step "Configuring firewall for DNS services"
    
    # Check if firewalld is available
    if command -v firewall-cmd &> /dev/null; then
        systemctl enable --now firewalld >> "$LOG_FILE" 2>&1
        
        # Allow DNS services
        firewall-cmd --permanent --add-service=dns >> "$LOG_FILE" 2>&1
        firewall-cmd --permanent --add-port=53/tcp >> "$LOG_FILE" 2>&1
        firewall-cmd --permanent --add-port=53/udp >> "$LOG_FILE" 2>&1
        
        # Allow SSH
        firewall-cmd --permanent --add-service=ssh >> "$LOG_FILE" 2>&1
        
        # Allow Cockpit for monitoring (if available)
        firewall-cmd --permanent --add-service=cockpit >> "$LOG_FILE" 2>&1 || true
        
        # Apply rules
        firewall-cmd --reload >> "$LOG_FILE" 2>&1
        
        print_success "Firewall configured for DNS services"
    else
        print_step "Firewalld not available, skipping firewall configuration"
        print_status "warning" "Please manually configure firewall to allow ports 53/tcp and 53/udp"
    fi
}

# Configure SELinux (if available)
configure_selinux() {
    if command -v getenforce &> /dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
        print_step "Configuring SELinux for DNS containers"
        
        # Configure SELinux booleans for container operations
        setsebool -P container_manage_cgroup on >> "$LOG_FILE" 2>&1
        setsebool -P virt_use_nfs on >> "$LOG_FILE" 2>&1
        setsebool -P nis_enabled on >> "$LOG_FILE" 2>&1
        setsebool -P container_connect_any on >> "$LOG_FILE" 2>&1
        setsebool -P domain_can_mmap_files on >> "$LOG_FILE" 2>&1
        
        # Allow containers to bind to DNS ports
        if command -v semanage >/dev/null 2>&1; then
            semanage port -a -t container_port_t -p tcp 53 >> "$LOG_FILE" 2>&1 || true
            semanage port -a -t container_port_t -p udp 53 >> "$LOG_FILE" 2>&1 || true
        else
            print_step "Installing SELinux management tools"
            $PKG_INSTALL policycoreutils-python-utils >> "$LOG_FILE" 2>&1
            semanage port -a -t container_port_t -p tcp 53 >> "$LOG_FILE" 2>&1 || true
            semanage port -a -t container_port_t -p udp 53 >> "$LOG_FILE" 2>&1 || true
        fi
        
        print_success "SELinux configured for DNS container operations"
        log_system_message "SELinux status: $(sestatus | head -n1)"
    else
        print_step "SELinux not available or disabled, skipping SELinux configuration"
    fi
}

# Install BindCaptain
install_bindcaptain() {
    print_step "Installing BindCaptain from GitHub"
    
    if [[ -d "$BINDCAPTAIN_DIR/.git" ]]; then
        print_step "Updating existing BindCaptain installation"
        cd "$BINDCAPTAIN_DIR"
        git pull origin main >> "$LOG_FILE" 2>&1
    else
        print_step "Cloning BindCaptain repository"
        rm -rf "$BINDCAPTAIN_DIR"
        git clone https://github.com/randyoyarzabal/bindcaptain.git "$BINDCAPTAIN_DIR" >> "$LOG_FILE" 2>&1
    fi
    
    cd "$BINDCAPTAIN_DIR"
    
    # Make scripts executable
    chmod +x *.sh tools/*.sh tests/*.sh
    
    print_success "BindCaptain installed to $BINDCAPTAIN_DIR"
}

# Disable conflicting services
disable_conflicting_services() {
    print_step "Checking for conflicting DNS services"
    
    # Disable systemd-resolved if present
    if systemctl is-active --quiet systemd-resolved; then
        print_step "Disabling systemd-resolved to avoid conflicts"
        systemctl disable --now systemd-resolved >> "$LOG_FILE" 2>&1
        print_success "systemd-resolved disabled"
    fi
    
    # Check for named/bind
    if systemctl is-active --quiet named; then
        print_step "Found active BIND service - stopping to avoid conflicts"
        systemctl stop named >> "$LOG_FILE" 2>&1
        print_success "BIND service stopped"
    fi
}

# Run basic tests
run_tests() {
    print_step "Running BindCaptain tests"
    
    cd "$BINDCAPTAIN_DIR"
    
    # Run basic tests (skip container tests if no config yet)
    SKIP_CONTAINER_TESTS=1 ./tests/run-tests.sh >> "$LOG_FILE" 2>&1
    
    print_success "Basic tests completed"
}

# Show completion summary
show_summary() {
    echo
    print_header "Setup Complete!"
    echo
    print_status "success" "System successfully prepared for BindCaptain!"
    echo
    print_status "info" "Next steps:"
    echo "1. Configure your DNS zones:"
    echo "   cd $BINDCAPTAIN_DIR"
    echo "   sudo ./tools/config-setup.sh wizard"
    echo
    echo "2. Build and run BindCaptain:"
    echo "   sudo ./bindcaptain.sh build"
    echo "   sudo ./bindcaptain.sh run"
    echo
    echo "3. Test your DNS service:"
    echo "   sudo ./bindcaptain.sh status"
    echo "   dig @localhost yourdomain.com"
    echo
    echo "4. Monitor with Cockpit (if available):"
    echo "   https://$(hostname -I | awk '{print $1}'):9090"
    echo
    print_status "info" "Logs available at: $LOG_FILE"
    print_status "info" "BindCaptain directory: $BINDCAPTAIN_DIR"
    echo
    print_status "success" "Ready to deploy BindCaptain!"
}

# Main execution
main() {
    print_system_header
    
    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log_system_message "BindCaptain system setup starting"
    
    # Run setup steps
    check_root
    detect_package_manager
    check_os
    update_system
    install_podman
    configure_firewall
    configure_selinux
    disable_conflicting_services
    install_bindcaptain
    run_tests
    
    show_summary
    
    log_system_message "BindCaptain system setup completed successfully"
}

# Execute main function
main "$@"
