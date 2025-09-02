#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - PROFILE TESTING SCRIPT
# =============================================================================
# Comprehensive testing for different Docker Compose deployment profiles

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
PROFILES_TESTED=0
PROFILES_PASSED=0
PROFILES_FAILED=0

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${CYAN}=== $1 ===${NC}"; }

# Simple profile test
test_profile() {
    local profile="$1"
    local verbose="${2:-false}"
    
    PROFILES_TESTED=$((PROFILES_TESTED + 1))
    
    print_info "Testing profile: $profile"
    
    # Test Docker Compose configuration validation
    if ! COMPOSE_PROFILES="$profile" docker compose config >/dev/null 2>&1; then
        print_error "Profile configuration invalid: $profile"
        PROFILES_FAILED=$((PROFILES_FAILED + 1))
        return 1
    fi
    
    print_success "Configuration valid"
    
    # Count services in profile
    local service_count
    service_count=$(COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null | wc -l)
    
    if [[ "$verbose" == "true" ]]; then
        print_info "Services in profile: $service_count"
        print_info "Service list:"
        COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null | sed 's/^/  - /'
    else
        print_info "Services in profile: $service_count"
    fi
    
    # Validate profile-specific requirements
    local services
    services=$(COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null)
    
    # Check for core services in default profile
    if [[ "$profile" == *"default"* ]]; then
        if echo "$services" | grep -E "(traefik|postgres|n8n)" >/dev/null; then
            if [[ "$verbose" == "true" ]]; then
                print_success "Core services found in default profile"
            fi
        else
            print_error "Missing core services in default profile: $profile"
            PROFILES_FAILED=$((PROFILES_FAILED + 1))
            return 1
        fi
    fi
    
    # Check monitoring services
    if [[ "$profile" == *"monitoring"* ]]; then
        if echo "$services" | grep -E "(grafana|prometheus)" >/dev/null; then
            if [[ "$verbose" == "true" ]]; then
                print_success "Monitoring services found"
            fi
        else
            print_warning "No monitoring services found in monitoring profile"
        fi
    fi
    
    # Check developer services
    if [[ "$profile" == *"developer"* ]]; then
        if echo "$services" | grep -E "(document-processor|lightrag|web-interface)" >/dev/null; then
            if [[ "$verbose" == "true" ]]; then
                print_success "Developer services found"
            fi
        else
            print_warning "No developer services found in developer profile"
        fi
    fi
    
    # Check GPU services
    if [[ "$profile" == *"gpu"* ]]; then
        if echo "$services" | grep -q "gpu"; then
            if [[ "$verbose" == "true" ]]; then
                print_success "GPU services found"
            fi
        else
            print_warning "No GPU services found in gpu profile"
        fi
    fi
    
    # Test startup if requested
    if [[ "$WITH_STARTUP" == "true" ]]; then
        test_profile_startup "$profile"
    fi
    
    PROFILES_PASSED=$((PROFILES_PASSED + 1))
    print_success "Profile test passed: $profile"
    echo
    return 0
}

# Test actual service startup
test_profile_startup() {
    local profile="$1"
    
    print_info "Testing startup for profile: $profile"
    
    # Check if services are already running
    if docker compose ps -q 2>/dev/null | grep -q .; then
        print_warning "Services already running, stopping them first..."
        docker compose down >/dev/null 2>&1 || true
        sleep 5
    fi
    
    # Start services with profile
    print_info "Starting services with profile: $profile"
    if ! COMPOSE_PROFILES="$profile" timeout "$TIMEOUT" docker compose up -d >/dev/null 2>&1; then
        print_error "Failed to start services with profile: $profile"
        docker compose down >/dev/null 2>&1 || true
        return 1
    fi
    
    # Wait for services to be ready
    print_info "Waiting for services to be ready..."
    local max_wait=60
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if check_profile_health "$profile"; then
            print_success "Services started successfully for profile: $profile"
            break
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        
        if [[ $wait_time -ge $max_wait ]]; then
            print_error "Services failed to become ready within timeout for profile: $profile"
            if [[ "$VERBOSE" == "true" ]]; then
                docker compose logs --tail=20
            fi
            docker compose down >/dev/null 2>&1 || true
            return 1
        fi
    done
    
    # Stop services
    print_info "Stopping services..."
    docker compose down >/dev/null 2>&1 || true
    
    return 0
}

# Check health of services in a profile
check_profile_health() {
    local profile="$1"
    local services
    services=$(COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null)
    
    # Define health check endpoints
    declare -A HEALTH_ENDPOINTS
    HEALTH_ENDPOINTS[traefik]="http://localhost:8080/api/rawdata"
    HEALTH_ENDPOINTS[n8n]="http://localhost:5678/"
    HEALTH_ENDPOINTS[web-interface]="http://localhost:8000/health"
    HEALTH_ENDPOINTS[document-processor]="http://localhost:8001/health"
    HEALTH_ENDPOINTS[document-processor-gpu]="http://localhost:8011/health"
    HEALTH_ENDPOINTS[etl-processor]="http://localhost:8002/health"
    HEALTH_ENDPOINTS[lightrag]="http://localhost:8003/health"
    HEALTH_ENDPOINTS[lightrag-gpu]="http://localhost:8013/health"
    HEALTH_ENDPOINTS[gpu-monitor]="http://localhost:8014/health"
    HEALTH_ENDPOINTS[grafana]="http://localhost:3000/api/health"
    HEALTH_ENDPOINTS[prometheus]="http://localhost:9090/-/healthy"
    HEALTH_ENDPOINTS[qdrant]="http://localhost:6333/health"
    HEALTH_ENDPOINTS[ollama]="http://localhost:11434/api/version"
    
    local failed_services=()
    local tested_services=0
    
    while IFS= read -r service; do
        if [[ -n "${HEALTH_ENDPOINTS[$service]:-}" ]]; then
            tested_services=$((tested_services + 1))
            if ! curl -f -s --max-time 5 "${HEALTH_ENDPOINTS[$service]}" >/dev/null 2>&1; then
                failed_services+=("$service")
            fi
        fi
    done <<< "$services"
    
    if [[ $tested_services -eq 0 ]]; then
        # No services with health endpoints, consider it successful
        return 0
    fi
    
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_success "All $tested_services health checks passed"
        fi
        return 0
    else
        if [[ "$VERBOSE" == "true" ]]; then
            print_warning "Failed health checks: ${failed_services[*]} (${#failed_services[@]}/$tested_services)"
        fi
        return 1
    fi
}

# Generate test report
generate_report() {
    local report_file="test-results/profile-test-report-$(date +%Y%m%d_%H%M%S).md"
    
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
# Profile Testing Report

**Generated:** $(date)
**Profile Set:** $PROFILE_SET
**Test Mode:** $(if [[ "$WITH_STARTUP" == "true" ]]; then echo "With Startup"; else echo "Configuration Only"; fi)

## Summary

- **Profiles Tested:** $PROFILES_TESTED
- **Profiles Passed:** $PROFILES_PASSED
- **Profiles Failed:** $PROFILES_FAILED
- **Success Rate:** $((PROFILES_PASSED * 100 / PROFILES_TESTED))%

## Test Configuration

- With Startup: $WITH_STARTUP
- Timeout: ${TIMEOUT}s
- Verbose: $VERBOSE

EOF
    
    print_success "Report generated: $report_file"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [PROFILE_SET]

Test Docker Compose profiles for N8N AI Starter Kit

PROFILE SETS:
    basic           Test basic profile combinations (default)
    extended        Test all possible profile combinations
    gpu             Test GPU-specific profiles
    production      Test production-recommended profiles
    custom PROFILES Test specific profile combination

OPTIONS:
    --dry-run       Only validate configurations without starting services
    --with-startup  Test actual service startup (requires clean environment)
    --timeout N     Startup timeout in seconds (default: 300)
    --verbose       Verbose output
    --report        Generate detailed test report
    --help          Show this help

EXAMPLES:
    $0                              # Test basic profile combinations
    $0 extended --dry-run          # Validate all profile combinations
    $0 gpu --verbose               # Test GPU profiles with verbose output
    $0 custom "default,monitoring"  # Test specific profile combination

EOF
}

# Configuration
WITH_STARTUP=false
TIMEOUT=300
VERBOSE=false
GENERATE_REPORT=false
PROFILE_SET="basic"
CUSTOM_PROFILES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-startup) WITH_STARTUP=true; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        --report) GENERATE_REPORT=true; shift ;;
        --help|-h) print_usage; exit 0 ;;
        basic|extended|gpu|production) PROFILE_SET="$1"; shift ;;
        custom) PROFILE_SET="custom"; CUSTOM_PROFILES="$2"; shift 2 ;;
        *) print_error "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

# Define profile sets
declare -A PROFILE_SETS
PROFILE_SETS[basic]="default|default,developer|default,monitoring|default,developer,monitoring"
PROFILE_SETS[extended]="default|default,developer|default,monitoring|default,analytics|default,gpu|default,developer,monitoring|default,developer,analytics|default,monitoring,analytics|default,developer,monitoring,analytics"
PROFILE_SETS[gpu]="default,gpu|default,developer,gpu|default,monitoring,gpu|default,developer,monitoring,gpu"
PROFILE_SETS[production]="default|default,monitoring|default,developer,monitoring|default,monitoring,analytics"

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    # Load environment variables
    if [[ -f ".env" ]]; then
        set -a
        source .env
        set +a
        print_info "Environment loaded from .env"
    elif [[ -f "template.env" ]]; then
        print_warning "No .env file found, copying from template.env"
        cp template.env .env
        set -a
        source .env
        set +a
    else
        print_warning "No environment file found, using defaults"
    fi
    
    print_header "N8N AI Starter Kit - Profile Testing"
    print_info "Profile set: $PROFILE_SET"
    if [[ "$WITH_STARTUP" == "true" ]]; then
        print_info "Test mode: Configuration validation + Service startup"
    else
        print_info "Test mode: Configuration validation only"
    fi
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not available"
        exit 1
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose is not available"
        exit 1
    fi
    
    # Get profiles to test
    local profiles_to_test
    if [[ "$PROFILE_SET" == "custom" ]]; then
        profiles_to_test="$CUSTOM_PROFILES"
    else
        profiles_to_test="${PROFILE_SETS[$PROFILE_SET]}"
    fi
    
    if [[ -z "$profiles_to_test" ]]; then
        print_error "No profiles defined for set: $PROFILE_SET"
        exit 1
    fi
    
    # Convert pipe-separated to array
    IFS='|' read -ra PROFILES_ARRAY <<< "$profiles_to_test"
    
    print_info "Testing ${#PROFILES_ARRAY[@]} profile combinations..."
    echo
    
    # Test each profile
    for profile in "${PROFILES_ARRAY[@]}"; do
        test_profile "$profile" "$VERBOSE"
    done
    
    # Print summary
    print_header "Test Summary"
    print_info "Profiles tested: $PROFILES_TESTED"
    print_success "Profiles passed: $PROFILES_PASSED"
    
    if [[ $PROFILES_FAILED -gt 0 ]]; then
        print_error "Profiles failed: $PROFILES_FAILED"
    fi
    
    local success_rate=$((PROFILES_PASSED * 100 / PROFILES_TESTED))
    print_info "Success rate: ${success_rate}%"
    
    # Generate report if requested
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        generate_report
    fi
    
    # Exit with error if any profiles failed
    if [[ $PROFILES_FAILED -gt 0 ]]; then
        exit 1
    fi
}

# Execute main function
main "$@"