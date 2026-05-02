#!/bin/bash

# ⚓ BindCaptain Configuration Setup Script
# Helps users get started quickly with their own DNS configuration
#
# USAGE:
#   sudo ./tools/config-setup.sh [COMMAND]
#
# COMMANDS:
#   wizard  - Interactive configuration wizard (recommended)
#   setup   - Copy templates to user-config/ directory
#   check   - Check prerequisites
#   help    - Show this help
#
# WHAT IT DOES:
#   - Checks prerequisites (Podman, root access)
#   - Creates user-config/ directory with DNS templates
#   - Interactive wizard for customized configuration
#   - Generates named.conf and zone files from templates
#   - Sets up proper file permissions
#
# EXAMPLES:
#   # Interactive setup (recommended)
#   sudo ./tools/config-setup.sh wizard
#
#   # Manual setup
#   sudo ./tools/config-setup.sh setup
#   # Edit files in user-config/ directory
#
#   # Check if ready
#   sudo ./tools/config-setup.sh check
#
# REQUIREMENTS:
#   - Root privileges (sudo)
#   - Podman installed (use system-setup.sh first)
#   - config-examples/ directory present

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Custom header for this script
print_setup_header() {
    print_header "BindCaptain Setup"
}

# Check prerequisites
check_prerequisites() {
    print_status "info" "Checking prerequisites..."
    
    local missing=()
    
    # Check for podman
    if ! command -v podman &> /dev/null; then
        missing+=("podman")
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_status "error" "This script must be run as root (use sudo)"
        exit 1
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_status "error" "Missing required packages:"
        for pkg in "${missing[@]}"; do
            echo "  - $pkg"
        done
        echo
        print_status "info" "Install with: dnf install ${missing[*]}"
        exit 1
    fi
    
    print_status "success" "Prerequisites satisfied"
}

# Setup user configuration
setup_user_config() {
    print_status "info" "Setting up user configuration directory..."
    
    if [ -d "user-config" ] && [ "$(ls -A user-config)" ]; then
        print_status "warning" "user-config directory already exists and is not empty"
        read -p "Overwrite existing configuration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing configuration"
            return 0
        fi
        rm -rf user-config/*
    fi
    
    mkdir -p user-config
    
    # Copy template files
    cp config-examples/named.conf.template user-config/named.conf
    cp config-examples/example.com.db user-config/
    cp config-examples/reverse.in-addr.arpa.db user-config/
    
    print_status "success" "User configuration template created"
    
    echo
    print_status "info" "Next steps:"
    echo "  1. Edit user-config/named.conf with your settings:"
    echo "     - Replace YOUR_DNS_SERVER_IP with your server IP"
    echo "     - Replace YOUR_DOMAIN.com with your actual domain"
    echo "     - Replace YOUR_NETWORK with your network range"
    echo "     - Replace YOUR_SECONDARY_DNS_* with your secondary DNS servers"
    echo
    echo "  2. Create/edit zone files in user-config/:"
    echo "     - Rename example.com.db to yourdomain.com.db"
    echo "     - Update records for your hosts"
    echo "     - Create reverse zone files as needed"
    echo
    echo "  3. Run: sudo ./bindcaptain.sh run"
}

# Interactive configuration
interactive_config() {
    print_status "info" "Interactive configuration setup"
    echo
    
    # Get basic information
    echo -e "${YELLOW}Enter your DNS configuration details:${NC}"
    
    read -p "DNS Server IP (e.g., 192.0.2.10): " dns_ip
    read -p "Your Domain (e.g., example.com): " domain_name
    read -p "Your Network Range (e.g., 192.0.2.0/24): " network_range
    read -p "Secondary DNS 1 (optional): " secondary_dns1
    read -p "Secondary DNS 2 (optional): " secondary_dns2
    
    if [ -z "$dns_ip" ] || [ -z "$domain_name" ] || [ -z "$network_range" ]; then
        print_status "error" "DNS IP, domain name, and network range are required"
        exit 1
    fi
    
    print_status "info" "Creating customized configuration..."
    
    # Create user-config directory
    mkdir -p user-config
    
    # Create customized named.conf
    sed -e "s/YOUR_DNS_SERVER_IP/$dns_ip/g" \
        -e "s/YOUR_DOMAIN\.com/$domain_name/g" \
        -e "s/YOUR_NETWORK\/16/$network_range/g" \
        -e "s/YOUR_SECONDARY_DNS_1/${secondary_dns1:-127.0.0.1}/g" \
        -e "s/YOUR_SECONDARY_DNS_2/${secondary_dns2:-127.0.0.1}/g" \
        -e "s/YOUR_REVERSE_ZONE/$(echo $network_range | cut -d'.' -f1-2 | sed 's/\./ /g' | awk '{print $2"."$1}')/g" \
        config-examples/named.conf.template > user-config/named.conf
    
    # Create customized zone file
    sed -e "s/example\.com/$domain_name/g" \
        -e "s/172\.25\.50\.156/$dns_ip/g" \
        config-examples/example.com.db > "user-config/${domain_name}.db"
    
    # Create reverse zone file
    local reverse_zone="$(echo $network_range | cut -d'.' -f1-2 | sed 's/\./ /g' | awk '{print $2"."$1}').in-addr.arpa"
    sed -e "s/example\.com/$domain_name/g" \
        -e "s/25\.172/$reverse_zone/g" \
        -e "s/172\.25\.50\.156/$dns_ip/g" \
        config-examples/reverse.in-addr.arpa.db > "user-config/${reverse_zone}.db"
    
    print_status "success" "Customized configuration created"
    
    echo
    print_status "info" "Configuration created:"
    echo "  - user-config/named.conf"
    echo "  - user-config/${domain_name}.db"
    echo "  - user-config/${reverse_zone}.db"
    echo
    print_status "info" "You can now run: sudo ./bindcaptain.sh run"
}

# Show usage
show_help() {
    print_setup_header
    echo "BindCaptain Setup - Navigate DNS complexity with captain-grade precision"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  setup      - Copy templates from config-examples/ to config/"
    echo "  wizard     - Interactive configuration wizard"
    echo "  check      - Check prerequisites"
    echo "  help       - Show this help"
    echo
    echo "Examples:"
    echo "  sudo $0 setup     # Create templates in user-config/"
    echo "  sudo $0 wizard    # Interactive setup with your details"
    echo "  sudo $0 check     # Check if system is ready"
    echo
}

# Main execution
main() {
    local command=${1:-"help"}
    
    case $command in
        "setup")
            print_setup_header
            check_prerequisites
            setup_user_config
            ;;
            
        "wizard")
            print_setup_header
            check_prerequisites
            interactive_config
            ;;
            
        "check")
            print_setup_header
            check_prerequisites
            print_status "success" "System is ready for BIND DNS container"
            ;;
            
        "help"|"-h"|"--help")
            show_help
            ;;
            
        *)
            print_status "error" "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
