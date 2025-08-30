# Ollama Integration Guide

This guide covers integrating and using Ollama for local LLM inference in the N8N AI Starter Kit.

## Overview

Ollama provides an easy way to run large language models locally, offering:

- **Privacy**: All data stays on your infrastructure
- **Cost Efficiency**: No API costs after initial setup
- **Speed**: Local inference without network latency
- **Offline Operation**: Works without internet connectivity
- **Model Flexibility**: Easy model switching and management

## Prerequisites

### Hardware Requirements

**Minimum:**
- 8GB RAM
- 4GB VRAM (for 7B models)
- 50GB free disk space

**Recommended:**
- 16GB+ RAM
- 8GB+ VRAM (for 13B models)
- 100GB+ free disk space
- NVIDIA GPU with CUDA support

### Software Requirements

- Docker and Docker Compose
- NVIDIA Docker runtime (for GPU acceleration)
- N8N AI Starter Kit with GPU profile enabled

## Quick Start

### 1. Enable GPU Profile

Ensure the `gpu` profile is included in your configuration:

```bash
# In .env file
COMPOSE_PROFILES=default,developer,gpu
```

### 2. Configure Ollama Settings

Edit your `.env` file to use Ollama:

```bash
# Model Provider Selection
USE_LOCAL_MODELS=true
MODEL_PROVIDER=ollama

# Ollama Configuration
OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_DEFAULT_MODEL=llama2:7b
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
OLLAMA_TEMPERATURE=0.7
```

### 3. Start Services

```bash
./start.sh --profile default,developer,gpu
```

### 4. Verify Ollama is Running

```bash
# Check Ollama health
curl http://localhost:11434/api/tags

# Check LightRAG integration
curl http://localhost:8013/health
```

## Model Management

### Listing Available Models

```bash
# Via Ollama API
curl http://localhost:11434/api/tags

# Via LightRAG integration
curl http://localhost:8013/models
```

### Pulling New Models

```bash
# Pull a model via Ollama API
curl -X POST http://localhost:11434/api/pull \
  -d '{"name": "llama2:13b"}'

# Pull via LightRAG integration
curl -X POST "http://localhost:8013/models/pull?model_name=llama2:13b"
```

### Popular Models

#### Text Generation Models

#### Text Generation Models

**For General Use (Recommended):**
```bash
llama2:7b      # Balanced, well-tested, 4GB VRAM
llama3.3:8b    # Latest version, improved performance
llama3.2:3b    # Lighter version, 2GB VRAM
```

**For Programming & Code Generation:**
```bash
codellama:7b     # Meta's code specialist, 4GB VRAM
codellama:13b    # Better code quality, 8GB VRAM
dolphin-mixtral:8x7b  # Advanced code understanding
qwen2.5-coder:7b     # Alibaba's code model, multilingual
qwen2.5-coder:32b    # Enterprise-grade coding
```

**For High-Performance & Long Context:**
```bash
llama3.3:70b    # Most capable, requires 40GB+ VRAM
mistral-nemo:12b    # 128k context window, 8GB VRAM
olmo2:13b       # Open research model
deepseek-v3:67b # Advanced reasoning capabilities
```

**For Mathematical Reasoning:**
```bash
neumind-math:7b  # Specialized math model
deepseek-r1:7b   # RL-trained reasoning model
mistral:7b-instruct  # Good at step-by-step reasoning
```

**For Resource-Constrained Hardware:**
```bash
smollm2:1.7b    # Ultra-lightweight, <1GB VRAM
llama3.2:1b     # Fastest inference, minimal resources
gemma2:2b       # Google's efficient model
phi3:3.8b       # Microsoft's optimized model
```

**Legacy Models (Still Supported):**
```bash
llama2:7b      # 4GB VRAM, good for general use
llama2:13b     # 8GB VRAM, better quality
llama2:70b     # 40GB+ VRAM, best quality
mistral:7b     # 4GB VRAM, fast inference
vicuna:7b      # Conversational AI
orca-mini:3b   # Lightweight, 2GB VRAM
```

