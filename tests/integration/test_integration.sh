#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - INTEGRATION TESTS
# =============================================================================
# End-to-end integration tests for the complete system

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
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Test full deployment workflow
test_full_deployment() {
    print_info "Testing full deployment workflow..."
    
    cd "$PROJECT_ROOT"
    
    # Test environment setup
    print_info "Setting up environment..."
    if ./scripts/setup.sh --non-interactive --force >/dev/null 2>&1; then
        print_success "Environment setup completed"
    else
        print_error "Environment setup failed"
        return 1
    fi
    
    # Validate environment file
    if [[ -f ".env" ]]; then
        print_success "Environment file created"
        
        # Check for placeholder values (should be replaced)
        if grep -q "change_this_" .env; then
            print_error "Environment file contains unreplaced placeholders"
            return 1
        else
            print_success "Environment file properly generated"
        fi
    else
        print_error "Environment file not created"
        return 1
    fi
    
    return 0
}

# Test service orchestration
test_service_orchestration() {
    print_info "Testing service orchestration..."
    
    cd "$PROJECT_ROOT"
    
    # Test Docker Compose configuration
    if docker compose config >/dev/null 2>&1; then
        print_success "Docker Compose configuration valid"
    else
        print_error "Docker Compose configuration invalid"
        return 1
    fi
    
    # Test profile-based startup (dry run) - Extended test suite
    local profiles=(
        "default" 
        "default,developer" 
        "default,monitoring" 
        "default,analytics"
        "default,gpu"
        "default,developer,monitoring" 
        "default,developer,analytics"
        "default,monitoring,analytics"
        "default,developer,monitoring,analytics"
        "developer,monitoring,gpu"
        "default,developer,monitoring,gpu"
    )
    
    print_info "Testing ${#profiles[@]} profile combinations..."
    
    for profile in "${profiles[@]}"; do
        print_info "Validating profile combination: $profile"
        if COMPOSE_PROFILES="$profile" docker compose config >/dev/null 2>&1; then
            print_success "Profile configuration valid: $profile"
            
            # Test that profile has expected services
            local service_count
            service_count=$(COMPOSE_PROFILES="$profile" docker compose config --services | wc -l)
            print_info "  Services in profile '$profile': $service_count"
            
            # Validate specific profile requirements
            case "$profile" in
                *gpu*)
                    if COMPOSE_PROFILES="$profile" docker compose config --services | grep -q "gpu"; then
                        print_success "  GPU services found in profile"
                    else
                        print_warning "  No GPU services found in GPU profile"
                    fi
                    ;;
                *monitoring*)
                    if COMPOSE_PROFILES="$profile" docker compose config --services | grep -E "(grafana|prometheus)" >/dev/null; then
                        print_success "  Monitoring services found in profile"
                    else
                        print_warning "  No monitoring services found in monitoring profile"
                    fi
                    ;;
                *analytics*)
                    if COMPOSE_PROFILES="$profile" docker compose config --services | grep -E "(clickhouse|etl)" >/dev/null; then
                        print_success "  Analytics services found in profile"
                    else
                        print_warning "  No analytics services found in analytics profile"
                    fi
                    ;;
            esac
        else
            print_error "Profile configuration invalid: $profile"
            return 1
        fi
    done
    
    return 0
}

# Test document processing workflow (if services are running)
test_document_workflow() {
    print_info "Testing document processing workflow..."
    
    # Check if document processor is running
    if ! curl -f -s http://localhost:8001/health >/dev/null 2>&1; then
        print_warning "Document processor not running, skipping workflow test"
        return 0
    fi
    
    # Create test document
    local test_file="/tmp/integration_test_doc.txt"
    cat > "$test_file" << EOF
This is a test document for the N8N AI Starter Kit integration test.
It contains multiple sentences to test the document processing pipeline.
The document processor should extract this text, create chunks, and generate embeddings.
This allows us to test the complete AI workflow from upload to search.
EOF
    
    # Test document upload
    local upload_response
    if upload_response=$(curl -s -f -X POST "http://localhost:8001/docs/upload" -F "file=@$test_file"); then
        print_success "Document upload successful"
        
        # Extract document ID if possible
        if command -v jq >/dev/null 2>&1 && echo "$upload_response" | jq . >/dev/null 2>&1; then
            local doc_id=$(echo "$upload_response" | jq -r '.document_id // empty')
            
            if [[ -n "$doc_id" ]]; then
                print_success "Document ID received: ${doc_id:0:8}..."
                
                # Wait a moment for processing
                sleep 2
                
                # Test status check
                if curl -f -s "http://localhost:8001/docs/$doc_id/status" >/dev/null 2>&1; then
                    print_success "Document status check successful"
                else
                    print_warning "Document status check failed (may still be processing)"
                fi
            fi
        fi
    else
        print_error "Document upload failed"
        rm -f "$test_file"
        return 1
    fi
    
    # Test search functionality
    local search_response
    if search_response=$(curl -s -f -X POST "http://localhost:8001/docs/search" \
        -H "Content-Type: application/json" \
        -d '{"query":"integration test document","limit":5,"threshold":0.5}'); then
        
        print_success "Document search successful"
        
        # Check if we got results
        if command -v jq >/dev/null 2>&1 && echo "$search_response" | jq . >/dev/null 2>&1; then
            local result_count=$(echo "$search_response" | jq 'length')
            print_info "Search returned $result_count results"
        fi
    else
        print_warning "Document search failed (may need time for indexing)"
    fi
    
    # Cleanup
    rm -f "$test_file"
    return 0
}

