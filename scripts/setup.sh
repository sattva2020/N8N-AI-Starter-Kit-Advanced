#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - ENVIRONMENT SETUP SCRIPT
# =============================================================================
# This script initializes the environment for the N8N AI Starter Kit
# It copies template.env to .env and generates secure passwords

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
TEMPLATE_FILE="$PROJECT_ROOT/template.env"

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
    echo "                    N8N AI STARTER KIT - SETUP"
    echo "============================================================================="
    echo
}

# Function to check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi
    
    if ! command -v sed >/dev/null 2>&1; then
        missing_deps+=("sed")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
    
    print_success "All dependencies are available"
}

# Function to backup existing .env file
backup_existing_env() {
    if [[ -f "$ENV_FILE" ]]; then
        local backup_file="$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENV_FILE" "$backup_file"
        print_warning "Existing .env backed up to: $(basename "$backup_file")"
    fi
}

# Function to copy template
copy_template() {
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    cp "$TEMPLATE_FILE" "$ENV_FILE"
    print_success "Created .env from template"
}

# Function to generate secure password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-$length
}

# Function to generate secure API key
generate_api_key() {
    local length=${1:-64}
    openssl rand -hex "$length"
}

# Function to generate passwords and update .env
generate_passwords() {
    print_info "Generating secure passwords..."
    
    # Generate secure passwords
    local postgres_password=$(generate_password 32)
    local qdrant_key=$(generate_api_key 32)
    local grafana_password=$(generate_password 24)
    local clickhouse_password=$(generate_password 28)
    local n8n_token=$(generate_api_key 40)
    local n8n_api_key=$(generate_api_key 32)
    
    # Update passwords in .env file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/change_this_secure_password_123/${postgres_password}/g" "$ENV_FILE"
        sed -i '' "s/change_this_qdrant_key_456/${qdrant_key}/g" "$ENV_FILE"
        sed -i '' "s/change_this_grafana_password_789/${grafana_password}/g" "$ENV_FILE"
        sed -i '' "s/change_this_clickhouse_password_012/${clickhouse_password}/g" "$ENV_FILE"
        sed -i '' "s/change_this_n8n_token_123/${n8n_token}/g" "$ENV_FILE"
        sed -i '' "s/change_this_n8n_api_key_456/${n8n_api_key}/g" "$ENV_FILE"
    else
        # Linux/Windows Git Bash
        sed -i "s/change_this_secure_password_123/${postgres_password}/g" "$ENV_FILE"
        sed -i "s/change_this_qdrant_key_456/${qdrant_key}/g" "$ENV_FILE"
        sed -i "s/change_this_grafana_password_789/${grafana_password}/g" "$ENV_FILE"
        sed -i "s/change_this_clickhouse_password_012/${clickhouse_password}/g" "$ENV_FILE"
        sed -i "s/change_this_n8n_token_123/${n8n_token}/g" "$ENV_FILE"
        sed -i "s/change_this_n8n_api_key_456/${n8n_api_key}/g" "$ENV_FILE"
    fi
    
    print_success "Generated and applied secure passwords"
}

# Function to prompt for domain configuration
configure_domain() {
    print_info "Configuring domain settings..."
    
    local domain
    read -p "Enter your domain name (or press Enter for localhost): " domain
    domain=${domain:-localhost}
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/DOMAIN=localhost/DOMAIN=${domain}/g" "$ENV_FILE"
    else
        # Linux/Windows Git Bash
        sed -i "s/DOMAIN=localhost/DOMAIN=${domain}/g" "$ENV_FILE"
    fi
    
    print_success "Domain configured: $domain"
}

# Function to configure compose profiles
configure_profiles() {
    print_info "Configuring Docker Compose profiles..."
    
    echo "Available profiles:"
    echo "  - default: Core services (Traefik, n8n, PostgreSQL)"
    echo "  - developer: + Qdrant, Web Interface, Document Processor, LightRAG"
    echo "  - monitoring: + Grafana, Prometheus"
    echo "  - analytics: + ETL Processor, ClickHouse"
    echo "  - gpu: + GPU-accelerated AI services with local models"
    echo
    
    local profiles
    read -p "Enter comma-separated profiles (or press Enter for 'default,developer,monitoring'): " profiles
    profiles=${profiles:-"default,developer,monitoring"}
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/COMPOSE_PROFILES=.*/COMPOSE_PROFILES=${profiles}/g" "$ENV_FILE"
    else
        # Linux/Windows Git Bash
        sed -i "s/COMPOSE_PROFILES=.*/COMPOSE_PROFILES=${profiles}/g" "$ENV_FILE"
    fi
    
    print_success "Profiles configured: $profiles"
}

# Function to validate environment file
validate_env() {
    print_info "Validating environment configuration..."
    
    # Check if .env exists and is readable
    if [[ ! -r "$ENV_FILE" ]]; then
        print_error "Cannot read .env file: $ENV_FILE"
        return 1
    fi
    
    # Check for placeholder values that weren't replaced
    local placeholders=(
        "change_this_secure_password"
        "change_this_qdrant_key"
        "change_this_grafana_password"
        "change_this_clickhouse_password"
        "change_this_n8n_token"
        "change_this_n8n_api_key"
    )
    
    local validation_failed=false
    for placeholder in "${placeholders[@]}"; do
        if grep -q "$placeholder" "$ENV_FILE"; then
            print_error "Found unreplaced placeholder: $placeholder"
            validation_failed=true
        fi
    done
    
    if [[ "$validation_failed" == "true" ]]; then
        print_error "Environment validation failed"
        return 1
    fi
    
    print_success "Environment validation passed"
}

# Function to display summary
display_summary() {
    echo
    print_info "Setup Summary:"
    echo "  ✓ Environment file created: .env"
    echo "  ✓ Secure passwords generated"
    echo "  ✓ Configuration validated"
    echo
    print_info "Next steps:"
    echo "  1. Review .env file and adjust settings if needed"
    echo "  2. Run: ./start.sh"
    echo "  3. Or run: docker compose up -d"
    echo
    print_warning "Keep your .env file secure and do not commit it to version control!"
}

# Main setup function
main() {
    print_header
    
    # Parse command line arguments
    local force=false
    local interactive=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --non-interactive)
                interactive=false
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force           Overwrite existing .env file without confirmation"
                echo "  --non-interactive Use default values without prompting"
                echo "  --help           Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check if .env already exists
    if [[ -f "$ENV_FILE" && "$force" != "true" ]]; then
        echo "Environment file already exists: $ENV_FILE"
        read -p "Do you want to overwrite it? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi
    
    # Execute setup steps
    check_dependencies
    backup_existing_env
    copy_template
    generate_passwords
    
    if [[ "$interactive" == "true" ]]; then
        configure_domain
        configure_profiles
    fi
    
    validate_env
    
    # Run GPU detection if available
    if [[ -x "$SCRIPT_DIR/detect-gpu.sh" ]]; then
        print_info "Running GPU detection..."
        "$SCRIPT_DIR/detect-gpu.sh" || true  # Don't fail if GPU detection fails
    fi
    
    display_summary
    
    print_success "Environment setup completed successfully!"
}

# Run main function
main "$@"