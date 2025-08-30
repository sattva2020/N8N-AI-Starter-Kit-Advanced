#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - AUTOMATED BACKUP & DISASTER RECOVERY
# =============================================================================
# Comprehensive backup, restore, and disaster recovery system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${CYAN}=== $1 ===${NC}"; }

# Configuration
BACKUP_DIR="${BACKUP_DIR:-backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-gzip}"
REMOTE_BACKUP_URL="${REMOTE_BACKUP_URL:-}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-daily}"

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

Automated backup and disaster recovery for N8N AI Starter Kit

COMMANDS:
    backup          Create a full system backup
    restore         Restore from backup
    list            List available backups
    verify          Verify backup integrity
    cleanup         Clean old backups
    schedule        Setup automated backup schedule
    disaster-recovery   Full disaster recovery procedure
    sync-remote     Sync backups to remote location

OPTIONS:
    --backup-dir DIR     Backup directory (default: backups)
    --retention N        Backup retention in days (default: 30)
    --compression TYPE   Compression type: gzip|xz|none (default: gzip)
    --encrypt           Encrypt backups (requires ENCRYPTION_KEY)
    --remote URL        Remote backup URL (rsync, s3, etc.)
    --schedule TYPE     Backup schedule: hourly|daily|weekly (default: daily)
    --verify            Verify backup after creation
    --verbose           Verbose output
    --help              Show this help

EXAMPLES:
    $0 backup --verify --encrypt                # Create encrypted backup with verification
    $0 restore backup-20240130-123456          # Restore specific backup
    $0 schedule --schedule daily               # Setup daily automated backups
    $0 disaster-recovery --from-backup latest  # Full disaster recovery

EOF
}

# Initialize backup system
init_backup_system() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/logs"
    mkdir -p "$BACKUP_DIR/metadata"
    
    # Create backup metadata template
    if [[ ! -f "$BACKUP_DIR/metadata/backup.json" ]]; then
        cat > "$BACKUP_DIR/metadata/backup.json" << 'EOF'
{
  "backup_system": {
    "version": "1.0",
    "created": "$(date -Iseconds)",
    "retention_days": 30,
    "compression": "gzip",
    "encryption": false
  },
  "backups": []
}
EOF
    fi
    
    print_success "Backup system initialized"
}

# Create comprehensive backup
create_backup() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    local log_file="$BACKUP_DIR/logs/$backup_name.log"
    
    print_header "Creating Backup: $backup_name"
    
    mkdir -p "$backup_path"
    
    # Start logging
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    print_info "Backup started at $(date)"
    
    # 1. Backup Docker volumes and data
    print_info "Backing up Docker volumes..."
    if docker volume ls >/dev/null 2>&1; then
        mkdir -p "$backup_path/docker-volumes"
        
        local volumes=($(docker volume ls --format "{{.Name}}" | grep -E "(n8n|postgres|qdrant|grafana|prometheus)" 2>/dev/null || true))
        
        for volume in "${volumes[@]}"; do
            print_info "  Backing up volume: $volume"
            
            if [[ "$BACKUP_COMPRESSION" == "gzip" ]]; then
                docker run --rm -v "$volume:/data" -v "$PWD/$backup_path/docker-volumes:/backup" alpine:latest tar czf "/backup/$volume.tar.gz" -C /data . 2>/dev/null || {
                    print_warning "Failed to backup volume: $volume"
                }
            elif [[ "$BACKUP_COMPRESSION" == "xz" ]]; then
                docker run --rm -v "$volume:/data" -v "$PWD/$backup_path/docker-volumes:/backup" alpine:latest tar cJf "/backup/$volume.tar.xz" -C /data . 2>/dev/null || {
                    print_warning "Failed to backup volume: $volume"
                }
            else
                docker run --rm -v "$volume:/data" -v "$PWD/$backup_path/docker-volumes:/backup" alpine:latest tar cf "/backup/$volume.tar" -C /data . 2>/dev/null || {
                    print_warning "Failed to backup volume: $volume"
                }
            fi
        done
    fi
    
    # 2. Backup configuration files
    print_info "Backing up configuration files..."
    mkdir -p "$backup_path/config"
    
    local config_files=(
        ".env"
        "docker-compose.yml"
        "config/"
        "scripts/"
        "README.md"
        "project.md"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -e "$PROJECT_ROOT/$config_file" ]]; then
            cp -r "$PROJECT_ROOT/$config_file" "$backup_path/config/" 2>/dev/null || {
                print_warning "Failed to backup: $config_file"
            }
        fi
    done
    
    # 3. Backup database (if accessible)
    print_info "Backing up databases..."
    mkdir -p "$backup_path/databases"
    
    # PostgreSQL backup
    if docker compose ps postgres >/dev/null 2>&1 && docker compose exec postgres pg_isready >/dev/null 2>&1; then
        print_info "  Backing up PostgreSQL database..."
        
        local postgres_container=$(docker compose ps postgres -q)
        if [[ -n "$postgres_container" ]]; then
            docker compose exec -T postgres pg_dumpall -U postgres > "$backup_path/databases/postgres_dump.sql" 2>/dev/null || {
                print_warning "PostgreSQL backup failed"
            }
        fi
    fi
    
    # 4. Export N8N workflows (if accessible)
    if command -v curl >/dev/null && curl -f -s http://localhost:5678/healthz >/dev/null 2>&1; then
        print_info "Backing up N8N workflows..."
        mkdir -p "$backup_path/n8n-workflows"
        
        # Try to export workflows via API (requires authentication)
        if [[ -n "${N8N_PERSONAL_ACCESS_TOKEN:-}" ]] || [[ -n "${N8N_API_KEY:-}" ]]; then
            local auth_header=""
            if [[ -n "${N8N_PERSONAL_ACCESS_TOKEN:-}" ]]; then
                auth_header="Authorization: Bearer $N8N_PERSONAL_ACCESS_TOKEN"
            elif [[ -n "${N8N_API_KEY:-}" ]]; then
                auth_header="X-N8N-API-KEY: $N8N_API_KEY"
            fi
            
            if curl -f -s -H "$auth_header" "http://localhost:5678/api/v1/workflows" > "$backup_path/n8n-workflows/workflows.json" 2>/dev/null; then
                print_success "  N8N workflows exported"
            else
                print_warning "  Failed to export N8N workflows"
            fi
        else
            print_warning "  No N8N authentication configured, skipping workflow export"
        fi
    fi
    
    # 5. Create backup metadata
    print_info "Creating backup metadata..."
    local backup_metadata=$(cat << EOF
{
  "name": "$backup_name",
  "created": "$(date -Iseconds)",
  "timestamp": $(date +%s),
  "compression": "$BACKUP_COMPRESSION",
  "encrypted": false,
  "size": 0,
  "checksum": "",
  "components": {
    "docker_volumes": true,
    "configuration": true,
    "databases": true,
    "n8n_workflows": true
  },
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "docker_version": "$(docker --version 2>/dev/null || echo 'Not available')",
    "compose_version": "$(docker compose version 2>/dev/null || echo 'Not available')"
  }
}
EOF
)
    
    echo "$backup_metadata" > "$backup_path/metadata.json"
    
    # 6. Calculate backup size and checksum
    local backup_size=$(du -sb "$backup_path" | cut -f1)
    local backup_checksum=""
    
    if command -v sha256sum >/dev/null; then
        backup_checksum=$(find "$backup_path" -type f -exec sha256sum {} \; | sha256sum | cut -d' ' -f1)
    fi
    
    # Update metadata with size and checksum
    local updated_metadata=$(echo "$backup_metadata" | jq ".size = $backup_size | .checksum = \"$backup_checksum\"")
    echo "$updated_metadata" > "$backup_path/metadata.json"
    
    # 7. Encrypt backup if requested
    if [[ -n "$ENCRYPTION_KEY" ]] && command -v openssl >/dev/null; then
        print_info "Encrypting backup..."
        
        local encrypted_backup="$backup_path.tar.gz.enc"
        
        if [[ "$BACKUP_COMPRESSION" == "gzip" ]]; then
            tar czf - -C "$BACKUP_DIR" "$backup_name" | openssl enc -aes-256-cbc -salt -k "$ENCRYPTION_KEY" > "$encrypted_backup"
        elif [[ "$BACKUP_COMPRESSION" == "xz" ]]; then
            tar cJf - -C "$BACKUP_DIR" "$backup_name" | openssl enc -aes-256-cbc -salt -k "$ENCRYPTION_KEY" > "$encrypted_backup"
        else
            tar cf - -C "$BACKUP_DIR" "$backup_name" | openssl enc -aes-256-cbc -salt -k "$ENCRYPTION_KEY" > "$encrypted_backup"
        fi
        
        # Remove unencrypted backup
        rm -rf "$backup_path"
        
        # Update metadata
        local encrypted_metadata=$(echo "$updated_metadata" | jq ".encrypted = true | .encrypted_file = \"$encrypted_backup\"")
        echo "$encrypted_metadata" > "$BACKUP_DIR/metadata/$backup_name.json"
        
        print_success "Backup encrypted: $encrypted_backup"
    else
        # Compress unencrypted backup
        if [[ "$BACKUP_COMPRESSION" == "gzip" ]]; then
            tar czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "$backup_name"
            rm -rf "$backup_path"
            backup_path="$backup_path.tar.gz"
        elif [[ "$BACKUP_COMPRESSION" == "xz" ]]; then
            tar cJf "$backup_path.tar.xz" -C "$BACKUP_DIR" "$backup_name"
            rm -rf "$backup_path"
            backup_path="$backup_path.tar.xz"
        fi
        
        cp "$backup_path/metadata.json" "$BACKUP_DIR/metadata/$backup_name.json" 2>/dev/null || true
    fi
    
    # 8. Verify backup if requested
    if [[ "${VERIFY_BACKUP:-false}" == "true" ]]; then
        print_info "Verifying backup integrity..."
        verify_backup "$backup_name"
    fi
    
    # 9. Sync to remote if configured
    if [[ -n "$REMOTE_BACKUP_URL" ]]; then
        print_info "Syncing to remote location..."
        sync_to_remote "$backup_name"
    fi
    
    print_success "Backup completed: $backup_name"
    print_info "Backup location: $backup_path"
    print_info "Backup size: $(du -h "$backup_path" 2>/dev/null | cut -f1 || echo 'Unknown')"
    print_info "Log file: $log_file"
}

