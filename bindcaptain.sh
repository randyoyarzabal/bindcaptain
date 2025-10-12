#!/bin/bash

# BIND DNS Container Management Script
# Works with any user configuration - completely reusable

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/tools/common.sh"

# Configuration
IMAGE_NAME="bindcaptain"
IMAGE_TAG="latest"

# Default paths (can be overridden by user)
BINDCAPTAIN_CONFIG_PATH="${BINDCAPTAIN_CONFIG_PATH:-$SCRIPT_DIR/config}"
# Direct mount from bindcaptain directory - no staging needed

# Custom header for this script
print_bindcaptain_header() {
    print_header "BIND DNS Container"
}

# Validate user configuration directory
validate_user_config() {
    print_status "info" "Validating user configuration directory: $BINDCAPTAIN_CONFIG_PATH"
    
    if [ ! -d "$BINDCAPTAIN_CONFIG_PATH" ]; then
        print_status "error" "User configuration directory not found: $BINDCAPTAIN_CONFIG_PATH"
        echo "  Please create your configuration directory with:"
        echo "  mkdir -p $BINDCAPTAIN_CONFIG_PATH"
        echo "  cp config-examples/* $BINDCAPTAIN_CONFIG_PATH/"
        echo "  # Or use: sudo ./tools/config-setup.sh wizard"
        echo "  # Edit files in $BINDCAPTAIN_CONFIG_PATH/ for your setup"
        exit 1
    fi
    
    # Check for required files
    local required_files=("named.conf")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$BINDCAPTAIN_CONFIG_PATH/$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_status "error" "Missing required files in $BINDCAPTAIN_CONFIG_PATH:"
        for file in "${missing_files[@]}"; do
            echo "    - $file"
        done
        echo "  Copy examples: cp config-examples/* $BINDCAPTAIN_CONFIG_PATH/"
        exit 1
    fi
    
    # Validate named.conf using common function
    if ! validate_bind_config "$BINDCAPTAIN_CONFIG_PATH/named.conf"; then
        exit 1
    fi
    
    # Count zone files
    local zone_count=$(find "$BINDCAPTAIN_CONFIG_PATH" -name "*.db" | wc -l)
    print_status "success" "Configuration validated ($zone_count zone files found)"
}

# Build container image
build_container() {
    print_status "info" "Building BIND DNS container..."
    
    cd "$SCRIPT_DIR"
    
    if podman build \
        --layers \
        --force-rm \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        -f Containerfile .; then
        print_status "success" "Container image built successfully"
        
        # Show image size
        local size=$(podman images --format "{{.Size}}" "${IMAGE_NAME}:${IMAGE_TAG}")
        print_status "info" "Final image size: $size"
    else
        print_status "error" "Failed to build container image"
        exit 1
    fi
}

# Stop and remove existing container
stop_container() {
    print_status "info" "Checking for existing container..."
    
    if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_status "warning" "Stopping existing container..."
        podman stop "$CONTAINER_NAME" 2>/dev/null || true
        
        print_status "warning" "Removing existing container..."
        podman rm "$CONTAINER_NAME" 2>/dev/null || true
        
        print_status "success" "Existing container removed"
    else
        print_status "info" "No existing container found"
    fi
}