# Test N8N integration (if running and configured)
test_n8n_integration() {
    print_info "Testing N8N integration..."
    
    # Check if N8N is running
    if ! curl -f -s http://localhost:5678/healthz >/dev/null 2>&1; then
        print_warning "N8N not running, skipping integration test"
        return 0
    fi
    
    print_success "N8N is accessible"
    
    # Test credential management if authentication is configured
    if [[ -n "${N8N_PERSONAL_ACCESS_TOKEN:-}" ]] || [[ -n "${N8N_API_KEY:-}" ]]; then
        if ./scripts/create_n8n_credential.sh --list >/dev/null 2>&1; then
            print_success "N8N credential management working"
        else
            print_warning "N8N credential management failed (check authentication)"
        fi
    else
        print_info "N8N authentication not configured, skipping credential tests"
    fi
    
    return 0
}

# Test monitoring stack (if running)
test_monitoring_stack() {
    print_info "Testing monitoring stack..."
    
    # Test Grafana
    if curl -f -s http://localhost:3000/api/health >/dev/null 2>&1; then
        print_success "Grafana is accessible"
    else
        print_warning "Grafana not accessible (may not be running)"
    fi
    
    # Test Prometheus (if running)
    if curl -f -s http://localhost:9090/-/healthy >/dev/null 2>&1; then
        print_success "Prometheus is accessible"
    else
        print_warning "Prometheus not accessible (may not be running)"
    fi
    
    # Test service metrics endpoints
    local services=(
        "8000:Web Interface"
        "8001:Document Processor"
        "8002:ETL Processor"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r port name <<< "$service_info"
        
        if curl -f -s "http://localhost:$port/metrics" >/dev/null 2>&1; then
            print_success "$name metrics endpoint accessible"
        else
            print_warning "$name metrics endpoint not accessible"
        fi
    done
    
    return 0
}

# Test backup and restore workflow
test_backup_restore() {
    print_info "Testing backup and restore workflow..."
    
    cd "$PROJECT_ROOT"
    
    # Test backup dry-run
    if ./scripts/maintenance/backup.sh --dry-run >/dev/null 2>&1; then
        print_success "Backup dry-run successful"
    else
        print_error "Backup dry-run failed"
        return 1
    fi
    
    # Test restore list
    if ./scripts/maintenance/restore.sh list >/dev/null 2>&1; then
        print_success "Restore list command successful"
    else
        print_error "Restore list command failed"
        return 1
    fi
    
    return 0
}

# Test system monitoring
test_system_monitoring() {
    print_info "Testing system monitoring..."
    
    cd "$PROJECT_ROOT"
    
    # Test monitoring script
    if ./scripts/maintenance/monitor.sh all --dry-run >/dev/null 2>&1; then
        print_success "System monitoring dry-run successful"
    else
        print_error "System monitoring dry-run failed"
        return 1
    fi
    
    # Test specific monitoring functions
    local monitor_tests=("health" "performance" "disk" "network")
    
    for test_name in "${monitor_tests[@]}"; do
        if ./scripts/maintenance/monitor.sh "$test_name" --dry-run >/dev/null 2>&1; then
            print_success "Monitor $test_name test successful"
        else
            print_warning "Monitor $test_name test failed"
        fi
    done
    
    return 0
}

# Main integration test function
main() {
    local test_suite="${1:-all}"
    
    print_info "Running N8N AI Starter Kit Integration Tests"
    print_info "Test suite: $test_suite"
    echo
    
    local exit_code=0
    
    case "$test_suite" in
        all)
            test_full_deployment || exit_code=1
            test_service_orchestration || exit_code=1
            test_document_workflow || exit_code=1
            test_n8n_integration || exit_code=1
            test_monitoring_stack || exit_code=1
            test_backup_restore || exit_code=1
            test_system_monitoring || exit_code=1
            ;;
        deployment)
            test_full_deployment || exit_code=1
            test_service_orchestration || exit_code=1
            ;;
        services)
            test_document_workflow || exit_code=1
            test_n8n_integration || exit_code=1
            test_monitoring_stack || exit_code=1
            ;;
        maintenance)
            test_backup_restore || exit_code=1
            test_system_monitoring || exit_code=1
            ;;
        *)
            print_error "Unknown test suite: $test_suite"
            echo "Available suites: all, deployment, services, maintenance"
            exit 1
            ;;
    esac
    
    echo
    if [[ $exit_code -eq 0 ]]; then
        print_success "All integration tests completed successfully!"
    else
        print_error "Some integration tests failed or had warnings"
    fi
    
    return $exit_code
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi