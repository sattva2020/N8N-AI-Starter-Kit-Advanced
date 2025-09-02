#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - AUTOMATED CREDENTIAL SETUP
# =============================================================================
# This script automatically creates all necessary N8N credentials for the
# services included in this project using the N8N API.
# Requires a valid N8N API key or Personal Access Token.

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source environment if available
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # Load environment variables, excluding those that might interfere
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

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
print_step() { echo -e "${CYAN}➤${NC} $1"; }

print_header() {
    echo "============================================================================="
    echo "                    N8N AI STARTER KIT - AUTO CREDENTIAL SETUP"
    echo "============================================================================="
    echo
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automatically create N8N credentials for all services in the project.

OPTIONS:
    --dry-run           Show what would be created without creating
    --force             Overwrite existing credentials
    --skip-existing     Skip credentials that already exist (default)
    --services LIST     Comma-separated list of services to configure
                       Available: postgres,qdrant,redis,neo4j,clickhouse,ollama,openai
                       Default: postgres,qdrant,openai,ollama
    --list-services     Show available services and exit
    --check-auth        Test authentication and exit
    --help             Show this help message

AUTHENTICATION:
    Set one of these environment variables:
    - N8N_PERSONAL_ACCESS_TOKEN: Personal Access Token for REST API
    - N8N_API_KEY: Public API Key for webhook/public endpoints

    N8N_BASE_URL: N8N base URL (default: http://localhost:5678)

EXAMPLES:
    # Create all default credentials
    $0

    # Dry run to see what would be created
    $0 --dry-run

    # Create only database credentials
    $0 --services postgres,qdrant

    # Force recreate all credentials
    $0 --force

CREDENTIAL TEMPLATES:
    The script uses predefined templates for each service type, automatically
    populated with values from your .env file. All credentials include
    proper naming and descriptions for easy identification in N8N.

EOF
}

# Configuration
N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
CREDENTIAL_API_URL="$N8N_BASE_URL/api/v1/credentials"

# Default services to configure
DEFAULT_SERVICES="postgres,qdrant,openai,ollama"

# Service configuration templates
declare -A SERVICE_TEMPLATES=(
    ["postgres"]='postgres_template'
    ["qdrant"]='qdrant_template'
    ["redis"]='redis_template'
    ["neo4j"]='neo4j_template'
    ["clickhouse"]='clickhouse_template'
    ["ollama"]='ollama_template'
    ["openai"]='openai_template'
)

# Credential templates
postgres_template() {
    cat << 'EOF'
{
  "name": "PostgreSQL - Main Database",
  "type": "postgres", 
  "description": "Main PostgreSQL database for N8N and application data",
  "data": {
    "host": "${POSTGRES_HOST:-postgres}",
    "port": "${POSTGRES_PORT:-5432}",
    "database": "${POSTGRES_DB:-n8n}",
    "username": "${POSTGRES_USER:-n8n_user}",
    "password": "${POSTGRES_PASSWORD}",
    "ssl": "disable"
  }
}
EOF
}

qdrant_template() {
    cat << 'EOF'
{
  "name": "Qdrant - Vector Database",
  "type": "httpHeaderAuth",
  "description": "Qdrant vector database for AI embeddings and similarity search",
  "data": {
    "name": "api-key",
    "value": "${QDRANT_API_KEY}"
  }
}
EOF
}

redis_template() {
    cat << 'EOF'
{
  "name": "Redis - Cache Database", 
  "type": "redis",
  "description": "Redis cache for session storage and temporary data",
  "data": {
    "host": "${REDIS_HOST:-redis}",
    "port": "${REDIS_PORT:-6379}",
    "password": "${REDIS_PASSWORD:-}",
    "database": "${REDIS_DATABASE:-0}"
  }
}
EOF
}

neo4j_template() {
    cat << 'EOF'
{
  "name": "Neo4j - Graph Database",
  "type": "neo4j",
  "description": "Neo4j graph database for knowledge graphs and relationship data",
  "data": {
    "scheme": "${NEO4J_SCHEME:-bolt}",
    "host": "${NEO4J_HOST:-neo4j}",
    "port": "${NEO4J_PORT:-7687}",
    "username": "${NEO4J_USER:-neo4j}",
    "password": "${NEO4J_PASSWORD}"
  }
}
EOF
}

clickhouse_template() {
    cat << 'EOF'
{
  "name": "ClickHouse - Analytics Database",
  "type": "httpHeaderAuth",
  "description": "ClickHouse analytics database for time-series and analytics data",
  "data": {
    "name": "X-ClickHouse-User",
    "value": "${CLICKHOUSE_USER:-default}"
  }
}
EOF
}

ollama_template() {
    cat << 'EOF'
{
  "name": "Ollama - Local LLM Server",
  "type": "httpHeaderAuth", 
  "description": "Ollama local LLM server for AI model inference",
  "data": {
    "name": "Authorization",
    "value": "Bearer ollama-local"
  }
}
EOF
}

openai_template() {
    cat << 'EOF'
{
  "name": "OpenAI - API Service",
  "type": "httpHeaderAuth",
  "description": "OpenAI API for GPT models and embeddings",
  "data": {
    "name": "Authorization",
    "value": "Bearer ${OPENAI_API_KEY}"
  }
}
EOF
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
        echo
        echo "Please set one of the following environment variables:"
        echo "  - N8N_PERSONAL_ACCESS_TOKEN (recommended for full API access)"
        echo "  - N8N_API_KEY (for public API endpoints)"
        echo
        echo "You can generate these in N8N at:"
        echo "  Settings → Personal Access Token (for PAT)"
        echo "  Settings → API Key (for API Key)"
        exit 1
    fi
}

# Function to expand environment placeholders
expand_placeholders() {
    local template="$1"
    # Use envsubst to replace ${VAR} placeholders with actual values
    echo "$template" | envsubst
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
        400|401|403|404|422|500)
            echo "$response" >&2
            return 1
            ;;
        *)
            echo "HTTP $http_code: $response" >&2
            return 1
            ;;
    esac
}

