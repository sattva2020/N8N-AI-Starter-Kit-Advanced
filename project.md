# N8N AI Starter Kit - Technical Design Document

## Project Overview

The N8N AI Starter Kit is a production-ready, containerized deployment platform that provides a comprehensive environment for workflow automation with integrated AI services. It combines n8n's powerful workflow capabilities with modern AI technologies, vector search, and enterprise-grade monitoring in a single, orchestrated deployment.

### Core Value Propositions

- **One-Command Deployment**: Complete setup from zero to production in minutes
- **AI-Ready Infrastructure**: Integrated document processing and vector search
- **Production Security**: Automatic TLS, strong passwords, network isolation
- **Cross-Platform**: Works on Linux, macOS, and Windows (Git Bash)
- **Zero-Secret Repository**: No credentials committed, template-based generation
- **Enterprise Monitoring**: Grafana dashboards and Prometheus metrics

### Target Use Cases

1. **Rapid Prototyping**: Quickly spin up n8n with AI services for experimentation
2. **Production Deployment**: Robust, secure deployment for real-world use cases
3. **Development Environment**: Consistent setup for teams working on n8n workflows
4. **AI Integration**: Ready-to-use document processing and vector search capabilities
5. **Monitoring Setup**: Complete observability stack for workflow monitoring

## Architecture Design

### System Architecture

The platform follows a microservices architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────────┐
│                        EXTERNAL LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│                      Traefik (Reverse Proxy)                   │
│                    • TLS Termination                           │
│                    • Let's Encrypt ACME                       │
│                    • Security Headers                         │
├─────────────────────────────────────────────────────────────────┤
│                     APPLICATION LAYER                          │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │    N8N      │  │ Web Interface│  │   FastAPI Services    │  │
│  │ Workflows   │  │  Dashboard   │  │ • Document Processor  │  │
│  │             │  │              │  │ • ETL Processor      │  │
│  │             │  │              │  │ • LightRAG           │  │
│  └─────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                        DATA LAYER                              │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ PostgreSQL  │  │   Qdrant     │  │     ClickHouse       │  │
│  │ + pgvector  │  │ Vector DB    │  │   (Analytics)        │  │
│  └─────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    MONITORING LAYER                            │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Prometheus  │  │   Grafana    │  │    Health Checks     │  │
│  │  Metrics    │  │ Dashboards   │  │                      │  │
│  └─────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Service Communication

Services communicate through a private Docker network with the following patterns:

1. **HTTP REST APIs**: Primary communication method
2. **Database Connections**: Direct TCP connections with connection pooling
3. **Message Passing**: N8N webhook endpoints for event-driven workflows
4. **Health Checks**: Regular HTTP health endpoints for monitoring

### Deployment Profiles

The system supports multiple deployment profiles for different use cases:

| Profile | Services | Use Case |
|---------|----------|----------|
| `default` | Traefik, N8N, PostgreSQL | Minimal n8n deployment |
| `developer` | + Qdrant, Web Interface, Document Processor, LightRAG | Development with AI features |
| `monitoring` | + Grafana, Prometheus | Production monitoring |
| `analytics` | + ETL Processor, ClickHouse | Full analytics capability |

## Technology Stack

### Core Infrastructure

- **Container Runtime**: Docker 20.10+ with Docker Compose v2
- **Reverse Proxy**: Traefik v3.0 with automatic ACME certificates
- **Networking**: Docker bridge networking with service discovery
- **Storage**: Named Docker volumes for persistence
- **Operating System**: Linux containers (tested on Ubuntu 20.04+, Alpine)

### Application Layer

- **Workflow Engine**: n8n (latest stable)
- **Web Framework**: FastAPI 0.104+ with Pydantic v2 validation
- **Template Engine**: Jinja2 for web interface rendering
- **ASGI Server**: Uvicorn with multiple worker support
- **Authentication**: JWT tokens and API keys

### Data Storage

- **Primary Database**: PostgreSQL 15+ with extensions:
  - `pgvector`: Vector similarity search
  - `uuid-ossp`: UUID generation
  - `pg_stat_statements`: Query performance monitoring
