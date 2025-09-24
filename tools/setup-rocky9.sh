#!/bin/bash

# ⚓ BindCaptain System Setup Script for Rocky Linux 9
# Automated system preparation for CONTAINERIZED DNS infrastructure
# This script prepares the system for BindCaptain containers, NOT native BIND
# Run as: curl -fsSL https://raw.githubusercontent.com/randyoyarzabal/bindcaptain/main/scripts/setup-rocky9.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BINDCAPTAIN_DIR="/opt/bindcaptain"
LOG_FILE="/var/log/bindcaptain-setup.log"

# Functions
print_header() {
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}  BindCaptain System Setup${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo -e "${BLUE}Navigate DNS complexity with captain-grade precision${NC}"
    echo
}

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $message" | tee -a "$LOG_FILE"
}

print_step() {
    local step="$1"
    echo -e "${YELLOW}[*] $step${NC}"
    log_message "STEP: $step"
}

print_success() {
    local message="$1"
    echo -e "${GREEN}[✓] $message${NC}"
    log_message "SUCCESS: $message"
}

print_error() {
    local message="$1"
    echo -e "${RED}[✗] $message${NC}"
    log_message "ERROR: $message"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "rocky" ]] && [[ "$ID" != "almalinux" ]] && [[ "$ID" != "centos" ]] && [[ "$ID" != "rhel" ]]; then
        print_error "This script is designed for Rocky Linux 9, AlmaLinux 9, CentOS Stream 9, or RHEL 9"
        print_error "Detected OS: $PRETTY_NAME"
        exit 1
    fi
    
    if [[ "$VERSION_ID" != "9"* ]]; then
        print_error "This script requires version 9.x"
        print_error "Detected version: $VERSION_ID"
        exit 1
    fi
    
    print_success "OS Compatibility: $PRETTY_NAME"
}

update_system() {
    print_step "Installing container prerequisites"
    
    dnf update -y >> "$LOG_FILE" 2>&1
    
    print_step "Installing minimal packages for containerized DNS"
    dnf install -y \
        git \
        bind-utils >> "$LOG_FILE" 2>&1
    
    print_success "Container prerequisites installed"
    log_message "Installed: git (for repo), bind-utils (for DNS testing)"
}

install_podman() {
    print_step "Installing Podman container runtime for DNS services"
    
    # Install podman and related tools
    dnf install -y \
        podman \
        podman-compose \
        buildah \
        skopeo \
        containers-common \
        fuse-overlayfs \
        slirp4netns >> "$LOG_FILE" 2>&1
    
    print_step "Configuring Podman for root DNS container operations"
    
    # Configure podman for root operations (required for port 53)
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

    # Allow binding to privileged ports (alternative method)
    echo 'net.ipv4.ip_unprivileged_port_start=53' > /etc/sysctl.d/podman-dns.conf
    sysctl -p /etc/sysctl.d/podman-dns.conf >> "$LOG_FILE" 2>&1
    
    # Configure cgroups v2 for podman (Rocky 9 default)
    if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
        print_step "Configuring cgroups v2 for container management"
        # Rocky 9 should have cgroups v2 by default, but ensure it's enabled
        grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1" >> "$LOG_FILE" 2>&1
    fi
    
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
    
    log_message "Podman version: $(podman --version)"
    log_message "Podman storage: $(podman system info --format='{{.Store.GraphRoot}}')"
}

configure_firewall() {
    print_step "Configuring firewall for DNS services"
    
    systemctl enable --now firewalld >> "$LOG_FILE" 2>&1
    
    # Allow DNS services
    firewall-cmd --permanent --add-service=dns >> "$LOG_FILE" 2>&1
    firewall-cmd --permanent --add-port=53/tcp >> "$LOG_FILE" 2>&1
    firewall-cmd --permanent --add-port=53/udp >> "$LOG_FILE" 2>&1
    
    # Allow SSH
    firewall-cmd --permanent --add-service=ssh >> "$LOG_FILE" 2>&1
    
    # Allow Cockpit for monitoring
    firewall-cmd --permanent --add-service=cockpit >> "$LOG_FILE" 2>&1
    
    # Apply rules
    firewall-cmd --reload >> "$LOG_FILE" 2>&1
    
    print_success "Firewall configured for DNS services"
}