#### Embedding Models

```bash
nomic-embed-text    # General embeddings
all-minilm:l6-v2   # Sentence embeddings
bge-large:en       # High-quality embeddings
```

### Model Selection Guidelines

### Model Selection Guidelines

**For 2-4GB VRAM (Entry Level):**
- `llama3.2:1b` or `smollm2:1.7b` for fastest response
- `llama3.2:3b` for balanced performance
- `gemma2:2b` for efficient general use
- `nomic-embed-text` for embeddings

**For 4-6GB VRAM (Standard):**
- `llama3.3:8b` or `llama2:7b` for general use
- `codellama:7b` or `qwen2.5-coder:7b` for coding
- `neumind-math:7b` for mathematical reasoning
- `mistral:7b` for fast inference

**For 8-12GB VRAM (Performance):**
- `llama2:13b` or `mistral-nemo:12b` for high quality
- `codellama:13b` for advanced coding
- `qwen2.5-coder:32b` for enterprise coding
- Multiple smaller models simultaneously

**For 16GB+ VRAM (Enthusiast):**
- `llama3.3:70b` for maximum capability
- `deepseek-v3:67b` for advanced reasoning
- `dolphin-mixtral:8x7b` for complex tasks
- Multiple specialized models loaded

**For 32GB+ VRAM (Professional):**
- `llama3.3:70b` with full precision
- Multiple 13B+ models simultaneously
- Fine-tuned custom models
- Production workloads with high concurrency

**Use Case Specific Recommendations:**

📝 **Content Writing & General Chat:**
- Primary: `llama3.3:8b`, `llama3.2:3b`
- Alternative: `mistral:7b-instruct`

💻 **Programming & Development:**
- Primary: `qwen2.5-coder:7b`, `codellama:7b`
- Advanced: `qwen2.5-coder:32b`, `dolphin-mixtral:8x7b`

🧮 **Mathematics & Logic:**
- Primary: `neumind-math:7b`, `deepseek-r1:7b`
- Advanced: `deepseek-v3:67b`

📊 **Data Analysis & Long Documents:**
- Primary: `mistral-nemo:12b` (128k context)
- Advanced: `llama3.3:70b`

⚡ **Quick Responses & Chatbots:**
- Primary: `llama3.2:1b`, `smollm2:1.7b`
- Balanced: `phi3:3.8b`, `gemma2:2b`

## Configuration Options

### Environment Variables

```bash
# Core Ollama Settings
OLLAMA_HOST=ollama                    # Server hostname
OLLAMA_PORT=11434                     # Server port
OLLAMA_BASE_URL=http://ollama:11434   # Full API URL

# Model Configuration
OLLAMA_DEFAULT_MODEL=llama2:7b        # Default LLM model
OLLAMA_EMBEDDING_MODEL=nomic-embed-text  # Embedding model
OLLAMA_PULL_TIMEOUT=300               # Download timeout (seconds)

# Performance Tuning
OLLAMA_NUM_PARALLEL=4                 # Parallel requests
OLLAMA_NUM_CTX=4096                   # Context window size
OLLAMA_NUM_PREDICT=512                # Max prediction tokens
OLLAMA_TEMPERATURE=0.7                # Response creativity
OLLAMA_TOP_K=40                       # Top-K sampling
OLLAMA_TOP_P=0.9                      # Top-P sampling
```

### Model-Specific Parameters

```bash
# For faster inference (less quality)
OLLAMA_TEMPERATURE=0.3
OLLAMA_TOP_P=0.8
OLLAMA_NUM_PREDICT=256

# For creative tasks (more variety)
OLLAMA_TEMPERATURE=1.0
OLLAMA_TOP_K=100
OLLAMA_TOP_P=0.95

# For precise tasks (deterministic)
OLLAMA_TEMPERATURE=0.1
OLLAMA_TOP_K=1
```

## Usage Examples

### Basic Text Generation

```bash
# Simple completion
curl -X POST http://localhost:8013/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Explain quantum computing in simple terms",
    "mode": "hybrid"
  }'
```

### Document Processing

```bash
# Ingest document with local models
curl -X POST http://localhost:8013/documents/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Your document content here...",
    "metadata": {"source": "local_processing"}
  }'
```

### Code Generation

```bash
# Switch to code model for programming tasks
# Set OLLAMA_DEFAULT_MODEL=codellama:7b in .env

curl -X POST http://localhost:8013/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Write a Python function to calculate fibonacci numbers",
    "mode": "local"
  }'
```

### Embeddings Generation

```bash
# Generate embeddings for similarity search
curl -X POST http://localhost:8013/documents/ingest \
  -F "file=@document.pdf"
```

## Model Switching

### Runtime Switching

```python
# Via API (requires service restart)
import requests

# Check current models
response = requests.get("http://localhost:8013/models")
print(response.json())

# Pull new model
requests.post("http://localhost:8013/models/pull?model_name=mistral:7b")
```

### Configuration File Updates

```bash
# Update .env file
sed -i 's/OLLAMA_DEFAULT_MODEL=.*/OLLAMA_DEFAULT_MODEL=mistral:7b/' .env

# Restart services
./start.sh restart
```

### Multi-Model Setup

```yaml
# Custom docker-compose override
services:
  ollama-chat:
    extends: ollama
    environment:
      - OLLAMA_MODEL=llama2:13b
    
  ollama-code:
    extends: ollama
    environment:
      - OLLAMA_MODEL=codellama:7b
    ports:
      - "11435:11434"
```

## Performance Optimization

### Memory Management

```bash
# Monitor GPU memory usage
nvidia-smi -l 1

# Check Ollama memory usage
curl http://localhost:11434/api/ps
```

### Model Optimization

**For Speed:**
- Use smaller models (7B vs 13B)
- Reduce context window (`OLLAMA_NUM_CTX=2048`)
- Lower prediction tokens (`OLLAMA_NUM_PREDICT=256`)

**For Quality:**
- Use larger models (13B+)
- Increase context window (`OLLAMA_NUM_CTX=8192`)
- Higher prediction tokens (`OLLAMA_NUM_PREDICT=1024`)

**For Memory Efficiency:**
- Unload unused models: `curl -X POST http://localhost:11434/api/generate -d '{"model": "model_name", "keep_alive": 0}'`
- Use quantized models (Q4, Q8 variants)
- Enable model offloading

### Concurrent Processing

```bash
# Increase parallel processing
OLLAMA_NUM_PARALLEL=8           # More concurrent requests
LIGHTRAG_GPU_WORKERS=2          # Multiple workers

# Load balancing across multiple Ollama instances
# Use Docker Compose scaling
docker compose up -d --scale ollama=3
```

## Troubleshooting

### Common Issues

**1. Model Download Failures**
```bash
# Check disk space
df -h

# Check network connectivity
curl -I https://ollama.ai

# Manual model pull
docker exec -it n8n-ollama ollama pull llama2:7b
```

**2. Out of Memory Errors**
```bash
# Check GPU memory
nvidia-smi

# Reduce model size or context
OLLAMA_DEFAULT_MODEL=llama2:7b  # Instead of 13b
OLLAMA_NUM_CTX=2048             # Reduce context
```

**3. Slow Inference**
```bash
# Check GPU utilization
nvidia-smi -l 1

# Optimize model parameters
OLLAMA_NUM_PREDICT=256          # Reduce output length
OLLAMA_TEMPERATURE=0.3          # Faster sampling
```

**4. Service Connection Issues**
```bash
# Check Ollama container status
docker logs n8n-ollama

# Test direct connection
curl http://localhost:11434/api/version

# Restart Ollama service
docker restart n8n-ollama
```

### Performance Issues

**Low GPU Utilization:**
- Increase batch size in model parameters
- Use multiple workers
- Check for CPU bottlenecks

**High Memory Usage:**
- Use smaller models
- Reduce context window
- Enable model offloading

**Slow Model Loading:**
- Pre-pull models during setup
- Use SSD storage for model cache
- Increase model loading timeout

### Debugging Commands

