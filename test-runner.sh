#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - TEST RUNNER
# =============================================================================
# Comprehensive test suite for validating the N8N AI Starter Kit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Print functions
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${CYAN}$1${NC}"; }

print_usage() {
    cat << EOF
Usage: $0 [TEST_SUITE] [OPTIONS]

Test suites:
    all                 Run all tests (default)
    unit               Unit tests only
    integration        Integration tests only
    config             Configuration validation
    services           Service health checks
    scripts            Script functionality tests
    
OPTIONS:
    --verbose          Verbose output
    --stop-on-fail     Stop on first failure
    --dry-run          Show what tests would run
    --timeout N        Test timeout in seconds (default: 30)
    --help             Show this help

EXAMPLES:
    $0                              # Run all tests
    $0 integration --verbose       # Run integration tests with verbose output
    $0 services --stop-on-fail     # Stop on first service test failure

EOF
}

# Test framework functions
test_start() {
    local test_name="$1"
    ((TESTS_TOTAL++))
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        print_info "Starting test: $test_name"
    fi
}

test_pass() {
    local test_name="$1"
    ((TESTS_PASSED++))
    print_success "$test_name"
}

test_fail() {
    local test_name="$1"
    local error_msg="${2:-}"
    ((TESTS_FAILED++))
    print_error "$test_name"
    
    if [[ -n "$error_msg" ]]; then
        echo "  Error: $error_msg"
    fi
    
    if [[ "${STOP_ON_FAIL:-false}" == "true" ]]; then
        print_error "Stopping on first failure (--stop-on-fail enabled)"
        exit 1
    fi
}

test_skip() {
    local test_name="$1"
    local reason="${2:-}"
    ((TESTS_SKIPPED++))
    print_warning "$test_name (SKIPPED)"
    
    if [[ -n "$reason" ]]; then
        echo "  Reason: $reason"
    fi
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local timeout="${3:-30}"
    
    test_start "$test_name"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        print_info "Would run: $test_command"
        test_pass "$test_name"
        return 0
    fi
    
    if timeout "$timeout" bash -c "$test_command" >/dev/null 2>&1; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Command failed or timed out"
        return 1
    fi
}

# Configuration tests
test_environment_schema() {
    print_header "Testing Environment Configuration"
    
    # Test env.schema exists and is valid
    run_test "Environment schema exists" "test -f '$PROJECT_ROOT/env.schema'"
    run_test "Template environment exists" "test -f '$PROJECT_ROOT/template.env'"
    
    # Test setup script functionality
    if [[ -x "$PROJECT_ROOT/scripts/setup.sh" ]]; then
        run_test "Setup script is executable" "true"
        run_test "Setup script dry-run" "$PROJECT_ROOT/scripts/setup.sh --dry-run --non-interactive"
    else
        test_fail "Setup script executable check" "Script not found or not executable"
    fi
    
    # Test docker-compose configuration
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        run_test "Docker Compose config validation" "cd '$PROJECT_ROOT' && docker compose config >/dev/null"
    else
        test_skip "Docker Compose validation" "Docker or Docker Compose not available"
    fi
}

test_required_files() {
    print_header "Testing Required Files"
    
    local required_files=(
        "README.md"
        "project.md"
        "docker-compose.yml"
        "compose-check.yml"
        "start.sh"
        "scripts/setup.sh"
        "scripts/create_n8n_credential.sh"
        "services/web-interface/main.py"
        "services/document-processor/main.py"
        "services/etl-processor/main.py"
    )
    
    for file in "${required_files[@]}"; do
        run_test "Required file: $file" "test -f '$PROJECT_ROOT/$file'"
    done
    
    # Test script permissions
    local executable_files=(
        "start.sh"
        "scripts/setup.sh"
        "scripts/create_n8n_credential.sh"
        "scripts/maintenance/backup.sh"
        "scripts/maintenance/restore.sh"
        "scripts/maintenance/monitor.sh"
    )
    
    for script in "${executable_files[@]}"; do
        run_test "Executable: $script" "test -x '$PROJECT_ROOT/$script'"
    done
}

