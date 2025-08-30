# Advanced Operations Guide

This guide covers advanced operational features for the N8N AI Starter Kit, including CI/CD integration, advanced monitoring, and disaster recovery.

## Table of Contents

1. [CI/CD Integration](#cicd-integration)
2. [Advanced Monitoring & Alerting](#advanced-monitoring--alerting)
3. [Backup & Disaster Recovery](#backup--disaster-recovery)
4. [Performance Testing](#performance-testing)
5. [Security & Compliance](#security--compliance)

## CI/CD Integration

### GitHub Actions Workflows

The project includes comprehensive GitHub Actions workflows for automated testing and deployment:

#### 1. Comprehensive Testing Pipeline (`.github/workflows/test.yml`)

Runs automatically on push and pull requests:

```bash
# Triggered on:
# - Push to main/develop branches
# - Pull requests to main
# - Manual workflow dispatch
```

**Test Coverage:**
- ✅ Profile configuration validation
- ✅ Unit tests with Python/pytest
- ✅ Integration tests with service startup
- ✅ Service startup tests across multiple profiles
- ✅ Security and audit tests

**Matrix Testing:**
- Tests 4 core profile combinations
- Parallel execution for faster results
- Artifact collection for test reports

#### 2. Docker Build & Deploy (`.github/workflows/deploy.yml`)

Automated image building and deployment:

```bash
# Triggered on:
# - Push to main branch
# - Git tags (v*)
# - Releases
```

**Features:**
- Multi-platform image builds (amd64, arm64)
- Container registry integration (GitHub Container Registry)
- Automated staging deployment
- Production deployment on release tags

#### 3. Performance Testing (`.github/workflows/performance.yml`)

Scheduled performance and stress testing:

```bash
# Triggered on:
# - Weekly schedule (Monday 2 AM)
# - Manual dispatch with custom parameters
```

**Test Types:**
- Load testing with K6
- Stress testing with peak user simulation
- Performance threshold validation
- Automated reporting

### Local CI/CD Testing

Test the CI/CD pipeline locally:

```bash
# Simulate the CI/CD test pipeline
./scripts/run-comprehensive-tests.sh all --verbose

# Test specific components
./scripts/run-comprehensive-tests.sh profiles monitoring backup

# Generate comprehensive report
./scripts/run-comprehensive-tests.sh all --report-dir ci-test-results
```

## Advanced Monitoring & Alerting

### Enhanced Monitoring System

The advanced monitoring system provides comprehensive system oversight:

```bash
# Start continuous monitoring daemon
./scripts/advanced-monitor.sh start --daemon --interval 60

# Run single health check with details
./scripts/advanced-monitor.sh check --verbose

# Collect and display metrics
./scripts/advanced-monitor.sh metrics

# Show live monitoring dashboard
./scripts/advanced-monitor.sh dashboard
```

### Features

#### Real-time Metrics Collection
- **System Metrics**: CPU, Memory, Disk usage
- **Service Health**: Response times and availability
- **Docker Statistics**: Container resource consumption
- **Custom Metrics**: Application-specific indicators

#### Alert System
Configurable alerting with multiple notification channels:

```bash
# Setup webhook alerts (Slack, Discord, etc.)
export ALERT_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Configure alert thresholds and cooldown
export ALERT_COOLDOWN=300  # 5 minutes between same alerts

# Start monitoring with alerts
./scripts/advanced-monitor.sh start --webhook "$ALERT_WEBHOOK" --daemon
```

**Alert Conditions:**
- 🚨 **High CPU Usage** (>80%)
- 🚨 **High Memory Usage** (>85%)
- 🚨 **High Disk Usage** (>90%)
- 🔴 **Service Down** (health check fails)

#### Monitoring Dashboard

Interactive dashboard with progress bars and color-coded status:

```bash
# Launch live dashboard
./scripts/advanced-monitor.sh dashboard

# Dashboard shows:
# - System resource usage with visual progress bars
# - Service health status with response times
# - Real-time updates every 5 seconds
```

#### Comprehensive Reporting

Generate detailed monitoring reports:

```bash
# Generate monitoring report
./scripts/advanced-monitor.sh report

# Reports include:
# - Current system status
# - Historical metrics (last 24 hours)
# - Service health trends
# - Automated recommendations
```

### Monitoring Integration

#### Grafana Dashboard Integration
The monitoring system complements existing Grafana dashboards:

```bash
# Access Grafana dashboard
open http://grafana.localhost
# Default: admin / (check .env for password)

# Import advanced monitoring data sources
# - System metrics endpoint: http://localhost:9090
# - Service health endpoints: various ports
```

#### Prometheus Metrics
Services expose Prometheus-compatible metrics:

```bash
# Check service metrics
curl http://localhost:8000/metrics  # Web Interface
curl http://localhost:8001/metrics  # Document Processor
curl http://localhost:8002/metrics  # ETL Processor
```

## Backup & Disaster Recovery

### Comprehensive Backup System

Automated backup with encryption and remote sync:

```bash
# Create full system backup
./scripts/backup-disaster-recovery.sh backup --verify --encrypt

# List available backups
./scripts/backup-disaster-recovery.sh list

# Verify backup integrity
./scripts/backup-disaster-recovery.sh verify backup-20240130-123456
```

### Backup Components

#### What Gets Backed Up
- ✅ **Docker Volumes**: All persistent data (n8n, postgres, qdrant, grafana)
- ✅ **Configuration Files**: .env, docker-compose.yml, config/ directory
- ✅ **Database Dumps**: PostgreSQL database export
- ✅ **N8N Workflows**: Workflow definitions via API
- ✅ **System Metadata**: Backup verification data

#### Backup Features

**Compression Options:**
```bash
# Gzip compression (default)
./scripts/backup-disaster-recovery.sh backup --compression gzip

# XZ compression (higher ratio)
./scripts/backup-disaster-recovery.sh backup --compression xz

# No compression (faster)
./scripts/backup-disaster-recovery.sh backup --compression none
```

**Encryption:**
```bash
# Encrypt with auto-generated key
./scripts/backup-disaster-recovery.sh backup --encrypt

# Use custom encryption key
export ENCRYPTION_KEY="your-secure-key-here"
./scripts/backup-disaster-recovery.sh backup --encrypt
```

**Remote Sync:**
```bash
# Sync to S3 (requires AWS CLI)
export REMOTE_BACKUP_URL="s3://your-backup-bucket/"
./scripts/backup-disaster-recovery.sh backup
./scripts/backup-disaster-recovery.sh sync-remote

# Sync via rsync
export REMOTE_BACKUP_URL="user@backup-server:/backup/path/"
./scripts/backup-disaster-recovery.sh sync-remote
```

### Automated Backup Scheduling

Setup automated backups with cron:

```bash
# Setup daily backups at 2 AM
./scripts/backup-disaster-recovery.sh schedule --schedule daily

# Setup hourly backups
./scripts/backup-disaster-recovery.sh schedule --schedule hourly

# Setup weekly backups (Sundays 2 AM)
./scripts/backup-disaster-recovery.sh schedule --schedule weekly
```

### Disaster Recovery

#### Full System Restore

```bash
# List available backups
./scripts/backup-disaster-recovery.sh list

# Restore from specific backup
./scripts/backup-disaster-recovery.sh restore backup-20240130-123456

# Restore to custom location
./scripts/backup-disaster-recovery.sh restore backup-20240130-123456 /custom/restore/path
```

#### Recovery Process

1. **Stop Current Services**: `./start.sh down`
2. **Restore Backup**: `./scripts/backup-disaster-recovery.sh restore [backup-name]`
3. **Verify Configuration**: Check restored `.env` and config files
4. **Start Services**: `./start.sh up --profile [your-profile]`
5. **Verify Functionality**: Run health checks and test key workflows

#### Recovery Testing

Regular recovery testing ensures backup reliability:

```bash
# Test backup creation and verification
./scripts/run-comprehensive-tests.sh backup

# Include in comprehensive testing
./scripts/run-comprehensive-tests.sh all
```

### Backup Maintenance

#### Cleanup Old Backups

```bash
# Clean backups older than 30 days (default)
./scripts/backup-disaster-recovery.sh cleanup

# Custom retention period
export BACKUP_RETENTION_DAYS=14
./scripts/backup-disaster-recovery.sh cleanup
```

#### Backup Verification

```bash
# Verify specific backup
./scripts/backup-disaster-recovery.sh verify backup-20240130-123456

# Automated verification during backup
./scripts/backup-disaster-recovery.sh backup --verify
```

## Performance Testing

### K6 Load Testing

The performance testing system uses K6 for comprehensive load testing:

#### Baseline Performance Testing

```bash
# Manual performance test
k6 run k6-tests/load-test.js --duration 10m

# Automated via GitHub Actions
# Triggered weekly or on-demand
```

**Test Scenarios:**
- Gradual load ramp-up (10 → 20 users)
- Sustained load testing (5 minutes)
- Health endpoint validation
- Response time thresholds

#### Stress Testing

```bash
# Stress test with peak load
k6 run k6-tests/stress-test.js

# Test profile:
# 1m: 50 users
# 3m: 100 users  
# 1m: 150 users (peak)
# 2m: ramp down
```

### Performance Thresholds

**Response Time Targets:**
- Health endpoints: < 200ms (95th percentile)
- API endpoints: < 500ms (95th percentile)
- Error rate: < 10%

**Monitoring Integration:**
- Grafana performance dashboards
- Real-time metrics during testing
- Historical performance tracking

## Security & Compliance

### Security Testing

Automated security testing and compliance checking:

```bash
# Run security audit
./scripts/maintenance/monitor.sh security --dry-run

# Include in comprehensive testing
./scripts/run-comprehensive-tests.sh security
```

### Security Features

#### Container Security
- Non-root user containers
- Read-only root filesystems where possible
- Security scanning with Trivy/Clair
- Minimal attack surface

#### Network Security
- Internal network isolation
- TLS termination at proxy level
- Secure service communication
- Environment variable security

#### Data Protection
- Encrypted backups
- Secure credential management
- Database connection encryption
- Audit logging

### Compliance Monitoring

Regular compliance checks for:
- ✅ **Secret Management**: No hardcoded secrets
- ✅ **Access Control**: Proper authentication setup
- ✅ **Data Encryption**: Encrypted data at rest and transit
- ✅ **Audit Trails**: Comprehensive logging
- ✅ **Backup Security**: Encrypted backup storage

## Integration Examples

### Complete DevOps Workflow

```bash
# 1. Development testing
./scripts/test-profiles.sh basic --with-startup --verbose

# 2. Comprehensive testing before commit
./scripts/run-comprehensive-tests.sh all

# 3. Setup monitoring for development
./scripts/advanced-monitor.sh start --daemon

# 4. Create baseline backup
./scripts/backup-disaster-recovery.sh backup --verify

# 5. Deploy with confidence
git push origin main  # Triggers CI/CD pipeline
```

### Production Deployment

```bash
# 1. Production backup before deployment
./scripts/backup-disaster-recovery.sh backup --encrypt --verify

# 2. Deploy new version
./start.sh down
git pull origin main
./start.sh up --profile production

# 3. Start production monitoring
./scripts/advanced-monitor.sh start --daemon --webhook "$SLACK_WEBHOOK"

# 4. Verify deployment
./scripts/test-profiles.sh production --with-startup

# 5. Setup automated backups
./scripts/backup-disaster-recovery.sh schedule --schedule daily
```

This advanced operations guide provides the foundation for running N8N AI Starter Kit in production with confidence, comprehensive monitoring, and robust disaster recovery capabilities.