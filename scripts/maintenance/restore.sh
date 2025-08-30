#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - RESTORE SCRIPT
# =============================================================================
# Restore data from backups created by backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/.internal/backups}"
DRY_RUN=false

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

print_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Restore N8N AI Starter Kit from backups.

COMMANDS:
    list                    List available backups
    restore BACKUP_FILE     Restore from specific backup
    latest                  Restore from latest backup

OPTIONS:
    --backup-dir DIR        Backup directory (default: $BACKUP_DIR)
    --force                 Skip confirmation prompts
    --services LIST         Comma-separated services to restore (default: all)
    --dry-run              Show what would be restored
    --help                 Show this help

EXAMPLES:
    $0 list                           # List available backups
    $0 restore backup_20240101.tar.gz # Restore specific backup
    $0 latest --services postgres     # Restore only PostgreSQL from latest

EOF
}

list_backups() {
    print_info "Available backups in $BACKUP_DIR:"
    echo
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_warning "Backup directory does not exist: $BACKUP_DIR"
        return 0
    fi
    
    local backups=($(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf "%f\\n" 2>/dev/null | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        print_warning "No backups found"
        return 0
    fi
    
    printf "%-30s %-15s %-10s\\n" "BACKUP FILE" "DATE" "SIZE"
    echo "$(printf '%.0s-' {1..60})"
    
    for backup in "${backups[@]}"; do
        local backup_path="$BACKUP_DIR/$backup"
        local date_str=""
        local size_str=""
        
        if [[ -f "$backup_path" ]]; then
            date_str=$(stat -c %y "$backup_path" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            size_str=$(du -h "$backup_path" 2>/dev/null | cut -f1 || echo "unknown")
        fi
        
        printf "%-30s %-15s %-10s\\n" "$backup" "$date_str" "$size_str"
    done
}

find_latest_backup() {
    local latest_backup=""
    
    if [[ -d "$BACKUP_DIR" ]]; then
        latest_backup=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf "%T+ %f\\n" 2>/dev/null | sort -r | head -n1 | cut -d' ' -f2-)
    fi
    
    echo "$latest_backup"
}

validate_backup() {
    local backup_file="$1"
    local backup_path="$BACKUP_DIR/$backup_file"
    
    if [[ ! -f "$backup_path" ]]; then
        print_error "Backup file not found: $backup_path"
        return 1
    fi
    
    # Validate tar file
    if ! tar -tzf "$backup_path" >/dev/null 2>&1; then
        print_error "Invalid or corrupted backup file: $backup_file"
        return 1
    fi
    
    # Check for manifest
    if tar -tzf "$backup_path" | grep -q "manifest.json"; then
        print_success "Backup validation passed"
        return 0
    else
        print_warning "Backup does not contain manifest.json (older format?)"
        return 0
    fi
}

show_backup_info() {
    local backup_file="$1"
    local backup_path="$BACKUP_DIR/$backup_file"
    local temp_dir=$(mktemp -d)
    
    print_info "Backup Information:"
    
    # Extract and show manifest
    if tar -xzf "$backup_path" -C "$temp_dir" --wildcards "*/manifest.json" 2>/dev/null; then
        local manifest_file=$(find "$temp_dir" -name "manifest.json" -type f)
        if [[ -f "$manifest_file" ]] && command -v jq >/dev/null 2>&1; then
            echo
            jq -r '
                "  Backup Date: " + .backup_timestamp +
                "\\n  Project Version: " + .project_version +
                "\\n  Backup Size: " + (.backup_size_mb | tostring) + " MB" +
                "\\n  Services: " + (.services | keys | join(", "))
            ' "$manifest_file"
            echo
        fi
    fi
    
    # Show contents
    print_info "Backup Contents:"
    tar -tzf "$backup_path" | head -20
    
    local total_files=$(tar -tzf "$backup_path" | wc -l)
    if [[ $total_files -gt 20 ]]; then
        echo "  ... and $((total_files - 20)) more files"
    fi
    
    rm -rf "$temp_dir"
}

restore_backup() {
    local backup_file="$1"
    local services="${2:-all}"
    local force="${3:-false}"
    local backup_path="$BACKUP_DIR/$backup_file"
    
    # Validate backup
    if ! validate_backup "$backup_file"; then
        return 1
    fi
    
    # Show backup information
    show_backup_info "$backup_file"
    
    # Confirmation
    if [[ "$force" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        print_warning "⚠️  WARNING: This will overwrite existing data! ⚠️"
        echo
        read -p "Type 'RESTORE' to confirm: " confirm
        if [[ "$confirm" != "RESTORE" ]]; then
            print_info "Restore cancelled"
            return 0
        fi
    fi
    
    print_info "Starting restore process..."
    
    # Stop services
    print_info "Stopping services..."
    if [[ "$DRY_RUN" != "true" ]]; then
        cd "$PROJECT_ROOT"
        ./start.sh down >/dev/null 2>&1 || true
    fi
    
    # Extract backup
    local temp_dir=$(mktemp -d)
    local extract_dir=""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        print_info "Extracting backup..."
        tar -xzf "$backup_path" -C "$temp_dir"
        extract_dir=$(find "$temp_dir" -maxdepth 1 -type d ! -path "$temp_dir" | head -1)
    else
        print_info "Would extract backup to temporary directory"
    fi
    
    # Restore volumes
    restore_volumes "$extract_dir" "$services"
    
    # Restore configurations
    restore_configs "$extract_dir"
    
    # Cleanup
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "$temp_dir"
    fi
    
    # Restart services
    print_info "Restarting services..."
    if [[ "$DRY_RUN" != "true" ]]; then
        cd "$PROJECT_ROOT"
        ./start.sh up -d
    fi
    
    print_success "Restore completed successfully"
}

restore_volumes() {
    local extract_dir="$1"
    local services="$2"
    
    print_info "Restoring Docker volumes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Would restore volumes from: $extract_dir"
        return 0
    fi
    
    local volumes=(
        "postgres_data"
        "qdrant_data"
        "grafana_data"
        "prometheus_data"
        "clickhouse_data"
        "traefik_data"
    )
    
    for volume in "${volumes[@]}"; do
        if [[ "$services" != "all" ]] && [[ "$services" != *"${volume%_data}"* ]]; then
            continue
        fi
        
        local volume_backup="$extract_dir/$volume.tar.gz"
        
        if [[ -f "$volume_backup" ]]; then
            print_info "Restoring volume: $volume"
            
            # Remove existing volume
            docker volume rm "$volume" 2>/dev/null || true
            
            # Create new volume
            docker volume create "$volume"
            
            # Restore data
            docker run --rm \
                -v "$volume:/data" \
                -v "$extract_dir:/backup" \
                alpine:latest \
                tar xzf "/backup/$volume.tar.gz" -C /data
                
            print_success "Restored volume: $volume"
        else
            print_warning "Volume backup not found: $volume.tar.gz"
        fi
    done
}

restore_configs() {
    local extract_dir="$1"
    
    print_info "Restoring configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Would restore configs from: $extract_dir"
        return 0
    fi
    
    # Restore .env if exists
    if [[ -f "$extract_dir/.env" ]]; then
        print_warning "Backing up current .env to .env.backup"
        cp "$PROJECT_ROOT/.env" "$PROJECT_ROOT/.env.backup" 2>/dev/null || true
        
        print_info "Restoring .env file"
        cp "$extract_dir/.env" "$PROJECT_ROOT/"
    fi
    
    # Restore other configs
    for config_archive in "$extract_dir"/*.tar.gz; do
        if [[ -f "$config_archive" ]]; then
            local config_name=$(basename "$config_archive" .tar.gz)
            
            case "$config_name" in
                config|data)
                    print_info "Restoring $config_name directory"
                    rm -rf "$PROJECT_ROOT/$config_name.backup" 2>/dev/null || true
                    mv "$PROJECT_ROOT/$config_name" "$PROJECT_ROOT/$config_name.backup" 2>/dev/null || true
                    tar xzf "$config_archive" -C "$PROJECT_ROOT"
                    ;;
            esac
        fi
    done
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    local command="${1:-list}"
    
    case "$command" in
        list)
            list_backups
            ;;
        restore)
            if [[ -z "${2:-}" ]]; then
                print_error "Backup file required for restore command"
                print_usage
                exit 1
            fi
            
            shift 2
            local services="all"
            local force=false
            
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --services)
                        services="$2"
                        shift 2
                        ;;
                    --force)
                        force=true
                        shift
                        ;;
                    --dry-run)
                        DRY_RUN=true
                        shift
                        ;;
                    *)
                        print_error "Unknown option: $1"
                        print_usage
                        exit 1
                        ;;
                esac
            done
            
            restore_backup "$2" "$services" "$force"
            ;;
        latest)
            shift
            local latest_backup=$(find_latest_backup)
            
            if [[ -z "$latest_backup" ]]; then
                print_error "No backups found"
                exit 1
            fi
            
            print_info "Latest backup: $latest_backup"
            restore_backup "$latest_backup" "${1:-all}" "${2:-false}"
            ;;
        --help|-h)
            print_usage
            ;;
        *)
            print_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
fi