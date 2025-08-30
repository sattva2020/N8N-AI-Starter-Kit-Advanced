#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - EXECUTION MONITORING SCRIPT
# =============================================================================
# This script monitors and manages workflow executions in N8N using the REST API
# Supports execution listing, filtering by status/workflow, and detailed analysis

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
NC='\033[0m' # No Color

# Print functions
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_stat() { echo -e "${CYAN}📊${NC} $1"; }

print_header() {
    echo "============================================================================="
    echo "                    N8N EXECUTION MONITORING"
    echo "============================================================================="
    echo
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Monitor and manage N8N workflow executions using the REST API.

OPTIONS:
    --list              List executions (default action)
    --get ID            Get detailed execution information
    --delete ID         Delete execution by ID
    --watch             Watch executions in real-time (refresh every 10s)
    --stats             Show execution statistics
    --export FILE       Export executions to JSON file
    
FILTERING OPTIONS:
    --workflow ID       Filter by workflow ID
    --workflow-name NAME Filter by workflow name
    --status STATUS     Filter by status (error, success, waiting, running)
    --limit LIMIT       Limit results per page (default: 50, max: 250)
    --cursor CURSOR     Cursor for pagination
    --all               Get all results across all pages
    --since DATE        Show executions since date (YYYY-MM-DD)
    --details           Include execution details in listing

AUTHENTICATION:
    Set one of these environment variables:
    - N8N_PERSONAL_ACCESS_TOKEN: Personal Access Token for REST API
    - N8N_API_KEY: Public API Key for webhook/public endpoints

    N8N_BASE_URL: N8N base URL (default: http://localhost:5678)

EXAMPLES:
    # List recent executions
    $0 --list --limit 20
    
    # Watch executions in real-time
    $0 --watch
    
    # Show failed executions
    $0 --list --status error --details
    
    # Get execution statistics
    $0 --stats
    
    # Export all executions to file
    $0 --export executions.json --all
    
    # Monitor specific workflow
    $0 --list --workflow-name "Data Processing" --watch

EXECUTION STATUSES:
    - error: Execution failed
    - success: Execution completed successfully  
    - waiting: Execution is waiting for trigger or manual input
    - running: Execution is currently running

EOF
}

# Configuration
N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
EXECUTIONS_API_URL="$N8N_BASE_URL/api/v1/executions"
WORKFLOWS_API_URL="$N8N_BASE_URL/api/v1/workflows"

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

# Function to get workflow name by ID
get_workflow_name() {
    local workflow_id="$1"
    local response
    
    if response=$(make_api_request "GET" "$WORKFLOWS_API_URL/$workflow_id" 2>/dev/null); then
        echo "$response" | jq -r '.name // "Unknown"'
    else
        echo "Unknown"
    fi
}

# Function to format execution duration
format_duration() {
    local start_time="$1"
    local end_time="$2"
    
    if [[ "$start_time" == "null" || "$end_time" == "null" ]]; then
        echo "N/A"
        return
    fi
    
    # Convert to timestamps (handle both formats)
    local start_ts end_ts
    start_ts=$(date -d "$start_time" +%s 2>/dev/null || echo "0")
    end_ts=$(date -d "$end_time" +%s 2>/dev/null || echo "0")
    
    if [[ "$start_ts" == "0" || "$end_ts" == "0" ]]; then
        echo "N/A"
        return
    fi
    
    local duration=$((end_ts - start_ts))
    
    if [[ $duration -lt 60 ]]; then
        echo "${duration}s"
    elif [[ $duration -lt 3600 ]]; then
        printf "%dm %ds" $((duration / 60)) $((duration % 60))
    else
        printf "%dh %dm %ds" $((duration / 3600)) $(((duration % 3600) / 60)) $((duration % 60))
    fi
}

# Function to list executions with filtering and pagination
list_executions() {
    local limit="${1:-50}"
    local cursor="${2:-}"
    local workflow_filter="${3:-}"
    local status_filter="${4:-}"
    local all_results="${5:-false}"
    local include_details="${6:-false}"
    local since_date="${7:-}"
    
    local url="$EXECUTIONS_API_URL"
    local query_params=()
    
    # Add limit parameter
    query_params+=("limit=$limit")
    
    # Add cursor parameter if provided
    if [[ -n "$cursor" ]]; then
        query_params+=("cursor=$cursor")
    fi
    
    # Add workflow filter
    if [[ -n "$workflow_filter" ]]; then
        query_params+=("workflowId=$workflow_filter")
    fi
    
    # Add status filter
    if [[ -n "$status_filter" ]]; then
        query_params+=("status=$status_filter")
    fi
    
    # Add include details
    if [[ "$include_details" == "true" ]]; then
        query_params+=("includeData=true")
    fi
    
    # Build URL with query parameters
    if [[ ${#query_params[@]} -gt 0 ]]; then
        url="$url?$(IFS='&'; echo "${query_params[*]}")"
    fi
    
    local response
    if ! response=$(make_api_request "GET" "$url"); then
        return 1
    fi
    
    local count
    count=$(echo "$response" | jq '.data | length')
    
    if [[ "$count" -eq 0 ]]; then
        print_info "No executions found"
        return 0
    fi
    
    # Filter by date if specified
    if [[ -n "$since_date" ]]; then
        local since_ts
        since_ts=$(date -d "$since_date" +%s 2>/dev/null || echo "0")
        if [[ "$since_ts" == "0" ]]; then
            print_error "Invalid date format. Use YYYY-MM-DD"
            return 1
        fi
        
        # Filter executions
        response=$(echo "$response" | jq --arg since_ts "$since_ts" '
            .data |= map(select(((.startedAt // .createdAt) | fromdateiso8601) >= ($since_ts | tonumber)))
        ')
        count=$(echo "$response" | jq '.data | length')
        
        if [[ "$count" -eq 0 ]]; then
            print_info "No executions found since $since_date"
            return 0
        fi
    fi
    
    # Display results
    if [[ -z "$cursor" ]]; then
        if [[ -n "$status_filter" ]]; then
            print_success "Found $count executions with status: $status_filter"
        else
            print_success "Found $count executions:"
        fi
    else
        print_success "Found $count executions (page):"
    fi
    echo
    
    if [[ "$include_details" == "true" ]]; then
        printf "%-36s %-15s %-10s %-20s %-10s %-15s\\n" "ID" "WORKFLOW" "STATUS" "STARTED" "DURATION" "MODE"
    else
        printf "%-36s %-15s %-10s %-20s %-10s\\n" "ID" "WORKFLOW" "STATUS" "STARTED" "DURATION"
    fi
    echo "$(printf '%.0s-' {1..100})"
    
    echo "$response" | jq -r '.data[] | "\(.id) \(.workflowId) \(.status) \(.startedAt // .createdAt) \(.stoppedAt // "null") \(.mode // "trigger")"' | \
    while read -r id workflow_id status started stopped mode; do
        local duration
        duration=$(format_duration "$started" "$stopped")
        
        # Truncate workflow ID for display
        local short_workflow_id="${workflow_id:0:12}..."
        
        # Color code status
        local status_display
        case "$status" in
            "success") status_display="${GREEN}$status${NC}" ;;
            "error") status_display="${RED}$status${NC}" ;;
            "waiting") status_display="${YELLOW}$status${NC}" ;;
            "running") status_display="${CYAN}$status${NC}" ;;
            *) status_display="$status" ;;
        esac
        
        if [[ "$include_details" == "true" ]]; then
            printf "%-36s %-15s %-18s %-20s %-10s %-15s\\n" "$id" "$short_workflow_id" "$status_display" "${started:0:19}" "$duration" "$mode"
        else
            printf "%-36s %-15s %-18s %-20s %-10s\\n" "$id" "$short_workflow_id" "$status_display" "${started:0:19}" "$duration"
        fi
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
            list_executions "$limit" "$next_cursor" "$workflow_filter" "$status_filter" "true" "$include_details" "$since_date"
        else
            print_info "To get next page, use: $0 --list --cursor $next_cursor"
        fi
    fi
}

# Function to get detailed execution information
get_execution_details() {
    local execution_id="$1"
    
    print_info "Fetching execution details for: $execution_id"
    
    local response
    if response=$(make_api_request "GET" "$EXECUTIONS_API_URL/$execution_id?includeData=true"); then
        print_success "Execution Details:"
        echo
        
        # Basic info
        local workflow_id status started stopped mode
        workflow_id=$(echo "$response" | jq -r '.workflowId')
        status=$(echo "$response" | jq -r '.status')
        started=$(echo "$response" | jq -r '.startedAt // .createdAt')
        stopped=$(echo "$response" | jq -r '.stoppedAt // "null"')
        mode=$(echo "$response" | jq -r '.mode // "trigger"')
        
        local workflow_name
        workflow_name=$(get_workflow_name "$workflow_id")
        local duration
        duration=$(format_duration "$started" "$stopped")
        
        echo "Execution ID: $execution_id"
        echo "Workflow: $workflow_name ($workflow_id)"
        echo "Status: $status"
        echo "Mode: $mode"
        echo "Started: ${started:0:19}"
        if [[ "$stopped" != "null" ]]; then
            echo "Stopped: ${stopped:0:19}"
        fi
        echo "Duration: $duration"
        
        # Error details if failed
        if [[ "$status" == "error" ]]; then
            echo
            print_error "Error Details:"
            echo "$response" | jq -r '.data.resultData.error.message // "No error message available"'
        fi
        
        # Data summary
        echo
        print_info "Execution Data Summary:"
        local node_count
        node_count=$(echo "$response" | jq '.data.resultData.runData | length // 0')
        echo "Nodes executed: $node_count"
        
        if [[ $node_count -gt 0 ]]; then
            echo "Node execution details:"
            echo "$response" | jq -r '.data.resultData.runData | keys[] as $node | "  - \($node): \(.[$node] | length) runs"'
        fi
    else
        return 1
    fi
}

# Function to delete execution
delete_execution() {
    local execution_id="$1"
    
    print_info "Deleting execution: $execution_id"
    
    if make_api_request "DELETE" "$EXECUTIONS_API_URL/$execution_id" >/dev/null; then
        print_success "Deleted execution: $execution_id"
        return 0
    else
        return 1
    fi
}

# Function to show execution statistics
show_execution_stats() {
    print_info "Calculating execution statistics..."
    
    # Get recent executions (last 1000)
    local response
    if ! response=$(make_api_request "GET" "$EXECUTIONS_API_URL?limit=250"); then
        return 1
    fi
    
    local total_count
    total_count=$(echo "$response" | jq '.data | length')
    
    if [[ "$total_count" -eq 0 ]]; then
        print_info "No executions found for statistics"
        return 0
    fi
    
    print_success "Execution Statistics (last $total_count executions):"
    echo
    
    # Status breakdown
    print_stat "Status Breakdown:"
    echo "$response" | jq -r '.data | group_by(.status) | .[] | "  \(.[0].status): \(length) executions"'
    
    echo
    # Success rate
    local success_count error_count
    success_count=$(echo "$response" | jq '[.data[] | select(.status == "success")] | length')
    error_count=$(echo "$response" | jq '[.data[] | select(.status == "error")] | length')
    
    if [[ $((success_count + error_count)) -gt 0 ]]; then
        local success_rate
        success_rate=$(echo "scale=1; $success_count * 100 / ($success_count + $error_count)" | bc 2>/dev/null || echo "N/A")
        print_stat "Success Rate: ${success_rate}% ($success_count/$((success_count + error_count)))"
    fi
    
    echo
    # Most active workflows
    print_stat "Most Active Workflows:"
    echo "$response" | jq -r '.data | group_by(.workflowId) | sort_by(length) | reverse | .[0:5] | .[] | "  \(.[0].workflowId): \(length) executions"'
    
    echo
    # Recent activity
    print_stat "Recent Activity (last 24h):"
    local yesterday
    yesterday=$(date -d "yesterday" +%s)
    local recent_count
    recent_count=$(echo "$response" | jq --arg yesterday "$yesterday" '[.data[] | select(((.startedAt // .createdAt) | fromdateiso8601) >= ($yesterday | tonumber))] | length')
    echo "  Executions in last 24h: $recent_count"
}

# Function to export executions
export_executions() {
    local output_file="$1"
    local all_results="${2:-false}"
    local workflow_filter="${3:-}"
    local status_filter="${4:-}"
    
    print_info "Exporting executions to: $output_file"
    
    local url="$EXECUTIONS_API_URL"
    local query_params=()
    
    if [[ "$all_results" == "false" ]]; then
        query_params+=("limit=250")
    else
        query_params+=("limit=250")
    fi
    
    # Add filters
    if [[ -n "$workflow_filter" ]]; then
        query_params+=("workflowId=$workflow_filter")
    fi
    
    if [[ -n "$status_filter" ]]; then
        query_params+=("status=$status_filter")
    fi
    
    # Include execution details
    query_params+=("includeData=true")
    
    # Build URL with query parameters
    if [[ ${#query_params[@]} -gt 0 ]]; then
        url="$url?$(IFS='&'; echo "${query_params[*]}")"
    fi
    
    local all_executions="[]"
    local cursor=""
    
    while true; do
        local current_url="$url"
        if [[ -n "$cursor" ]]; then
            current_url="$url&cursor=$cursor"
        fi
        
        local response
        if ! response=$(make_api_request "GET" "$current_url"); then
            return 1
        fi
        
        # Merge executions
        all_executions=$(echo "$all_executions" "$response" | jq -s '.[0] + .[1].data')
        
        # Check for next page
        cursor=$(echo "$response" | jq -r '.nextCursor // empty')
        
        if [[ -z "$cursor" || "$all_results" == "false" ]]; then
            break
        fi
        
        print_info "Fetched $(echo "$response" | jq '.data | length') executions, continuing..."
    done
    
    # Write to file
    echo "$all_executions" | jq '.' > "$output_file"
    
    local total_count
    total_count=$(echo "$all_executions" | jq 'length')
    print_success "Exported $total_count executions to: $output_file"
}

# Function to watch executions in real-time
watch_executions() {
    local workflow_filter="${1:-}"
    local status_filter="${2:-}"
    
    print_info "Watching executions in real-time (Press Ctrl+C to stop)"
    echo
    
    while true; do
        clear
        print_header
        
        # Show current time
        print_info "Last updated: $(date)"
        echo
        
        # List recent executions
        list_executions 20 "" "$workflow_filter" "$status_filter" false false
        
        # Wait 10 seconds
        sleep 10
    done
}

# Function to find workflow ID by name
find_workflow_by_name() {
    local workflow_name="$1"
    
    local response
    if response=$(make_api_request "GET" "$WORKFLOWS_API_URL?active=true"); then
        echo "$response" | jq -r --arg name "$workflow_name" '.data[] | select(.name == $name) | .id'
    fi
}

# Main function
main() {
    print_header
    
    # Parse command line arguments
    local action="list"
    local execution_id=""
    local limit="50"
    local cursor=""
    local workflow_filter=""
    local workflow_name=""
    local status_filter=""
    local all_results=false
    local include_details=false
    local since_date=""
    local export_file=""
    local watch_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                action="list"
                shift
                ;;
            --get)
                action="get"
                execution_id="$2"
                shift 2
                ;;
            --delete)
                action="delete"
                execution_id="$2"
                shift 2
                ;;
            --watch)
                action="watch"
                watch_mode=true
                shift
                ;;
            --stats)
                action="stats"
                shift
                ;;
            --export)
                action="export"
                export_file="$2"
                shift 2
                ;;
            --workflow)
                workflow_filter="$2"
                shift 2
                ;;
            --workflow-name)
                workflow_name="$2"
                shift 2
                ;;
            --status)
                status_filter="$2"
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
            --details)
                include_details=true
                shift
                ;;
            --since)
                since_date="$2"
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
    
    # Check dependencies
    check_dependencies
    
    # Setup authentication
    setup_authentication
    test_n8n_connection
    
    # Handle workflow name to ID conversion
    if [[ -n "$workflow_name" ]]; then
        workflow_filter=$(find_workflow_by_name "$workflow_name")
        if [[ -z "$workflow_filter" ]]; then
            print_error "Workflow not found: $workflow_name"
            exit 1
        fi
        print_info "Found workflow ID: $workflow_filter for name: $workflow_name"
    fi
    
    # Validate status filter
    if [[ -n "$status_filter" && ! "$status_filter" =~ ^(error|success|waiting|running)$ ]]; then
        print_error "Invalid status filter. Use: error, success, waiting, or running"
        exit 1
    fi
    
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
            list_executions "$limit" "$cursor" "$workflow_filter" "$status_filter" "$all_results" "$include_details" "$since_date"
            ;;
        get)
            if [[ -z "$execution_id" ]]; then
                print_error "Execution ID required with --get option"
                exit 1
            fi
            get_execution_details "$execution_id"
            ;;
        delete)
            if [[ -z "$execution_id" ]]; then
                print_error "Execution ID required with --delete option"
                exit 1
            fi
            delete_execution "$execution_id"
            ;;
        watch)
            watch_executions "$workflow_filter" "$status_filter"
            ;;
        stats)
            show_execution_stats
            ;;
        export)
            if [[ -z "$export_file" ]]; then
                print_error "Output file required with --export option"
                exit 1
            fi
            export_executions "$export_file" "$all_results" "$workflow_filter" "$status_filter"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi