#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - CREDENTIAL MANAGEMENT SCRIPT
# =============================================================================
# This script creates and manages credentials in N8N using the REST API
# Supports both Personal Access Token (PAT) and Public API Key authentication
# Includes type normalization, placeholder expansion, and bulk operations

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
    echo "                    N8N CREDENTIAL MANAGEMENT"
    echo "============================================================================="
    echo
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] --type TYPE --name NAME --data DATA

Create or manage credentials in N8N using the REST API.

OPTIONS:
    --type TYPE         Credential type (postgres, redis, qdrant, neo4j, http, etc.)
    --name NAME         Credential name
    --data DATA         Credential data (JSON string or @file.json)
    --file FILE         JSON file containing credential data
    --bulk FILE         Bulk create from JSON file with array of credentials
    --list              List existing credentials
    --limit LIMIT       Limit results per page (default: 100, max: 250)
    --cursor CURSOR     Cursor for pagination (get from previous response)
    --all               Get all results across all pages
    --get-schema TYPE   Get credential schema for specific type
    --list-types        List available credential types
    --delete ID         Delete credential by ID
    --update ID         Update existing credential
    --test ID           Test credential connection (if supported)
    --dry-run          Show what would be created without actually doing it
    --help             Show this help message

AUTHENTICATION:
    Set one of these environment variables:
    - N8N_PERSONAL_ACCESS_TOKEN: Personal Access Token for REST API
    - N8N_API_KEY: Public API Key for webhook/public endpoints

    N8N_BASE_URL: N8N base URL (default: http://localhost:5678)

EXAMPLES:
    # Create PostgreSQL credential
    $0 --type postgres --name "main-db" --data '{"host":"postgres","port":5432,"database":"n8n","username":"user","password":"pass"}'
    
    # Create from file
    $0 --type redis --name "cache" --file redis-config.json
    
    # Bulk create from file
    $0 --bulk credentials.json
    
    # List credentials
    $0 --list
    
    # List with custom page size
    $0 --list --limit 50
    
    # Get all credentials across all pages
    $0 --list --all
    
    # Get specific page using cursor
    $0 --list --cursor MTIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDA
    
    # Get credential schema
    $0 --get-schema githubApi
    
    # List available credential types
    $0 --list-types
    
    # Delete credential
    $0 --delete cred_123

SUPPORTED TYPES:
    - postgres/postgresql: PostgreSQL database
    - redis: Redis cache
    - qdrant: Qdrant vector database
    - neo4j: Neo4j graph database
    - http: HTTP authentication
    - webhook: Webhook credentials
    - oauth2: OAuth2 credentials

EOF
}

# Configuration
N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
CREDENTIAL_API_URL="$N8N_BASE_URL/api/v1/credentials"

# Credential type mappings for normalization
declare -A CREDENTIAL_TYPE_MAP=(
    ["postgres"]="postgres"
    ["postgresql"]="postgres"
    ["redis"]="redis"
    ["qdrant"]="httpHeaderAuth"
    ["neo4j"]="neo4j"
    ["http"]="httpHeaderAuth"
    ["webhook"]="webhook"
    ["oauth2"]="oAuth2Api"
)

# Default credential schemas
get_credential_schema() {
    local type="$1"
    case "$type" in
        postgres)
            echo '{
                "host": "${POSTGRES_HOST:-postgres}",
                "port": "${POSTGRES_PORT:-5432}",
                "database": "${POSTGRES_DB:-n8n}",
                "username": "${POSTGRES_USER:-n8n_user}",
                "password": "${POSTGRES_PASSWORD}",
                "ssl": "disable"
            }'
            ;;
        redis)
            echo '{
                "host": "${REDIS_HOST:-redis}",
                "port": "${REDIS_PORT:-6379}",
                "password": "${REDIS_PASSWORD:-}",
                "database": "${REDIS_DATABASE:-0}"
            }'
            ;;
        qdrant)
            echo '{
                "name": "X-API-Key",
                "value": "${QDRANT_API_KEY}"
            }'
            ;;
        neo4j)
            echo '{
                "scheme": "${NEO4J_SCHEME:-bolt}",
                "host": "${NEO4J_HOST:-neo4j}",
                "port": "${NEO4J_PORT:-7687}",
                "username": "${NEO4J_USER:-neo4j}",
                "password": "${NEO4J_PASSWORD}"
            }'
            ;;
        *)
            echo '{}'
            ;;
    esac
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl jq envsubst; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies:"
        echo "  - Ubuntu/Debian: sudo apt install curl jq gettext-base"
        echo "  - CentOS/RHEL: sudo yum install curl jq gettext"
        echo "  - macOS: brew install curl jq gettext"
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

