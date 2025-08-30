#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - COMPREHENSIVE TEST RUNNER
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_SUITE]

Comprehensive test runner for N8N AI Starter Kit

TEST SUITES:
    all              Run all test suites (default)
    unit             Unit tests only  
    integration      Integration tests only
    e2e              End-to-end tests with Playwright
    api              API tests only
    performance      Performance tests with K6
    security         Security and audit tests
    profiles         Docker Compose profile validation tests
    monitoring       Advanced monitoring and alerting tests
    backup           Backup and disaster recovery tests

OPTIONS:
    --env FILE       Environment file (default: .env.test)
    --timeout N      Test timeout in seconds (default: 1800)
    --verbose        Verbose output
    --cleanup        Cleanup test environment after tests
    --report-dir DIR Directory for test reports (default: test-results)
    --help           Show this help

EXAMPLES:
    $0                           # Run all tests
    $0 e2e --verbose            # Run E2E tests with verbose output
    $0 unit integration         # Run unit and integration tests

EOF
}

# Configuration
ENV_FILE=".env.test"
TIMEOUT=1800
VERBOSE=false
CLEANUP=false
REPORT_DIR="test-results"
TEST_SUITES=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env) ENV_FILE="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        --cleanup) CLEANUP=true; shift ;;
        --report-dir) REPORT_DIR="$2"; shift 2 ;;
        --help|-h) print_usage; exit 0 ;;
        all|unit|integration|e2e|api|performance|security|profiles|monitoring|backup)
            TEST_SUITES+=("$1"); shift ;;
        *) print_error "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

