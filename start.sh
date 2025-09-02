#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - STARTUP SCRIPT
# =============================================================================
# Main entry point for starting the N8N AI Starter Kit
# Handles environment setup, service orchestration, and health monitoring

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ENV_FILE="$PROJECT_ROOT/.env"

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
print_header() { echo -e "${CYAN}$1${NC}"; }

print_banner() {
    echo
    echo -e "${CYAN}=============================================================================${NC}"
    echo -e "${CYAN}                          N8N AI STARTER KIT${NC}"
    echo -e "${CYAN}=============================================================================${NC}"
    echo -e "${GREEN}  Production-ready n8n deployment with AI services${NC}"
    echo -e "${GREEN}  • Workflow Automation (n8n)${NC}"
    echo -e "${GREEN}  • Vector Search (Qdrant)${NC}"
    echo -e "${GREEN}  • Document Processing (SentenceTransformers)${NC}"
    echo -e "${GREEN}  • Monitoring (Grafana + Prometheus)${NC}"
    echo -e "${GREEN}  • Reverse Proxy with TLS (Traefik)${NC}"
    echo -e "${CYAN}=============================================================================${NC}"
    echo
}

print_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    up              Start all services (default)
    down            Stop all services
    restart         Restart all services
    status          Show service status
    logs            Show service logs
    update          Update and restart services
    cleanup         Clean up unused Docker resources
    reset           Reset all data (DESTRUCTIVE!)
    setup-credentials  Setup N8N credentials for all services
    init-credentials   Setup N8N credentials (legacy)
    
OPTIONS:
    --profile PROFILES  Comma-separated list of profiles (default,developer,monitoring,analytics,supabase)
    --detach           Run in detached mode (background)
    --build            Force rebuild of images
    --pull             Pull latest images before starting
    --follow SERVICE   Follow logs for specific service
    --tail N           Show last N lines of logs (default: 50)
    --no-setup         Skip environment setup check
    --dry-run          Show commands without executing
    --help            Show this help message

EXAMPLES:
    $0                                    # Start with default configuration
    $0 up --profile default,monitoring    # Start core services + monitoring
    $0 logs --follow n8n                 # Follow n8n logs
    $0 status                             # Show all service status
    $0 down && $0 up --build             # Restart with rebuild

PROFILES:
    default     Core services (Traefik, n8n, PostgreSQL)
    developer   + Qdrant, Web Interface, Document Processor, LightRAG
    monitoring  + Grafana, Prometheus
    analytics   + ETL Processor, ClickHouse
    gpu         + GPU-accelerated AI services with local models
    supabase    + Supabase integration for AI/analytics data (hybrid approach)

SECURITY:
    The setup script prompts for:
    - Domain name for service access
    - Email for Let's Encrypt SSL certificates
    - Password for Traefik dashboard access
EOF
}

# Configuration variables
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
DEFAULT_PROFILES="default,developer,monitoring"
DETACHED=false
BUILD=false
PULL=false
FOLLOW_SERVICE=""
TAIL_LINES=50
SKIP_SETUP=false
DRY_RUN=false

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        if ! command -v docker-compose >/dev/null 2>&1; then
            missing_deps+=("docker-compose")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install Docker and Docker Compose:"
        echo "  - Docker: https://docs.docker.com/get-docker/"
        echo "  - Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# Function to check environment setup
check_environment() {
    if [[ "$SKIP_SETUP" == "true" ]]; then
        return 0
    fi
    
    print_info "Checking environment configuration..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        print_warning "Environment file not found: $ENV_FILE"
        print_info "Running setup script..."
        
        if [[ -x "$SCRIPT_DIR/setup.sh" ]]; then
            "$SCRIPT_DIR/setup.sh"
        else
            print_error "Setup script not found or not executable"
            exit 1
        fi
    fi
    
    # Source environment file
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
        print_success "Environment loaded from $ENV_FILE"
    else
        print_error "Failed to create environment file"
        exit 1
    fi
    
    # Check if we're using localhost in what appears to be a production environment
    if [[ "${DOMAIN:-localhost}" == "localhost" ]]; then
        print_warning "Currently using localhost as domain"
        print_info "For production deployments, you should use a real domain name"
        # Only prompt if running in interactive mode (not in CI/CD)
        if [[ -t 0 ]]; then
            echo
            read -p "Would you like to update the domain now? (y/N): " update_domain
            if [[ "$update_domain" =~ ^[Yy]$ ]]; then
                print_info "Running setup script to configure domain..."
                if [[ -x "$SCRIPT_DIR/setup.sh" ]]; then
                    "$SCRIPT_DIR/setup.sh"
                    # Reload environment after setup
                    set -a
                    source "$ENV_FILE"
                    set +a
                    print_success "Environment reloaded with new settings"
                fi
            fi
        fi
    fi
    
    # Validate critical environment variables
    local missing_vars=()
    
    for var in POSTGRES_PASSWORD GRAFANA_ADMIN_PASSWORD; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing critical environment variables: ${missing_vars[*]}"
        print_info "Please run: $SCRIPT_DIR/setup.sh"
        exit 1
    fi
}

# Function to get Docker Compose command
get_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        print_error "Neither 'docker compose' nor 'docker-compose' is available"
        exit 1
    fi
}

# Function to execute Docker Compose command
exec_compose() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    local profiles="${COMPOSE_PROFILES:-$DEFAULT_PROFILES}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would execute: COMPOSE_PROFILES=$profiles $compose_cmd $*"
        return 0
    fi
    
    print_info "Executing: $compose_cmd $*"
    COMPOSE_PROFILES="$profiles" $compose_cmd "$@"
}

# Function to start services
start_services() {
    print_header "Starting N8N AI Starter Kit services..."
    
    local compose_args=("up")
    
    if [[ "$DETACHED" == "true" ]]; then
        compose_args+=("-d")
    fi
    
    if [[ "$BUILD" == "true" ]]; then
        compose_args+=("--build")
    fi
    
    if [[ "$PULL" == "true" ]]; then
        compose_args+=("--pull" "always")
    fi
    
    exec_compose "${compose_args[@]}"
    
    if [[ "$DETACHED" == "true" ]]; then
        print_success "Services started in background"
        show_service_urls
        show_access_instructions
        print_info "Use '$0 logs' to view logs or '$0 status' to check status"
    fi
}

# Function to stop services
stop_services() {
    print_header "Stopping N8N AI Starter Kit services..."
    
    exec_compose down
    
    print_success "Services stopped"
}

# Function to restart services
restart_services() {
    print_header "Restarting N8N AI Starter Kit services..."
    
    stop_services
    sleep 2
    start_services
}

# Function to show service status
show_status() {
    print_header "Service Status"
    
    exec_compose ps
    
    echo
    print_header "Docker System Info"
    docker system df
}

# Function to show service logs
show_logs() {
    if [[ -n "$FOLLOW_SERVICE" ]]; then
        print_info "Following logs for service: $FOLLOW_SERVICE"
        exec_compose logs -f --tail "$TAIL_LINES" "$FOLLOW_SERVICE"
    else
        print_info "Showing last $TAIL_LINES lines of logs for all services"
        exec_compose logs --tail "$TAIL_LINES"
    fi
}

# Function to update services
update_services() {
    print_header "Updating N8N AI Starter Kit..."
    
    print_info "Pulling latest images..."
    exec_compose pull
    
    print_info "Rebuilding custom images..."
    exec_compose build --no-cache
    
    print_info "Restarting services..."
    exec_compose up -d
    
    print_success "Update completed"
}

# Function to cleanup Docker resources
cleanup_docker() {
    print_header "Cleaning up Docker resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would execute Docker cleanup commands"
        return 0
    fi
    
    print_info "Removing unused containers..."
    docker container prune -f
    
    print_info "Removing unused images..."
    docker image prune -f
    
    print_info "Removing unused volumes..."
    docker volume prune -f
    
    print_info "Removing unused networks..."
    docker network prune -f
    
    print_success "Docker cleanup completed"
    
    echo
    print_info "Disk usage after cleanup:"
    docker system df
}

# Function to reset all data (DESTRUCTIVE!)
reset_all_data() {
    print_warning "⚠️  WARNING: This will DELETE ALL DATA! ⚠️"
    echo
    print_error "This operation will:"
    echo "  - Stop all services"
    echo "  - Remove all Docker volumes (databases, files, etc.)"
    echo "  - Remove all containers and images"
    echo "  - Reset the entire system to initial state"
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would execute complete system reset"
        return 0
    fi
    
    read -p "Type 'RESET' to confirm: " confirm
    if [[ "$confirm" != "RESET" ]]; then
        print_info "Reset cancelled"
        return 0
    fi
    
    print_header "Resetting N8N AI Starter Kit..."
    
    # Stop all services
    exec_compose down -v --remove-orphans
    
    # Remove all related images
    docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(n8n|postgres|qdrant|grafana|traefik|clickhouse)" | xargs -r docker rmi -f
    
    # Remove project volumes specifically
    docker volume ls --format "{{.Name}}" | grep -E "n8n.*_(postgres|qdrant|grafana|prometheus|clickhouse|traefik)_data" | xargs -r docker volume rm
    
    print_success "System reset completed"
    print_info "Run '$0 up' to start fresh"
}

# Function to initialize N8N credentials
init_credentials() {
    print_header "Initializing N8N credentials..."
    
    local cred_script="$SCRIPT_DIR/create_n8n_credential.sh"
    
    if [[ ! -x "$cred_script" ]]; then
        print_error "Credential script not found or not executable: $cred_script"
        return 1
    fi
    
    # Wait for N8N to be ready
    print_info "Waiting for N8N to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f -s "http://localhost:5678/healthz" >/dev/null 2>&1; then
            break
        fi
        
        ((attempt++))
        print_info "Waiting... ($attempt/$max_attempts)"
        sleep 5
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        print_error "N8N did not become ready in time"
        return 1
    fi
    
    print_success "N8N is ready"
    
    # Automatically create credentials for all services
    print_info "Setting up N8N credentials for project services..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would create N8N credentials automatically"
    else
        # Use the new automated credential setup
        local auto_cred_script="$SCRIPT_DIR/auto-setup-credentials.sh"
        if [[ -f "$auto_cred_script" ]]; then
            print_info "Running automated credential setup..."
            if "$auto_cred_script" --services postgres,qdrant,openai,ollama --skip-existing; then
                print_success "Automated credential setup completed"
            else
                print_warning "Automated setup failed, falling back to manual creation"
                # Fallback to original manual creation
                "$cred_script" --type postgres --name "Main PostgreSQL" --data '{
                    "host": "postgres",
                    "port": 5432,
                    "database": "n8n",
                    "username": "n8n_user",
                    "password": "${POSTGRES_PASSWORD}",
                    "ssl": "disable"
                }' || print_warning "Failed to create PostgreSQL credential"
            fi
        else
            print_warning "Auto-setup script not found, using basic credential creation"
            "$cred_script" --type postgres --name "Main PostgreSQL" --data '{
                "host": "postgres",
                "port": 5432,
                    "database": "n8n",
                    "username": "n8n_user",
                    "password": "${POSTGRES_PASSWORD}",
                    "ssl": "disable"
                }' || print_warning "Failed to create PostgreSQL credential"
        fi
    fi
    
    print_success "Credential initialization completed"
}

# Function to setup all project credentials
setup_project_credentials() {
    print_header "Setting up N8N Credentials for All Services"
    
    # Check if N8N is running
    if ! curl -f -s "http://localhost:5678/healthz" >/dev/null 2>&1; then
        print_error "N8N is not running. Please start services first with: $0 up"
        exit 1
    fi
    
    # Check authentication
    if [[ -z "${N8N_PERSONAL_ACCESS_TOKEN:-}" && -z "${N8N_API_KEY:-}" ]]; then
        print_error "No N8N authentication configured"
        echo "Please set N8N_PERSONAL_ACCESS_TOKEN or N8N_API_KEY in your .env file"
        echo "You can generate these in N8N at Settings → Personal Access Token or Settings → API Key"
        exit 1
    fi
    
    local auto_cred_script="$SCRIPT_DIR/auto-setup-credentials.sh"
    local python_manager="$SCRIPT_DIR/credential-manager.py"
    
    # Try Python manager first (more features)
    if command -v python3 >/dev/null 2>&1 && [[ -f "$python_manager" ]]; then
        print_info "Using advanced Python credential manager..."
        
        # Check if requests is available
        if python3 -c "import requests" >/dev/null 2>&1; then
            python3 "$python_manager" --setup all
            return $?
        else
            print_warning "Python requests library not found, falling back to bash script"
        fi
    fi
    
    # Fallback to bash script
    if [[ -f "$auto_cred_script" ]]; then
        print_info "Using automated credential setup script..."
        "$auto_cred_script" --services postgres,qdrant,openai,ollama,redis,neo4j,clickhouse
        return $?
    else
        print_error "No credential setup scripts found"
        echo "Please ensure scripts/auto-setup-credentials.sh or scripts/credential-manager.py exists"
        exit 1
    fi
}

