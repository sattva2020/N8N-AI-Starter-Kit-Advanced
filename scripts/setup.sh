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

# Function to hash password for Traefik basic auth
hash_traefik_password() {
    local password="$1"
    # Use htpasswd to generate the hash (if available)
    if command -v htpasswd >/dev/null 2>&1; then
        htpasswd -nb admin "$password" | cut -d: -f2
    else
        # Fallback: use openssl to generate a simple hash
        # Note: This is not as secure as htpasswd but works for basic needs
        echo -n "$password" | openssl passwd -apr1 -stdin
    fi
}

# Function to configure domain settings
configure_domain() {
    print_info "Configuring domain settings..."
    
    local domain
    read -p "Enter your domain name (or press Enter for localhost): " domain
    domain=${domain:-localhost}
    
    # Update DOMAIN and related variables
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/DOMAIN=localhost/DOMAIN=${domain}/g" "$ENV_FILE"
    else
        # Linux/Windows Git Bash
        sed -i "s/DOMAIN=localhost/DOMAIN=${domain}/g" "$ENV_FILE"
    fi
    
    print_success "Domain configured: $domain"
}

# Function to configure Let's Encrypt email
configure_letsencrypt_email() {
    print_info "Configuring Let's Encrypt email..."
    
    # Only prompt for email if domain is not localhost
    local domain=$(grep "^DOMAIN=" "$ENV_FILE" | cut -d'=' -f2)
    
    if [[ "$domain" != "localhost" ]]; then
        local email
        read -p "Enter your email for Let's Encrypt notifications (or press Enter for admin@${domain}): " email
        email=${email:-"admin@${domain}"}
        
        # Escape special characters for sed
        local escaped_email=$(printf '%s\n' "$email" | sed -e 's/[\/&]/\\&/g')
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s/ACME_EMAIL=admin@\${DOMAIN}/ACME_EMAIL=${escaped_email}/g" "$ENV_FILE"
        else
            # Linux/Windows Git Bash
            sed -i "s/ACME_EMAIL=admin@\${DOMAIN}/ACME_EMAIL=${escaped_email}/g" "$ENV_FILE"
        fi
        
        print_success "Let's Encrypt email configured: $email"
    else
        print_info "Using localhost - Let's Encrypt not needed"
    fi
}

# Function to prompt for Traefik dashboard password
configure_traefik_password() {
    print_info "Configuring Traefik dashboard password..."
    
    local traefik_password
    
    read -p "Enter password for Traefik dashboard (or press Enter to generate): " traefik_password
    
    if [[ -z "$traefik_password" ]]; then
        # Generate a secure password if none provided
        traefik_password=$(generate_password 20)
        print_info "Generated Traefik dashboard password: $traefik_password"
        print_warning "Please save this password - you'll need it to access the Traefik dashboard"
    fi
    
    # Hash the password for Traefik
    local hashed_password=$(hash_traefik_password "$traefik_password")
    
    # Update the Traefik password in .env file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/change_this_traefik_password/${traefik_password}/g" "$ENV_FILE"
        # Update the hashed password for Traefik config
        sed -i '' "s/change_this_traefik_hashed_password/${hashed_password}/g" "$ENV_FILE"
    else
        # Linux/Windows Git Bash
        sed -i "s/change_this_traefik_password/${traefik_password}/g" "$ENV_FILE"
        # Update the hashed password for Traefik config
        sed -i "s/change_this_traefik_hashed_password/${hashed_password}/g" "$ENV_FILE"
    fi
    
    print_success "Traefik dashboard password configured"
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
    echo "  - supabase: + Supabase integration for AI/analytics data"
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

# Function to generate API keys
generate_api_keys() {
    print_info "API Keys Configuration..."
    
    # Note: API keys are not automatically generated for security reasons
    # Users should manually add their own API keys to the .env file
    print_info "Please manually add your API keys to the .env file:"
    print_info "  - OPENAI_API_KEY (for LightRAG service)"
    print_info "  - QDRANT_API_KEY (for vector database authentication)"
    print_info "  - N8N_API_KEY (alternative to Personal Access Token)"
    print_info "These fields are intentionally left empty for security."
}

# Function to generate passwords and update .env
generate_passwords() {
    print_info "Generating secure passwords..."
    
    # Generate secure passwords (excluding Traefik passwords which are handled separately)
    local postgres_password=$(generate_password 32)
    local grafana_password=$(generate_password 24)
    local clickhouse_password=$(generate_password 28)
    local n8n_token=$(generate_api_key 40)
    
    # Update passwords in .env file (excluding Traefik passwords)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/change_this_secure_password_123/${postgres_password}/g" "$ENV_FILE"
        sed -i '' "s/change_this_grafana_password_789/${grafana_password}/g" "$ENV_FILE"
        sed -i '' "s/change_this_clickhouse_password_012/${clickhouse_password}/g" "$ENV_FILE"
        sed -i '' "s/change_this_n8n_token_123/${n8n_token}/g" "$ENV_FILE"
    else
        # Linux/Windows Git Bash
        sed -i "s/change_this_secure_password_123/${postgres_password}/g" "$ENV_FILE"
        sed -i "s/change_this_grafana_password_789/${grafana_password}/g" "$ENV_FILE"
        sed -i "s/change_this_clickhouse_password_012/${clickhouse_password}/g" "$ENV_FILE"
        sed -i "s/change_this_n8n_token_123/${n8n_token}/g" "$ENV_FILE"
    fi
    
    print_success "Generated and applied secure passwords"
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
        "change_this_grafana_password"
        "change_this_clickhouse_password"
        "change_this_n8n_token"
        # Note: We're intentionally not checking for API key placeholders
        # as they should remain empty until user adds their own keys
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
    print_warning "IMPORTANT: Please add your API keys to the .env file:"
    print_warning "  - OPENAI_API_KEY (for LightRAG service)"
    print_warning "  - QDRANT_API_KEY (for vector database authentication)"
    print_warning "  - N8N_API_KEY (alternative to Personal Access Token)"
    echo
    print_info "Next steps:"
    echo "  1. Review .env file and add your API keys"
    echo "  2. Adjust other settings if needed"
    echo "  3. Run: ./start.sh"
    echo "  4. Or run: docker compose up -d"
    echo
    print_warning "Keep your .env file secure and do not commit it to version control!"
}

# Function to set default values for non-interactive mode
set_default_values_non_interactive() {
    print_info "Setting default values for non-interactive mode..."
    
    # For production environments, we might want to prompt for a real domain
    # But in non-interactive mode, we'll stick with localhost
    # Users can manually edit the .env file if they want to change this
    
    # We could also check if we're in a CI/CD environment or have other hints
    # about whether this is a production setup
    
    print_info "Using localhost as default domain in non-interactive mode"
    print_info "To use a custom domain, run setup in interactive mode or edit .env manually"
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
        if [[ "$interactive" == "true" ]]; then
            read -p "Do you want to overwrite it? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                print_info "Setup cancelled"
                exit 0
            fi
        else
            print_info "Overwriting existing .env file in non-interactive mode"
        fi
    fi
    
    # Execute setup steps
    check_dependencies
    backup_existing_env
    copy_template
    
    # Generate passwords and API keys
    generate_passwords
    generate_api_keys
    
    # Configure domain and profiles based on mode
    if [[ "$interactive" == "true" ]]; then
        configure_domain
        configure_letsencrypt_email
        configure_traefik_password
        configure_profiles
    else
        # In non-interactive mode, we still want to ensure proper configuration
        set_default_values_non_interactive
        # We could add logic here to detect if we're likely in a production environment
        # and prompt for a domain accordingly, but for now we'll keep it simple
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