- **Vector Database**: Qdrant 1.7+ with named collections
- **Analytics Database**: ClickHouse 23.x for time-series analytics
- **File Storage**: Docker volumes with backup capabilities

### AI/ML Stack

- **Embedding Models**: SentenceTransformers library
  - Default: `sentence-transformers/all-MiniLM-L6-v2` (384 dimensions)
  - Configurable model selection
- **Document Processing**: 
  - PyPDF2 for PDF text extraction
  - python-docx for Word documents
  - Custom chunking algorithms
- **Task Scheduling**: APScheduler for ETL operations

### Monitoring & Observability

- **Metrics Collection**: Prometheus 2.x with custom exporters
- **Visualization**: Grafana 10.x with provisioned dashboards
- **Health Monitoring**: Custom health check endpoints
- **Logging**: Structured logging with JSON format
- **Alerting**: Grafana alerting with webhook notifications

## Component Deep Dive

### Traefik Configuration

**Key Features:**
- Automatic service discovery via Docker labels
- Let's Encrypt certificate generation with HTTP-01 challenge
- Security middleware injection (HSTS, CSP, X-Frame-Options)
- Load balancing with health checks
- Request routing based on host headers

**Configuration Highlights:**
```yaml
# Automatic HTTPS redirect
--entrypoints.web.http.redirections.entrypoint.to=websecure
--entrypoints.web.http.redirections.entrypoint.scheme=https

# Let's Encrypt integration
--certificatesresolvers.letsencrypt.acme.httpchallenge=true
--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}
```

### N8N Integration

**Authentication Methods:**
- Personal Access Token (PAT) for REST API access
- Public API Key for webhook endpoints
- Basic authentication for web interface (optional)

**Database Integration:**
- PostgreSQL as primary storage backend
- Persistent execution history and workflow data
- Credential encryption at rest

**API Endpoints:**
- `/api/v1/workflows` - Workflow management
- `/api/v1/executions` - Execution history
- `/api/v1/credentials` - Credential management
- `/webhook/*` - Webhook endpoints

### FastAPI Microservices Architecture

#### Web Interface Service (Port 8000)

**Purpose**: Provides a management dashboard and API gateway

**Key Features:**
- Responsive web interface with Bootstrap 5
- Real-time service monitoring
- Document management interface
- Workflow execution dashboard
- System health monitoring

**API Endpoints:**
```python
GET  /health              # Service health check
GET  /status              # Detailed system status
GET  /metrics             # Prometheus metrics
GET  /ui/dashboard        # Main dashboard
GET  /api/v1/documents    # Document listing API
```

#### Document Processor Service (Port 8001)

**Purpose**: AI-powered document processing with embedding generation

**Processing Pipeline:**
1. **Document Upload**: Multi-format file upload with validation
2. **Text Extraction**: Format-specific text extraction (PDF, DOCX, TXT)
3. **Text Chunking**: Intelligent text segmentation with overlap
4. **Embedding Generation**: SentenceTransformers model inference  
5. **Storage**: Dual storage in PostgreSQL and Qdrant

**Key Features:**
- Background task processing with async/await
- Configurable chunking strategies
- Model warming for faster inference
- Progress tracking for long operations
- Error handling with retry logic

**API Endpoints:**
```python
POST /docs/upload         # Upload document for processing
POST /docs/search         # Vector similarity search
GET  /docs/{id}/status    # Processing status
```

#### ETL Processor Service (Port 8002)

**Purpose**: Scheduled data processing and analytics pipeline

**Core Functions:**
- Workflow execution data synchronization from N8N
- Document processing metrics aggregation
- Analytics data preparation for ClickHouse
- System performance monitoring

**Scheduling Framework:**
- APScheduler with AsyncIO backend
- Configurable cron and interval triggers
- Job persistence and recovery
- Manual job triggering via API

**Data Pipeline:**
```python
# Example workflow sync job
@scheduler.add_job('interval', minutes=5)
async def sync_workflow_executions():
    executions = await n8n_client.get_executions()
    await store_in_postgres(executions)
    await store_in_clickhouse(executions)
```

#### LightRAG Service (Port 8003)

**Purpose**: Graph-based Retrieval Augmented Generation for intelligent document analysis