# Prepare configuration for direct mounting
prepare_config() {
    print_status "info" "Preparing configuration for direct mounting..."
    
    # Ensure proper permissions on source config files
    sudo chown -R named:named "$BINDCAPTAIN_CONFIG_PATH"
    sudo chmod 644 "$BINDCAPTAIN_CONFIG_PATH/named.conf"
    sudo chmod 644 "$BINDCAPTAIN_CONFIG_PATH"/*/*.db 2>/dev/null || true
    
    # Create necessary directories for container operation
    mkdir -p "$BINDCAPTAIN_CONFIG_PATH/data" "$BINDCAPTAIN_CONFIG_PATH/logs"
    sudo chown -R named:named "$BINDCAPTAIN_CONFIG_PATH/data" "$BINDCAPTAIN_CONFIG_PATH/logs"
    
    print_status "success" "Configuration prepared for direct mounting"
}

# No longer needed - mounting directly from source

# Auto-detect bind IP from named.conf
detect_bind_ip() {
    local bind_ip="172.25.50.156"  # Default fallback
    
    if [ -f "$BINDCAPTAIN_CONFIG_PATH/named.conf" ]; then
        # Try to extract listen-on IP
        local extracted_ip=$(grep -E "listen-on.*port.*53.*{" "$BINDCAPTAIN_CONFIG_PATH/named.conf" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$extracted_ip" ]; then
            bind_ip="$extracted_ip"
        fi
    fi
    
    echo "$bind_ip"
}

# Run container
run_container() {
    local bind_ip=$(detect_bind_ip)
    
    print_status "info" "Starting BIND DNS container on $bind_ip:53..."
    
    # Run container with direct mounting from source config
    podman run -d \
        --name "$CONTAINER_NAME" \
        --hostname "ns1.$(basename $BINDCAPTAIN_CONFIG_PATH)" \
        -p "${bind_ip}:53:53/tcp" \
        -p "${bind_ip}:53:53/udp" \
        -v "$BINDCAPTAIN_CONFIG_PATH/named.conf:/etc/named.conf:ro,Z" \
        -v "$BINDCAPTAIN_CONFIG_PATH:/var/named:rw,Z" \
        -v "$BINDCAPTAIN_CONFIG_PATH/data:/var/named/data:rw,Z" \
        -v "$BINDCAPTAIN_CONFIG_PATH/logs:/var/log/named:rw,Z" \
        -v "$SCRIPT_DIR/tools:/usr/local/scripts:ro,Z" \
        --env TZ="${TZ:-UTC}" \
        --env BIND_USER=named \
        --env BIND_DEBUG_LEVEL="${BIND_DEBUG_LEVEL:-1}" \
        --restart unless-stopped \
        --cap-add NET_BIND_SERVICE \
        --security-opt label=disable \
        "${IMAGE_NAME}:${IMAGE_TAG}"
    
    if [ $? -eq 0 ]; then
        print_status "success" "Container started successfully"
    else
        print_status "error" "Failed to start container"
        exit 1
    fi
}

# Check container status and test DNS
check_status() {
    print_status "info" "Checking container status..."
    
    if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_status "success" "Container is running"
        
        # Wait for DNS to start
        sleep 5
        
        # Test DNS resolution
        local bind_ip=$(detect_bind_ip)
        local test_passed=false
        
        # Try to find a zone to test
        if [ -f "$BINDCAPTAIN_CONFIG_PATH/named.conf" ]; then
            local test_zone=$(grep -E '^[[:space:]]*zone[[:space:]]+\"' "$BINDCAPTAIN_CONFIG_PATH/named.conf" | grep -v '"\."' | head -1 | sed 's/.*zone[[:space:]]*"\([^"]*\)".*/\1/')
            if [ -n "$test_zone" ]; then
                if dig "@$bind_ip" "$test_zone" SOA +short >/dev/null 2>&1; then
                    print_status "success" "DNS is responding correctly for zone: $test_zone"
                    test_passed=true
                fi
            fi
        fi
        
        if [ "$test_passed" = false ]; then
            if dig "@$bind_ip" . NS +short >/dev/null 2>&1; then
                print_status "success" "DNS server is responding"
            else
                print_status "warning" "DNS may not be fully ready yet"
            fi
        fi
    else
        print_status "error" "Container is not running"
        exit 1
    fi
}

# Show container information
show_info() {
    local bind_ip=$(detect_bind_ip)
    
    echo
    print_status "info" "Container Information:"
    echo "  Name: $CONTAINER_NAME"
    echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "  DNS IP: $bind_ip:53"
    echo "  User Config: $BINDCAPTAIN_CONFIG_PATH"
    echo "  Mount Source: $BINDCAPTAIN_CONFIG_PATH (direct mount)"
    echo
    
    print_status "info" "Useful Commands:"
    echo "  View logs:       sudo podman logs -f $CONTAINER_NAME"
    echo "  Enter container: sudo podman exec -it $CONTAINER_NAME bash"
    echo "  Stop container:  sudo podman stop $CONTAINER_NAME"
    echo "  Restart:         sudo podman restart $CONTAINER_NAME"
    echo "  Test DNS:        dig @$bind_ip \$(first_zone_name)"
    echo "  Manage DNS:      sudo podman exec $CONTAINER_NAME /usr/local/scripts/bindcaptain_manager.sh"
    echo
}

