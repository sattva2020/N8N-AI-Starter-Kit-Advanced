#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - ADVANCED MONITORING & ALERTING SYSTEM
# =============================================================================
# Enhanced monitoring with alerts, metrics collection, and reporting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${CYAN}=== $1 ===${NC}"; }
print_metric() { echo -e "${PURPLE}📊${NC} $1"; }

# Configuration
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
METRICS_RETENTION_DAYS="${METRICS_RETENTION_DAYS:-7}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-60}"
ALERT_COOLDOWN="${ALERT_COOLDOWN:-300}"
METRICS_DIR="monitoring-data"

# Alert tracking
ALERT_STATE_FILE="$METRICS_DIR/alert-state.json"
LAST_METRICS_FILE="$METRICS_DIR/last-metrics.json"

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

Advanced monitoring and alerting for N8N AI Starter Kit

COMMANDS:
    start           Start continuous monitoring daemon
    check           Run single health check
    metrics         Collect and display metrics
    alerts          Check and send alerts
    dashboard       Display monitoring dashboard
    report          Generate monitoring report
    cleanup         Clean old monitoring data

OPTIONS:
    --interval N    Health check interval in seconds (default: 60)
    --webhook URL   Alert webhook URL for notifications
    --retention N   Metrics retention in days (default: 7)
    --daemon        Run as background daemon
    --verbose       Verbose output
    --help          Show this help

EXAMPLES:
    $0 start --interval 30 --daemon          # Start monitoring daemon
    $0 check --verbose                       # Run health check with details
    $0 metrics --report                      # Collect metrics and report
    $0 dashboard                             # Show live dashboard
    $0 alerts --webhook https://hooks.slack.com/...

EOF
}

# Initialize monitoring data directory
init_monitoring() {
    mkdir -p "$METRICS_DIR"
    
    if [[ ! -f "$ALERT_STATE_FILE" ]]; then
        echo '{}' > "$ALERT_STATE_FILE"
    fi
    
    if [[ ! -f "$LAST_METRICS_FILE" ]]; then
        echo '{}' > "$LAST_METRICS_FILE"
    fi
}

# Collect comprehensive system metrics
collect_metrics() {
    local timestamp=$(date +%s)
    local metrics_file="$METRICS_DIR/metrics-$(date +%Y%m%d-%H%M%S).json"
    
    print_info "Collecting system metrics..."
    
    # Docker stats
    local docker_stats=""
    if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
        docker_stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "")
    fi
    
    # System metrics
    local cpu_usage=""
    local memory_usage=""
    local disk_usage=""
    
    if command -v top >/dev/null; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    fi
    
    if command -v free >/dev/null; then
        memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "0")
    fi
    
    if command -v df >/dev/null; then
        disk_usage=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1 2>/dev/null || echo "0")
    fi
    
    # Service health checks
    declare -A service_health
    local services=(
        "n8n:5678:/healthz"
        "web-interface:8000:/health"
        "document-processor:8001:/health"
        "etl-processor:8002:/health"
        "lightrag:8003:/health"
        "grafana:3000:/api/health"
        "prometheus:9090:-/healthy"
        "qdrant:6333:/health"
        "traefik:8080:/ping"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name port endpoint <<< "$service_info"
        
        local health_status="down"
        local response_time="0"
        
        if command -v curl >/dev/null; then
            local start_time=$(date +%s%N)
            if curl -f -s --max-time 5 "http://localhost:$port$endpoint" >/dev/null 2>&1; then
                health_status="up"
                local end_time=$(date +%s%N)
                response_time=$(( (end_time - start_time) / 1000000 ))
            fi
        fi
        
        service_health["$service_name"]='{"status":"'$health_status'","response_time":'$response_time'}'
    done
    
    # Create metrics JSON
    cat > "$metrics_file" << EOF
{
  "timestamp": $timestamp,
  "date": "$(date -Iseconds)",
  "system": {
    "cpu_usage": $cpu_usage,
    "memory_usage": $memory_usage,
    "disk_usage": $disk_usage
  },
  "services": {
$(
    local first=true
    for service in "${!service_health[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo "    \"$service\": ${service_health[$service]}"
    done
)
  },
  "docker_stats": "$docker_stats"
}
EOF
    
    # Update last metrics
    cp "$metrics_file" "$LAST_METRICS_FILE"
    
    print_success "Metrics collected: $metrics_file"
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        print_metric "CPU Usage: ${cpu_usage}%"
        print_metric "Memory Usage: ${memory_usage}%"
        print_metric "Disk Usage: ${disk_usage}%"
        
        local healthy_services=0
        local total_services=${#service_health[@]}
        
        for service in "${!service_health[@]}"; do
            local status=$(echo "${service_health[$service]}" | jq -r '.status')
            if [[ "$status" == "up" ]]; then
                ((healthy_services++))
            fi
        done
        
        print_metric "Service Health: $healthy_services/$total_services services healthy"
    fi
}

# Check for alert conditions and send alerts
check_alerts() {
    if [[ ! -f "$LAST_METRICS_FILE" ]]; then
        print_warning "No metrics available for alert checking"
        return 0
    fi
    
    local current_time=$(date +%s)
    local alerts_sent=false
    
    # Load current metrics
    local cpu_usage=$(jq -r '.system.cpu_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
    local memory_usage=$(jq -r '.system.memory_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
    local disk_usage=$(jq -r '.system.disk_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
    
    # Load alert states
    local alert_state=$(cat "$ALERT_STATE_FILE" 2>/dev/null || echo '{}')
    
    # Check CPU usage alert
    if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo "0") )); then
        local last_cpu_alert=$(echo "$alert_state" | jq -r '.cpu_high // 0')
        if (( current_time - last_cpu_alert > ALERT_COOLDOWN )); then
            send_alert "🚨 High CPU Usage" "CPU usage is at ${cpu_usage}% (threshold: 80%)"
            alert_state=$(echo "$alert_state" | jq ".cpu_high = $current_time")
            alerts_sent=true
        fi
    fi
    
    # Check memory usage alert
    if (( $(echo "$memory_usage > 85" | bc -l 2>/dev/null || echo "0") )); then
        local last_memory_alert=$(echo "$alert_state" | jq -r '.memory_high // 0')
        if (( current_time - last_memory_alert > ALERT_COOLDOWN )); then
            send_alert "🚨 High Memory Usage" "Memory usage is at ${memory_usage}% (threshold: 85%)"
            alert_state=$(echo "$alert_state" | jq ".memory_high = $current_time")
            alerts_sent=true
        fi
    fi
    
    # Check disk usage alert
    if (( $(echo "$disk_usage > 90" | bc -l 2>/dev/null || echo "0") )); then
        local last_disk_alert=$(echo "$alert_state" | jq -r '.disk_high // 0')
        if (( current_time - last_disk_alert > ALERT_COOLDOWN )); then
            send_alert "🚨 High Disk Usage" "Disk usage is at ${disk_usage}% (threshold: 90%)"
            alert_state=$(echo "$alert_state" | jq ".disk_high = $current_time")
            alerts_sent=true
        fi
    fi
    
    # Check service health alerts
    if command -v jq >/dev/null; then
        while IFS= read -r service; do
            local status=$(jq -r ".services.\"$service\".status" "$LAST_METRICS_FILE" 2>/dev/null)
            if [[ "$status" == "down" ]]; then
                local last_service_alert=$(echo "$alert_state" | jq -r ".service_down.\"$service\" // 0")
                if (( current_time - last_service_alert > ALERT_COOLDOWN )); then
                    send_alert "🔴 Service Down" "Service '$service' is not responding"
                    alert_state=$(echo "$alert_state" | jq ".service_down.\"$service\" = $current_time")
                    alerts_sent=true
                fi
            fi
        done < <(jq -r '.services | keys[]' "$LAST_METRICS_FILE" 2>/dev/null)
    fi
    
    # Save updated alert state
    echo "$alert_state" > "$ALERT_STATE_FILE"
    
    if [[ "$alerts_sent" == "true" ]]; then
        print_warning "Alerts sent for system issues"
    else
        print_success "No alerts triggered"
    fi
}

# Send alert via webhook
send_alert() {
    local title="$1"
    local message="$2"
    
    print_warning "$title: $message"
    
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        local payload=$(cat << EOF
{
  "text": "$title",
  "attachments": [
    {
      "color": "danger",
      "fields": [
        {
          "title": "Alert",
          "value": "$message",
          "short": false
        },
        {
          "title": "Time",
          "value": "$(date -Iseconds)",
          "short": true
        },
        {
          "title": "System",
          "value": "N8N AI Starter Kit",
          "short": true
        }
      ]
    }
  ]
}
EOF
)
        
        if command -v curl >/dev/null; then
            if curl -f -s -X POST -H "Content-Type: application/json" -d "$payload" "$ALERT_WEBHOOK" >/dev/null 2>&1; then
                print_success "Alert sent via webhook"
            else
                print_error "Failed to send alert via webhook"
            fi
        fi
    fi
}

# Display monitoring dashboard
show_dashboard() {
    clear
    print_header "N8N AI Starter Kit - Monitoring Dashboard"
    echo
    
    if [[ ! -f "$LAST_METRICS_FILE" ]]; then
        print_warning "No metrics available. Run 'collect_metrics' first."
        return 1
    fi
    
    local last_update=$(jq -r '.date' "$LAST_METRICS_FILE" 2>/dev/null || echo "Unknown")
    print_info "Last Update: $last_update"
    echo
    
    # System metrics
    print_header "System Metrics"
    local cpu_usage=$(jq -r '.system.cpu_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
    local memory_usage=$(jq -r '.system.memory_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
    local disk_usage=$(jq -r '.system.disk_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
    
    printf "%-20s %s\n" "CPU Usage:" "$(create_progress_bar "$cpu_usage" 100) ${cpu_usage}%"
    printf "%-20s %s\n" "Memory Usage:" "$(create_progress_bar "$memory_usage" 100) ${memory_usage}%"
    printf "%-20s %s\n" "Disk Usage:" "$(create_progress_bar "$disk_usage" 100) ${disk_usage}%"
    echo
    
    # Service health
    print_header "Service Health"
    if command -v jq >/dev/null; then
        while IFS= read -r service; do
            local status=$(jq -r ".services.\"$service\".status" "$LAST_METRICS_FILE" 2>/dev/null)
            local response_time=$(jq -r ".services.\"$service\".response_time" "$LAST_METRICS_FILE" 2>/dev/null)
            
            local status_icon="❌"
            local status_color="$RED"
            if [[ "$status" == "up" ]]; then
                status_icon="✅"
                status_color="$GREEN"
            fi
            
            printf "%-25s %s%-8s%s %sms\n" "$service:" "$status_color" "$status_icon $status" "$NC" "$response_time"
        done < <(jq -r '.services | keys[]' "$LAST_METRICS_FILE" 2>/dev/null | sort)
    fi
    echo
    
    print_info "Press Ctrl+C to exit dashboard"
}

# Create a simple progress bar
create_progress_bar() {
    local value=$1
    local max=$2
    local width=20
    local percentage=$(( value * width / max ))
    
    local bar=""
    for ((i=0; i<width; i++)); do
        if [[ $i -lt $percentage ]]; then
            if [[ $value -gt 80 ]]; then
                bar="${bar}${RED}█${NC}"
            elif [[ $value -gt 60 ]]; then
                bar="${bar}${YELLOW}█${NC}"
            else
                bar="${bar}${GREEN}█${NC}"
            fi
        else
            bar="${bar}░"
        fi
    done
    
    echo "[$bar]"
}

# Generate monitoring report
generate_report() {
    local report_file="$METRICS_DIR/monitoring-report-$(date +%Y%m%d-%H%M%S).md"
    
    print_info "Generating monitoring report..."
    
    cat > "$report_file" << EOF
# N8N AI Starter Kit - Monitoring Report

**Generated:** $(date)
**Period:** Last $METRICS_RETENTION_DAYS days

## System Overview

EOF
    
    if [[ -f "$LAST_METRICS_FILE" ]]; then
        local cpu_usage=$(jq -r '.system.cpu_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
        local memory_usage=$(jq -r '.system.memory_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
        local disk_usage=$(jq -r '.system.disk_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
        
        cat >> "$report_file" << EOF
### Current System Status
- **CPU Usage:** ${cpu_usage}%
- **Memory Usage:** ${memory_usage}%
- **Disk Usage:** ${disk_usage}%

### Service Health Status
EOF
        
        if command -v jq >/dev/null; then
            while IFS= read -r service; do
                local status=$(jq -r ".services.\"$service\".status" "$LAST_METRICS_FILE" 2>/dev/null)
                local response_time=$(jq -r ".services.\"$service\".response_time" "$LAST_METRICS_FILE" 2>/dev/null)
                
                local status_emoji="❌"
                if [[ "$status" == "up" ]]; then
                    status_emoji="✅"
                fi
                
                echo "- **$service:** $status_emoji $status (${response_time}ms)" >> "$report_file"
            done < <(jq -r '.services | keys[]' "$LAST_METRICS_FILE" 2>/dev/null | sort)
        fi
    fi
    
    cat >> "$report_file" << EOF

## Metrics History

EOF
    
    # Add historical data if available
    local metrics_files=($(ls -t "$METRICS_DIR"/metrics-*.json 2>/dev/null | head -24))
    if [[ ${#metrics_files[@]} -gt 0 ]]; then
        echo "| Time | CPU% | Memory% | Disk% | Services Up |" >> "$report_file"
        echo "|------|------|---------|-------|-------------|" >> "$report_file"
        
        for metrics_file in "${metrics_files[@]}"; do
            if [[ -f "$metrics_file" ]]; then
                local timestamp=$(jq -r '.timestamp' "$metrics_file" 2>/dev/null)
                local date_str=$(date -d "@$timestamp" '+%H:%M' 2>/dev/null || echo "N/A")
                local cpu=$(jq -r '.system.cpu_usage' "$metrics_file" 2>/dev/null || echo "0")
                local memory=$(jq -r '.system.memory_usage' "$metrics_file" 2>/dev/null || echo "0")
                local disk=$(jq -r '.system.disk_usage' "$metrics_file" 2>/dev/null || echo "0")
                
                local services_up=0
                local total_services=0
                if command -v jq >/dev/null; then
                    while IFS= read -r service; do
                        ((total_services++))
                        local status=$(jq -r ".services.\"$service\".status" "$metrics_file" 2>/dev/null)
                        if [[ "$status" == "up" ]]; then
                            ((services_up++))
                        fi
                    done < <(jq -r '.services | keys[]' "$metrics_file" 2>/dev/null)
                fi
                
                echo "| $date_str | $cpu | $memory | $disk | $services_up/$total_services |" >> "$report_file"
            fi
        done
    else
        echo "No historical metrics available." >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Recommendations

EOF
    
    # Add recommendations based on metrics
    if [[ -f "$LAST_METRICS_FILE" ]]; then
        local cpu_usage=$(jq -r '.system.cpu_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
        local memory_usage=$(jq -r '.system.memory_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
        local disk_usage=$(jq -r '.system.disk_usage' "$LAST_METRICS_FILE" 2>/dev/null || echo "0")
        
        if (( $(echo "$cpu_usage > 70" | bc -l 2>/dev/null || echo "0") )); then
            echo "⚠️ **High CPU Usage:** Consider scaling services or optimizing workloads." >> "$report_file"
        fi
        
        if (( $(echo "$memory_usage > 75" | bc -l 2>/dev/null || echo "0") )); then
            echo "⚠️ **High Memory Usage:** Consider increasing available memory or optimizing services." >> "$report_file"
        fi
        
        if (( $(echo "$disk_usage > 80" | bc -l 2>/dev/null || echo "0") )); then
            echo "⚠️ **High Disk Usage:** Consider cleaning up old data or expanding storage." >> "$report_file"
        fi
        
        # Check for services that are consistently down
        local down_services=()
        if command -v jq >/dev/null; then
            while IFS= read -r service; do
                local status=$(jq -r ".services.\"$service\".status" "$LAST_METRICS_FILE" 2>/dev/null)
                if [[ "$status" == "down" ]]; then
                    down_services+=("$service")
                fi
            done < <(jq -r '.services | keys[]' "$LAST_METRICS_FILE" 2>/dev/null)
        fi
        
        if [[ ${#down_services[@]} -gt 0 ]]; then
            echo "🔴 **Services Down:** ${down_services[*]} - Investigate and restart if needed." >> "$report_file"
        fi
        
        if [[ ${#down_services[@]} -eq 0 ]] && (( $(echo "$cpu_usage < 50" | bc -l 2>/dev/null || echo "1") )) && (( $(echo "$memory_usage < 60" | bc -l 2>/dev/null || echo "1") )); then
            echo "✅ **System Health:** All systems operating normally." >> "$report_file"
        fi
    fi
    
    print_success "Report generated: $report_file"
}

# Cleanup old monitoring data
cleanup_monitoring_data() {
    print_info "Cleaning up old monitoring data (older than $METRICS_RETENTION_DAYS days)..."
    
    if [[ -d "$METRICS_DIR" ]]; then
        local deleted_count=0
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((deleted_count++))
        done < <(find "$METRICS_DIR" -name "metrics-*.json" -mtime +$METRICS_RETENTION_DAYS -print0 2>/dev/null)
        
        print_success "Deleted $deleted_count old metrics files"
    else
        print_info "No monitoring data directory found"
    fi
}

# Start monitoring daemon
start_monitoring_daemon() {
    print_header "Starting N8N AI Starter Kit Monitoring Daemon"
    print_info "Health check interval: ${HEALTH_CHECK_INTERVAL}s"
    print_info "Metrics retention: ${METRICS_RETENTION_DAYS} days"
    
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        print_info "Alert webhook configured"
    else
        print_warning "No alert webhook configured"
    fi
    
    local pid_file="$METRICS_DIR/monitor.pid"
    echo $$ > "$pid_file"
    
    print_success "Monitoring daemon started (PID: $$)"
    
    # Cleanup function
    cleanup_daemon() {
        print_info "Stopping monitoring daemon..."
        rm -f "$pid_file"
        exit 0
    }
    
    trap cleanup_daemon SIGTERM SIGINT
    
    while true; do
        collect_metrics
        check_alerts
        
        # Cleanup old data daily
        if (( $(date +%H%M) == 0000 )); then
            cleanup_monitoring_data
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    init_monitoring
    
    local command="${1:-check}"
    
    case "$command" in
        start)
            if [[ "${DAEMON:-false}" == "true" ]]; then
                start_monitoring_daemon &
                print_success "Monitoring daemon started in background"
            else
                start_monitoring_daemon
            fi
            ;;
        check)
            collect_metrics
            check_alerts
            ;;
        metrics)
            collect_metrics
            ;;
        alerts)
            check_alerts
            ;;
        dashboard)
            while true; do
                show_dashboard
                sleep 5
            done
            ;;
        report)
            generate_report
            ;;
        cleanup)
            cleanup_monitoring_data
            ;;
        *)
            print_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# Parse arguments
DAEMON=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --interval) HEALTH_CHECK_INTERVAL="$2"; shift 2 ;;
        --webhook) ALERT_WEBHOOK="$2"; shift 2 ;;
        --retention) METRICS_RETENTION_DAYS="$2"; shift 2 ;;
        --daemon) DAEMON=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --help|-h) print_usage; exit 0 ;;
        --*) print_error "Unknown option: $1"; print_usage; exit 1 ;;
        *) main "$1"; exit $? ;;
    esac
done

# Default to check command if no arguments
main "check"