# Function to show service URLs
show_service_urls() {
    echo
    print_header "Service URLs"
    
    local domain="${DOMAIN:-localhost}"
    local protocol="https"
    
    if [[ "$domain" == "localhost" ]]; then
        protocol="http"
    fi
    
    echo "  🤖 N8N Workflow Engine:    $protocol://n8n.$domain"
    echo "  📊 Grafana Dashboard:      $protocol://grafana.$domain"
    echo "  🌐 Web Interface:          $protocol://api.$domain/ui/"
    echo "  📈 Traefik Dashboard:      $protocol://traefik.$domain"
    echo "  🔍 Qdrant (if enabled):    http://localhost:6333"
    echo "  🗄️  PostgreSQL:             localhost:5432"
    echo
    
    if [[ "$domain" == "localhost" ]]; then
        print_warning "Using localhost - services available via HTTP only"
        print_info "For HTTPS, set a proper domain in .env and configure DNS"
    fi
}

# Function to show access instructions
show_access_instructions() {
    echo
    print_header "Access Instructions"
    
    echo "📋 Services you can access:"
    echo "   • N8N Workflow Engine - Main workflow automation platform"
    echo "   • Grafana Dashboard - System monitoring and metrics visualization"
    echo "   • Web Interface - API gateway and management dashboard"
    echo "   • Traefik Dashboard - Reverse proxy and load balancer monitoring"
    echo "   • Qdrant - Vector database for similarity search (if enabled)"
    echo "   • PostgreSQL - Main database for N8N (internal use)"
    
    echo
    echo "🔐 Automatic Credential Creation:"
    echo "   After services are fully running (wait 1-2 minutes), you can automatically"
    echo "   create credentials for all services using one of these methods:"
    echo
    echo "   Method 1 - Enhanced Python credential manager (recommended):"
    echo "   $ $0 setup-credentials"
    echo
    echo "   Method 2 - Legacy bash credential setup:"
    echo "   $ $0 init-credentials"
    echo
    echo "   Both methods will:"
    echo "   • Create credentials for PostgreSQL, Qdrant, OpenAI, Ollama"
    echo "   • Use configuration from your .env file"
    echo "   • Skip creation if credentials already exist"
    echo
    echo "   🔧 Manual credential creation (if needed):"
    echo "   $ ./scripts/create_n8n_credential.sh --help"
    echo
    print_info "First access: Visit N8N at the URL above and use default credentials"
    print_info "Default N8N credentials are in your .env file (N8N_USER/N8N_PASSWORD)"
}

# Function to health check services
health_check() {
    print_header "Service Health Check"
    
    local services=(
        "http://localhost:5678/healthz:N8N"
        "http://localhost:3000/api/health:Grafana"
        "http://localhost:6333/health:Qdrant"
        "http://localhost:8000/health:Web Interface"
        "http://localhost:8001/health:Document Processor"
        "http://localhost:8002/health:ETL Processor"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r url name <<< "$service_info"
        
        if curl -f -s "$url" >/dev/null 2>&1; then
            print_success "$name is healthy"
        else
            print_error "$name is not responding"
        fi
    done
}

# Main function
main() {
    local command="${1:-up}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            up|start)
                command="up"
                shift
                ;;
            down|stop)
                command="down"
                shift
                ;;
            restart)
                command="restart"
                shift
                ;;
            status)
                command="status"
                shift
                ;;
            logs)
                command="logs"
                shift
                ;;
            update)
                command="update"
                shift
                ;;
            cleanup)
                command="cleanup"
                shift
                ;;
            reset)
                command="reset"
                shift
                ;;
            init-credentials)
                command="init-credentials"
                shift
                ;;
            setup-credentials)
                command="setup-credentials"
                shift
                ;;
            health)
                command="health"
                shift
                ;;
            --profile)
                COMPOSE_PROFILES="$2"
                shift 2
                ;;
            --detach|-d)
                DETACHED=true
                shift
                ;;
            --build)
                BUILD=true
                shift
                ;;
            --pull)
                PULL=true
                shift
                ;;
            --follow|-f)
                FOLLOW_SERVICE="$2"
                shift 2
                ;;
            --tail)
                TAIL_LINES="$2"
                shift 2
                ;;
            --no-setup)
                SKIP_SETUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                print_banner
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
    
    print_banner
    
    # Check dependencies
    check_dependencies
    
    # Execute command
    case "$command" in
        up)
            check_environment
            start_services
            ;;
        down)
            stop_services
            ;;
        restart)
            check_environment
            restart_services
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        update)
            update_services
            ;;
        cleanup)
            cleanup_docker
            ;;
        reset)
            reset_all_data
            ;;
        init-credentials)
            init_credentials
            ;;
        setup-credentials)
            setup_project_credentials
            ;;
        health)
            health_check
            ;;
        *)
            print_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi