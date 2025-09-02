# N8N AI Starter Kit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Required-blue)](https://www.docker.com/)
[![N8N](https://img.shields.io/badge/N8N-Latest-green)](https://n8n.io/)

A production-ready, containerized N8N deployment with integrated AI services, vector search capabilities, monitoring, and auxiliary microservices. Deploy a complete workflow automation platform with one command.

## 🚀 Quick Start

### Prerequisites

- **Docker & Docker Compose** (v2.x recommended)
- **Git** (for cloning the repository)
- **Bash** (Linux/macOS) or **Git Bash** (Windows)

### One-Command Deployment

```bash
# Clone the repository
git clone https://github.com/your-org/n8n-ai-starter-kit.git
cd n8n-ai-starter-kit

# Setup environment and start services
./start.sh
```

That's it! The setup script will:
1. Generate secure passwords and API keys
2. Create environment configuration
3. Start all services with Docker Compose
4. Display service URLs and credentials

After deployment, the script will show:
- All accessible services with their URLs
- Instructions for automatic credential creation
- Information about waiting for services to initialize

## 📋 What's Included

### Core Services

| Service | Purpose | URL | Port |
|---------|---------|-----|------|
| **N8N** | Workflow Automation Engine | https://n8n.localhost | 5678 |
| **Traefik** | Reverse Proxy + TLS | https://traefik.localhost | 80, 443 |
| **PostgreSQL** | Primary Database (+ pgvector) | - | 5432 |
| **Grafana** | Monitoring Dashboard | https://grafana.localhost | 3000 |
| **Qdrant** | Vector Search Database | - | 6333 |

### AI Services

| Service | Purpose | URL | Port |
|---------|---------|-----|------|
| **Web Interface** | Management Dashboard | https://api.localhost/ui | 8000 |
| **Document Processor** | AI Document Processing | https://api.localhost/docs | 8001 |
| **ETL Processor** | Data Pipeline & Analytics | https://api.localhost/etl | 8002 |
| **LightRAG** | Graph-based RAG System | https://api.localhost/lightrag | 8003 |

### Hybrid Database Architecture

| Service | Purpose | Type | Usage |
|---------|---------|------|-------|
| **PostgreSQL** | Core N8N Data | Local | Workflows, credentials, execution history |
| **Supabase** | AI/Analytics Data | Cloud | Document processing results, embeddings, AI analytics |

### Management Tools

| Tool | Purpose | Location |
|------|---------|----------|
| **Credential Manager** | Enhanced N8N credential management with pagination | `scripts/create_n8n_credential.sh` |
| **Execution Monitor** | Real-time workflow execution monitoring | `scripts/n8n-execution-monitor.sh` |
| **Workflow Manager** | Complete workflow lifecycle management | `scripts/n8n-workflow-manager.sh` |
| **Security Monitor** | Integrated security auditing and monitoring | `scripts/maintenance/monitor.sh` |

### Optional Services

| Service | Purpose | Profile | Port |
|---------|---------|---------|------|
| **ClickHouse** | Analytics Database | analytics | 8123 |
| **Prometheus** | Metrics Collection | monitoring | 9090 |

## 🏗️ Architecture Overview

```
graph TB
    subgraph "External Access"
        User[Users]
        Domain[Domain/DNS]
    end
    
    subgraph "Reverse Proxy Layer"
        Traefik[Traefik + Let's Encrypt]
    end
    
    subgraph "Core Services"
        N8N[n8n Workflows]
        WebUI[Web Interface<br/>FastAPI]
    end
    
    subgraph "AI Services"
        DocProc[Document Processor<br/>FastAPI + SentenceTransformers]
        ETLProc[ETL Processor<br/>FastAPI + Scheduler]
        LightRAG[LightRAG<br/>Graph-based RAG + OpenAI]
    end
    
    subgraph "Data Layer"
        Postgres[(PostgreSQL + pgvector<br/>Local)]
        Qdrant[(Qdrant Vector DB)]
        ClickHouse[(ClickHouse<br/>Optional)]
        Supabase[(Supabase<br/>Cloud - Optional)]
    end
    
    subgraph "Monitoring"
        Grafana[Grafana Dashboards]
        Prometheus[Prometheus Metrics]
    end
    
    User --> Domain
    Domain --> Traefik
    Traefik -->|HTTPS| N8N
    Traefik -->|HTTPS| WebUI
    Traefik -->|HTTPS| Grafana
    
    N8N --> Postgres
    N8N --> Qdrant
    DocProc --> Qdrant
    DocProc --> Postgres
    DocProc -.->|AI Data| Supabase
    ETLProc --> Postgres
    ETLProc --> ClickHouse
    ETLProc -.->|Analytics| Supabase
    LightRAG --> Postgres
    LightRAG -.->|Knowledge Graphs| Supabase
    
    Prometheus --> N8N
    Prometheus --> DocProc
    Prometheus --> ETLProc
    Prometheus --> LightRAG
    Grafana --> Prometheus
```

## 🔧 Configuration

### Environment Profiles

Choose which services to run with Docker Compose profiles:

```bash
# Core services only (minimal deployment)
./start.sh --profile default

# Development setup (recommended)
./start.sh --profile default,developer,monitoring

# Full analytics stack
./start.sh --profile default,developer,monitoring,analytics
```

### Profile Breakdown

- **`default`**: Traefik, N8N, PostgreSQL
- **`developer`**: + Qdrant, Web Interface, Document Processor, LightRAG
- **`monitoring`**: + Grafana, Prometheus
- **`analytics`**: + ETL Processor, ClickHouse
- **`gpu`**: + GPU-accelerated AI services with local models
- **`supabase`**: + Supabase integration for AI/analytics data (hybrid approach)

### Environment Configuration

All configuration is managed through environment variables. The setup script generates a secure `.env` file automatically.

Key variables you might want to customize:

```
# Domain configuration (change for production)
DOMAIN=localhost
ACME_EMAIL=admin@yourdomain.com

# Service profiles
COMPOSE_PROFILES=default,developer,monitoring

# AI/ML settings
DOC_PROCESSOR_MODEL=sentence-transformers/all-MiniLM-L6-v2
CHUNK_SIZE=500
CHUNK_OVERLAP=50

# LightRAG settings
OPENAI_API_KEY=your_openai_api_key_here
LIGHTRAG_LLM_MODEL=gpt-4o-mini
LIGHTRAG_EMBEDDING_MODEL=text-embedding-3-small

# GPU settings (for gpu profile)
GPU_TYPE=auto
CUDA_VISIBLE_DEVICES=0

# Supabase settings (for hybrid database approach)
# SUPABASE_URL=https://your-project.supabase.co
# SUPABASE_KEY=your-anon-or-service-key
# COMPOSE_PROFILES=default,developer,monitoring,supabase
```

### Interactive Domain Configuration

When running the setup script, you'll be prompted to enter your domain name:

```bash
./scripts/setup.sh
```

The script will ask:
```
Enter your domain name (or press Enter for localhost):
```

For production deployments, enter your real domain name (e.g., `example.com`). For local development, you can press Enter to use `localhost`.

If you're running `./start.sh` and have an existing configuration with `localhost`, the script will detect this and offer to update it:

```
⚠ Currently using localhost as domain
ℹ For production deployments, you should use a real domain name

Would you like to update the domain now? (y/N):
```

### Security Configuration

The setup script also prompts for additional security configuration:

1. **Let's Encrypt Email**: For SSL certificate notifications
2. **Traefik Dashboard Password**: For accessing the Traefik dashboard

```
Enter your email for Let's Encrypt notifications (or press Enter for admin@yourdomain.com):
Enter password for Traefik dashboard (or press Enter to generate):
```

- Press Enter to automatically generate a secure password for the Traefik dashboard
- Or enter your own password for the dashboard

The Traefik dashboard can be accessed at `https://traefik.yourdomain.com` (production) or `http://traefik.localhost` (development) using the username `admin` and the password you configured.

**API Keys**: For security reasons, API key fields are intentionally left empty in the generated `.env` file:
- OpenAI API Key (for LightRAG service)
- Qdrant API Key (for vector database authentication) 
- N8N API Key (alternative to Personal Access Token)

You must manually add your real API keys to the `.env` file after setup. Services that require these keys will not function until valid keys are provided.

## 📊 Management and Monitoring

### Enhanced N8N API Tools

The kit includes enhanced management scripts with full N8N API integration:

#### Credential Management
```
# Enhanced credential management with pagination and API integration
./scripts/create_n8n_credential.sh --list --limit 50
./scripts/create_n8n_credential.sh --list --all  # Get all pages
./scripts/create_n8n_credential.sh --get-schema githubApi
./scripts/create_n8n_credential.sh --list-types
./scripts/create_n8n_credential.sh --bulk credentials.json  # Mass creation

# Create PostgreSQL credential
./scripts/create_n8n_credential.sh --type postgres --name "main-db" \
  --data '{"host":"postgres","port":5432,"database":"n8n","username":"user","password":"pass"}'

# Automatic credential setup after deployment (wait 1-2 minutes after start.sh)
./start.sh setup-credentials  # Uses enhanced Python credential manager
./start.sh init-credentials   # Uses legacy bash credential setup
```

#### Workflow Management
``bash
# Complete workflow lifecycle management
./scripts/n8n-workflow-manager.sh --list --active
./scripts/n8n-workflow-manager.sh --activate workflow_123
./scripts/n8n-workflow-manager.sh --export workflow_123 backup.json
./scripts/n8n-workflow-manager.sh --duplicate workflow_123
./scripts/n8n-workflow-manager.sh --health  # Check workflow health
```

#### Execution Monitoring
```
# Real-time execution monitoring with advanced filtering
./scripts/n8n-execution-monitor.sh --watch
./scripts/n8n-execution-monitor.sh --stats
./scripts/n8n-execution-monitor.sh --workflow workflow_123
./scripts/n8n-execution-monitor.sh --status error  # Filter by status
./scripts/n8n-execution-monitor.sh --export executions.json
./scripts/n8n-execution-monitor.sh --analytics  # Performance analytics
```

#### System Monitoring
```
# Comprehensive system monitoring with security audit
./scripts/maintenance/monitor.sh                    # All checks
./scripts/maintenance/monitor.sh health             # Service health
./scripts/maintenance/monitor.sh security           # Security audit
./scripts/maintenance/monitor.sh performance        # Performance metrics
./scripts/maintenance/monitor.sh --format json      # JSON output
```

#### Testing Infrastructure
```
# Comprehensive testing with Playwright E2E
./scripts/run-comprehensive-tests.sh               # All tests
./scripts/run-comprehensive-tests.sh e2e           # End-to-end tests
./scripts/run-comprehensive-tests.sh api           # API tests
./scripts/run-comprehensive-tests.sh security      # Security tests
```

#### Workflow Management
```
# Complete workflow lifecycle management
./scripts/n8n-workflow-manager.sh --list --active
./scripts/n8n-workflow-manager.sh --health
./scripts/n8n-workflow-manager.sh --performance
```

#### Security Auditing
```
# Integrated security monitoring
./scripts/maintenance/monitor.sh security
./scripts/maintenance/monitor.sh all  # includes security audit
```

📚 **Detailed API Documentation**: See [`docs/N8N-API-ENHANCEMENTS.md`](docs/N8N-API-ENHANCEMENTS.md) for comprehensive API usage guides.

### System Monitoring

Built-in monitoring stack with Grafana dashboards:

```bash
# System health checks
./scripts/maintenance/monitor.sh health

# Performance monitoring
./scripts/maintenance/monitor.sh performance

# Log analysis
./scripts/maintenance/monitor.sh logs --days 7

# Complete monitoring suite
./scripts/maintenance/monitor.sh all
```

## 🚀 GPU Acceleration

The kit supports GPU acceleration for AI workloads with NVIDIA and AMD hardware:

### Automatic GPU Detection

```
# Run GPU detection script
./scripts/detect-gpu.sh

# Force NVIDIA detection
./scripts/detect-gpu.sh --nvidia

# Force AMD detection  
./scripts/detect-gpu.sh --amd

# Run GPU benchmark
./scripts/detect-gpu.sh --benchmark
```

### GPU Requirements

**NVIDIA GPUs:**
- CUDA 11.8+ compatible GPU (RTX 20xx/30xx/40xx, Tesla, A100, etc.)
- NVIDIA Docker runtime installed
- 8GB+ VRAM recommended for local models

**AMD GPUs:**
- ROCm 5.4+ compatible GPU (RX 6000+, MI series)
- ROCm Docker support
- Experimental support

### GPU Services

When using the `gpu` profile, these services become available:

- **document-processor-gpu** (port 8011): GPU-accelerated document processing
- **lightrag-gpu** (port 8013): Local AI models with GPU acceleration  
- **gpu-monitor** (port 8014): Real-time GPU monitoring and management
- **ollama** (port 11434): Local LLM server for running models offline

### Starting with GPU Support

```
# Auto-detect and start with GPU
./start.sh --profile default,developer,gpu

# Check GPU status
curl http://localhost:8014/gpu/info

# Monitor GPU usage
docker logs n8n-gpu-monitor
```

### Local AI Models

The GPU profile enables running local AI models:

```
# Use local models instead of OpenAI API
curl -X POST "http://localhost:8013/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "Explain machine learning", "use_local": true}'
```

### Ollama Integration

Ollama provides easy local LLM deployment:

```
# Check available models
curl http://localhost:8013/models

# Pull a new model (e.g., Llama 2)
curl -X POST "http://localhost:8013/models/pull?model_name=llama2:13b"

# Switch to local models
# Set MODEL_PROVIDER=ollama in .env file
```

**Popular Ollama Models:**
- `llama3.3:8b` - Latest general purpose, 4GB VRAM
- `llama3.2:1b` - Ultra-fast responses, <1GB VRAM
- `qwen2.5-coder:7b` - Advanced code generation, 4GB VRAM
- `codellama:7b` - Meta's code specialist, 4GB VRAM
- `mistral-nemo:12b` - Long context (128k), 8GB VRAM
- `neumind-math:7b` - Mathematical reasoning, 4GB VRAM
- `nomic-embed-text` - Embeddings, <1GB VRAM

### Performance Benefits

- **10-100x faster** embedding generation
- **Local model inference** without API costs
- **Batch processing** of large document sets
- **Real-time responses** for complex queries

## 🛠️ Usage Guide

### Starting and Stopping

```bash
# Start all services
./start.sh

# Start in background
./start.sh --detach

# Start specific profiles
./start.sh --profile default,developer,monitoring

# Stop all services
./start.sh down

# Restart all services
./start.sh restart

# View service status
./start.sh status

# View service logs
./start.sh logs
./start.sh logs --follow n8n
```

### Post-Deployment Setup

After starting services with `./start.sh`, the script will display:

1. **Accessible Services**: List of all services with their URLs
2. **Credential Setup Instructions**: How to automatically create credentials
3. **Wait Time**: Recommendation to wait 1-2 minutes for services to initialize

To automatically create credentials for all services:
```
# Enhanced Python credential manager (recommended)
./start.sh setup-credentials

# Legacy bash credential setup
./start.sh init-credentials
```

Both methods will:
- Create credentials for PostgreSQL, Qdrant, OpenAI, Ollama
- Use configuration from your .env file
- Skip creation if credentials already exist

### Manual Credential Creation

If you need to create credentials manually:
```bash
# Enhanced Python credential manager
./scripts/credential-manager.py --help

# Legacy bash credential setup
./scripts/auto-setup-credentials.sh --help

# Original credential creation script
./scripts/create_n8n_credential.sh --help
```

### Environment Management

```bash
# Regenerate environment file
./scripts/setup.sh

# Backup current environment
cp .env .env.backup

# Reset to default configuration
rm .env && ./scripts/setup.sh
```

### Monitoring and Maintenance

```bash
# System health check
./scripts/maintenance/monitor.sh health

# Security audit
./scripts/maintenance/monitor.sh security

# Performance metrics
./scripts/maintenance/monitor.sh performance

# Cleanup unused Docker resources
./start.sh cleanup
```

### Testing

```bash
# Run all tests
./scripts/run-comprehensive-tests.sh

# Run specific test types
./scripts/run-comprehensive-tests.sh e2e
./scripts/run-comprehensive-tests.sh api
./scripts/run-comprehensive-tests.sh security
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [N8N](https://n8n.io/) - Workflow automation engine
- [Qdrant](https://qdrant.tech/) - Vector search database
- [PostgreSQL](https://www.postgresql.org/) - Relational database with vector extensions
- [Grafana](https://grafana.com/) - Analytics and monitoring platform
- [Traefik](https://traefik.io/) - Modern reverse proxy
- [Sentence Transformers](https://www.sbert.net/) - State-of-the-art sentence embeddings
- [LightRAG](https://github.com/HKUDS/LightRAG) - Graph-based retrieval augmented generation

## 📞 Support

For issues, questions, or contributions, please:
1. Check the [Documentation](docs/)
2. Review existing [Issues](https://github.com/your-org/n8n-ai-starter-kit/issues)
3. Create a new issue if needed