```bash
# Check Ollama system info
curl http://localhost:11434/api/version

# List loaded models
curl http://localhost:11434/api/ps

# Monitor resource usage
docker stats n8n-ollama

# Check LightRAG integration
curl http://localhost:8013/health | jq '.models'

# Test model inference directly
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "llama2:7b", "prompt": "Hello, world!"}'
```

## Integration with N8N Workflows

### Workflow Examples

**1. Local Document Processing**
```json
{
  "nodes": [
    {
      "name": "HTTP Request - Ingest",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lightrag:8013/documents/ingest",
        "method": "POST",
        "body": {
          "content": "{{ $json.document_text }}",
          "metadata": {"workflow": "n8n_processing"}
        }
      }
    }
  ]
}
```

**2. AI-Powered Content Generation**
```json
{
  "nodes": [
    {
      "name": "Local LLM Query",
      "type": "n8n-nodes-base.httpRequest", 
      "parameters": {
        "url": "http://lightrag:8013/query",
        "method": "POST",
        "body": {
          "query": "{{ $json.user_prompt }}",
          "mode": "hybrid"
        }
      }
    }
  ]
}
```

### Workflow Templates

The kit includes pre-built N8N workflows for:
- Document ingestion and processing
- Automated content generation
- Question-answering systems
- Code generation and review
- Data analysis and summarization

## Security Considerations

### Network Security
- Ollama runs in isolated Docker network
- API access through Traefik reverse proxy
- No external network access required for inference

### Data Privacy
- All model inference happens locally
- No data sent to external APIs
- Full control over model weights and parameters

### Model Security
- Verify model checksums after download
- Use official Ollama model registry
- Monitor for unusual model behavior

## Production Deployment

### Scaling Strategies

**Horizontal Scaling:**
```yaml
services:
  ollama:
    deploy:
      replicas: 3
    ports:
      - "11434-11436:11434"
```

**Load Balancing:**
```yaml
services:
  ollama-lb:
    image: nginx:alpine
    volumes:
      - ./nginx-ollama.conf:/etc/nginx/nginx.conf
    ports:
      - "11434:80"
```

### Monitoring

**Prometheus Metrics:**
```yaml
services:
  ollama-exporter:
    image: ollama/ollama-exporter
    environment:
      - OLLAMA_URL=http://ollama:11434
```

**Grafana Dashboards:**
- Model inference rates
- Memory utilization
- Response latencies
- Error rates

### Backup and Recovery

```bash
# Backup model data
docker run --rm -v ollama_data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/ollama_models.tar.gz /data

# Restore model data
docker run --rm -v ollama_data:/data -v $(pwd):/backup \
  ubuntu tar xzf /backup/ollama_models.tar.gz -C /
```

## Best Practices

### Model Selection
1. **Start Small**: Begin with 7B models and scale up based on needs
2. **Task-Specific**: Use specialized models for specific tasks (code, chat, etc.)
3. **Quality vs Speed**: Balance model size with performance requirements

### Resource Management
1. **Memory Planning**: Allocate 1.5x model size in VRAM
2. **Concurrent Limits**: Don't exceed GPU memory capacity
3. **Model Rotation**: Unload unused models to free memory

### Development Workflow
1. **Local Testing**: Test models locally before deployment
2. **Version Control**: Track model versions and configurations
3. **Performance Benchmarks**: Establish baseline performance metrics

### Production Operations
1. **Health Monitoring**: Implement comprehensive monitoring
2. **Backup Strategy**: Regular model and configuration backups
3. **Update Process**: Staged model updates with rollback capability

## Conclusion

Ollama integration transforms the N8N AI Starter Kit into a fully self-contained AI platform. With proper setup and optimization, you can achieve:

- **Complete Privacy**: All AI processing happens locally
- **Cost Efficiency**: No ongoing API costs
- **High Performance**: GPU-accelerated local inference
- **Flexibility**: Easy model switching and management
- **Reliability**: No dependency on external services

The combination of N8N's workflow automation with Ollama's local LLM capabilities provides a powerful foundation for privacy-focused AI applications.