# Function to test N8N connectivity and authentication
test_n8n_connection() {
    print_step "Testing N8N connectivity..."
    
    # Test basic connectivity
    if ! curl -s --connect-timeout 5 "$N8N_BASE_URL/healthz" >/dev/null 2>&1; then
        print_error "Cannot connect to N8N at $N8N_BASE_URL"
        echo "Please ensure N8N is running and accessible."
        return 1
    fi
    
    print_success "N8N is accessible"
    
    # Test API authentication
    print_step "Testing API authentication..."
    
    local response
    if response=$(make_api_request "GET" "$CREDENTIAL_API_URL" 2>/dev/null); then
        print_success "Authentication successful"
        local count=$(echo "$response" | jq '.data | length' 2>/dev/null || echo "0")
        print_info "Found $count existing credentials"
        return 0
    else
        print_error "Authentication failed"
        echo "Please check your N8N_PERSONAL_ACCESS_TOKEN or N8N_API_KEY"
        return 1
    fi
}

# Function to check if credential exists
credential_exists() {
    local cred_name="$1"
    local response
    
    if response=$(make_api_request "GET" "$CREDENTIAL_API_URL" 2>/dev/null); then
        local exists
        exists=$(echo "$response" | jq --arg name "$cred_name" '.data[] | select(.name == $name) | .id' 2>/dev/null || echo "")
        
        if [[ -n "$exists" ]]; then
            echo "$exists"
            return 0
        fi
    fi
    
    return 1
}

# Function to delete existing credential
delete_credential() {
    local cred_id="$1"
    local cred_name="$2"
    
    print_step "Deleting existing credential: $cred_name"
    
    if make_api_request "DELETE" "$CREDENTIAL_API_URL/$cred_id" >/dev/null 2>/dev/null; then
        print_success "Deleted existing credential: $cred_name"
        return 0
    else
        print_warning "Failed to delete credential: $cred_name"
        return 1
    fi
}