**Core Functions:**
- Automatic entity and relationship extraction from documents
- Knowledge graph construction and maintenance
- Multi-modal query processing (naive, local, global, hybrid)
- Context-aware response generation using OpenAI models

**Graph-based RAG Features:**
- Dynamic knowledge graph construction from unstructured text
- Entity relationship mapping with automatic linking
- Multiple query strategies for different use cases
- Contextual response generation with source attribution

**API Endpoints:**
```python
POST /documents/ingest      # Ingest text content into knowledge graph
POST /documents/ingest-file # Upload and process file content
POST /query               # Query knowledge graph with various modes
GET  /documents           # List stored documents with metadata
GET  /stats               # Service statistics and graph metrics
```

**Query Modes:**
- **Naive**: Simple semantic search without graph traversal
- **Local**: Local graph search focusing on nearby entities
- **Global**: Global graph analysis for comprehensive understanding
- **Hybrid**: Combines local and global approaches (recommended)

**Integration with OpenAI:**
- GPT-4o-mini or GPT-4o for text generation
- Text-embedding-3-small for vector representations
- Configurable model selection and parameters
- Automatic rate limiting and error handling

### Database Architecture

#### PostgreSQL Schema Design

**Primary Schemas:**
- `n8n`: N8N core data (workflows, executions, credentials)
- `documents`: Document storage and embedding data
- `analytics`: Aggregated analytics and metrics

**Key Tables:**
```sql
-- Document storage
CREATE TABLE documents.document_store (
    id UUID PRIMARY KEY,
    filename VARCHAR(500) NOT NULL,
    content TEXT,
    metadata JSONB DEFAULT '{}',
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Vector embeddings
CREATE TABLE documents.embeddings (
    id UUID PRIMARY KEY,
    document_id UUID REFERENCES documents.document_store(id),
    chunk_index INTEGER NOT NULL,
    chunk_text TEXT NOT NULL,
    embedding VECTOR(384),  -- SentenceTransformers dimension
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

#### Qdrant Collection Schema

**Configuration:**
```json
{
  "vectors": {
    "size": 384,
    "distance": "Cosine"
  },
  "payload_schema": {
    "document_id": "keyword",
    "filename": "keyword",
    "chunk_index": "integer",
    "chunk_text": "text",
    "metadata": "object"
  }
}
```

**Search Capabilities:**
- Cosine similarity search with configurable thresholds
- Metadata filtering (document type, date range, etc.)
- Hybrid search combining vector and keyword filtering
- Pagination and result ranking

### Security Implementation

#### TLS and Certificate Management

**Automatic Certificate Generation:**
- Let's Encrypt ACME HTTP-01 challenge
- Automatic renewal before expiration
- Certificate storage in persistent volumes
- Support for wildcard certificates (DNS challenge)

#### Network Security

**Container Isolation:**
- Dedicated Docker bridge network
- No direct external access to internal services
- Reverse proxy as single entry point
- Internal service discovery via Docker DNS

#### Secret Management

**Environment Variable Security:**
- Template-based secret generation
- Strong password generation using OpenSSL
- No secrets committed to repository
- Environment validation on startup

#### Authentication & Authorization

**N8N API Security:**
```bash
# Personal Access Token
Authorization: Bearer ${N8N_PERSONAL_ACCESS_TOKEN}

# Public API Key
X-N8N-API-KEY: ${N8N_API_KEY}
```

**Service-to-Service Authentication:**
- Internal network communication (no external auth required)
- Database connection with username/password
- API key-based authentication for Qdrant

### Monitoring and Observability

#### Metrics Collection

**Prometheus Configuration:**
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
  
  - job_name: 'document-processor'
    static_configs:
      - targets: ['document-processor:8001']
```

**Custom Metrics:**
```python
# Document processing metrics
DOCUMENTS_PROCESSED = Counter('documents_processed_total', 
                            'Total documents processed', 
                            ['status'])

PROCESSING_TIME = Histogram('document_processing_duration_seconds',
                          'Document processing duration')

ACTIVE_PROCESSES = Gauge('active_document_processes',
                       'Number of active processing tasks')
```

#### Grafana Dashboards