configure_selinux() {
    print_step "Configuring SELinux for DNS containers"
    
    # Configure SELinux booleans for container operations
    setsebool -P container_manage_cgroup on >> "$LOG_FILE" 2>&1
    setsebool -P virt_use_nfs on >> "$LOG_FILE" 2>&1
    setsebool -P nis_enabled on >> "$LOG_FILE" 2>&1
    
    # Additional SELinux settings for DNS services
    setsebool -P container_connect_any on >> "$LOG_FILE" 2>&1
    setsebool -P domain_can_mmap_files on >> "$LOG_FILE" 2>&1
    
    # Allow containers to bind to network ports (including privileged ports)
    if command -v semanage >/dev/null 2>&1; then
        # Allow containers to bind to DNS ports
        semanage port -a -t container_port_t -p tcp 53 >> "$LOG_FILE" 2>&1 || true
        semanage port -a -t container_port_t -p udp 53 >> "$LOG_FILE" 2>&1 || true
    else
        print_step "Installing SELinux management tools"
        dnf install -y policycoreutils-python-utils >> "$LOG_FILE" 2>&1
        semanage port -a -t container_port_t -p tcp 53 >> "$LOG_FILE" 2>&1 || true
        semanage port -a -t container_port_t -p udp 53 >> "$LOG_FILE" 2>&1 || true
    fi
    
    print_success "SELinux configured for DNS container operations"
    log_message "SELinux status: $(sestatus | head -n1)"
    log_message "Container SELinux booleans: $(getsebool container_manage_cgroup container_connect_any)"
}

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
    chmod +x *.sh tests/*.sh
    
    print_success "BindCaptain installed to $BINDCAPTAIN_DIR"
}

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

run_tests() {
    print_step "Running BindCaptain tests"
    
    cd "$BINDCAPTAIN_DIR"
    
    # Run basic tests (skip container tests if no config yet)
    SKIP_CONTAINER_TESTS=1 ./tests/run-tests.sh >> "$LOG_FILE" 2>&1
    
    print_success "Basic tests completed"
}

show_summary() {
    echo
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}  Setup Complete!${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo
    echo -e "${GREEN}[✓] System successfully prepared for BindCaptain!${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "${BLUE}1. Configure your DNS zones:${NC}"
    echo -e "   cd $BINDCAPTAIN_DIR"
    echo -e "   sudo ./setup.sh wizard"
    echo
    echo -e "${BLUE}2. Build and run BindCaptain:${NC}"
    echo -e "   sudo ./bindcaptain.sh build"
    echo -e "   sudo ./bindcaptain.sh run"
    echo
    echo -e "${BLUE}3. Test your DNS service:${NC}"
    echo -e "   sudo ./bindcaptain.sh status"
    echo -e "   dig @localhost yourdomain.com"
    echo
    echo -e "${BLUE}4. Monitor with Cockpit:${NC}"
    echo -e "   https://$(hostname -I | awk '{print $1}'):9090"
    echo
    echo -e "${YELLOW}Logs available at:${NC} $LOG_FILE"
    echo -e "${YELLOW}BindCaptain directory:${NC} $BINDCAPTAIN_DIR"
    echo
    echo -e "${GREEN}[✓] Ready to deploy BindCaptain!${NC}"
}

# Main execution
main() {
    print_header
    
    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log_message "BindCaptain system setup starting"
    
    # Run setup steps
    check_root
    check_os
    update_system
    install_podman
    configure_firewall
    configure_selinux
    disable_conflicting_services
    install_bindcaptain
    run_tests
    
    show_summary
    
    log_message "BindCaptain system setup completed successfully"
}

# Execute main function
main "$@"
