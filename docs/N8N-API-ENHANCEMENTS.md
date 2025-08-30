# N8N API Enhancements Documentation

## Overview

This document describes the enhanced N8N API capabilities added to the N8N-AI-Starter-Kit-Qoder project, including new scripts, monitoring tools, and security features based on the official N8N API documentation.

## New Scripts and Tools

### 1. Enhanced Credential Management (`create_n8n_credential.sh`)

**Location**: `scripts/create_n8n_credential.sh`

#### New Features Added:
- **Pagination Support**: List credentials with customizable page sizes and cursor-based navigation
- **Schema Retrieval**: Get credential schemas directly from the N8N API
- **Type Listing**: Display available credential types

#### Usage Examples:

```bash
# List credentials with pagination
./scripts/create_n8n_credential.sh --list --limit 50

# Get all credentials across all pages
./scripts/create_n8n_credential.sh --list --all

# Get specific page using cursor
./scripts/create_n8n_credential.sh --list --cursor MTIzZTQ1NjctZTg5Yi0xMmQzLWE0NTYtNDI2NjE0MTc0MDA

# Get credential schema for specific type
./scripts/create_n8n_credential.sh --get-schema githubApi

# List available credential types
./scripts/create_n8n_credential.sh --list-types
```

### 2. Execution Monitoring Script (`n8n-execution-monitor.sh`)

**Location**: `scripts/n8n-execution-monitor.sh`

#### Features:
- **Real-time Monitoring**: Watch workflow executions in real-time
- **Advanced Filtering**: Filter by workflow, status, date range
- **Performance Metrics**: Execution statistics and performance analysis
- **Export Capabilities**: Export execution data to JSON

#### Usage Examples:

```bash
# List recent executions
./scripts/n8n-execution-monitor.sh --list --limit 20

# Watch executions in real-time
./scripts/n8n-execution-monitor.sh --watch

# Show failed executions with details
./scripts/n8n-execution-monitor.sh --list --status error --details

# Get execution statistics
./scripts/n8n-execution-monitor.sh --stats

# Export all executions to file
./scripts/n8n-execution-monitor.sh --export executions.json --all

# Monitor specific workflow
./scripts/n8n-execution-monitor.sh --list --workflow-name "Data Processing" --watch
```

### 3. Workflow Management Script (`n8n-workflow-manager.sh`)

**Location**: `scripts/n8n-workflow-manager.sh`

#### Features:
- **Workflow Lifecycle**: Create, update, activate, deactivate, delete workflows
- **Bulk Operations**: List, filter, and manage multiple workflows
- **Health Monitoring**: Check workflow health and performance
- **Import/Export**: Workflow backup and deployment capabilities

#### Usage Examples:

```bash
# List all workflows
./scripts/n8n-workflow-manager.sh --list

# List only active workflows
./scripts/n8n-workflow-manager.sh --list --active

# Activate a workflow
./scripts/n8n-workflow-manager.sh --activate workflow_123

# Get workflow details
./scripts/n8n-workflow-manager.sh --get workflow_123

# Watch workflow status in real-time
./scripts/n8n-workflow-manager.sh --watch

# Show workflow health summary
./scripts/n8n-workflow-manager.sh --health

# Export workflow to file
./scripts/n8n-workflow-manager.sh --export workflow_123 my-workflow.json

# Create workflow from file
./scripts/n8n-workflow-manager.sh --create new-workflow.json

# Show performance metrics
./scripts/n8n-workflow-manager.sh --performance
```

### 4. Enhanced Security Monitoring (`scripts/maintenance/monitor.sh`)

#### New Security Audit Features:
- **N8N Security Audit**: Integrated N8N API security assessment
- **Credential Security**: Validation of credential configurations
- **Workflow Security**: Analysis of workflow security risks
- **Infrastructure Security**: Docker and system security checks

#### Usage Examples:

```bash
# Run complete monitoring including security audit
./scripts/maintenance/monitor.sh all

# Run only security audit
./scripts/maintenance/monitor.sh security

# Security audit with dry-run
./scripts/maintenance/monitor.sh security --dry-run
```

## API Integration Details

### Authentication
All scripts support two authentication methods:
- **Personal Access Token**: Set `N8N_PERSONAL_ACCESS_TOKEN`
- **API Key**: Set `N8N_API_KEY`

### Pagination
Implemented according to N8N API standards:
- Default page size: 100 results (configurable up to 250)
- Cursor-based pagination with `nextCursor` field
- Support for retrieving all results across pages

### Error Handling
Comprehensive error handling for HTTP status codes:
- 200/201: Success
- 400: Bad request with detailed error messages
- 401: Authentication issues
- 403: Permission errors
- 404: Resource not found
- 422: Validation errors
- 500: Server errors

## Security Features

### Built-in N8N Audit
Leverages N8N's built-in audit API with configurable categories:
- **Credentials**: Security of stored credentials
- **Database**: Database access and permissions
- **Filesystem**: File system security
- **Instance**: N8N instance configuration
- **Nodes**: Node security analysis

### Security Monitoring
- Container security assessment
- Port exposure analysis
- Permission validation
- Network security checks

## Configuration

### Environment Variables

```bash
# N8N API Configuration
N8N_BASE_URL="http://localhost:5678"
N8N_PERSONAL_ACCESS_TOKEN="your_token_here"
# OR
N8N_API_KEY="your_api_key_here"

# Security Audit Configuration
AUDIT_ABANDONED_DAYS=90  # Days for abandoned workflow detection
```

### Dependencies
All scripts require:
- `curl` - HTTP requests
- `jq` - JSON processing
- `date` - Date/time operations

## Integration with Existing Infrastructure

### Monitoring Integration
- Seamless integration with existing monitoring stack
- Prometheus metrics support (configurable)
- Grafana dashboard compatibility
- Alert system integration

### Backup and Recovery
- Workflow export/import capabilities
- Execution data archival
- Configuration backup support

## Best Practices

### Security
1. Use Personal Access Tokens for enhanced security
2. Limit API key scopes (Enterprise feature)
3. Regular security audits using built-in audit API
4. Monitor credential usage and rotation

### Performance
1. Use pagination for large datasets
2. Implement cursor-based navigation for efficient browsing
3. Monitor execution performance metrics
4. Archive old execution data

### Maintenance
1. Regular workflow health checks
2. Automated backup procedures
3. Performance monitoring and optimization
4. Security audit scheduling

## Troubleshooting

### Common Issues

#### Authentication Errors
```bash
# Verify API access
curl -H "X-N8N-API-KEY: your_key" http://localhost:5678/api/v1/workflows

# Check token validity
curl -H "Authorization: Bearer your_token" http://localhost:5678/api/v1/workflows
```

#### API Connectivity
```bash
# Test N8N health
curl http://localhost:5678/healthz

# Verify API endpoint
curl http://localhost:5678/api/v1/workflows
```

#### Script Execution
```bash
# Check dependencies
which curl jq date

# Test with dry-run
./scripts/n8n-execution-monitor.sh --list --dry-run
```

### Log Analysis
Monitor script execution through standard output and Docker logs:
```bash
# View container logs
docker compose logs n8n

# Monitor script execution
./scripts/n8n-workflow-manager.sh --list --verbose
```

## Future Enhancements

### Planned Features
1. **Advanced Analytics**: Enhanced execution analytics and reporting
2. **Automated Remediation**: Self-healing capabilities for common issues
3. **Integration APIs**: RESTful APIs for external system integration
4. **Dashboard UI**: Web-based management interface

### API Extensions
1. **Bulk Operations**: Enhanced bulk workflow and credential operations
2. **Advanced Filtering**: More sophisticated filtering and search capabilities
3. **Real-time Events**: WebSocket-based real-time event streaming
4. **Custom Metrics**: Application-specific monitoring metrics

## Support and Maintenance

### Script Maintenance
- Regular updates to match N8N API changes
- Performance optimization based on usage patterns
- Security enhancements and vulnerability fixes

### Documentation Updates
- Keep documentation synchronized with N8N API changes
- Add new examples and use cases
- Update troubleshooting guides

---

For more information about the N8N API, refer to the official documentation:
- [N8N API Documentation](https://docs.n8n.io/api/)
- [N8N API Authentication](https://docs.n8n.io/api/authentication/)
- [N8N API Pagination](https://docs.n8n.io/api/pagination/)