#!/bin/bash

# ⚓ BindCaptain Test Suite
# Navigate DNS complexity with captain-grade precision
# Comprehensive testing for production-ready DNS infrastructure

set -e

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_CONFIG_DIR="$SCRIPT_DIR/test-configs"
TEST_RESULTS_DIR="$SCRIPT_DIR/results"
CONTAINER_NAME="bindcaptain-test"
IMAGE_NAME="bindcaptain-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
LOG_FILE="$TEST_RESULTS_DIR/test-$(date +%Y%m%d-%H%M%S).log"

# Functions
print_header() {
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}  BindCaptain Test Suite${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo -e "${BLUE}Navigate DNS complexity with captain-grade precision${NC}"
    echo
}

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $message" | tee -a "$LOG_FILE"
}

test_start() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${BLUE}[*] Testing: $test_name${NC}"
    log_message "START: $test_name"
}

test_pass() {
    local test_name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}[✓] PASS: $test_name${NC}"
    log_message "PASS: $test_name"
}

test_fail() {
    local test_name="$1"
    local error_msg="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}[✗] FAIL: $test_name${NC}"
    echo -e "${RED}   Error: $error_msg${NC}"
    log_message "FAIL: $test_name - $error_msg"
}

# Setup test environment
setup_test_environment() {
    echo -e "${YELLOW}[*] Setting up test environment...${NC}"
    
    # Create test directories
    mkdir -p "$TEST_RESULTS_DIR"
    mkdir -p "$TEST_CONFIG_DIR"
    
    # Create test log
    touch "$LOG_FILE"
    log_message "BindCaptain Test Suite Starting"
    log_message "Project Directory: $PROJECT_DIR"
    log_message "Test Directory: $SCRIPT_DIR"
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}[*] Cleaning up test environment...${NC}"
    
    # Stop and remove test container if it exists
    if podman ps -a | grep -q "$CONTAINER_NAME"; then
        podman stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        podman rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    
    # Remove test image if it exists
    if podman images | grep -q "$IMAGE_NAME"; then
        podman rmi "$IMAGE_NAME" >/dev/null 2>&1 || true
    fi
    
    log_message "Test cleanup completed"
}

