#!/bin/bash

# BIND DNS Container Management Script
# Works with any user configuration - completely reusable

set -e

# Configuration
CONTAINER_NAME="bindcaptain"
IMAGE_NAME="bindcaptain"
IMAGE_TAG="latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths (can be overridden by user)
USER_CONFIG_DIR="${USER_CONFIG_DIR:-$SCRIPT_DIR/config}"
CONTAINER_DATA_DIR="${CONTAINER_DATA_DIR:-/opt/bindcaptain}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Icons
CHECK="✓"
CROSS="✗"

# Print colored status
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}${CHECK}${NC} $message" ;;
        "error") echo -e "${RED}${CROSS}${NC} $message" ;;
        "warning") echo -e "${YELLOW}${CROSS}${NC} $message" ;;
        "info") echo -e "${BLUE}${CHECK}${NC} $message" ;;
    esac
}

# Print header
print_header() {
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}  BIND DNS Container${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_status "error" "This script must be run as root (use sudo)"
        echo "  Container needs to bind to port 53 (privileged port)"
        exit 1
    fi
}

# Check if podman is installed
check_podman() {
    if ! command -v podman &> /dev/null; then
        print_status "error" "Podman is not installed"
        echo "  Install with: dnf install podman"
        exit 1
    fi
    print_status "success" "Podman is available"
}