# Show help
# Systemctl service management functions
install_service() {
    print_bindcaptain_header
    check_root
    check_podman
    
    local service_file="/etc/systemd/system/bindcaptain.service"
    local script_path="/opt/bindcaptain/bindcaptain.sh"
    local install_dir="/opt/bindcaptain"
    local config_dir="$install_dir/config"
    
    print_status "info" "Installing BindCaptain systemd service..."
    
    # Create /opt/bindcaptain directory if it doesn't exist
    if [ ! -d "$install_dir" ]; then
        print_status "info" "Creating installation directory: $install_dir"
        mkdir -p "$install_dir"
    fi
    
    # Copy script to /opt/bindcaptain
    print_status "info" "Installing script to $script_path..."
    cp "$SCRIPT_DIR/bindcaptain.sh" "$script_path"
    chmod +x "$script_path"
    
    # Copy service file
    print_status "info" "Installing service file to $service_file..."
    cp "$SCRIPT_DIR/bindcaptain.service" "$service_file"
    
    # Create config directory if it doesn't exist
    if [ ! -d "$config_dir" ]; then
        print_status "info" "Creating config directory: $config_dir"
        mkdir -p "$config_dir"
        
        # Copy example configs if they exist
        if [ -d "$SCRIPT_DIR/config-examples" ]; then
            print_status "info" "Copying example configurations..."
            cp -r "$SCRIPT_DIR/config-examples"/* "$config_dir/"
        fi
    fi
    
    # Reload systemd
    print_status "info" "Reloading systemd daemon..."
    systemctl daemon-reload
    
    print_status "success" "Service installed successfully!"
    echo
    echo "Next steps:"
    echo "1. Configure your DNS settings in $config_dir"
    echo "2. Enable the service: sudo systemctl enable bindcaptain"
    echo "3. Start the service: sudo systemctl start bindcaptain"
    echo "4. Check status: sudo systemctl status bindcaptain"
    echo
    echo "Service management:"
    echo "  sudo systemctl start bindcaptain    # Start service"
    echo "  sudo systemctl stop bindcaptain     # Stop service"
    echo "  sudo systemctl restart bindcaptain  # Restart service"
    echo "  sudo systemctl status bindcaptain   # Check status"
    echo "  sudo systemctl enable bindcaptain   # Enable at boot"
    echo "  sudo systemctl disable bindcaptain  # Disable at boot"
}

uninstall_service() {
    print_bindcaptain_header
    check_root
    
    print_status "info" "Uninstalling BindCaptain systemd service..."
    
    # Stop and disable service
    systemctl stop bindcaptain 2>/dev/null || true
    systemctl disable bindcaptain 2>/dev/null || true
    
    # Remove service file
    rm -f /etc/systemd/system/bindcaptain.service
    
    # Reload systemd
    systemctl daemon-reload
    
    print_status "success" "Service uninstalled successfully"
}

enable_service() {
    print_bindcaptain_header
    check_root
    
    print_status "info" "Enabling BindCaptain service to start at boot..."
    systemctl enable bindcaptain
    print_status "success" "Service enabled for startup"
}

disable_service() {
    print_bindcaptain_header
    check_root
    
    print_status "info" "Disabling BindCaptain service from starting at boot..."
    systemctl disable bindcaptain
    print_status "success" "Service disabled from startup"
}

start_service() {
    print_bindcaptain_header
    check_root
    
    print_status "info" "Starting BindCaptain service..."
    systemctl start bindcaptain
    print_status "success" "Service started"
}

stop_service() {
    print_bindcaptain_header
    check_root
    
    print_status "info" "Stopping BindCaptain service..."
    systemctl stop bindcaptain
    print_status "success" "Service stopped"
}

restart_service() {
    print_bindcaptain_header
    check_root
    
    print_status "info" "Restarting BindCaptain service..."
    systemctl restart bindcaptain
    print_status "success" "Service restarted"
}

show_service_status() {
    print_bindcaptain_header
    print_status "info" "BindCaptain service status:"
    echo
    systemctl status bindcaptain --no-pager
}

show_help() {
    print_bindcaptain_header
    echo "BIND DNS Container Management"
    echo
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Environment Variables:"
    echo "  BINDCAPTAIN_CONFIG_PATH      - Directory with your BIND configuration (default: ./config)"
    echo "  BIND_DEBUG_LEVEL     - BIND debug level (default: 1)"
    echo "  TZ                   - Timezone (default: UTC)"
    echo
    echo "Container Commands:"
    echo "  build         - Build the container image"
    echo "  run           - Run the container (builds if needed)"
    echo "  stop          - Stop the container"
    echo "  restart       - Restart the container"
    echo "  logs          - Show container logs"
    echo "  status        - Show container status"
    echo "  shell         - Enter container shell"
    echo "  cleanup       - Remove container and image"
    echo "  validate      - Validate user configuration"
    echo
    echo "Service Commands:"
    echo "  install       - Install systemd service"
    echo "  uninstall     - Uninstall systemd service"
    echo "  enable        - Enable service to start at boot"
    echo "  disable       - Disable service from starting at boot"
    echo "  start         - Start the service"
    echo "  stop-service  - Stop the service"
    echo "  restart       - Restart the service"
    echo "  service-status - Show service status"
    echo
    echo "First Time Setup:"
    echo "  System Setup:    sudo ./tools/system-setup.sh"
    echo "  Config Setup:    sudo ./tools/config-setup.sh wizard"
    echo "  Manual Setup:    See docs/manual-setup.md for other distributions"
    echo "  The script will offer to install the systemd service"
    echo "  when 'run' is executed as root and service is not found."
    echo
    echo "Examples:"
    echo "  # First time setup (will prompt for service installation)"
    echo "  sudo $0 run"
    echo
    echo "  # Manual service installation"
    echo "  sudo $0 install"
    echo "  sudo $0 enable"
    echo "  sudo $0 start"
    echo
    echo "  # Use custom configuration directory"
    echo "  BINDCAPTAIN_CONFIG_PATH=/path/to/my/dns-config sudo $0 run"
    echo
}

# Check if service is installed and offer installation for run command
check_and_install_service() {
    if [ ! -f "/etc/systemd/system/bindcaptain.service" ] && [ "$EUID" -eq 0 ]; then
        echo
        print_status "info" "Systemd service not found."
        echo "BindCaptain can be installed as a systemd service for automatic startup."
        echo
        read -p "Would you like to install the systemd service? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_service
            echo
            read -p "Would you like to enable and start the service now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                systemctl enable bindcaptain
                systemctl start bindcaptain
                print_status "success" "Service enabled and started!"
                echo "Check status with: systemctl status bindcaptain"
            fi
            echo
        fi
    fi
}

# Main execution
main() {
    local command=${1:-"help"}
    
    # Check for service installation for run command
    if [ "$command" == "run" ] && [ "$EUID" -eq 0 ]; then
        check_and_install_service
    fi
    
    case $command in
        "build")
            print_bindcaptain_header
            check_root
            check_podman
            build_container
            ;;
            
        "run")
            print_bindcaptain_header
            check_root
            check_podman
            validate_user_config
            stop_container
            build_container
            prepare_config
            run_container
            check_status
            show_info
            ;;
            
        "stop")
            print_bindcaptain_header
            check_root
            print_status "info" "Stopping container..."
            if podman stop "$CONTAINER_NAME" 2>/dev/null; then
                print_status "success" "Container stopped"
            else
                print_status "warning" "Container was not running"
            fi
            ;;
            
        "restart")
            print_bindcaptain_header
            check_root
            print_status "info" "Restarting container..."
            if podman restart "$CONTAINER_NAME" 2>/dev/null; then
                print_status "success" "Container restarted"
                sleep 5
                check_status
            else
                print_status "error" "Failed to restart container"
            fi
            ;;
            
        "logs")
            print_bindcaptain_header
            print_status "info" "Showing container logs (Ctrl+C to exit)..."
            echo
            podman logs -f "$CONTAINER_NAME"
            ;;
            
        "status")
            print_bindcaptain_header
            check_status
            show_info
            ;;
            
        "shell")
            print_bindcaptain_header
            print_status "info" "Entering container shell..."
            podman exec -it "$CONTAINER_NAME" /bin/bash
            ;;
            
        "cleanup")
            print_bindcaptain_header
            check_root
            print_status "warning" "This will remove the container and image"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                podman stop "$CONTAINER_NAME" 2>/dev/null || true
                podman rm "$CONTAINER_NAME" 2>/dev/null || true
                podman rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
                print_status "success" "Cleanup completed"
            else
                print_status "info" "Cleanup cancelled"
            fi
            ;;
            
        "validate")
            print_bindcaptain_header
            validate_user_config
            print_status "success" "User configuration is valid"
            ;;
            
        "install")
            install_service
            ;;
            
        "uninstall")
            uninstall_service
            ;;
            
        "enable")
            enable_service
            ;;
            
        "disable")
            disable_service
            ;;
            
        "start")
            start_service
            ;;
            
        "stop-service")
            stop_service
            ;;
            
        "restart")
            restart_service
            ;;
            
        "service-status")
            show_service_status
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