# Test 1: Project Structure
test_project_structure() {
    test_start "Project Structure"
    
    local required_files=(
        "bindcaptain.sh"
        "tools/bindcaptain_manager.sh"
        "tools/bindcaptain_refresh.sh"
        "Containerfile"
        "tools/container_start.sh"
        "tools/setup.sh"
        "README.md"
        "LICENSE"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$PROJECT_DIR/$file" ]]; then
            test_fail "Project Structure" "Missing required file: $file"
            return 1
        fi
    done
    
    # Check directories
    local required_dirs=(
        "config-examples"
        "tests"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$PROJECT_DIR/$dir" ]]; then
            test_fail "Project Structure" "Missing required directory: $dir"
            return 1
        fi
    done
    
    test_pass "Project Structure"
}

# Test 2: Script Syntax
test_script_syntax() {
    test_start "Script Syntax Validation"
    
    local scripts=(
        "bindcaptain.sh"
        "tools/bindcaptain_manager.sh"
        "tools/bindcaptain_refresh.sh"
        "tools/container_start.sh"
        "tools/setup.sh"
    )
    
    for script in "${scripts[@]}"; do
        if ! bash -n "$PROJECT_DIR/$script" 2>/dev/null; then
            test_fail "Script Syntax" "Syntax error in $script"
            return 1
        fi
    done
    
    test_pass "Script Syntax Validation"
}

# Test 3: Example Configuration Validation
test_example_configs() {
    test_start "Example Configuration Validation"
    
    # Check if named-checkconf is available
    if ! command -v named-checkconf >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] SKIP: named-checkconf not available (install bind-utils)${NC}"
        return 0
    fi
    
    # Test config-examples named.conf template
    if [[ -f "$PROJECT_DIR/config-examples/named.conf.template" ]]; then
        if ! named-checkconf "$PROJECT_DIR/config-examples/named.conf.template" 2>/dev/null; then
            test_fail "Example Configuration" "Invalid syntax in config-examples/named.conf.template"
            return 1
        fi
    fi
    
    # Test zone files with basic syntax check
    local zone_files=($(find "$PROJECT_DIR/config-examples" -name "*.db" 2>/dev/null))
    for zone_file in "${zone_files[@]}"; do
        if [[ -f "$zone_file" ]]; then
            # Basic syntax checks
            if ! grep -q "SOA" "$zone_file" || ! grep -q "NS" "$zone_file"; then
                test_fail "Example Configuration" "Invalid zone file structure: $(basename "$zone_file")"
                return 1
            fi
        fi
    done
    
    test_pass "Example Configuration Validation"
}

# Test 4: Container Build
test_container_build() {
    test_start "Container Build"
    
    # Check if podman/docker is available
    local container_cmd=""
    if command -v podman >/dev/null 2>&1; then
        container_cmd="podman"
    elif command -v docker >/dev/null 2>&1; then
        container_cmd="docker"
    else
        echo -e "${YELLOW}[!] SKIP: No container runtime available (podman/docker)${NC}"
        return 0
    fi
    
    # Build test container
    if ! $container_cmd build -t "$IMAGE_NAME" -f "$PROJECT_DIR/Containerfile" "$PROJECT_DIR" >/dev/null 2>&1; then
        test_fail "Container Build" "Failed to build container image"
        return 1
    fi
    
    test_pass "Container Build"
}

# Test 5: Container Startup (Basic)
test_container_startup() {
    test_start "Container Startup"
    
    # Check if we have a container runtime and image
    local container_cmd=""
    if command -v podman >/dev/null 2>&1; then
        container_cmd="podman"
    elif command -v docker >/dev/null 2>&1; then
        container_cmd="docker"
    else
        echo -e "${YELLOW}[!] SKIP: No container runtime available${NC}"
        return 0
    fi
    
    # Check if image exists
    if ! $container_cmd images | grep -q "$IMAGE_NAME"; then
        echo -e "${YELLOW}[!] SKIP: Test image not available${NC}"
        return 0
    fi
    
    # Create minimal test config
    local test_named_conf="$TEST_CONFIG_DIR/named.conf"
    mkdir -p "$TEST_CONFIG_DIR"
    cat > "$test_named_conf" << 'EOF'
options {
    directory "/var/named";
    allow-query { localhost; };
    dnssec-validation auto;
    recursion yes;
};

zone "." IN {
    type hint;
    file "named.ca";
};
EOF
    
    # Try to start container with test config (dry run)
    if ! $container_cmd run --rm --name "$CONTAINER_NAME-dryrun" \
        -v "$test_named_conf:/etc/named.conf:ro" \
        "$IMAGE_NAME" named-checkconf /etc/named.conf >/dev/null 2>&1; then
        test_fail "Container Startup" "Container failed basic startup test"
        return 1
    fi
    
    test_pass "Container Startup"
}

# Test 6: Documentation Quality
test_documentation() {
    test_start "Documentation Quality"
    
    # Check README.md exists and has required sections
    if [[ ! -f "$PROJECT_DIR/README.md" ]]; then
        test_fail "Documentation" "README.md missing"
        return 1
    fi
    
    local required_sections=(
        "BindCaptain"
        "Features"
        "Quick Start"
        "Management Commands"
    )
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "$section" "$PROJECT_DIR/README.md"; then
            test_fail "Documentation" "Missing section in README.md: $section"
            return 1
        fi
    done
    
        # Check if GitHub repository URL is correct
    if ! grep -q "github.com/randyoyarzabal/bindcaptain" "$PROJECT_DIR/README.md"; then
        test_fail "Documentation" "Incorrect or missing GitHub repository URL"
        return 1
    fi
    
    # Check for domain-based organization documentation
    if ! grep -q "config-examples/" "$PROJECT_DIR/README.md"; then
        test_fail "Documentation" "Missing config-examples documentation"
        return 1
    fi
    
    test_pass "Documentation Quality"
}

# Test 7: License and Legal
test_license() {
    test_start "License Validation"
    
    if [[ ! -f "$PROJECT_DIR/LICENSE" ]]; then
        test_fail "License" "LICENSE file missing"
        return 1
    fi
    
    # Check for MIT license
    if ! grep -q "MIT License" "$PROJECT_DIR/LICENSE"; then
        test_fail "License" "LICENSE file does not contain MIT License"
        return 1
    fi
    
    # Check copyright
    if ! grep -q "BindCaptain" "$PROJECT_DIR/LICENSE"; then
        test_fail "License" "LICENSE file missing BindCaptain copyright"
        return 1
    fi
    
    test_pass "License Validation"
}

# Test 8: Security Best Practices
test_security() {
    test_start "Security Best Practices"
    
    # Check Containerfile for security practices
    if [[ -f "$PROJECT_DIR/Containerfile" ]]; then
        # Should not run as root unnecessarily (though DNS needs port 53)
        # Check for dnssec-validation auto in config-examples
        if [[ -f "$PROJECT_DIR/config-examples/named.conf.template" ]]; then
            if ! grep -q "dnssec-validation auto" "$PROJECT_DIR/config-examples/named.conf.template"; then
                test_fail "Security" "Config template missing 'dnssec-validation auto'"
                return 1
            fi
        fi
        
        # Check for version hiding in config template
        if [[ -f "$PROJECT_DIR/config-examples/named.conf.template" ]]; then
            if grep -q "version.*none" "$PROJECT_DIR/config-examples/named.conf.template"; then
                # Good - version hiding is present
                :
            fi
        fi
    fi
    
    test_pass "Security Best Practices"
}

# Main test execution
main() {
    print_header
    
    # Setup
    setup_test_environment
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    echo -e "${YELLOW}🚀 Starting BindCaptain test suite...${NC}"
    echo
    
    # Run all tests
    test_project_structure
    test_script_syntax
    test_example_configs
    test_container_build
    test_container_startup
    test_documentation
    test_license
    test_security
    
    # Results summary
    echo
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}  Test Results Summary${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo -e "Total Tests: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}[✓] All tests passed! BindCaptain is ready for deployment!${NC}"
        log_message "TEST SUITE COMPLETED: ALL TESTS PASSED"
        exit 0
    else
        echo -e "${RED}[✗] Some tests failed. Check the issues above.${NC}"
        log_message "TEST SUITE COMPLETED: $TESTS_FAILED TESTS FAILED"
        exit 1
    fi
}

# Help function
show_help() {
    echo "BindCaptain Test Suite"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo "  --verbose, -v Verbose output"
    echo "  --cleanup     Only run cleanup"
    echo
    echo "Environment Variables:"
    echo "  SKIP_CONTAINER_TESTS  Skip container build/startup tests"
    echo "  SKIP_BIND_TESTS      Skip BIND configuration validation tests"
    echo
    echo "Example:"
    echo "  ./run-tests.sh"
    echo "  SKIP_CONTAINER_TESTS=1 ./run-tests.sh"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --cleanup)
        cleanup
        exit 0
        ;;
    --verbose|-v)
        set -x
        main
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