# Validate user configuration directory
validate_user_config() {
    print_status "info" "Validating user configuration directory: $USER_CONFIG_DIR"
    
    if [ ! -d "$USER_CONFIG_DIR" ]; then
        print_status "error" "User configuration directory not found: $USER_CONFIG_DIR"
        echo "  Please create your configuration directory with:"
        echo "  mkdir -p $USER_CONFIG_DIR"
        echo "  cp config-examples/* $USER_CONFIG_DIR/"
        echo "  # Edit files in $USER_CONFIG_DIR/ for your setup"
        exit 1
    fi
    
    # Check for required files
    local required_files=("named.conf")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$USER_CONFIG_DIR/$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_status "error" "Missing required files in $USER_CONFIG_DIR:"
        for file in "${missing_files[@]}"; do
            echo "    - $file"
        done
        echo "  Copy examples: cp config-examples/* $USER_CONFIG_DIR/"
        exit 1
    fi
    
    # Validate named.conf
    if ! named-checkconf "$USER_CONFIG_DIR/named.conf"; then
        print_status "error" "Invalid BIND configuration in $USER_CONFIG_DIR/named.conf"
        exit 1
    fi
    
    # Count zone files
    local zone_count=$(find "$USER_CONFIG_DIR" -name "*.db" | wc -l)
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

# Create host directories
create_directories() {
    print_status "info" "Creating container data directories..."
    
    local dirs=(
        "$CONTAINER_DATA_DIR/config"
        "$CONTAINER_DATA_DIR/zones"
        "$CONTAINER_DATA_DIR/data"
        "$CONTAINER_DATA_DIR/logs"
        "$CONTAINER_DATA_DIR/scripts"
        "$CONTAINER_DATA_DIR/backups"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
    done
    
    print_status "success" "Container directories created at $CONTAINER_DATA_DIR"
}

# Copy user configuration to container directories
copy_user_config() {
    print_status "info" "Copying user configuration to container directories..."
    
    # Copy main configuration (preserve permissions)
    cp -p "$USER_CONFIG_DIR/named.conf" "$CONTAINER_DATA_DIR/config/"
    
    # Copy zone files (preserve permissions)
    find "$USER_CONFIG_DIR" -name "*.db" -exec cp -p {} "$CONTAINER_DATA_DIR/zones/" \;
    
    # Copy scripts if they exist
    if [ -d "$USER_CONFIG_DIR/scripts" ]; then
        cp "$USER_CONFIG_DIR/scripts"/* "$CONTAINER_DATA_DIR/scripts/" 2>/dev/null || true
    fi
    
    # Copy management scripts
    cp "$SCRIPT_DIR/tools/bindcaptain_manager.sh" "$CONTAINER_DATA_DIR/scripts/"
    cp "$SCRIPT_DIR/tools/bindcaptain_refresh.sh" "$CONTAINER_DATA_DIR/scripts/"
    
    # Set proper permissions
    chown -R root:root "$CONTAINER_DATA_DIR/config" "$CONTAINER_DATA_DIR/scripts"
    chown -R 25:25 "$CONTAINER_DATA_DIR/zones" "$CONTAINER_DATA_DIR/data" "$CONTAINER_DATA_DIR/logs" "$CONTAINER_DATA_DIR/backups"
    chmod 640 "$CONTAINER_DATA_DIR/config/named.conf"
    chmod 644 "$CONTAINER_DATA_DIR/zones"/*.db 2>/dev/null || true
    chmod +x "$CONTAINER_DATA_DIR/scripts"/*.sh 2>/dev/null || true
    
    print_status "success" "User configuration copied and permissions set"
}

# Auto-detect bind IP from named.conf
detect_bind_ip() {
    local bind_ip="172.25.50.156"  # Default fallback
    
    if [ -f "$USER_CONFIG_DIR/named.conf" ]; then
        # Try to extract listen-on IP
        local extracted_ip=$(grep -E "listen-on.*port.*53.*{" "$USER_CONFIG_DIR/named.conf" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
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
    
    # Run container with user's configuration mounted
    podman run -d \
        --name "$CONTAINER_NAME" \
        --hostname "ns1.$(basename $USER_CONFIG_DIR)" \
        -p "${bind_ip}:53:53/tcp" \
        -p "${bind_ip}:53:53/udp" \
        -v "$CONTAINER_DATA_DIR/config/named.conf:/etc/named.conf:ro,Z" \
        -v "$CONTAINER_DATA_DIR/zones:/var/named:rw,Z" \
        -v "$CONTAINER_DATA_DIR/data:/var/named/data:rw,Z" \
        -v "$CONTAINER_DATA_DIR/logs:/var/log/named:rw,Z" \
        -v "$CONTAINER_DATA_DIR/scripts:/usr/local/scripts:ro,Z" \
        -v "$CONTAINER_DATA_DIR/backups:/var/backups/bind:rw,Z" \
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
        if [ -f "$USER_CONFIG_DIR/named.conf" ]; then
            local test_zone=$(grep -E '^[[:space:]]*zone[[:space:]]+\"' "$USER_CONFIG_DIR/named.conf" | grep -v '"\."' | head -1 | sed 's/.*zone[[:space:]]*"\([^"]*\)".*/\1/')
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
    echo "  User Config: $USER_CONFIG_DIR"
    echo "  Container Data: $CONTAINER_DATA_DIR"
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
show_help() {
    print_header
    echo "BIND DNS Container Management"
    echo
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Environment Variables:"
    echo "  USER_CONFIG_DIR      - Directory with your BIND configuration (default: ./config)"
    echo "  CONTAINER_DATA_DIR   - Container data directory (default: /opt/bind-dns)"
    echo "  BIND_DEBUG_LEVEL     - BIND debug level (default: 1)"
    echo "  TZ                   - Timezone (default: UTC)"
    echo
    echo "Commands:"
    echo "  build         - Build the container image"
    echo "  run           - Run the container (builds if needed)"
    echo "  stop          - Stop the container"
    echo "  restart       - Restart the container"
    echo "  logs          - Show container logs"
    echo "  status        - Show container status"
    echo "  shell         - Enter container shell"
    echo "  cleanup       - Remove container and image"
    echo "  validate      - Validate user configuration"
    echo "  help          - Show this help"
    echo
    echo "Examples:"
    echo "  # Use default config directory"
    echo "  sudo $0 run"
    echo
    echo "  # Use custom configuration directory"
    echo "  USER_CONFIG_DIR=/path/to/my/dns-config sudo $0 run"
    echo
    echo "  # Use custom data directory"
    echo "  CONTAINER_DATA_DIR=/opt/my-dns sudo $0 run"
    echo
}

# Main execution
main() {
    local command=${1:-"help"}
    
    case $command in
        "build")
            print_header
            check_root
            check_podman
            build_container
            ;;
            
        "run")
            print_header
            check_root
            check_podman
            validate_user_config
            stop_container
            build_container
            create_directories
            copy_user_config
            run_container
            check_status
            show_info
            ;;
            
        "stop")
            print_header
            check_root
            print_status "info" "Stopping container..."
            if podman stop "$CONTAINER_NAME" 2>/dev/null; then
                print_status "success" "Container stopped"
            else
                print_status "warning" "Container was not running"
            fi
            ;;
            
        "restart")
            print_header
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
            print_header
            print_status "info" "Showing container logs (Ctrl+C to exit)..."
            echo
            podman logs -f "$CONTAINER_NAME"
            ;;
            
        "status")
            print_header
            check_status
            show_info
            ;;
            
        "shell")
            print_header
            print_status "info" "Entering container shell..."
            podman exec -it "$CONTAINER_NAME" /bin/bash
            ;;
            
        "cleanup")
            print_header
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
            print_header
            validate_user_config
            print_status "success" "User configuration is valid"
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