**Pre-configured Dashboards:**
1. **N8N Overview**: Workflow executions, success rates, duration
2. **System Resources**: CPU, memory, disk usage
3. **Document Processing**: Upload rates, processing times, error rates
4. **Database Performance**: Query performance, connection pools

**Dashboard Features:**
- Real-time data updates
- Alerting rules with notifications
- Custom time ranges and filters
- Export and import capabilities

## Development Workflow

### Local Development Setup

```bash
# 1. Clone and setup
git clone <repository>
cd n8n-ai-starter-kit
./scripts/setup.sh --non-interactive

# 2. Start development environment  
./start.sh --profile default,developer --detach

# 3. Enable debug mode
echo "DEBUG=true" >> .env
echo "LOG_LEVEL=DEBUG" >> .env
./start.sh restart

# 4. Monitor logs
./start.sh logs --follow document-processor
```

### Service Development

**Adding New Services:**
1. Create service directory in `services/`
2. Add Dockerfile and requirements
3. Update docker-compose.yml
4. Add health check endpoint
5. Update monitoring configuration

**FastAPI Service Template:**
```python
from fastapi import FastAPI
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="New Service")

@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow()}

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

### Testing Strategy

**Health Check Testing:**
```bash
# Service health checks
./scripts/maintenance/monitor.sh health

# Individual service testing
curl -f http://localhost:8001/health
curl -f http://localhost:8000/health  
curl -f http://localhost:8002/health
```

**Integration Testing:**
```bash
# Document processing workflow
curl -X POST "http://localhost:8001/docs/upload" \
  -F "file=@test-document.pdf"

# Search functionality
curl -X POST "http://localhost:8001/docs/search" \
  -H "Content-Type: application/json" \
  -d '{"query": "test query", "limit": 5}'
```

### Backup and Recovery

#### Backup Strategy

**Automated Backups:**
```bash
# Full system backup
./scripts/maintenance/backup.sh

# Service-specific backup
./scripts/maintenance/backup.sh --services postgres,qdrant

# Scheduled backup (add to cron)
0 2 * * * /path/to/n8n-ai-starter-kit/scripts/maintenance/backup.sh
```

**Backup Contents:**
- All Docker volumes (postgres_data, qdrant_data, etc.)
- Configuration files (.env, docker-compose.yml)
- Custom configurations (config/ directory)
- Application data (data/ directory)

#### Recovery Procedures

**Disaster Recovery:**
```bash
# List available backups
./scripts/maintenance/restore.sh list

# Restore from latest backup
./scripts/maintenance/restore.sh latest --force

# Partial restore (specific services)
./scripts/maintenance/restore.sh latest --services postgres
```

## Production Deployment

### Infrastructure Requirements

**Minimum System Requirements:**
- **CPU**: 4 cores (8+ recommended for AI workloads)
- **Memory**: 8GB RAM (16GB+ recommended)
- **Storage**: 50GB SSD (100GB+ for production)
- **Network**: Stable internet for certificate generation

**Recommended Production Setup:**
- **CPU**: 8+ cores with good single-thread performance
- **Memory**: 32GB+ RAM for ML model inference
- **Storage**: NVMe SSD with regular backups
- **Network**: Load balancer with SSL termination

### Production Configuration

**Environment Variables:**
```bash
# Production domain
DOMAIN=your-production-domain.com
ACME_EMAIL=admin@your-production-domain.com

# Security settings
N8N_SECURE_COOKIE=true
N8N_PROTOCOL=https

# Performance settings
WEB_INTERFACE_WORKERS=4
DOC_PROCESSOR_WORKERS=2
ETL_PROCESSOR_WORKERS=1

# Profiles
COMPOSE_PROFILES=default,developer,monitoring,analytics
```

**SSL Certificate Setup:**
1. Ensure DNS points to your server
2. Configure firewall (ports 80, 443 open)
3. Start services and verify certificate generation
4. Set up certificate renewal monitoring

### Scaling Considerations

**Horizontal Scaling:**
- Multiple document processor instances
- Load balancing with Traefik
- Database connection pooling
- Qdrant cluster configuration

**Vertical Scaling:**
- Increase worker counts for CPU-bound services
- Allocate more memory for ML model inference
- SSD storage for better I/O performance

**Monitoring at Scale:**
- Set up Grafana alerting
- Configure log aggregation
- Monitor resource utilization trends
- Set up automated backup verification

### Maintenance Procedures

**Regular Maintenance:**
```bash
# Weekly health check
./scripts/maintenance/monitor.sh all