# Function to create credential
create_credential() {
    local service="$1"
    local dry_run="${2:-false}"
    local force="${3:-false}"
    local skip_existing="${4:-true}"
    
    # Check if service template exists
    local template_func="${SERVICE_TEMPLATES[$service]:-}"
    if [[ -z "$template_func" ]]; then
        print_error "Unknown service: $service"
        return 1
    fi
    
    # Generate credential data from template
    local template
    template=$($template_func)
    
    # Expand placeholders
    local expanded
    expanded=$(expand_placeholders "$template")
    
    # Parse credential details
    local cred_name cred_type cred_description cred_data
    cred_name=$(echo "$expanded" | jq -r '.name')
    cred_type=$(echo "$expanded" | jq -r '.type')
    cred_description=$(echo "$expanded" | jq -r '.description // empty')
    cred_data=$(echo "$expanded" | jq -c '.data')
    
    # Check if credential already exists
    local existing_id
    if existing_id=$(credential_exists "$cred_name"); then
        if [[ "$skip_existing" == "true" && "$force" == "false" ]]; then
            print_info "Credential already exists, skipping: $cred_name"
            return 0
        elif [[ "$force" == "true" ]]; then
            if [[ "$dry_run" == "false" ]]; then
                delete_credential "$existing_id" "$cred_name"
            else
                print_info "Would delete existing credential: $cred_name"
            fi
        else
            print_warning "Credential already exists: $cred_name (use --force to overwrite)"
            return 1
        fi
    fi
    
    # Create credential payload
    local payload
    if [[ -n "$cred_description" ]]; then
        payload=$(jq -n \
            --arg name "$cred_name" \
            --arg type "$cred_type" \
            --arg description "$cred_description" \
            --argjson data "$cred_data" \
            '{name: $name, type: $type, description: $description, data: $data}')
    else
        payload=$(jq -n \
            --arg name "$cred_name" \
            --arg type "$cred_type" \
            --argjson data "$cred_data" \
            '{name: $name, type: $type, data: $data}')
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Would create credential for service '$service':"
        echo "$payload" | jq '.'
        return 0
    fi
    
    print_step "Creating credential for service: $service"
    
    local response
    if response=$(make_api_request "POST" "$CREDENTIAL_API_URL" "$payload" 2>/dev/null); then
        local cred_id
        cred_id=$(echo "$response" | jq -r '.id')
        print_success "Created credential: $cred_name (ID: $cred_id)"
        return 0
    else
        print_error "Failed to create credential for service: $service"
        return 1
    fi
}

# Function to validate service configuration
validate_service_config() {
    local service="$1"
    local warnings=0
    
    case "$service" in
        postgres)
            if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
                print_warning "POSTGRES_PASSWORD not set - credential may not work"
                ((warnings++))
            fi
            ;;
        qdrant)
            if [[ -z "${QDRANT_API_KEY:-}" ]]; then
                print_warning "QDRANT_API_KEY not set - credential may not work"
                ((warnings++))
            fi
            ;;
        openai)
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                print_warning "OPENAI_API_KEY not set - credential may not work"
                ((warnings++))
            fi
            ;;
        neo4j)
            if [[ -z "${NEO4J_PASSWORD:-}" ]]; then
                print_warning "NEO4J_PASSWORD not set - credential may not work"
                ((warnings++))
            fi
            ;;
        clickhouse)
            if [[ -z "${CLICKHOUSE_USER:-}" ]]; then
                print_warning "CLICKHOUSE_USER not set - using default"
            fi
            ;;
    esac
    
    return $warnings
}

# Function to list available services
list_services() {
    echo "Available services for credential creation:"
    echo
    printf "%-15s %-20s %s\\n" "SERVICE" "TYPE" "DESCRIPTION"
    echo "$(printf '%.0s-' {1..80})"
    printf "%-15s %-20s %s\\n" "postgres" "PostgreSQL" "Main application database"
    printf "%-15s %-20s %s\\n" "qdrant" "Vector DB" "AI embeddings and search"
    printf "%-15s %-20s %s\\n" "redis" "Cache" "Session and cache storage"
    printf "%-15s %-20s %s\\n" "neo4j" "Graph DB" "Knowledge graphs and relationships"
    printf "%-15s %-20s %s\\n" "clickhouse" "Analytics DB" "Time-series and analytics"
    printf "%-15s %-20s %s\\n" "ollama" "Local LLM" "Local AI model server"
    printf "%-15s %-20s %s\\n" "openai" "OpenAI API" "GPT models and embeddings"
    echo
    echo "Default services: $DEFAULT_SERVICES"
}

# Function to show setup instructions
show_setup_instructions() {
    echo "N8N AI Starter Kit - Credential Setup Instructions"
    echo "=================================================="
    echo
    echo "📋 Available Services:"
    list_services
    echo
    echo "✅ Automatic Setup Options:"
    echo "  1. Setup all default services:"
    echo "     $0"
    echo
    echo "  2. Setup specific services:"
    echo "     $0 --services postgres,qdrant,openai"
    echo
    echo "  3. Force recreate all credentials:"
    echo "     $0 --force"
    echo
    echo "  4. Dry run to see what would be created:"
    echo "     $0 --dry-run"
    echo
    echo "⚠️  Prerequisites:"
    echo "  • N8N must be running (check with: ../start.sh status)"
    echo "  • Environment variables must be set in .env file"
    echo "  • Valid N8N authentication token or API key required"
    echo
    echo "🔐 Authentication:"
    echo "  Set one of these environment variables in your .env file:"
    echo "    N8N_PERSONAL_ACCESS_TOKEN=your_token_here"
    echo "    N8N_API_KEY=your_api_key_here"
    echo
    echo "💡 Tips:"
    echo "  • Wait 1-2 minutes after starting services before running this script"
    echo "  • Existing credentials are skipped by default (use --force to overwrite)"
    echo "  • Check the logs if you encounter issues: ../start.sh logs n8n"
}

# Main function
main() {
    local services="$DEFAULT_SERVICES"
    local dry_run=false
    local force=false
    local skip_existing=true
    local check_auth_only=false
    local show_instructions=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --services)
                services="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                skip_existing=false
                shift
                ;;
            --skip-existing)
                skip_existing=true
                shift
                ;;
            --list-services)
                list_services
                exit 0
                ;;
            --check-auth)
                check_auth_only=true
                shift
                ;;
            --instructions)
                show_instructions=true
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
    
    # Show instructions if requested
    if [[ "$show_instructions" == "true" ]]; then
        show_setup_instructions
        exit 0
    fi
    
    print_header
    
    # Check dependencies
    check_dependencies
    
    # Setup authentication
    setup_authentication
    
    # Test connection and authentication
    if ! test_n8n_connection; then
        exit 1
    fi
    
    if [[ "$check_auth_only" == "true" ]]; then
        print_success "Authentication check passed"
        exit 0
    fi
    
    # Parse services list
    IFS=',' read -ra SERVICE_LIST <<< "$services"
    
    print_info "Services to configure: ${SERVICE_LIST[*]}"
    
    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN MODE - No credentials will be actually created"
    fi
    
    echo
    
    # Validate service configurations
    print_step "Validating service configurations..."
    local total_warnings=0
    for service in "${SERVICE_LIST[@]}"; do
        service=$(echo "$service" | xargs)  # Trim whitespace
        if ! validate_service_config "$service"; then
            ((total_warnings += $?))
        fi
    done
    
    if [[ $total_warnings -gt 0 ]]; then
        print_warning "Found $total_warnings configuration warnings"
        echo "Please review your .env file before proceeding."
        echo
    fi
    
    # Create credentials
    local success_count=0
    local error_count=0
    
    for service in "${SERVICE_LIST[@]}"; do
        service=$(echo "$service" | xargs)  # Trim whitespace
        
        if create_credential "$service" "$dry_run" "$force" "$skip_existing"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    echo
    print_info "Credential setup completed:"
    print_success "  Successfully processed: $success_count"
    if [[ $error_count -gt 0 ]]; then
        print_error "  Failed: $error_count"
    fi
    
    if [[ "$dry_run" == "false" && $success_count -gt 0 ]]; then
        echo
        print_info "Credentials created successfully! You can now use them in your N8N workflows."
        print_info "Access N8N at: $N8N_BASE_URL"
        echo
        print_info "To list all credentials: ./scripts/create_n8n_credential.sh --list"
    fi
    
    exit 0
}

# Run main function with all arguments
main "$@"