# List available backups
list_backups() {
    print_header "Available Backups"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_warning "No backup directory found"
        return 1
    fi
    
    local backups=($(ls -t "$BACKUP_DIR"/backup-* 2>/dev/null | grep -E '\.(tar\.gz|tar\.xz|tar)$|backup-[0-9]{8}-[0-9]{6}$' || true))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        print_warning "No backups found"
        return 0
    fi
    
    printf "%-25s %-20s %-10s %-15s %s\n" "Backup Name" "Created" "Size" "Type" "Status"
    printf "%-25s %-20s %-10s %-15s %s\n" "----------" "-------" "----" "----" "------"
    
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_base_name=$(echo "$backup_name" | sed 's/\.(tar\.gz|tar\.xz|tar)$//')
        
        local created_date="Unknown"
        local size="Unknown"
        local backup_type="Standard"
        local status="✓"
        
        # Try to get metadata
        local metadata_file="$BACKUP_DIR/metadata/$backup_base_name.json"
        if [[ -f "$metadata_file" ]]; then
            created_date=$(jq -r '.created // "Unknown"' "$metadata_file" 2>/dev/null | cut -d'T' -f1)
            backup_type=$(jq -r 'if .encrypted then "Encrypted" else "Standard" end' "$metadata_file" 2>/dev/null)
        fi
        
        # Get file size
        if [[ -f "$backup" ]]; then
            size=$(du -h "$backup" 2>/dev/null | cut -f1)
        elif [[ -d "$backup" ]]; then
            size=$(du -sh "$backup" 2>/dev/null | cut -f1)
        else
            status="❌"
        fi
        
        printf "%-25s %-20s %-10s %-15s %s\n" "$backup_base_name" "$created_date" "$size" "$backup_type" "$status"
    done
}

# Verify backup integrity
verify_backup() {
    local backup_name="$1"
    
    print_header "Verifying Backup: $backup_name"
    
    local metadata_file="$BACKUP_DIR/metadata/$backup_name.json"
    if [[ ! -f "$metadata_file" ]]; then
        print_error "Backup metadata not found: $backup_name"
        return 1
    fi
    
    local is_encrypted=$(jq -r '.encrypted // false' "$metadata_file")
    local expected_checksum=$(jq -r '.checksum // ""' "$metadata_file")
    
    local backup_file=""
    if [[ "$is_encrypted" == "true" ]]; then
        backup_file=$(jq -r '.encrypted_file' "$metadata_file")
    else
        # Find the backup file
        for ext in ".tar.gz" ".tar.xz" ".tar" ""; do
            if [[ -f "$BACKUP_DIR/$backup_name$ext" ]]; then
                backup_file="$BACKUP_DIR/$backup_name$ext"
                break
            fi
        done
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "Backup file not found: $backup_name"
        return 1
    fi
    
    print_info "Verifying file integrity..."
    
    # Verify file can be read
    if [[ "$is_encrypted" == "true" ]]; then
        if [[ -z "$ENCRYPTION_KEY" ]]; then
            print_error "Encryption key required to verify encrypted backup"
            return 1
        fi
        
        # Test decryption
        if openssl enc -d -aes-256-cbc -k "$ENCRYPTION_KEY" -in "$backup_file" | tar tf - >/dev/null 2>&1; then
            print_success "Encrypted backup can be decrypted and extracted"
        else
            print_error "Failed to decrypt or extract backup"
            return 1
        fi
    else
        # Test extraction
        if tar tf "$backup_file" >/dev/null 2>&1; then
            print_success "Backup archive is valid"
        else
            print_error "Backup archive is corrupted"
            return 1
        fi
    fi
    
    # Verify checksum if available
    if [[ -n "$expected_checksum" ]] && command -v sha256sum >/dev/null; then
        print_info "Verifying checksum..."
        local actual_checksum=$(sha256sum "$backup_file" | cut -d' ' -f1)
        
        if [[ "$actual_checksum" == "$expected_checksum" ]]; then
            print_success "Checksum verification passed"
        else
            print_error "Checksum verification failed"
            print_error "Expected: $expected_checksum"
            print_error "Actual: $actual_checksum"
            return 1
        fi
    fi
    
    print_success "Backup verification completed successfully"
}

