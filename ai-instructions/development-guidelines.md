# AI Agent Instructions for N8N AI Starter Kit

This document provides guidelines and instructions for AI agents (like Claude, GPT-4, etc.) working with the N8N AI Starter Kit project.

## Project Overview for AI Agents

The N8N AI Starter Kit is a production-ready, containerized deployment that combines:
- **n8n workflow automation** as the core engine
- **AI services** for document processing and vector search
- **Monitoring stack** with Grafana and Prometheus
- **Security features** including automatic TLS and strong authentication
- **Cross-platform compatibility** (Linux, macOS, Windows with Git Bash)

## Key Design Principles

### 1. Zero-Secret Repository
- **NEVER** commit actual passwords, API keys, or certificates
- Use template-based environment generation with placeholders
- All secrets are generated during setup via `scripts/setup.sh`
- Pattern: `change_this_secure_password_123` for placeholders

### 2. Cross-Platform Compatibility
- Support Linux, macOS, and Windows (Git Bash)
- Use Docker named volumes (not bind mounts) for Windows compatibility
- Test scripts with both `bash` and Git Bash on Windows
- Use `sed` commands compatible with both GNU and BSD versions

### 3. Production-Ready Security
- Automatic TLS certificates via Let's Encrypt
- Strong password generation using OpenSSL
- Network isolation with Docker bridge networking
- Security headers and HTTPS redirects

## Common Tasks and Patterns

### Adding New Services

When adding a FastAPI service:

1. **Create service directory structure:**
   ```
   services/new-service/
   ├── Dockerfile
   ├── main.py
   ├── requirements.txt
   └── README.md
   ```

2. **Standard FastAPI template:**
   ```python
   from fastapi import FastAPI
   from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
   
   app = FastAPI(title="Service Name", version="1.0.0")
   
   @app.get("/health")
   async def health_check():
       return {"status": "healthy", "timestamp": datetime.utcnow()}
   
   @app.get("/metrics")  
   async def metrics():
       return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
   ```

3. **Add to docker-compose.yml:**
   ```yaml
   new-service:
     build:
       context: ./services/new-service
     profiles: ["developer"]  # Choose appropriate profile
     environment:
       - PORT=8003
     networks:
       - n8n-network
     healthcheck:
       test: ["CMD", "curl", "-f", "http://localhost:8003/health"]
   ```

### Environment Variable Management

**Adding new environment variables:**

1. **Update `env.schema`** with documentation
2. **Add to `template.env`** with placeholder values
3. **Update `scripts/setup.sh`** if special generation is needed
4. **Document in README.md** if user-configurable

**Example pattern:**
```bash
# In template.env
NEW_SERVICE_API_KEY=change_this_api_key_789

# In scripts/setup.sh (if auto-generated)
local new_api_key=$(generate_api_key 32)
sed -i "s/change_this_api_key_789/${new_api_key}/g" "$ENV_FILE"
```

### Script Development Guidelines

**Shell script standards:**
```bash
#!/bin/bash
set -euo pipefail  # Always use strict mode

# Standard color definitions
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Standard print functions
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
```

**Cross-platform compatibility:**
```bash
# Use conditional sed for macOS/Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/pattern/replacement/" file
else
    # Linux/Windows Git Bash
    sed -i "s/pattern/replacement/" file
fi
```

### Docker Configuration Patterns

**Service naming convention:**
- Container names: `n8n-servicename`
- Network: `n8n-network` 
- Volumes: `servicename_data`

**Health check template:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s  # Longer for services that need startup time
```

**Traefik labels template:**
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.servicename.rule=Host(`service.${DOMAIN}`)"
  - "traefik.http.routers.servicename.entrypoints=websecure"
  - "traefik.http.routers.servicename.tls.certresolver=letsencrypt"
  - "traefik.http.services.servicename.loadbalancer.server.port=PORT"
  - "traefik.http.routers.servicename.middlewares=security-headers@docker"
```

## Code Quality Standards

### Python Services (FastAPI)

**Required dependencies:**
```txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pydantic-settings==2.1.0
prometheus-client==0.19.0
structlog==23.2.0
```

**Logging configuration:**
```python
import structlog

structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()
```

**Configuration management:**
```python
from pydantic import BaseModel, Field

class Settings(BaseModel):
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    debug: bool = Field(default=False, env="DEBUG")
    # Use env parameter for environment variable mapping
```

### Shell Scripts

**Error handling:**
```bash
# Always check command success
if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker not found"
    exit 1
fi

# Use || for conditional execution
docker compose up -d || {
    print_error "Failed to start services"
    exit 1
}
```

**Argument parsing:**
```bash
while [[ $# -gt 0 ]]; do
    case $1 in
        --option)
            OPTION="$2"
            shift 2
            ;;
        --flag)
            FLAG=true
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done
```

## Troubleshooting Patterns

### Common Issues to Address

1. **Port conflicts**: Always check if ports are available
2. **Permission issues**: Provide clear chmod instructions
3. **Network connectivity**: Include network debugging steps
4. **Certificate issues**: Guide users through DNS/firewall setup
5. **Resource constraints**: Monitor and alert on resource usage

### Debugging Helpers

**Standard debugging commands:**
```bash
# Service status
./start.sh status

# Service logs
./start.sh logs --follow servicename

# Health checks
./scripts/maintenance/monitor.sh health

# Resource usage
./scripts/maintenance/monitor.sh performance
```

**Common fixes:**
```bash
# Restart services
./start.sh restart

# Clean up Docker
./start.sh cleanup

# Reset environment
./scripts/setup.sh --force

# Check configuration
docker compose config
```

## Documentation Standards

### README.md Sections
1. **Quick Start**: Get users running in under 5 minutes
2. **Architecture**: Visual diagram and service overview  
3. **Configuration**: Environment variables and profiles
4. **Usage**: Common commands and workflows
5. **Security**: Default security and production checklist
6. **Troubleshooting**: Common issues and solutions

### Code Documentation
- **Inline comments**: Explain complex logic
- **Function docstrings**: Purpose, parameters, return values
- **Configuration comments**: Explain why settings matter
- **Script help**: Comprehensive usage examples

### API Documentation
- **OpenAPI/Swagger**: Auto-generated for FastAPI services
- **Examples**: Working curl commands for all endpoints
- **Error codes**: Document expected error responses

## Testing Guidelines

### Health Check Testing
```bash
# Always verify services are healthy after changes
./scripts/maintenance/monitor.sh health

# Test individual endpoints
curl -f http://localhost:8000/health
curl -f http://localhost:8001/health
curl -f http://localhost:8002/health
```

### Integration Testing
```bash
# Test document processing workflow
curl -X POST "http://localhost:8001/docs/upload" \
  -F "file=@test-document.pdf"

# Test credential management
./scripts/create_n8n_credential.sh --dry-run \
  --type postgres --name "test" --data '{}'
```

### Cross-Platform Testing
- Test on Linux (Ubuntu/CentOS)
- Test on macOS
- Test on Windows with Git Bash
- Verify Docker volume persistence on Windows

## Security Considerations

### Never Commit
- Real passwords or API keys
- Certificate files
- Database connection strings with real credentials
- User data or logs

### Always Include
- Input validation in scripts
- Error handling for external commands
- Timeouts for network operations
- Proper file permissions (chmod +x for scripts)

### Security Checklist for Changes
- [ ] No secrets in code or configs
- [ ] Proper input validation
- [ ] Network isolation maintained
- [ ] HTTPS redirects working
- [ ] Security headers configured
- [ ] Default passwords changed

## Performance Considerations

### Resource Management
- Monitor Docker container resource usage
- Set appropriate health check intervals
- Configure worker counts based on available CPU
- Use connection pooling for database connections

### Scalability Patterns
- Design services to be stateless
- Use environment variables for configuration
- Support horizontal scaling with load balancing
- Implement proper logging for distributed tracing

---

## AI Agent Specific Guidelines

When working on this project:

1. **Always preserve the zero-secret principle** - never suggest committing real credentials
2. **Test cross-platform compatibility** - consider Windows users with Git Bash
3. **Maintain backward compatibility** - don't break existing configurations
4. **Follow existing patterns** - use the same structure and naming conventions
5. **Document thoroughly** - update both README.md and project.md for significant changes
6. **Security first** - always consider security implications of changes
7. **Use meaningful defaults** - configuration should work out-of-the-box
8. **Provide clear error messages** - help users troubleshoot issues quickly

Remember: This is a production-ready system that users depend on. Changes should be thoroughly tested and well-documented.