# Monthly cleanup
./start.sh cleanup

# Quarterly updates
git pull
./start.sh update
```

**Performance Optimization:**
```bash
# Monitor performance
./scripts/maintenance/monitor.sh performance

# Database maintenance
docker exec -it n8n-postgres psql -U n8n_user -d n8n -c "VACUUM ANALYZE;"

# Docker cleanup
docker system prune -f --volumes
```

## API Documentation

### N8N Credential Management API

The N8N AI Starter Kit includes comprehensive automated credential management:

**Automated Setup:**
```bash
# During service startup - automatic credential creation
./start.sh up

# Manual setup for all services  
./start.sh setup-credentials

# Advanced interactive setup
python3 scripts/credential-manager.py --interactive
```

**Service-Specific Setup:**
```bash
# Create credentials for specific services
./scripts/auto-setup-credentials.sh --services postgres,qdrant,openai,ollama

# Dry-run to preview changes
./scripts/auto-setup-credentials.sh --dry-run

# Force recreate existing credentials
./scripts/auto-setup-credentials.sh --force
```

**Supported Credential Types:**
- `postgres/postgresql`: PostgreSQL database connections
- `qdrant`: Vector database (HTTP header auth)
- `redis`: Redis cache connections
- `openai`: OpenAI API (HTTP header auth)
- `ollama`: Local LLM server (HTTP header auth)
- `neo4j`: Neo4j graph database connections
- `clickhouse`: ClickHouse analytics (HTTP header auth)
- `grafana`: Grafana dashboard (HTTP basic auth)

For detailed documentation, see [docs/CREDENTIAL-MANAGEMENT.md](docs/CREDENTIAL-MANAGEMENT.md)

### Original Credential Management API

The credential management script provides a comprehensive API for managing N8N credentials:

**Basic Usage:**
```bash
# Authentication via environment variables
export N8N_PERSONAL_ACCESS_TOKEN="your-token"
# OR
export N8N_API_KEY="your-api-key"

# List credentials
./scripts/create_n8n_credential.sh --list

# Create credential
./scripts/create_n8n_credential.sh \
  --type postgres \
  --name "Production DB" \
  --data '{"host":"db.example.com","port":5432}'
```

**Supported Credential Types:**
- `postgres/postgresql`: PostgreSQL database connections
- `redis`: Redis cache connections  
- `qdrant`: Qdrant vector database (uses HTTP header auth)
- `neo4j`: Neo4j graph database connections
- `http`: Generic HTTP authentication
- `oauth2`: OAuth2 authentication flows

**Bulk Operations:**
```json
[
  {
    "name": "Main Database",
    "type": "postgres", 
    "data": {
      "host": "${POSTGRES_HOST}",
      "port": "${POSTGRES_PORT}",
      "database": "${POSTGRES_DB}",
      "username": "${POSTGRES_USER}",
      "password": "${POSTGRES_PASSWORD}"
    }
  },
  {
    "name": "Vector Database",
    "type": "qdrant",
    "data": {
      "name": "X-API-Key",
      "value": "${QDRANT_API_KEY}"
    }
  }
]
```

### Document Processing API

**Upload Document:**
```bash
curl -X POST "http://localhost:8001/docs/upload" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@document.pdf"

# Response:
{
  "document_id": "uuid-here",
  "filename": "document.pdf", 
  "status": "processing",
  "message": "Document upload successful, processing started"
}
```

**Search Documents:**
```bash
curl -X POST "http://localhost:8001/docs/search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "machine learning algorithms",
    "limit": 10,
    "threshold": 0.7
  }'

# Response:
[
  {
    "document_id": "uuid-here",
    "filename": "ml-paper.pdf",
    "chunk_text": "Machine learning algorithms are...",
    "similarity_score": 0.85,
    "metadata": {"chunk_index": 2}
  }
]
```

**Processing Status:**
```bash
curl -X GET "http://localhost:8001/docs/{document_id}/status"

# Response:
{
  "document_id": "uuid-here",
  "status": "processed",
  "progress": 1.0,
  "chunks_processed": 15,
  "total_chunks": 15
}
```

### ETL Processor API

**List Jobs:**
```bash
curl -X GET "http://localhost:8002/etl/jobs"

# Response:
[
  {
    "job_id": "sync_workflow_executions",
    "job_type": "Sync Workflow Executions",
    "status": "scheduled",
    "next_run": "2024-01-01T15:30:00Z"
  }
]
```

**Trigger Manual Job:**
```bash
curl -X POST "http://localhost:8002/etl/jobs/run" \
  -H "Content-Type: application/json" \
  -d '{
    "job_type": "workflow_executions",
    "schedule": "0 */5 * * *"
  }'
```

**Analytics Summary:**
```bash
# Workflow analytics
curl -X GET "http://localhost:8002/etl/analytics/workflow-summary"

# Document analytics  
curl -X GET "http://localhost:8002/etl/analytics/document-summary"
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Certificate Generation Issues

**Problem**: Let's Encrypt certificate generation fails
**Solution**:
```bash
# Check domain DNS resolution
nslookup your-domain.com

# Verify port 80 accessibility
curl -I http://your-domain.com/.well-known/acme-challenge/test

# Check Traefik logs
./start.sh logs --follow traefik

# Restart with clean certificates
docker volume rm traefik_data
./start.sh restart
```

#### Service Startup Issues

**Problem**: Services fail to start or become healthy
**Solution**:
```bash
# Check service status
./start.sh status

# View service logs
./start.sh logs --follow <service-name>

# Check resource usage
./scripts/maintenance/monitor.sh performance

# Verify environment configuration
./scripts/setup.sh --dry-run
```

#### Database Connection Issues  

**Problem**: Services cannot connect to PostgreSQL
**Solution**:
```bash
# Check PostgreSQL status
docker exec -it n8n-postgres pg_isready -U n8n_user

# Verify credentials
echo $POSTGRES_PASSWORD

# Test connection manually
docker exec -it n8n-postgres psql -U n8n_user -d n8n -c "SELECT 1;"

# Check network connectivity
docker network inspect n8n-network
```

#### Performance Issues

**Problem**: Slow document processing or high resource usage
**Solution**:
```bash
# Monitor system resources
./scripts/maintenance/monitor.sh performance

# Check Docker stats
docker stats

# Optimize worker counts
echo "DOC_PROCESSOR_WORKERS=4" >> .env
./start.sh restart

# Clean up Docker system
./start.sh cleanup
```

### Debugging Techniques

**Service Debugging:**
```bash
# Enable debug logging
echo "DEBUG=true" >> .env
echo "LOG_LEVEL=DEBUG" >> .env
./start.sh restart

# Access service shell
docker exec -it n8n-document-processor bash

# Check service dependencies
./scripts/maintenance/monitor.sh network
```

**Network Debugging:**
```bash
# Test service connectivity
docker exec -it n8n-app ping postgres
docker exec -it n8n-app ping qdrant

# Check port accessibility
nc -zv localhost 5678  # N8N
nc -zv localhost 6333  # Qdrant
nc -zv localhost 5432  # PostgreSQL
```

### Performance Tuning

**Database Optimization:**
```sql
-- PostgreSQL performance tuning
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET effective_cache_size = '4GB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
SELECT pg_reload_conf();
```

**Application Optimization:**
```bash
# Increase worker counts for CPU-bound services
echo "DOC_PROCESSOR_WORKERS=4" >> .env
echo "WEB_INTERFACE_WORKERS=2" >> .env

# Adjust model settings
echo "DOC_PROCESSOR_MODEL=sentence-transformers/all-mpnet-base-v2" >> .env
echo "CHUNK_SIZE=1000" >> .env

# Restart services
./start.sh restart
```

This comprehensive technical design document provides the foundation for understanding, deploying, and maintaining the N8N AI Starter Kit. The architecture is designed for scalability, security, and ease of use while providing powerful AI capabilities for workflow automation.