# Service tests
test_service_health() {
    print_header "Testing Service Health"
    
    # Check if services are running
    local services=(
        "n8n:5678:/healthz"
        "web-interface:8000:/health"
        "document-processor:8001:/health"  
        "etl-processor:8002:/health"
        "grafana:3000:/api/health"
        "qdrant:6333:/health"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service port endpoint <<< "$service_info"
        
        if docker compose ps "$service" >/dev/null 2>&1; then
            run_test "Service health: $service" "curl -f -s -m 10 http://localhost:$port$endpoint"
        else
            test_skip "Service health: $service" "Service not running"
        fi
    done
}

test_database_connections() {
    print_header "Testing Database Connections"
    
    # Test PostgreSQL connection
    if docker compose ps postgres >/dev/null 2>&1; then
        run_test "PostgreSQL connection" "docker exec n8n-postgres pg_isready -U n8n_user -d n8n"
        run_test "PostgreSQL extensions" "docker exec n8n-postgres psql -U n8n_user -d n8n -c 'SELECT 1 FROM pg_extension WHERE extname IN ('"'"'pgvector'"'"', '"'"'uuid-ossp'"'"');' | grep -q '1'"
    else
        test_skip "PostgreSQL tests" "PostgreSQL not running"
    fi
    
    # Test Qdrant connection
    if docker compose ps qdrant >/dev/null 2>&1; then
        run_test "Qdrant connection" "curl -f -s http://localhost:6333/health"
        run_test "Qdrant collections" "curl -f -s http://localhost:6333/collections"
    else
        test_skip "Qdrant tests" "Qdrant not running"
    fi
}

# Integration tests
test_document_processing() {
    print_header "Testing Document Processing Integration"
    
    if ! docker compose ps document-processor >/dev/null 2>&1; then
        test_skip "Document processing tests" "Document processor not running"
        return 0
    fi
    
    # Create a test document
    local test_file="/tmp/test-document.txt"
    echo "This is a test document for the N8N AI Starter Kit integration test." > "$test_file"
    
    # Test document upload
    local upload_response
    if upload_response=$(curl -s -f -X POST "http://localhost:8001/docs/upload" -F "file=@$test_file" 2>/dev/null); then
        test_pass "Document upload API"
        
        # Extract document ID if possible
        if command -v jq >/dev/null 2>&1; then
            local doc_id=$(echo "$upload_response" | jq -r '.document_id // empty')
            if [[ -n "$doc_id" ]]; then
                # Test document status check
                run_test "Document status check" "curl -f -s http://localhost:8001/docs/$doc_id/status"
            fi
        fi
    else
        test_fail "Document upload API" "Upload request failed"
    fi
    
    # Test search endpoint
    run_test "Document search API" "curl -f -s -X POST http://localhost:8001/docs/search -H 'Content-Type: application/json' -d '{\"query\":\"test document\",\"limit\":5}'"
    
    # Cleanup
    rm -f "$test_file"
}

test_credential_management() {
    print_header "Testing Credential Management"
    
    local cred_script="$PROJECT_ROOT/scripts/create_n8n_credential.sh"
    
    if [[ ! -x "$cred_script" ]]; then
        test_fail "Credential script executable" "Script not found or not executable"
        return 0
    fi
    
    # Test script help
    run_test "Credential script help" "$cred_script --help"
    
    # Test dry-run functionality
    run_test "Credential creation (dry-run)" "$cred_script --dry-run --type postgres --name 'Test DB' --data '{\"host\":\"test\"}'"
    
    # Test credential listing (requires N8N to be running)
    if docker compose ps n8n >/dev/null 2>&1 && curl -f -s http://localhost:5678/healthz >/dev/null 2>&1; then
        # Only test if we have authentication configured
        if [[ -n "${N8N_PERSONAL_ACCESS_TOKEN:-}" ]] || [[ -n "${N8N_API_KEY:-}" ]]; then
            run_test "Credential listing" "$cred_script --list"
        else
            test_skip "Credential listing" "No N8N authentication configured"
        fi
    else
        test_skip "Credential management tests" "N8N not available"
    fi
}

# Script functionality tests
test_maintenance_scripts() {
    print_header "Testing Maintenance Scripts"
    
    # Test backup script
    local backup_script="$PROJECT_ROOT/scripts/maintenance/backup.sh"
    if [[ -x "$backup_script" ]]; then
        run_test "Backup script help" "$backup_script --help"
        run_test "Backup script dry-run" "$backup_script --dry-run"
    else
        test_fail "Backup script" "Script not found or not executable"
    fi
    
    # Test restore script
    local restore_script="$PROJECT_ROOT/scripts/maintenance/restore.sh"
    if [[ -x "$restore_script" ]]; then
        run_test "Restore script help" "$restore_script --help"
        run_test "Restore script list" "$restore_script list"
    else
        test_fail "Restore script" "Script not found or not executable"
    fi
    
    # Test monitoring script
    local monitor_script="$PROJECT_ROOT/scripts/maintenance/monitor.sh"
    if [[ -x "$monitor_script" ]]; then
        run_test "Monitor script help" "$monitor_script --help"
        run_test "Monitor script dry-run" "$monitor_script all --dry-run"
    else
        test_fail "Monitor script" "Script not found or not executable"
    fi
}

test_start_script() {
    print_header "Testing Start Script"
    
    local start_script="$PROJECT_ROOT/start.sh"
    
    if [[ ! -x "$start_script" ]]; then
        test_fail "Start script executable" "Script not found or not executable"
        return 0
    fi
    
    # Test help functionality
    run_test "Start script help" "$start_script --help"
    
    # Test status check (if services are running)
    if docker compose ps >/dev/null 2>&1; then
        run_test "Start script status" "$start_script status"
    else
        test_skip "Start script status" "No services running"
    fi
    
    # Test dry-run functionality
    run_test "Start script dry-run" "$start_script up --dry-run"
}

# Network and connectivity tests
test_network_connectivity() {
    print_header "Testing Network Connectivity"
    
    # Test Docker network
    if docker network ls | grep -q n8n-network; then
        test_pass "Docker network exists"
    else
        test_fail "Docker network exists" "n8n-network not found"
    fi
    
    # Test port accessibility
    local ports=(
        "5678:N8N"
        "6333:Qdrant"
        "5432:PostgreSQL"
        "3000:Grafana"
    )
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port service <<< "$port_info"
        
        if command -v nc >/dev/null 2>&1; then
            if nc -z localhost "$port" 2>/dev/null; then
                test_pass "Port accessibility: $service ($port)"
            else
                test_fail "Port accessibility: $service ($port)" "Port not accessible"
            fi
        else
            test_skip "Port accessibility: $service ($port)" "netcat not available"
        fi
    done
}

# Unit tests for Python services (if pytest is available)
test_python_services() {
    print_header "Testing Python Services"
    
    if ! command -v python3 >/dev/null 2>&1; then
        test_skip "Python service tests" "Python3 not available"
        return 0
    fi
    
    # Test service imports
    local services=(
        "services/web-interface"
        "services/document-processor"
        "services/etl-processor"
    )
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        
        if [[ -f "$PROJECT_ROOT/$service_dir/main.py" ]]; then
            # Test syntax by importing
            run_test "Python syntax: $service_name" "cd '$PROJECT_ROOT/$service_dir' && python3 -m py_compile main.py"
        else
            test_fail "Python service file" "$service_dir/main.py not found"
        fi
    done
}

# Print test summary
print_test_summary() {
    echo
    print_header "Test Summary"
    echo "  Total:   $TESTS_TOTAL"
    echo "  Passed:  $TESTS_PASSED"
    echo "  Failed:  $TESTS_FAILED"  
    echo "  Skipped: $TESTS_SKIPPED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo
        print_error "$TESTS_FAILED test(s) failed"
        return 1
    else
        echo
        print_success "All tests passed!"
        return 0
    fi
}

# Main function
main() {
    local test_suite="${1:-all}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            all|unit|integration|config|services|scripts)
                test_suite="$1"
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --stop-on-fail)
                STOP_ON_FAIL=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    print_header "N8N AI Starter Kit - Test Suite"
    echo "Running test suite: $test_suite"
    echo
    
    # Run tests based on suite
    case "$test_suite" in
        all)
            test_environment_schema
            test_required_files
            test_service_health
            test_database_connections
            test_document_processing
            test_credential_management
            test_maintenance_scripts
            test_start_script
            test_network_connectivity
            test_python_services
            ;;
        unit)
            test_environment_schema
            test_required_files
            test_python_services
            ;;
        integration)
            test_service_health
            test_database_connections
            test_document_processing
            test_credential_management
            test_network_connectivity
            ;;
        config)
            test_environment_schema
            test_required_files
            ;;
        services)
            test_service_health
            test_database_connections
            test_network_connectivity
            ;;
        scripts)
            test_maintenance_scripts
            test_start_script
            test_credential_management
            ;;
        *)
            print_error "Unknown test suite: $test_suite"
            exit 1
            ;;
    esac
    
    # Print summary and exit
    print_test_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi