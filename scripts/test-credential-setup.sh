#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - CREDENTIAL SETUP TEST
# =============================================================================
# This script tests the credential management system to ensure it works correctly

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

print_header() {
    echo "============================================================================="
    echo "                    N8N CREDENTIAL SETUP TEST"
    echo "============================================================================="
    echo
}

# Test functions
test_environment() {
    print_info "Testing environment setup..."
    
    # Check .env file
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        print_error ".env file not found - run ./scripts/setup.sh first"
        return 1
    fi
    
    # Source environment
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
    
    # Check critical variables
    local missing_vars=()
    
    for var in POSTGRES_PASSWORD QDRANT_API_KEY; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required variables: ${missing_vars[*]}"
        return 1
    fi
    
    print_success "Environment configuration is valid"
    return 0
}

test_n8n_running() {
    print_info "Testing N8N availability..."
    
    local n8n_url="${N8N_BASE_URL:-http://localhost:5678}"
    
    if curl -f -s "$n8n_url/healthz" >/dev/null 2>&1; then
        print_success "N8N is running at $n8n_url"
        return 0
    else
        print_error "N8N is not running - start services first with: ./start.sh up"
        return 1
    fi
}

test_authentication() {
    print_info "Testing N8N authentication..."
    
    if [[ -z "${N8N_PERSONAL_ACCESS_TOKEN:-}" && -z "${N8N_API_KEY:-}" ]]; then
        print_error "No N8N authentication configured"
        echo "Please set N8N_PERSONAL_ACCESS_TOKEN or N8N_API_KEY in .env"
        echo "Generate in N8N at: Settings → Personal Access Token"
        return 1
    fi
    
    local n8n_url="${N8N_BASE_URL:-http://localhost:5678}"
    local auth_header=""
    
    if [[ -n "${N8N_PERSONAL_ACCESS_TOKEN:-}" ]]; then
        auth_header="Authorization: Bearer $N8N_PERSONAL_ACCESS_TOKEN"
        print_info "Using Personal Access Token"
    elif [[ -n "${N8N_API_KEY:-}" ]]; then
        auth_header="X-N8N-API-KEY: $N8N_API_KEY"
        print_info "Using API Key"
    fi
    
    if curl -f -s -H "$auth_header" "$n8n_url/api/v1/credentials" >/dev/null 2>&1; then
        print_success "N8N authentication is working"
        return 0
    else
        print_error "N8N authentication failed - check your token/key"
        return 1
    fi
}

test_script_availability() {
    print_info "Testing credential management scripts..."
    
    local scripts=(
        "$PROJECT_ROOT/scripts/auto-setup-credentials.sh"
        "$PROJECT_ROOT/scripts/credential-manager.py"
        "$PROJECT_ROOT/scripts/create_n8n_credential.sh"
    )
    
    local missing_scripts=()
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            missing_scripts+=("$(basename "$script")")
        elif [[ ! -x "$script" ]]; then
            print_warning "Script not executable: $(basename "$script")"
            chmod +x "$script"
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        print_error "Missing scripts: ${missing_scripts[*]}"
        return 1
    fi
    
    print_success "All credential management scripts are available"
    return 0
}

test_dry_run() {
    print_info "Testing dry-run credential creation..."
    
    local auto_script="$PROJECT_ROOT/scripts/auto-setup-credentials.sh"
    
    if "$auto_script" --dry-run --services postgres >/dev/null 2>&1; then
        print_success "Dry-run test passed"
        return 0
    else
        print_error "Dry-run test failed"
        return 1
    fi
}

test_python_manager() {
    print_info "Testing Python credential manager..."
    
    if ! command -v python3 >/dev/null 2>&1; then
        print_warning "Python3 not available - skipping Python manager test"
        return 0
    fi
    
    # Test if requests is available
    if ! python3 -c "import requests" >/dev/null 2>&1; then
        print_warning "Python requests library not available - install with: pip install requests"
        return 0
    fi
    
    local python_manager="$PROJECT_ROOT/scripts/credential-manager.py"
    
    if python3 "$python_manager" --test-connection >/dev/null 2>&1; then
        print_success "Python credential manager test passed"
        return 0
    else
        print_error "Python credential manager test failed"
        return 1
    fi
}

test_template_loading() {
    print_info "Testing credential template loading..."
    
    local template_file="$PROJECT_ROOT/config/n8n/credentials-template.json"
    
    if [[ ! -f "$template_file" ]]; then
        print_warning "Credential template file not found: $template_file"
        return 0
    fi
    
    if jq empty "$template_file" >/dev/null 2>&1; then
        print_success "Credential template is valid JSON"
        return 0
    else
        print_error "Credential template has invalid JSON"
        return 1
    fi
}

run_all_tests() {
    print_header
    
    local tests=(
        "test_environment"
        "test_script_availability"
        "test_template_loading"
        "test_n8n_running"
        "test_authentication"
        "test_dry_run"
        "test_python_manager"
    )
    
    local passed=0
    local failed=0
    local skipped=0
    
    for test in "${tests[@]}"; do
        echo
        if $test; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    echo
    print_info "Test Results:"
    print_success "  Passed: $passed"
    if [[ $failed -gt 0 ]]; then
        print_error "  Failed: $failed"
    fi
    
    if [[ $failed -eq 0 ]]; then
        print_success "All tests passed! Credential system is ready to use."
        echo
        print_info "Next steps:"
        echo "  1. Run: ./start.sh setup-credentials"
        echo "  2. Or use: python3 scripts/credential-manager.py --interactive"
        echo "  3. Or automated: ./scripts/auto-setup-credentials.sh --services postgres,qdrant,openai"
        return 0
    else
        print_error "Some tests failed. Please fix the issues before using the credential system."
        return 1
    fi
}

main() {
    case "${1:-}" in
        --help|-h)
            echo "Usage: $0 [TEST_NAME]"
            echo
            echo "Available tests:"
            echo "  environment     - Test environment configuration"
            echo "  n8n-running     - Test N8N availability"
            echo "  authentication  - Test N8N authentication"
            echo "  scripts         - Test script availability"
            echo "  dry-run         - Test dry-run functionality"
            echo "  python-manager  - Test Python manager"
            echo "  templates       - Test template loading"
            echo
            echo "Run without arguments to execute all tests."
            ;;
        environment)
            test_environment
            ;;
        n8n-running)
            test_n8n_running
            ;;
        authentication)
            test_authentication
            ;;
        scripts)
            test_script_availability
            ;;
        dry-run)
            test_dry_run
            ;;
        python-manager)
            test_python_manager
            ;;
        templates)
            test_template_loading
            ;;
        "")
            run_all_tests
            ;;
        *)
            print_error "Unknown test: $1"
            echo "Run '$0 --help' for available tests"
            exit 1
            ;;
    esac
}

# Change to project directory
cd "$PROJECT_ROOT"

# Run main function
main "$@"