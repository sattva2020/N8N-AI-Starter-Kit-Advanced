#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - MONITORING SCRIPT
# =============================================================================
# Monitor system health, performance, and alert on issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
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

Monitor N8N AI Starter Kit health and performance.

COMMANDS:
    health              Check service health
    performance         Show performance metrics
    logs                Analyze recent logs for issues
    disk                Check disk usage
    network             Check network connectivity
    security            Run security audit
    all                 Run all checks (default)
    
OPTIONS:
    --threshold N       Disk usage warning threshold (default: 80)
    --days N           Days of logs to analyze (default: 1)
    --format FORMAT    Output format: text, json (default: text)
    --alert            Enable alerting (requires webhook configuration)
    --dry-run          Show what would be checked
    --help             Show this help

EXAMPLES:
    $0                          # Run all health checks
    $0 health                   # Check service health only
    $0 performance --format json  # Performance metrics in JSON
    $0 disk --threshold 90      # Disk check with 90% threshold

EOF
}

check_service_health() {
    print_info "Checking service health..."
    
    local services=(
        "http://localhost:5678/healthz:N8N:n8n"
        "http://localhost:3000/api/health:Grafana:grafana"
        "http://localhost:6333/health:Qdrant:qdrant"
        "http://localhost:8000/health:Web Interface:web-interface"
        "http://localhost:8001/health:Document Processor:document-processor"
        "http://localhost:8002/health:ETL Processor:etl-processor"
    )
    
    local healthy_count=0
    local total_count=${#services[@]}
    local unhealthy_services=()
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r url name container <<< "$service_info"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "Would check: $name ($url)"
            continue
        fi
        
        # Check if container is running
        if ! docker compose ps "$container" --format json 2>/dev/null | jq -e '.[0].State == "running"' >/dev/null 2>&1; then
            print_error "$name container is not running"
            unhealthy_services+=("$name")
            continue
        fi
        
        # Check HTTP endpoint
        if curl -f -s -m 10 "$url" >/dev/null 2>&1; then
            print_success "$name is healthy"
            ((healthy_count++))
        else
            print_error "$name is not responding at $url"
            unhealthy_services+=("$name")
        fi
    done
    
    echo
    print_info "Health Summary: $healthy_count/$total_count services healthy"
    
    if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
        print_warning "Unhealthy services: ${unhealthy_services[*]}"
        return 1
    fi
    
    return 0
}

check_performance() {
    print_info "Checking performance metrics..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Would collect performance metrics"
        return 0
    fi
    
    # Docker stats
    print_info "Container resource usage:"
    docker stats --no-stream --format "table {{.Container}}\\t{{.CPUPerc}}\\t{{.MemUsage}}\\t{{.MemPerc}}\\t{{.NetIO}}\\t{{.BlockIO}}" 2>/dev/null || print_warning "Could not get Docker stats"
    
    echo
    
    # System resources
    print_info "System resource usage:"
    
    # CPU usage
    if command -v top >/dev/null 2>&1; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "unknown")
        echo "  CPU Usage: ${cpu_usage}%"
    fi
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        local mem_info=$(free -m | awk 'NR==2{printf "%.1f", $3*100/$2}' || echo "unknown")
        echo "  Memory Usage: ${mem_info}%"
    fi
    
    # Load average
    if [[ -f /proc/loadavg ]]; then
        local load_avg=$(cat /proc/loadavg | cut -d' ' -f1-3)
        echo "  Load Average: $load_avg"
    fi
    
    # Docker system usage
    print_info "Docker system usage:"
    docker system df 2>/dev/null || print_warning "Could not get Docker system usage"
}