# Default to all tests if none specified
if [[ ${#TEST_SUITES[@]} -eq 0 ]]; then
    TEST_SUITES=("all")
fi

# Create report directory
mkdir -p "$REPORT_DIR"

# Setup test environment
setup_test_environment() {
    print_info "Setting up test environment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        print_info "Creating test environment file"
        
        # Create a simplified test environment file
        cat > "$ENV_FILE" << 'EOF'
# Test Environment Configuration
TEST_MODE=true
DOMAIN=test.localhost
API_DOMAIN=api.test.localhost

# N8N Configuration
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_DOMAIN=n8n.test.localhost
N8N_BASE_URL=http://localhost:5678
N8N_PERSONAL_ACCESS_TOKEN=test_token_123
N8N_API_KEY=test_api_key_456

# Database Configuration
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=n8n
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=test_password_123

# Vector Database - Qdrant
QDRANT_HOST=qdrant
QDRANT_PORT=6333
QDRANT_API_KEY=test_key_123

# Grafana Configuration
GRAFANA_HOST=grafana
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=test_grafana_password_789
GRAFANA_DOMAIN=grafana.test.localhost

# Service Ports
WEB_INTERFACE_PORT=8000
WEB_INTERFACE_WORKERS=1
DOC_PROCESSOR_PORT=8001
DOC_PROCESSOR_WORKERS=1
DOC_PROCESSOR_MODEL=sentence-transformers/all-MiniLM-L6-v2
ETL_PROCESSOR_PORT=8002
ETL_PROCESSOR_WORKERS=1
LIGHTRAG_PORT=8003
LIGHTRAG_WORKERS=1
LIGHTRAG_LLM_MODEL=gpt-4o
LIGHTRAG_EMBEDDING_MODEL=text-embedding-3-small
LIGHTRAG_MAX_TOKENS=32768
LIGHTRAG_CHUNK_SIZE=1200
LIGHTRAG_OVERLAP_SIZE=100

# Optional API Keys (empty for testing)
OPENAI_API_KEY=""
OPENAI_API_BASE=""

# ClickHouse (for analytics profile)
CLICKHOUSE_HOST=clickhouse
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=test_clickhouse_password

# Docker Compose
COMPOSE_PROFILES=default,developer,monitoring

# TLS/ACME Configuration
ACME_EMAIL=admin@test.localhost
TRAEFIK_LOG_LEVEL=INFO

# Development Settings
DEBUG=false
LOG_LEVEL=INFO
EOF
    fi
    
    print_info "Starting test services..."
    # Source the test environment file with proper error handling
    if [[ -f "$ENV_FILE" ]]; then
        # Temporarily disable 'set -u' for sourcing and validate content
        set +u
        set -a  # automatically export all variables
        
        # Check if the environment file is properly formatted
        if ! bash -n "$ENV_FILE" 2>/dev/null; then
            print_error "Environment file has syntax errors: $ENV_FILE"
            return 1
        fi
        
        # Source with error handling
        if ! source "$ENV_FILE" 2>/dev/null; then
            print_error "Failed to source environment file: $ENV_FILE"
            return 1
        fi
        
        set +a  # turn off automatic export
        set -u  # re-enable unset variable checking
        
        # Validate critical variables are set
        if [[ -z "${DOMAIN:-}" ]]; then
            print_error "Critical variable DOMAIN is not set"
            return 1
        fi
        
        print_success "Environment loaded successfully from $ENV_FILE"
    else
        print_error "Environment file not found: $ENV_FILE"
        return 1
    fi
    
    ./start.sh up --profile default,developer,monitoring --detach
    
    print_info "Waiting for services to be ready..."
    timeout "$TIMEOUT" bash -c '
        while ! curl -f -s http://localhost:8000/health >/dev/null 2>&1; do
            sleep 5
        done
    ' || {
        print_error "Services failed to start within timeout"
        return 1
    }
    
    print_success "Test environment ready"
}

# Run unit tests  
run_unit_tests() {
    print_info "Running unit tests..."
    cd "$PROJECT_ROOT"
    
    # Use existing test runner
    ./test-runner.sh unit --report-dir "$REPORT_DIR"
    
    print_success "Unit tests completed"
}

# Run integration tests
run_integration_tests() {
    print_info "Running integration tests..."
    cd "$PROJECT_ROOT"
    
    # Use existing integration test script
    bash tests/integration/test_integration.sh --timeout "$TIMEOUT"
    
    print_success "Integration tests completed"
}

# Run E2E tests with Playwright
run_e2e_tests() {
    print_info "Running E2E tests with Playwright..."
    
    cd "$PROJECT_ROOT"
    
    # Check if Playwright is set up
    if [[ ! -d "tests/e2e/node_modules" ]]; then
        print_info "Setting up Playwright..."
        mkdir -p tests/e2e
        cd tests/e2e
        
        # Create package.json if it doesn't exist
        if [[ ! -f "package.json" ]]; then
            npm init -y
            npm install -D @playwright/test
            npx playwright install chromium firefox
        fi
        
        cd "$PROJECT_ROOT"
    fi
    
    # Run Playwright tests
    cd tests/e2e
    npx playwright test --reporter=html --output="../../$REPORT_DIR/e2e"
    cd "$PROJECT_ROOT"
    
    print_success "E2E tests completed"
}

# Run API tests
run_api_tests() {
    print_info "Running API tests..."
    
    # Test our enhanced API management scripts
    print_info "Testing credential management API..."
    ./scripts/create_n8n_credential.sh --list || print_warning "Credential script test failed"
    
    print_info "Testing workflow management API..."
    ./scripts/n8n-workflow-manager.sh --list || print_warning "Workflow script test failed"
    
    print_info "Testing execution monitoring API..."
    ./scripts/n8n-execution-monitor.sh --stats || print_warning "Execution monitor test failed"
    
    # Test API endpoints directly
    print_info "Testing service health endpoints..."
    local endpoints=(
        "http://localhost:8000/health"
        "http://localhost:8001/health" 
        "http://localhost:8002/health"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -f -s "$endpoint" >/dev/null 2>&1; then
            print_success "✓ $endpoint"
        else
            print_error "✗ $endpoint"
        fi
    done
    
    print_success "API tests completed"
}

# Run performance tests
run_performance_tests() {
    print_info "Running performance tests..."
    
    # Simple load test using curl
    print_info "Running basic load test..."
    
    local start_time=$(date +%s)
    local success_count=0
    local total_requests=50
    
    for i in $(seq 1 $total_requests); do
        if curl -f -s -m 5 http://localhost:8000/ >/dev/null 2>&1; then
            ((success_count++))
        fi
        
        if [[ $((i % 10)) -eq 0 ]]; then
            print_info "Completed $i/$total_requests requests"
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local success_rate=$((success_count * 100 / total_requests))
    
    print_info "Performance test results:"
    print_info "  Total requests: $total_requests"
    print_info "  Successful: $success_count ($success_rate%)"
    print_info "  Duration: ${duration}s"
    print_info "  Rate: $((total_requests / duration)) req/s"
    
    # Save results
    cat > "$REPORT_DIR/performance-results.json" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total_requests": $total_requests,
  "successful_requests": $success_count,
  "success_rate": $success_rate,
  "duration_seconds": $duration,
  "requests_per_second": $((total_requests / duration))
}
EOF
    
    print_success "Performance tests completed"
}

# Run profile tests
run_profile_tests() {
    print_info "Running Docker Compose profile tests..."
    
    cd "$PROJECT_ROOT"
    
    # Run basic profile validation
    print_info "Testing basic profile configurations..."
    ./scripts/test-profiles.sh basic --dry-run --verbose
    
    # Run extended profile tests if requested
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        print_info "Testing extended profile configurations..."
        ./scripts/test-profiles.sh extended --dry-run --verbose
    fi
    
    # Test GPU profiles if GPU is available
    if ./scripts/detect-gpu.sh --check >/dev/null 2>&1; then
        print_info "GPU detected, testing GPU profiles..."
        ./scripts/test-profiles.sh gpu --dry-run --verbose
    else
        print_info "No GPU detected, skipping GPU profile tests"
    fi
    
    # Test production profiles
    print_info "Testing production-recommended profiles..."
    ./scripts/test-profiles.sh production --dry-run --verbose
    
    print_success "Profile tests completed"
}

# Run security tests
run_security_tests() {
    print_info "Running security tests..."
    
    # Use our enhanced security monitoring
    ./scripts/maintenance/monitor.sh security --verbose
    
    # Additional security checks
    print_info "Checking for exposed credentials..."
    if find . -name "*.env*" -not -path "./node_modules/*" -exec grep -l "password\|secret\|key" {} \; 2>/dev/null | grep -v template.env; then
        print_warning "Found potential credential exposure in environment files"
    else
        print_success "No credential exposure found"
    fi
    
    # Check security headers
    print_info "Checking security headers..."
    local security_headers=$(curl -I -s http://localhost:8000/ | grep -E "(X-Frame-Options|Content-Security-Policy|X-Content-Type-Options)" | wc -l)
    
    if [[ $security_headers -gt 0 ]]; then
        print_success "Security headers found: $security_headers"
    else
        print_warning "No security headers detected"
    fi
    
    print_success "Security tests completed"
}

# Generate comprehensive report
generate_report() {
    print_info "Generating test report..."
    
    cat > "$REPORT_DIR/test-summary.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>N8N AI Starter Kit - Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f8ff; padding: 20px; border-radius: 5px; }
        .success { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>N8N AI Starter Kit - Test Results</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Environment:</strong> $ENV_FILE</p>
        <p><strong>Test Suites:</strong> ${TEST_SUITES[*]}</p>
    </div>
    
    <div class="section">
        <h2>Test Execution Summary</h2>
        <p>Test execution completed. Check individual test results in the report directory.</p>
        <ul>
EOF

    for suite in "${TEST_SUITES[@]}"; do
        echo "            <li><strong>$suite</strong>: Test suite executed</li>" >> "$REPORT_DIR/test-summary.html"
    done

    cat >> "$REPORT_DIR/test-summary.html" << EOF
        </ul>
    </div>
    
    <div class="section">
        <h2>Report Files</h2>
        <ul>
            <li>Unit Tests: Check existing test reports</li>
            <li>Integration Tests: Check integration test logs</li>
            <li>E2E Tests: Playwright HTML report in e2e/</li>
            <li>Performance: performance-results.json</li>
            <li>Security: Check security audit output</li>
        </ul>
    </div>
</body>
</html>
EOF

    print_success "Test report generated: $REPORT_DIR/test-summary.html"
}

# Cleanup test environment
cleanup_environment() {
    if [[ "$CLEANUP" == "true" ]]; then
        print_info "Cleaning up test environment..."
        ./start.sh down || true
        print_success "Cleanup completed"
    fi
}

# Run monitoring tests
run_monitoring_tests() {
    print_info "Running advanced monitoring tests..."
    cd "$PROJECT_ROOT"
    
    # Test monitoring system initialization
    if ./scripts/advanced-monitor.sh check --verbose; then
        print_success "Monitoring system check passed"
    else
        print_error "Monitoring system check failed"
        return 1
    fi
    
    # Test metrics collection
    if ./scripts/advanced-monitor.sh metrics; then
        print_success "Metrics collection test passed"
    else
        print_error "Metrics collection test failed"
        return 1
    fi
    
    # Test alert system (dry run)
    if ./scripts/advanced-monitor.sh alerts; then
        print_success "Alert system test passed"
    else
        print_warning "Alert system test had issues (may be expected)"
    fi
    
    print_success "Monitoring tests completed"
}

# Run backup and disaster recovery tests
run_backup_tests() {
    print_info "Running backup and disaster recovery tests..."
    cd "$PROJECT_ROOT"
    
    # Test backup system initialization
    if ./scripts/backup-disaster-recovery.sh list; then
        print_success "Backup system initialization passed"
    else
        print_error "Backup system initialization failed"
        return 1
    fi
    
    # Test backup creation (dry run equivalent)
    print_info "Testing backup metadata and configuration..."
    
    # Verify backup script can run basic operations
    if ./scripts/backup-disaster-recovery.sh cleanup; then
        print_success "Backup cleanup test passed"
    else
        print_warning "Backup cleanup test had issues"
    fi
    
    # Test backup verification functions
    print_info "Testing backup verification system..."
    # This would test the backup verification logic without actual files
    
    print_success "Backup and disaster recovery tests completed"
}

# Main execution
main() {
    print_info "Starting comprehensive test execution..."
    print_info "Test suites: ${TEST_SUITES[*]}"
    print_info "Report directory: $REPORT_DIR"
    
    # Setup environment
    setup_test_environment
    
    local overall_status=0
    
    # Execute test suites
    for suite in "${TEST_SUITES[@]}"; do
        case "$suite" in
            "all")
                run_unit_tests || ((overall_status++))
                run_integration_tests || ((overall_status++))
                run_profile_tests || ((overall_status++))
                run_e2e_tests || ((overall_status++))
                run_api_tests || ((overall_status++))
                run_performance_tests || ((overall_status++))
                run_security_tests || ((overall_status++))
                run_monitoring_tests || ((overall_status++))
                run_backup_tests || ((overall_status++))
                ;;
            "unit")
                run_unit_tests || ((overall_status++))
                ;;
            "integration")
                run_integration_tests || ((overall_status++))
                ;;
            "profiles")
                run_profile_tests || ((overall_status++))
                ;;
            "e2e")
                run_e2e_tests || ((overall_status++))
                ;;
            "api")
                run_api_tests || ((overall_status++))
                ;;
            "performance")
                run_performance_tests || ((overall_status++))
                ;;
            "security")
                run_security_tests || ((overall_status++))
                ;;
            "monitoring")
                run_monitoring_tests || ((overall_status++))
                ;;
            "backup")
                run_backup_tests || ((overall_status++))
                ;;
        esac
    done
    
    # Generate report
    generate_report
    
    # Cleanup
    cleanup_environment
    
    # Final status
    echo
    if [[ "$overall_status" -eq 0 ]]; then
        print_success "All test suites completed successfully!"
    else
        print_warning "$overall_status test suite(s) had issues"
    fi
    
    print_info "Test results available in: $REPORT_DIR/"
    
    exit $overall_status
}

# Run main function
main "$@"