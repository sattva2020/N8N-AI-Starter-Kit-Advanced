#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - BACKUP SCRIPT
# =============================================================================
# Create backups of all persistent data including databases, volumes, and configurations

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
Usage: $0 [OPTIONS]

Create comprehensive backups of N8N AI Starter Kit data.

OPTIONS:
    --backup-dir DIR    Backup directory (default: $BACKUP_DIR)
    --compression LEVEL Compression level 1-9 (default: 6)
    --keep-days N       Keep backups for N days (default: 30)
    --services LIST     Comma-separated services to backup (default: all)
    --dry-run          Show what would be backed up
    --help             Show this help

EXAMPLES:
    $0                              # Full backup with defaults
    $0 --services postgres,qdrant  # Backup only specific services
    $0 --keep-days 7               # Keep backups for 7 days only

EOF
}

create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$timestamp"
    local compression_level=6
    local keep_days=30
    local services="all"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup-dir)
                BACKUP_DIR="$2"
                backup_path="$BACKUP_DIR/$timestamp"
                shift 2
                ;;
            --compression)
                compression_level="$2"
                shift 2
                ;;
            --keep-days)
                keep_days="$2"
                shift 2
                ;;
            --services)
                services="$2"
                shift 2
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
    
    print_info "Starting backup process..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN - would create backup at: $backup_path"
    else
        mkdir -p "$backup_path"
    fi
    
    # Backup Docker volumes
    backup_volumes "$backup_path" "$services"
    
    # Backup configuration files
    backup_configs "$backup_path"
    
    # Create backup manifest
    create_manifest "$backup_path"
    
    # Compress backup
    if [[ "$DRY_RUN" == "false" ]]; then
        compress_backup "$backup_path" "$compression_level"
    fi
    
    # Cleanup old backups
    cleanup_old_backups "$keep_days"
    
    print_success "Backup completed successfully"
}

backup_volumes() {
    local backup_path="$1"
    local services="$2"
    
    print_info "Backing up Docker volumes..."
    
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
        
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            print_info "Backing up volume: $volume"
            
            if [[ "$DRY_RUN" == "false" ]]; then
                docker run --rm \
                    -v "$volume:/data:ro" \
                    -v "$backup_path:/backup" \
                    alpine:latest \
                    tar czf "/backup/$volume.tar.gz" -C /data .
            fi
        else
            print_warning "Volume not found: $volume"
        fi
    done
}

backup_configs() {
    local backup_path="$1"
    
    print_info "Backing up configuration files..."
    
    local config_files=(
        ".env"
        "docker-compose.yml"
        "config/"
        "data/"
    )
    
    for config in "${config_files[@]}"; do
        if [[ -e "$PROJECT_ROOT/$config" ]]; then
            print_info "Backing up: $config"
            
            if [[ "$DRY_RUN" == "false" ]]; then
                if [[ -d "$PROJECT_ROOT/$config" ]]; then
                    tar czf "$backup_path/$(basename "$config").tar.gz" -C "$PROJECT_ROOT" "$config"
                else
                    cp "$PROJECT_ROOT/$config" "$backup_path/"
                fi
            fi
        fi
    done
}

create_manifest() {
    local backup_path="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    cat > "$backup_path/manifest.json" << EOF
{
  "backup_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_version": "1.0",
  "project_version": "$(git describe --tags --always 2>/dev/null || echo 'unknown')",
  "docker_compose_version": "$(docker compose version --short 2>/dev/null || echo 'unknown')",
  "services": {
    "postgres": "$(docker compose ps postgres --format json 2>/dev/null | jq -r '.[0].State' 2>/dev/null || echo 'unknown')",
    "qdrant": "$(docker compose ps qdrant --format json 2>/dev/null | jq -r '.[0].State' 2>/dev/null || echo 'unknown')",
    "grafana": "$(docker compose ps grafana --format json 2>/dev/null | jq -r '.[0].State' 2>/dev/null || echo 'unknown')"
  },
  "volumes": $(docker volume ls --format json | jq '[.[] | select(.Name | contains("n8n")) | .Name]' 2>/dev/null || echo '[]'),
  "backup_size_mb": 0
}
EOF
    
    # Calculate backup size
    if command -v du >/dev/null 2>&1; then
        local size_kb=$(du -sk "$backup_path" | cut -f1)
        local size_mb=$((size_kb / 1024))
        sed -i "s/\"backup_size_mb\": 0/\"backup_size_mb\": $size_mb/" "$backup_path/manifest.json" 2>/dev/null || true
    fi
}

compress_backup() {
    local backup_path="$1"
    local compression_level="$2"
    
    print_info "Compressing backup..."
    
    tar czf "$backup_path.tar.gz" -C "$(dirname "$backup_path")" "$(basename "$backup_path")"
    
    if [[ -f "$backup_path.tar.gz" ]]; then
        rm -rf "$backup_path"
        print_success "Backup compressed: $(basename "$backup_path").tar.gz"
    else
        print_error "Failed to compress backup"
    fi
}

cleanup_old_backups() {
    local keep_days="$1"
    
    print_info "Cleaning up backups older than $keep_days days..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$keep_days -ls 2>/dev/null || true
    else
        local deleted_count=0
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((deleted_count++))
        done < <(find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$keep_days -print0 2>/dev/null)
        
        if [[ $deleted_count -gt 0 ]]; then
            print_success "Deleted $deleted_count old backup(s)"
        fi
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-backup}" in
        backup)
            shift
            create_backup "$@"
            ;;
        --help|-h)
            print_usage
            ;;
        *)
            print_error "Unknown command: $1"
            print_usage
            exit 1
            ;;
    esac
fi