# Restore from backup
restore_backup() {
    local backup_name="$1"
    local restore_dir="${2:-restore-$(date +%Y%m%d-%H%M%S)}"
    
    print_header "Restoring Backup: $backup_name"
    print_warning "This will restore system configuration and data"
    
    # Confirmation
    read -p "Are you sure you want to restore? This may overwrite current data (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Restore cancelled"
        return 0
    fi
    
    mkdir -p "$restore_dir"
    
    # Find backup file
    local backup_file=""
    local metadata_file="$BACKUP_DIR/metadata/$backup_name.json"
    
    if [[ -f "$metadata_file" ]]; then
        local is_encrypted=$(jq -r '.encrypted // false' "$metadata_file")
        
        if [[ "$is_encrypted" == "true" ]]; then
            backup_file=$(jq -r '.encrypted_file' "$metadata_file")
            
            if [[ -z "$ENCRYPTION_KEY" ]]; then
                print_error "Encryption key required to restore encrypted backup"
                return 1
            fi
            
            print_info "Decrypting backup..."
            openssl enc -d -aes-256-cbc -k "$ENCRYPTION_KEY" -in "$backup_file" | tar xzf - -C "$restore_dir"
        else
            # Find unencrypted backup file
            for ext in ".tar.gz" ".tar.xz" ".tar" ""; do
                if [[ -f "$BACKUP_DIR/$backup_name$ext" ]]; then
                    backup_file="$BACKUP_DIR/$backup_name$ext"
                    break
                fi
            done
            
            if [[ -z "$backup_file" ]]; then
                print_error "Backup file not found: $backup_name"
                return 1
            fi
            
            print_info "Extracting backup..."
            tar xf "$backup_file" -C "$restore_dir"
        fi
    else
        print_error "Backup metadata not found: $backup_name"
        return 1
    fi
    
    # Restore components
    local extracted_backup="$restore_dir/$backup_name"
    
    print_info "Restoring configuration files..."
    if [[ -d "$extracted_backup/config" ]]; then
        cp -r "$extracted_backup/config"/* "$PROJECT_ROOT/" 2>/dev/null || {
            print_warning "Some configuration files could not be restored"
        }
    fi
    
    print_info "Restoring Docker volumes..."
    if [[ -d "$extracted_backup/docker-volumes" ]]; then
        for volume_backup in "$extracted_backup/docker-volumes"/*.tar*; do
            if [[ -f "$volume_backup" ]]; then
                local volume_name=$(basename "$volume_backup" | sed 's/\.(tar\.gz|tar\.xz|tar)$//')
                print_info "  Restoring volume: $volume_name"
                
                # Create volume if it doesn't exist
                docker volume create "$volume_name" >/dev/null 2>&1 || true
                
                # Restore volume data
                if [[ "$volume_backup" == *.tar.gz ]]; then
                    docker run --rm -v "$volume_name:/data" -v "$PWD/$volume_backup:/backup.tar.gz" alpine:latest tar xzf /backup.tar.gz -C /data
                elif [[ "$volume_backup" == *.tar.xz ]]; then
                    docker run --rm -v "$volume_name:/data" -v "$PWD/$volume_backup:/backup.tar.xz" alpine:latest tar xJf /backup.tar.xz -C /data
                else
                    docker run --rm -v "$volume_name:/data" -v "$PWD/$volume_backup:/backup.tar" alpine:latest tar xf /backup.tar -C /data
                fi
            fi
        done
    fi
    
    print_info "Restoring databases..."
    if [[ -f "$extracted_backup/databases/postgres_dump.sql" ]]; then
        print_info "  Restoring PostgreSQL database..."
        # This would require the PostgreSQL container to be running
        print_warning "  Database restore requires manual intervention - see: $extracted_backup/databases/postgres_dump.sql"
    fi
    
    print_success "Restore completed"
    print_info "Restored to: $restore_dir"
    print_info "Please restart services and verify functionality"
}

# Sync backups to remote location
sync_to_remote() {
    local backup_name="${1:-}"
    
    if [[ -z "$REMOTE_BACKUP_URL" ]]; then
        print_warning "No remote backup URL configured"
        return 0
    fi
    
    print_info "Syncing backups to remote location: $REMOTE_BACKUP_URL"
    
    if [[ "$REMOTE_BACKUP_URL" == s3://* ]]; then
        # S3 sync (requires aws CLI)
        if command -v aws >/dev/null; then
            if [[ -n "$backup_name" ]]; then
                # Sync specific backup
                aws s3 sync "$BACKUP_DIR" "$REMOTE_BACKUP_URL" --include "*$backup_name*"
            else
                # Sync all backups
                aws s3 sync "$BACKUP_DIR" "$REMOTE_BACKUP_URL"
            fi
            print_success "Backups synced to S3"
        else
            print_error "AWS CLI not available for S3 sync"
            return 1
        fi
    elif [[ "$REMOTE_BACKUP_URL" == *:* ]]; then
        # rsync to remote host
        if command -v rsync >/dev/null; then
            if [[ -n "$backup_name" ]]; then
                rsync -avz "$BACKUP_DIR"/*"$backup_name"* "$REMOTE_BACKUP_URL/"
            else
                rsync -avz "$BACKUP_DIR/" "$REMOTE_BACKUP_URL/"
            fi
            print_success "Backups synced via rsync"
        else
            print_error "rsync not available"
            return 1
        fi
    else
        print_error "Unsupported remote backup URL format: $REMOTE_BACKUP_URL"
        return 1
    fi
}

# Setup automated backup schedule
setup_backup_schedule() {
    print_header "Setting up Backup Schedule: $BACKUP_SCHEDULE"
    
    local cron_schedule=""
    case "$BACKUP_SCHEDULE" in
        hourly)
            cron_schedule="0 * * * *"
            ;;
        daily)
            cron_schedule="0 2 * * *"
            ;;
        weekly)
            cron_schedule="0 2 * * 0"
            ;;
        *)
            print_error "Invalid schedule: $BACKUP_SCHEDULE (use: hourly, daily, weekly)"
            return 1
            ;;
    esac
    
    local backup_script="$SCRIPT_DIR/$(basename "$0")"
    local cron_job="$cron_schedule cd '$PROJECT_ROOT' && '$backup_script' backup --verify"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    print_success "Backup schedule configured: $BACKUP_SCHEDULE"
    print_info "Cron job: $cron_job"
}

# Cleanup old backups
cleanup_old_backups() {
    print_info "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
    
    local deleted_count=0
    
    # Find and delete old backup files
    while IFS= read -r -d '' backup_file; do
        rm -f "$backup_file"
        ((deleted_count++))
        print_info "  Deleted: $(basename "$backup_file")"
    done < <(find "$BACKUP_DIR" -name "backup-*" -mtime +$BACKUP_RETENTION_DAYS -print0 2>/dev/null)
    
    # Clean up old metadata files
    while IFS= read -r -d '' metadata_file; do
        rm -f "$metadata_file"
    done < <(find "$BACKUP_DIR/metadata" -name "backup-*.json" -mtime +$BACKUP_RETENTION_DAYS -print0 2>/dev/null)
    
    # Clean up old log files
    while IFS= read -r -d '' log_file; do
        rm -f "$log_file"
    done < <(find "$BACKUP_DIR/logs" -name "backup-*.log" -mtime +$BACKUP_RETENTION_DAYS -print0 2>/dev/null)
    
    print_success "Cleaned up $deleted_count old backup files"
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    init_backup_system
    
    local command="${1:-help}"
    
    case "$command" in
        backup)
            create_backup
            ;;
        restore)
            if [[ $# -lt 2 ]]; then
                print_error "Backup name required for restore"
                list_backups
                exit 1
            fi
            restore_backup "$2" "${3:-}"
            ;;
        list)
            list_backups
            ;;
        verify)
            if [[ $# -lt 2 ]]; then
                print_error "Backup name required for verification"
                list_backups
                exit 1
            fi
            verify_backup "$2"
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        schedule)
            setup_backup_schedule
            ;;
        sync-remote)
            sync_to_remote "${2:-}"
            ;;
        disaster-recovery)
            print_header "Disaster Recovery Procedure"
            print_info "This will guide you through full system recovery"
            print_warning "Ensure you have a valid backup before proceeding"
            list_backups
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            print_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# Parse arguments
VERIFY_BACKUP=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
        --retention) BACKUP_RETENTION_DAYS="$2"; shift 2 ;;
        --compression) BACKUP_COMPRESSION="$2"; shift 2 ;;
        --encrypt) ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(openssl rand -hex 32)}"; shift ;;
        --remote) REMOTE_BACKUP_URL="$2"; shift 2 ;;
        --schedule) BACKUP_SCHEDULE="$2"; shift 2 ;;
        --verify) VERIFY_BACKUP=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --help|-h) print_usage; exit 0 ;;
        --*) print_error "Unknown option: $1"; print_usage; exit 1 ;;
        *) main "$@"; exit $? ;;
    esac
done

print_usage