check_disk_usage() {
    local threshold="${1:-80}"
    
    print_info "Checking disk usage (threshold: ${threshold}%)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Would check disk usage with ${threshold}% threshold"
        return 0
    fi
    
    local disk_usage=0
    local critical_mounts=()
    
    # Check system disks
    while IFS= read -r line; do
        local usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount=$(echo "$line" | awk '{print $6}')
        
        if [[ "$usage" -gt "$threshold" ]]; then
            print_warning "Disk usage high on $mount: ${usage}%"
            critical_mounts+=("$mount (${usage}%)")
        else
            print_success "Disk usage OK on $mount: ${usage}%"
        fi
        
        if [[ "$usage" -gt "$disk_usage" ]]; then
            disk_usage="$usage"
        fi
    done < <(df -h | grep -E '^/dev/')
    
    # Check Docker volumes
    print_info "Docker volume usage:"
    docker system df -v 2>/dev/null | grep -E "postgres_data|qdrant_data|grafana_data" || print_warning "Could not get volume usage"
    
    if [[ ${#critical_mounts[@]} -gt 0 ]]; then
        print_error "Critical disk usage detected: ${critical_mounts[*]}"
        return 1
    fi
    
    return 0
}

analyze_logs() {
    local days="${1:-1}"
    
    print_info "Analyzing logs for the last $days day(s)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Would analyze logs from last $days days"
        return 0
    fi
    
    local since_date=$(date -d "$days days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${days}d '+%Y-%m-%d' 2>/dev/null || echo "unknown")
    
    print_info "Checking for errors since $since_date..."
    
    # Check Docker container logs for errors
    local containers=("n8n" "postgres" "qdrant" "grafana" "web-interface" "document-processor" "etl-processor")
    local error_count=0
    
    for container in "${containers[@]}"; do
        if docker compose ps "$container" >/dev/null 2>&1; then
            local errors=$(docker compose logs --since "${days}d" "$container" 2>/dev/null | grep -i -E "(error|exception|failed|fatal)" | wc -l || echo 0)
            
            if [[ "$errors" -gt 0 ]]; then
                print_warning "$container: $errors error(s) found"
                ((error_count += errors))
                
                # Show recent errors
                print_info "Recent errors in $container:"
                docker compose logs --since "${days}d" --tail 5 "$container" 2>/dev/null | grep -i -E "(error|exception|failed|fatal)" | tail -3 || true
            else
                print_success "$container: No errors found"
            fi
        fi
    done
    
    if [[ "$error_count" -gt 0 ]]; then
        print_warning "Total errors found: $error_count"
        return 1
    fi
    
    return 0
}

check_network() {
    print_info "Checking network connectivity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Would check network connectivity"
        return 0
    fi
    
    local network_issues=0
    
    # Check Docker network
    local network_name=$(docker compose config | grep -A 10 "networks:" | grep -E "^\s+\w+:" | head -1 | sed 's/://g' | xargs || echo "n8n-network")
    
    if docker network inspect "$network_name" >/dev/null 2>&1; then
        print_success "Docker network '$network_name' is available"
    else
        print_error "Docker network '$network_name' not found"
        ((network_issues++))
    fi
    
    # Check container connectivity
    local containers=("n8n" "postgres" "qdrant")
    
    for container in "${containers[@]}"; do
        if docker compose exec -T "$container" ping -c 1 google.com >/dev/null 2>&1; then
            print_success "$container has external connectivity"
        else
            print_warning "$container may have connectivity issues"
        fi
    done
    
    # Check port accessibility
    local ports=("5678:N8N" "3000:Grafana" "6333:Qdrant" "5432:PostgreSQL")
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port service <<< "$port_info"
        
        if nc -z localhost "$port" 2>/dev/null; then
            print_success "$service port $port is accessible"
        else
            print_warning "$service port $port is not accessible"
        fi
    done
    
    return $network_issues
}

# Security audit function
run_security_audit() {
    print_info "Running security audit..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Would run security audit"
        return 0
    fi
    
    local security_issues=0
    local N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
    
    # Check N8N API access
    if curl -f -s -m 10 "$N8N_BASE_URL/healthz" >/dev/null 2>&1; then
        print_success "N8N API is accessible"
        
        # Check if authentication is configured
        if [[ -n "${N8N_API_KEY:-}${N8N_PERSONAL_ACCESS_TOKEN:-}" ]]; then
            local auth_header
            if [[ -n "${N8N_PERSONAL_ACCESS_TOKEN:-}" ]]; then
                auth_header="Authorization: Bearer $N8N_PERSONAL_ACCESS_TOKEN"
            else
                auth_header="X-N8N-API-KEY: $N8N_API_KEY"
            fi
            
            # Run N8N security audit
            local audit_payload='{"categories": ["credentials", "database", "filesystem", "instance", "nodes"], "daysAbandonedWorkflow": 90}'
            local audit_response
            
            if audit_response=$(curl -s -X POST -H "Content-Type: application/json" -H "$auth_header" -d "$audit_payload" "$N8N_BASE_URL/api/v1/audit" 2>/dev/null); then
                local risk_count
                risk_count=$(echo "$audit_response" | jq '.risk | length // 0' 2>/dev/null || echo "0")
                
                if [[ "$risk_count" -gt 0 ]]; then
                    print_warning "Found $risk_count security risks in N8N audit"
                    echo "$audit_response" | jq -r '.risk[]? | "  - \(.category): \(.title)"' 2>/dev/null | head -5
                    ((security_issues += risk_count))
                else
                    print_success "No security risks found in N8N audit"
                fi
            else
                print_warning "N8N audit API not available"
                ((security_issues++))
            fi
            
            # Check credentials
            local cred_response
            if cred_response=$(curl -s -H "$auth_header" "$N8N_BASE_URL/api/v1/credentials" 2>/dev/null); then
                local cred_count
                cred_count=$(echo "$cred_response" | jq '.data | length // 0' 2>/dev/null || echo "0")
                print_success "Found $cred_count configured credentials"
            else
                print_warning "Cannot access credentials for audit"
                ((security_issues++))
            fi
            
            # Check workflows
            local workflow_response
            if workflow_response=$(curl -s -H "$auth_header" "$N8N_BASE_URL/api/v1/workflows" 2>/dev/null); then
                local active_count webhook_count
                active_count=$(echo "$workflow_response" | jq '[.data[] | select(.active == true)] | length // 0' 2>/dev/null || echo "0")
                webhook_count=$(echo "$workflow_response" | jq '[.data[] | select(.nodes[]?.type == "n8n-nodes-base.webhook")] | length // 0' 2>/dev/null || echo "0")
                
                print_success "Found $active_count active workflows"
                if [[ "$webhook_count" -gt 0 ]]; then
                    print_warning "$webhook_count workflows expose webhook endpoints"
                fi
            else
                print_warning "Cannot access workflows for audit"
                ((security_issues++))
            fi
        else
            print_warning "No N8N authentication configured for security audit"
            ((security_issues++))
        fi
    else
        print_error "N8N API is not accessible for security audit"
        ((security_issues++))
    fi
    
    # Check Docker security
    print_info "Checking Docker security..."
    
    # Check for containers running as root
    local root_containers
    root_containers=$(docker compose ps --format json 2>/dev/null | jq -r '.[].Name' | xargs -I {} docker inspect {} --format '{{.Name}}: {{.Config.User}}' 2>/dev/null | grep -c ': $' || echo 0)
    
    if [[ "$root_containers" -gt 0 ]]; then
        print_warning "$root_containers containers running as root user"
        ((security_issues++))
    else
        print_success "No containers running as root"
    fi
    
    # Check exposed ports
    local exposed_ports
    exposed_ports=$(docker compose ps --format json 2>/dev/null | jq -r '.[].Publishers[]?.PublishedPort' 2>/dev/null | wc -l || echo 0)
    
    if [[ "$exposed_ports" -gt 0 ]]; then
        print_info "$exposed_ports ports exposed to host"
    fi
    
    return $security_issues
}

generate_report() {
    local format="${1:-text}"
    
    case "$format" in
        json)
            generate_json_report
            ;;
        text)
            generate_text_report
            ;;
        *)
            print_error "Unknown format: $format"
            return 1
            ;;
    esac
}

generate_json_report() {
    cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "healthy",
  "checks": {
    "health": {
      "status": "unknown",
      "details": "Check not run in this mode"
    },
    "performance": {
      "status": "unknown",
      "details": "Check not run in this mode"
    },
    "disk": {
      "status": "unknown",
      "details": "Check not run in this mode"
    },
    "network": {
      "status": "unknown",
      "details": "Check not run in this mode"
    }
  }
}
EOF
}

generate_text_report() {
    echo "N8N AI Starter Kit - Monitoring Report"
    echo "Generated: $(date)"
    echo "========================================"
    echo
    echo "Run individual checks with: $0 [health|performance|disk|network|logs]"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    command="${1:-all}"
    
    case "$command" in
        health)
            shift
            check_service_health "$@"
            ;;
        performance)
            shift
            check_performance "$@"
            ;;
        disk)
            shift
            threshold=80
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --threshold)
                        threshold="$2"
                        shift 2
                        ;;
                    --dry-run)
                        DRY_RUN=true
                        shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            check_disk_usage "$threshold"
            ;;
        logs)
            shift
            days=1
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --days)
                        days="$2"
                        shift 2
                        ;;
                    --dry-run)
                        DRY_RUN=true
                        shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            analyze_logs "$days"
            ;;
        network)
            shift
            check_network "$@"
            ;;
        security)
            shift
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --dry-run)
                        DRY_RUN=true
                        shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            run_security_audit
            ;;
        all)
            shift
            format="text"
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --format)
                        format="$2"
                        shift 2
                        ;;
                    --dry-run)
                        DRY_RUN=true
                        shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            
            overall_status=0
            
            check_service_health || ((overall_status++))
            echo
            check_performance
            echo
            check_disk_usage || ((overall_status++))
            echo
            check_network || ((overall_status++))
            echo
            run_security_audit || ((overall_status++))
            echo
            analyze_logs || ((overall_status++))
            
            echo
            if [[ "$overall_status" -eq 0 ]]; then
                print_success "All monitoring checks passed"
            else
                print_warning "$overall_status check(s) failed"
            fi
            
            exit $overall_status
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