# Function to normalize credential type
normalize_credential_type() {
    local input_type="$1"
    local normalized_type="${CREDENTIAL_TYPE_MAP[$input_type]:-$input_type}"
    echo "$normalized_type"
}

# Function to expand environment variables in JSON
expand_placeholders() {
    local data="$1"
    
    # Use envsubst to expand environment variables
    echo "$data" | envsubst
}

# Function to validate JSON
validate_json() {
    local json_data="$1"
    
    if ! echo "$json_data" | jq empty 2>/dev/null; then
        print_error "Invalid JSON data"
        return 1
    fi
    
    return 0
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

# Function to list credentials with pagination support
list_credentials() {
    local limit="${1:-100}"  # Default page size 100
    local cursor="${2:-}"    # Optional cursor for pagination
    local all_results="${3:-false}"  # Get all results flag
    
    local url="$CREDENTIAL_API_URL"
    local query_params=()
    
    # Add limit parameter
    if [[ "$limit" != "100" ]]; then
        query_params+=("limit=$limit")
    fi
    
    # Add cursor parameter if provided
    if [[ -n "$cursor" ]]; then
        query_params+=("cursor=$cursor")
    fi
    
    # Build URL with query parameters
    if [[ ${#query_params[@]} -gt 0 ]]; then
        url="$url?$(IFS='&'; echo "${query_params[*]}")"
    fi
    
    print_info "Fetching credentials from N8N..."
    
    local response
    if response=$(make_api_request "GET" "$url"); then
        local count
        count=$(echo "$response" | jq '.data | length')
        
        if [[ "$count" -eq 0 ]]; then
            print_info "No credentials found"
            return 0
        fi
        
        # Display current page results
        if [[ -z "$cursor" ]]; then
            print_success "Found $count credentials:"
        else
            print_success "Found $count credentials (page):"
        fi
        echo
        printf "%-36s %-20s %-15s %-20s\\n" "ID" "NAME" "TYPE" "CREATED"
        echo "$(printf '%.0s-' {1..92})"
        
        echo "$response" | jq -r '.data[] | "\(.id) \(.name) \(.type) \(.createdAt)"' | \
        while read -r id name type created; do
            printf "%-36s %-20s %-15s %-20s\\n" "$id" "$name" "$type" "${created:0:19}"
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
                list_credentials "$limit" "$next_cursor" "true"
            else
                print_info "To get next page, use: $0 --list --limit $limit --cursor $next_cursor"
            fi
        fi
    else
        return 1
    fi
}

# Function to create credential
create_credential() {
    local cred_name="$1"
    local cred_type="$2"
    local cred_data="$3"
    local dry_run="${4:-false}"
    
    # Normalize type
    local normalized_type
    normalized_type=$(normalize_credential_type "$cred_type")
    
    # Expand placeholders
    local expanded_data
    expanded_data=$(expand_placeholders "$cred_data")
    
    # Validate JSON
    if ! validate_json "$expanded_data"; then
        return 1
    fi
    
    # Create payload
    local payload
    payload=$(jq -n \
        --arg name "$cred_name" \
        --arg type "$normalized_type" \
        --argjson data "$expanded_data" \
        '{name: $name, type: $type, data: $data}')
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run - would create credential:"
        echo "$payload" | jq '.'
        return 0
    fi
    
    print_info "Creating credential: $cred_name ($normalized_type)"
    
    local response
    if response=$(make_api_request "POST" "$CREDENTIAL_API_URL" "$payload"); then
        local cred_id
        cred_id=$(echo "$response" | jq -r '.id')
        print_success "Created credential: $cred_name (ID: $cred_id)"
        return 0
    else
        return 1
    fi
}

# Function to update credential
update_credential() {
    local cred_id="$1"
    local cred_name="$2"
    local cred_type="$3"
    local cred_data="$4"
    local dry_run="${5:-false}"
    
    # Normalize type
    local normalized_type
    normalized_type=$(normalize_credential_type "$cred_type")
    
    # Expand placeholders
    local expanded_data
    expanded_data=$(expand_placeholders "$cred_data")
    
    # Validate JSON
    if ! validate_json "$expanded_data"; then
        return 1
    fi
    
    # Create payload
    local payload
    payload=$(jq -n \
        --arg name "$cred_name" \
        --arg type "$normalized_type" \
        --argjson data "$expanded_data" \
        '{name: $name, type: $type, data: $data}')
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run - would update credential:"
        echo "$payload" | jq '.'
        return 0
    fi
    
    print_info "Updating credential: $cred_id"
    
    local response
    if response=$(make_api_request "PUT" "$CREDENTIAL_API_URL/$cred_id" "$payload"); then
        print_success "Updated credential: $cred_id"
        return 0
    else
        return 1
    fi
}

# Function to delete credential
delete_credential() {
    local cred_id="$1"
    local dry_run="${2:-false}"
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run - would delete credential: $cred_id"
        return 0
    fi
    
    print_info "Deleting credential: $cred_id"
    
    if make_api_request "DELETE" "$CREDENTIAL_API_URL/$cred_id" >/dev/null; then
        print_success "Deleted credential: $cred_id"
        return 0
    else
        return 1
    fi
}

# Function to bulk create credentials
bulk_create_credentials() {
    local bulk_file="$1"
    local dry_run="${2:-false}"
    
    if [[ ! -f "$bulk_file" ]]; then
        print_error "Bulk file not found: $bulk_file"
        return 1
    fi
    
    print_info "Processing bulk credentials from: $bulk_file"
    
    # Validate bulk file
    if ! validate_json "$(cat "$bulk_file")"; then
        print_error "Invalid JSON in bulk file"
        return 1
    fi
    
    local credentials
    credentials=$(cat "$bulk_file")
    
    # Check if it's an array
    if ! echo "$credentials" | jq -e 'type == "array"' >/dev/null; then
        print_error "Bulk file must contain a JSON array of credentials"
        return 1
    fi
    
    local total_count
    total_count=$(echo "$credentials" | jq 'length')
    
    print_info "Found $total_count credentials to process"
    
    local success_count=0
    local error_count=0
    
    # Process each credential
    for i in $(seq 0 $((total_count - 1))); do
        local cred
        cred=$(echo "$credentials" | jq ".[$i]")
        
        local name type data
        name=$(echo "$cred" | jq -r '.name')
        type=$(echo "$cred" | jq -r '.type')
        data=$(echo "$cred" | jq -c '.data')
        
        if [[ "$name" == "null" || "$type" == "null" || "$data" == "null" ]]; then
            print_warning "Skipping invalid credential at index $i"
            ((error_count++))
            continue
        fi
        
        if create_credential "$name" "$type" "$data" "$dry_run"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    print_info "Bulk operation completed:"
    print_success "  Created: $success_count"
    if [[ $error_count -gt 0 ]]; then
        print_error "  Failed: $error_count"
    fi
    
    return 0
}

# Function to get credential schema from API
get_credential_schema_from_api() {
    local credential_type="$1"
    
    if [[ -z "$credential_type" ]]; then
        print_error "Credential type is required"
        return 1
    fi
    
    print_info "Fetching schema for credential type: $credential_type"
    
    local schema_url="$N8N_BASE_URL/api/v1/credentials/schema/$credential_type"
    local response
    
    if response=$(make_api_request "GET" "$schema_url"); then
        print_success "Schema for $credential_type:"
        echo "$response" | jq '.'
        return 0
    else
        print_error "Failed to fetch schema for credential type: $credential_type"
        return 1
    fi
}

# Function to list available credential types
list_credential_types() {
    print_info "Available credential types based on installed nodes:"
    
    # Common credential types
    local common_types=(
        "postgres"
        "redis"
        "httpHeaderAuth"
        "httpBasicAuth"
        "oAuth2Api"
        "githubApi"
        "notionApi"
        "slackApi"
        "googleSheetsOAuth2Api"
        "webhook"
    )
    
    echo
    print_success "Common credential types:"
    for type in "${common_types[@]}"; do
        echo "  - $type"
    done
    
    echo
    print_info "To get the exact schema for a type, use:"
    print_info "  $0 --get-schema <credential-type>"
}
generate_examples() {
    local example_file="$1"
    
    cat > "$example_file" << 'EOF'
[
  {
    "name": "Main PostgreSQL Database",
    "type": "postgres",
    "data": {
      "host": "${POSTGRES_HOST:-postgres}",
      "port": "${POSTGRES_PORT:-5432}",
      "database": "${POSTGRES_DB:-n8n}",
      "username": "${POSTGRES_USER:-n8n_user}",
      "password": "${POSTGRES_PASSWORD}",
      "ssl": "disable"
    }
  },
  {
    "name": "Redis Cache",
    "type": "redis",
    "data": {
      "host": "${REDIS_HOST:-redis}",
      "port": "${REDIS_PORT:-6379}",
      "password": "${REDIS_PASSWORD:-}",
      "database": "${REDIS_DATABASE:-0}"
    }
  },
  {
    "name": "Qdrant Vector DB",
    "type": "qdrant",
    "data": {
      "name": "X-API-Key",
      "value": "${QDRANT_API_KEY}"
    }
  }
]
EOF
    
    print_success "Generated example credentials file: $example_file"
    print_info "Edit the file and run: $0 --bulk $example_file"
}

# Main function
main() {
    print_header
    
    # Parse command line arguments
    local action=""
    local cred_type=""
    local cred_name=""
    local cred_data=""
    local cred_file=""
    local bulk_file=""
    local cred_id=""
    local dry_run=false
    local limit="100"
    local cursor=""
    local all_results=false
    local schema_type=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                cred_type="$2"
                shift 2
                ;;
            --name)
                cred_name="$2"
                shift 2
                ;;
            --data)
                cred_data="$2"
                shift 2
                ;;
            --file)
                cred_file="$2"
                shift 2
                ;;
            --bulk)
                action="bulk"
                bulk_file="$2"
                shift 2
                ;;
            --list)
                action="list"
                shift
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
            --get-schema)
                action="get-schema"
                schema_type="$2"
                shift 2
                ;;
            --list-types)
                action="list-types"
                shift
                ;;
            --delete)
                action="delete"
                cred_id="$2"
                shift 2
                ;;
            --update)
                action="update"
                cred_id="$2"
                shift 2
                ;;
            --test)
                action="test"
                cred_id="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --generate-examples)
                action="generate"
                cred_file="${2:-examples-credentials.json}"
                shift 2 2>/dev/null || shift
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
    
    # Setup authentication (skip for generate action)
    if [[ "$action" != "generate" ]]; then
        setup_authentication
        test_n8n_connection
    fi
    
    # Execute action
    case "$action" in
        list)
            # Validate limit parameter
            if [[ "$limit" =~ ^[0-9]+$ ]] && [[ "$limit" -gt 0 ]] && [[ "$limit" -le 250 ]]; then
                list_credentials "$limit" "$cursor" "$all_results"
            else
                print_error "Invalid limit value. Must be between 1 and 250."
                exit 1
            fi
            ;;
        bulk)
            if [[ -z "$bulk_file" ]]; then
                print_error "Bulk file required with --bulk option"
                exit 1
            fi
            bulk_create_credentials "$bulk_file" "$dry_run"
            ;;
        delete)
            if [[ -z "$cred_id" ]]; then
                print_error "Credential ID required with --delete option"
                exit 1
            fi
            delete_credential "$cred_id" "$dry_run"
            ;;
        update)
            if [[ -z "$cred_id" || -z "$cred_name" || -z "$cred_type" ]]; then
                print_error "Credential ID, name, and type required with --update option"
                exit 1
            fi
            
            # Get data from file or command line
            if [[ -n "$cred_file" ]]; then
                if [[ ! -f "$cred_file" ]]; then
                    print_error "Credential file not found: $cred_file"
                    exit 1
                fi
                cred_data=$(cat "$cred_file")
            elif [[ -z "$cred_data" ]]; then
                print_error "Credential data required (use --data or --file)"
                exit 1
            fi
            
            update_credential "$cred_id" "$cred_name" "$cred_type" "$cred_data" "$dry_run"
            ;;
        test)
            print_warning "Credential testing not yet implemented"
            ;;
        generate)
            generate_examples "$cred_file"
            ;;
        get-schema)
            if [[ -z "$schema_type" ]]; then
                print_error "Credential type required with --get-schema option"
                exit 1
            fi
            get_credential_schema_from_api "$schema_type"
            ;;
        list-types)
            list_credential_types
            ;;
        *)
            # Default: create credential
            if [[ -z "$cred_type" || -z "$cred_name" ]]; then
                print_error "Credential type and name are required"
                echo "Use --help for usage information"
                exit 1
            fi
            
            # Get data from file or command line
            if [[ -n "$cred_file" ]]; then
                if [[ ! -f "$cred_file" ]]; then
                    print_error "Credential file not found: $cred_file"
                    exit 1
                fi
                cred_data=$(cat "$cred_file")
            elif [[ -z "$cred_data" ]]; then
                # Use default schema if no data provided
                cred_data=$(get_credential_schema "$cred_type")
                print_info "Using default schema for type: $cred_type"
            fi
            
            # Handle @file.json syntax
            if [[ "$cred_data" == @* ]]; then
                local file_path="${cred_data:1}"
                if [[ ! -f "$file_path" ]]; then
                    print_error "Data file not found: $file_path"
                    exit 1
                fi
                cred_data=$(cat "$file_path")
            fi
            
            create_credential "$cred_name" "$cred_type" "$cred_data" "$dry_run"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi