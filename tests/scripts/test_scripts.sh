#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - SCRIPT TESTS
# =============================================================================
# Test functionality of shell scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Test setup script
test_setup_script() {
    print_info "Testing setup script..."
    
    local setup_script="$PROJECT_ROOT/scripts/setup.sh"
    
    # Test help
    if "$setup_script" --help >/dev/null 2>&1; then
        print_success "Setup script help works"
    else
        print_error "Setup script help failed"
        return 1
    fi
    
    # Test dry-run
    if "$setup_script" --dry-run --non-interactive >/dev/null 2>&1; then
        print_success "Setup script dry-run works"
    else
        print_error "Setup script dry-run failed"
        return 1
    fi
    
    return 0
}

# Test credential script
test_credential_script() {
    print_info "Testing credential management script..."
    
    local cred_script="$PROJECT_ROOT/scripts/create_n8n_credential.sh"
    
    # Test help
    if "$cred_script" --help >/dev/null 2>&1; then
        print_success "Credential script help works"
    else
        print_error "Credential script help failed"
        return 1
    fi
    
    # Test dry-run credential creation
    if "$cred_script" --dry-run --type postgres --name "Test" --data '{"host":"test"}' >/dev/null 2>&1; then
        print_success "Credential script dry-run works"
    else
        print_error "Credential script dry-run failed"
        return 1
    fi
    
    return 0
}

# Test start script
test_start_script() {
    print_info "Testing start script..."
    
    local start_script="$PROJECT_ROOT/start.sh"
    
    # Test help
    if "$start_script" --help >/dev/null 2>&1; then
        print_success "Start script help works"
    else
        print_error "Start script help failed"
        return 1
    fi
    
    # Test dry-run
    if "$start_script" up --dry-run >/dev/null 2>&1; then
        print_success "Start script dry-run works"
    else
        print_error "Start script dry-run failed"
        return 1
    fi
    
    return 0
}

# Test maintenance scripts
test_maintenance_scripts() {
    print_info "Testing maintenance scripts..."
    
    local scripts=(
        "$PROJECT_ROOT/scripts/maintenance/backup.sh"
        "$PROJECT_ROOT/scripts/maintenance/restore.sh"
        "$PROJECT_ROOT/scripts/maintenance/monitor.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_name=$(basename "$script")
        
        if [[ -x "$script" ]]; then
            if "$script" --help >/dev/null 2>&1; then
                print_success "$script_name help works"
            else
                print_error "$script_name help failed"
                return 1
            fi
        else
            print_error "$script_name not executable"
            return 1
        fi
    done
    
    # Test specific functionality
    if "$PROJECT_ROOT/scripts/maintenance/backup.sh" --dry-run >/dev/null 2>&1; then
        print_success "Backup script dry-run works"
    else
        print_error "Backup script dry-run failed"
        return 1
    fi
    
    if "$PROJECT_ROOT/scripts/maintenance/restore.sh" list >/dev/null 2>&1; then
        print_success "Restore script list works"
    else
        print_error "Restore script list failed"
        return 1
    fi
    
    if "$PROJECT_ROOT/scripts/maintenance/monitor.sh" all --dry-run >/dev/null 2>&1; then
        print_success "Monitor script dry-run works" 
    else
        print_error "Monitor script dry-run failed"
        return 1
    fi
    
    return 0
}

# Run all script tests
main() {
    print_info "Running script tests..."
    
    local exit_code=0
    
    test_setup_script || exit_code=1
    test_credential_script || exit_code=1
    test_start_script || exit_code=1
    test_maintenance_scripts || exit_code=1
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "All script tests passed!"
    else
        print_error "Some script tests failed"
    fi
    
    return $exit_code
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi