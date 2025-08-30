#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - WORKFLOW MANAGEMENT SCRIPT
# =============================================================================
# This script manages workflows in N8N using the REST API
# Supports workflow activation, deactivation, listing, creation, and status monitoring

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Print functions
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_workflow() { echo -e "${MAGENTA}🔄${NC} $1"; }

print_header() {
    echo "============================================================================="
    echo "                    N8N WORKFLOW MANAGEMENT"
    echo "============================================================================="
    echo
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Manage N8N workflows using the REST API.

ACTIONS:
    --list              List workflows (default action)
    --get ID            Get workflow details by ID
    --activate ID       Activate workflow by ID
    --deactivate ID     Deactivate workflow by ID  
    --delete ID         Delete workflow by ID
    --create FILE       Create workflow from JSON file
    --update ID FILE    Update workflow with JSON file
    --duplicate ID      Duplicate workflow
    --export ID FILE    Export workflow to JSON file
    --import FILE       Import workflow from JSON file
    --status            Show workflow status summary
    --health            Check workflow health and issues

FILTERING OPTIONS:
    --active            Show only active workflows
    --inactive          Show only inactive workflows
    --name NAME         Filter by workflow name (partial match)
    --tag TAG           Filter by tag
    --limit LIMIT       Limit results per page (default: 50, max: 250)
    --cursor CURSOR     Cursor for pagination
    --all               Get all results across all pages

MONITORING OPTIONS:
    --watch             Watch workflow status in real-time
    --errors            Show workflows with recent errors
    --performance       Show workflow performance metrics

AUTHENTICATION:
    Set one of these environment variables:
    - N8N_PERSONAL_ACCESS_TOKEN: Personal Access Token for REST API
    - N8N_API_KEY: Public API Key for webhook/public endpoints

    N8N_BASE_URL: N8N base URL (default: http://localhost:5678)

EXAMPLES:
    # List all workflows
    $0 --list
    
    # List only active workflows
    $0 --list --active
    
    # Activate a workflow
    $0 --activate workflow_123
    
    # Get workflow details
    $0 --get workflow_123
    
    # Watch workflow status
    $0 --watch
    
    # Show workflow health summary
    $0 --health
    
    # Export workflow to file
    $0 --export workflow_123 my-workflow.json
    
    # Create workflow from file
    $0 --create new-workflow.json
    
    # Show performance metrics
    $0 --performance

WORKFLOW STATUSES:
    - Active: Workflow is enabled and will execute
    - Inactive: Workflow is disabled
    - Error: Workflow has configuration errors
    - Warning: Workflow has potential issues

EOF
}

# Configuration
N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
WORKFLOWS_API_URL="$N8N_BASE_URL/api/v1/workflows"
EXECUTIONS_API_URL="$N8N_BASE_URL/api/v1/executions"

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl jq date; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies:"
        echo "  - Ubuntu/Debian: sudo apt install curl jq coreutils"
        echo "  - CentOS/RHEL: sudo yum install curl jq coreutils"
        echo "  - macOS: brew install curl jq coreutils"
        exit 1
    fi
}

# Function to setup authentication
setup_authentication() {
    if [[ -n "${N8N_PERSONAL_ACCESS_TOKEN:-}" ]]; then
        AUTH_HEADER="Authorization: Bearer $N8N_PERSONAL_ACCESS_TOKEN"
        print_info "Using Personal Access Token authentication"
    elif [[ -n "${N8N_API_KEY:-}" ]]; then
        AUTH_HEADER="X-N8N-API-KEY: $N8N_API_KEY"
        print_info "Using API Key authentication"
    else
        print_error "No authentication method configured"
        echo "Please set one of:"
        echo "  - N8N_PERSONAL_ACCESS_TOKEN"
        echo "  - N8N_API_KEY"
        exit 1
    fi
}

# Function to make API request
make_api_request() {
    local method="$1"
    local url="$2"
    local data="${3:-}"
    
    local curl_opts=(
        -s
        -X "$method"
        -H "Content-Type: application/json"
        -H "$AUTH_HEADER"
    )
    
    if [[ -n "$data" ]]; then
        curl_opts+=(-d "$data")
    fi
    
    # Add timeout and retry options
    curl_opts+=(--connect-timeout 10 --max-time 30 --retry 3)
    
    local response
    local http_code
    
    response=$(curl "${curl_opts[@]}" -w "\\n%{http_code}" "$url" 2>/dev/null)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | head -n -1)
    
    case "$http_code" in
        200|201)
            echo "$response"
            return 0
            ;;
        400)
            print_error "Bad request (400): $(echo "$response" | jq -r '.message // .error // .')"
            return 1
            ;;
        401)
            print_error "Unauthorized (401): Check your authentication credentials"
            return 1
            ;;
        403)
            print_error "Forbidden (403): Insufficient permissions"
            return 1
            ;;
        404)
            print_error "Not found (404): Resource does not exist"
            return 1
            ;;
        422)
            print_error "Validation error (422): $(echo "$response" | jq -r '.message // .error // .')"
            return 1
            ;;
        500)
            print_error "Server error (500): $(echo "$response" | jq -r '.message // .error // .')"
            return 1
            ;;
        *)
            print_error "HTTP $http_code: $response"
            return 1
            ;;
    esac
}

# Function to test N8N connectivity
test_n8n_connection() {
    print_info "Testing N8N connection..."
    
    local response
    if response=$(make_api_request "GET" "$N8N_BASE_URL/healthz" 2>/dev/null); then
        print_success "N8N is accessible"
    else
        print_warning "N8N health check failed, but will continue..."
    fi
}

# Function to list workflows with filtering and pagination
list_workflows() {
    local limit="${1:-50}"
    local cursor="${2:-}"
    local active_filter="${3:-}"
    local name_filter="${4:-}"
    local tag_filter="${5:-}"
    local all_results="${6:-false}"
    
    local url="$WORKFLOWS_API_URL"
    local query_params=()
    
    # Add limit parameter
    query_params+=("limit=$limit")
    
    # Add cursor parameter if provided
    if [[ -n "$cursor" ]]; then
        query_params+=("cursor=$cursor")
    fi
    
    # Add active filter
    if [[ "$active_filter" == "true" ]]; then
        query_params+=("active=true")
    elif [[ "$active_filter" == "false" ]]; then
        query_params+=("active=false")
    fi
    
    # Add tag filter
    if [[ -n "$tag_filter" ]]; then
        query_params+=("tags=$tag_filter")
    fi
    
    # Build URL with query parameters
    if [[ ${#query_params[@]} -gt 0 ]]; then
        url="$url?$(IFS='&'; echo "${query_params[*]}")"
    fi
    
    local response
    if ! response=$(make_api_request "GET" "$url"); then
        return 1
    fi
    
    # Filter by name if specified (API doesn't support name filtering)
    if [[ -n "$name_filter" ]]; then
        response=$(echo "$response" | jq --arg name "$name_filter" '.data |= map(select(.name | test($name; "i")))')
    fi
    
    local count
    count=$(echo "$response" | jq '.data | length')
    
    if [[ "$count" -eq 0 ]]; then
        print_info "No workflows found"
        return 0
    fi
    
    # Display results
    if [[ -z "$cursor" ]]; then
        if [[ -n "$active_filter" ]]; then
            local status_text
            [[ "$active_filter" == "true" ]] && status_text="active" || status_text="inactive"
            print_success "Found $count $status_text workflows:"
        else
            print_success "Found $count workflows:"
        fi
    else
        print_success "Found $count workflows (page):"
    fi
    echo
    
    printf "%-36s %-25s %-8s %-8s %-20s\\n" "ID" "NAME" "ACTIVE" "NODES" "UPDATED"
    echo "$(printf '%.0s-' {1..100})"
    
    echo "$response" | jq -r '.data[] | "\\(.id) \\(.name) \\(.active) \\(.nodes | length) \\(.updatedAt)"' | \
    while read -r id name active nodes updated; do
        # Truncate long names
        local short_name="${name:0:23}"
        if [[ ${#name} -gt 23 ]]; then
            short_name="${short_name}..."
        fi
        
        # Color code active status
        local active_display
        if [[ "$active" == "true" ]]; then
            active_display="${GREEN}✓${NC}"
        else
            active_display="${RED}✗${NC}"
        fi
        
        printf "%-36s %-25s %-16s %-8s %-20s\\n" "$id" "$short_name" "$active_display" "$nodes" "${updated:0:19}"
    done
    
    # Check for next page
    local next_cursor
    next_cursor=$(echo "$response" | jq -r '.nextCursor // empty')
    
    if [[ -n "$next_cursor" ]]; then
        echo
        print_info "Next page cursor: $next_cursor"
        
        if [[ "$all_results" == "true" ]]; then
            print_info "Fetching next page..."
            echo
            list_workflows "$limit" "$next_cursor" "$active_filter" "$name_filter" "$tag_filter" "true"
        else
            print_info "To get next page, use: $0 --list --cursor $next_cursor"
        fi
    fi
}

# Function to get workflow details
get_workflow_details() {
    local workflow_id="$1"
    
    print_info "Fetching workflow details for: $workflow_id"
    
    local response
    if response=$(make_api_request "GET" "$WORKFLOWS_API_URL/$workflow_id"); then
        print_success "Workflow Details:"
        echo
        
        local name active created updated tags
        name=$(echo "$response" | jq -r '.name')
        active=$(echo "$response" | jq -r '.active')
        created=$(echo "$response" | jq -r '.createdAt')
        updated=$(echo "$response" | jq -r '.updatedAt')
        tags=$(echo "$response" | jq -r '.tags[]? // empty' | tr '\n' ',' | sed 's/,$//')
        
        echo "Workflow ID: $workflow_id"
        echo "Name: $name"
        echo "Status: $(if [[ "$active" == "true" ]]; then echo "${GREEN}Active${NC}"; else echo "${RED}Inactive${NC}"; fi)"
        echo "Created: ${created:0:19}"
        echo "Updated: ${updated:0:19}"
        if [[ -n "$tags" ]]; then
            echo "Tags: $tags"
        fi
        
        # Node information
        local node_count
        node_count=$(echo "$response" | jq '.nodes | length')
        echo "Nodes: $node_count"
        
        if [[ $node_count -gt 0 ]]; then
            echo
            print_info "Node Types:"
            echo "$response" | jq -r '.nodes[] | "  - \\(.type): \\(.name)"' | head -10
            if [[ $node_count -gt 10 ]]; then
                echo "  ... and $((node_count - 10)) more nodes"
            fi
        fi
        
        # Trigger information
        local triggers
        triggers=$(echo "$response" | jq '[.nodes[] | select(.type | test("trigger|webhook|cron"))] | length')
        if [[ $triggers -gt 0 ]]; then
            echo
            print_info "Triggers: $triggers"
            echo "$response" | jq -r '.nodes[] | select(.type | test("trigger|webhook|cron")) | "  - \\(.type): \\(.name)"'
        fi
    else
        return 1
    fi
}

# Function to activate workflow
activate_workflow() {
    local workflow_id="$1"
    
    print_info "Activating workflow: $workflow_id"
    
    if make_api_request "POST" "$WORKFLOWS_API_URL/$workflow_id/activate" >/dev/null; then
        print_success "Workflow activated: $workflow_id"
        return 0
    else
        return 1
    fi
}

# Function to deactivate workflow
deactivate_workflow() {
    local workflow_id="$1"
    
    print_info "Deactivating workflow: $workflow_id"
    
    if make_api_request "POST" "$WORKFLOWS_API_URL/$workflow_id/deactivate" >/dev/null; then
        print_success "Workflow deactivated: $workflow_id"
        return 0
    else
        return 1
    fi
}

# Function to delete workflow
delete_workflow() {
    local workflow_id="$1"
    
    print_info "Deleting workflow: $workflow_id"
    
    if make_api_request "DELETE" "$WORKFLOWS_API_URL/$workflow_id" >/dev/null; then
        print_success "Workflow deleted: $workflow_id"
        return 0
    else
        return 1
    fi
}

# Function to create workflow
create_workflow() {
    local workflow_file="$1"
    
    if [[ ! -f "$workflow_file" ]]; then
        print_error "Workflow file not found: $workflow_file"
        return 1
    fi
    
    print_info "Creating workflow from: $workflow_file"
    
    local workflow_data
    workflow_data=$(cat "$workflow_file")
    
    # Validate JSON
    if ! echo "$workflow_data" | jq empty 2>/dev/null; then
        print_error "Invalid JSON in workflow file"
        return 1
    fi
    
    local response
    if response=$(make_api_request "POST" "$WORKFLOWS_API_URL" "$workflow_data"); then
        local new_id
        new_id=$(echo "$response" | jq -r '.id')
        local name
        name=$(echo "$response" | jq -r '.name')
        print_success "Created workflow: $name (ID: $new_id)"
        return 0
    else
        return 1
    fi
}

# Function to update workflow
update_workflow() {
    local workflow_id="$1"
    local workflow_file="$2"
    
    if [[ ! -f "$workflow_file" ]]; then
        print_error "Workflow file not found: $workflow_file"
        return 1
    fi
    
    print_info "Updating workflow: $workflow_id"
    
    local workflow_data
    workflow_data=$(cat "$workflow_file")
    
    # Validate JSON
    if ! echo "$workflow_data" | jq empty 2>/dev/null; then
        print_error "Invalid JSON in workflow file"
        return 1
    fi
    
    local response
    if response=$(make_api_request "PUT" "$WORKFLOWS_API_URL/$workflow_id" "$workflow_data"); then
        local name
        name=$(echo "$response" | jq -r '.name')
        print_success "Updated workflow: $name (ID: $workflow_id)"
        return 0
    else
        return 1
    fi
}

# Function to duplicate workflow
duplicate_workflow() {
    local workflow_id="$1"
    
    print_info "Duplicating workflow: $workflow_id"
    
    # First get the workflow
    local response
    if ! response=$(make_api_request "GET" "$WORKFLOWS_API_URL/$workflow_id"); then
        return 1
    fi
    
    # Modify for duplication
    local duplicate_data
    duplicate_data=$(echo "$response" | jq '.name = "Copy of " + .name | del(.id, .createdAt, .updatedAt) | .active = false')
    
    # Create the duplicate
    if response=$(make_api_request "POST" "$WORKFLOWS_API_URL" "$duplicate_data"); then
        local new_id
        new_id=$(echo "$response" | jq -r '.id')
        local name
        name=$(echo "$response" | jq -r '.name')
        print_success "Duplicated workflow: $name (ID: $new_id)"
        return 0
    else
        return 1
    fi
}

# Function to export workflow
export_workflow() {
    local workflow_id="$1"
    local output_file="$2"
    
    print_info "Exporting workflow: $workflow_id to $output_file"
    
    local response
    if response=$(make_api_request "GET" "$WORKFLOWS_API_URL/$workflow_id"); then
        # Clean up the response for export
        echo "$response" | jq 'del(.id, .createdAt, .updatedAt) | .active = false' > "$output_file"
        
        local name
        name=$(echo "$response" | jq -r '.name')
        print_success "Exported workflow: $name to $output_file"
        return 0
    else
        return 1
    fi
}

# Main function
main() {
    print_header
    
    # Parse command line arguments
    local action="list"
    local workflow_id=""
    local workflow_file=""
    local output_file=""
    local limit="50"
    local cursor=""
    local active_filter=""
    local name_filter=""
    local tag_filter=""
    local all_results=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                action="list"
                shift
                ;;
            --get)
                action="get"
                workflow_id="$2"
                shift 2
                ;;
            --activate)
                action="activate"
                workflow_id="$2"
                shift 2
                ;;
            --deactivate)
                action="deactivate"
                workflow_id="$2"
                shift 2
                ;;
            --delete)
                action="delete"
                workflow_id="$2"
                shift 2
                ;;
            --create)
                action="create"
                workflow_file="$2"
                shift 2
                ;;
            --update)
                action="update"
                workflow_id="$2"
                workflow_file="$3"
                shift 3
                ;;
            --duplicate)
                action="duplicate"
                workflow_id="$2"
                shift 2
                ;;
            --export)
                action="export"
                workflow_id="$2"
                output_file="$3"
                shift 3
                ;;
            --import)
                action="import"
                workflow_file="$2"
                shift 2
                ;;
            --status)
                action="status"
                shift
                ;;
            --health)
                action="health"
                shift
                ;;
            --performance)
                action="performance"
                shift
                ;;
            --watch)
                action="watch"
                shift
                ;;
            --active)
                active_filter="true"
                shift
                ;;
            --inactive)
                active_filter="false"
                shift
                ;;
            --name)
                name_filter="$2"
                shift 2
                ;;
            --tag)
                tag_filter="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --cursor)
                cursor="$2"
                shift 2
                ;;
            --all)
                all_results=true
                shift
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
    
    # Check dependencies
    check_dependencies
    
    # Setup authentication
    setup_authentication
    test_n8n_connection
    
    # Validate limit
    if [[ "$limit" =~ ^[0-9]+$ ]] && [[ "$limit" -gt 0 ]] && [[ "$limit" -le 250 ]]; then
        : # Valid limit
    else
        print_error "Invalid limit value. Must be between 1 and 250."
        exit 1
    fi
    
    # Execute action
    case "$action" in
        list)
            list_workflows "$limit" "$cursor" "$active_filter" "$name_filter" "$tag_filter" "$all_results"
            ;;
        get)
            if [[ -z "$workflow_id" ]]; then
                print_error "Workflow ID required with --get option"
                exit 1
            fi
            get_workflow_details "$workflow_id"
            ;;
        activate)
            if [[ -z "$workflow_id" ]]; then
                print_error "Workflow ID required with --activate option"
                exit 1
            fi
            activate_workflow "$workflow_id"
            ;;
        deactivate)
            if [[ -z "$workflow_id" ]]; then
                print_error "Workflow ID required with --deactivate option"
                exit 1
            fi
            deactivate_workflow "$workflow_id"
            ;;
        delete)
            if [[ -z "$workflow_id" ]]; then
                print_error "Workflow ID required with --delete option"
                exit 1
            fi
            delete_workflow "$workflow_id"
            ;;
        create|import)
            if [[ -z "$workflow_file" ]]; then
                print_error "Workflow file required with --create/--import option"
                exit 1
            fi
            create_workflow "$workflow_file"
            ;;
        update)
            if [[ -z "$workflow_id" || -z "$workflow_file" ]]; then
                print_error "Workflow ID and file required with --update option"
                exit 1
            fi
            update_workflow "$workflow_id" "$workflow_file"
            ;;
        duplicate)
            if [[ -z "$workflow_id" ]]; then
                print_error "Workflow ID required with --duplicate option"
                exit 1
            fi
            duplicate_workflow "$workflow_id"
            ;;
        export)
            if [[ -z "$workflow_id" || -z "$output_file" ]]; then
                print_error "Workflow ID and output file required with --export option"
                exit 1
            fi
            export_workflow "$workflow_id" "$output_file"
            ;;
        status)
            show_status_summary
            ;;
        health)
            check_workflow_health
            ;;
        performance)
            show_performance_metrics
            ;;
        watch)
            watch_workflows "$active_filter"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
