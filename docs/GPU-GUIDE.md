# GPU Acceleration Guide

This guide covers setting up and using GPU acceleration with the N8N AI Starter Kit.

## Overview

The GPU profile provides significant performance improvements for AI workloads by leveraging NVIDIA and AMD graphics cards. This enables:

- **10-100x faster** AI model inference
- **Local model deployment** without API dependencies
- **Real-time processing** of large document collections
- **Cost reduction** by minimizing external API usage

## Supported Hardware

### NVIDIA GPUs
- **RTX Series**: RTX 20xx, 30xx, 40xx (recommended)
- **Tesla/Quadro**: Tesla V100, A100, A40, RTX A6000
- **GTX Series**: GTX 1060 6GB+ (minimum)
- **Requirements**: CUDA 11.8+, 8GB+ VRAM recommended

### AMD GPUs
- **RX Series**: RX 6600 XT, 6700 XT, 6800 XT, 6900 XT
- **MI Series**: MI100, MI200 series
- **Requirements**: ROCm 5.4+, 8GB+ VRAM
- **Status**: Experimental support

## Prerequisites

### NVIDIA Setup

1. **Install NVIDIA Drivers**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install nvidia-driver-535
   
   # Verify installation
   nvidia-smi
   ```

2. **Install NVIDIA Docker Runtime**
   ```bash
   # Add NVIDIA GPG key and repository
   distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   
   curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   
   # Install nvidia-docker2
   sudo apt update
   sudo apt install nvidia-docker2
   
   # Restart Docker
   sudo systemctl restart docker
   
   # Test GPU access
   docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu22.04 nvidia-smi
   ```

### AMD Setup (Experimental)

1. **Install ROCm**
   ```bash
   # Ubuntu 22.04
   wget https://repo.radeon.com/amdgpu-install/5.4.3/ubuntu/jammy/amdgpu-install_5.4.50403-1_all.deb
   sudo apt install ./amdgpu-install_5.4.50403-1_all.deb
   sudo amdgpu-install --usecase=dkms,rocm
   
   # Add user to render group
   sudo usermod -a -G render $USER
   ```

2. **Verify ROCm Installation**
   ```bash
   rocm-smi
   /opt/rocm/bin/rocminfo
   ```

## Quick Start

### 1. Automatic Detection

Run the GPU detection script to automatically configure your system:

```bash
./scripts/detect-gpu.sh
```

This script will:
- Detect available GPUs (NVIDIA/AMD)
- Test Docker GPU access
- Configure environment variables
- Recommend optimal settings
- Run performance benchmarks

### 2. Manual Configuration

If you prefer manual setup, edit your `.env` file:

```bash
# GPU Configuration
GPU_TYPE=nvidia                    # or 'amd' or 'auto'
CUDA_VISIBLE_DEVICES=0            # GPU device IDs
GPU_MEMORY_FRACTION=0.8           # Memory allocation (0.1-1.0)

# GPU Service Ports
DOC_PROCESSOR_GPU_PORT=8011
LIGHTRAG_GPU_PORT=8013
GPU_MONITOR_PORT=8014

# Local Models
LIGHTRAG_GPU_LLM_MODEL=microsoft/DialoGPT-medium
LIGHTRAG_GPU_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
```

### 3. Start with GPU Profile

```bash
# Start all services with GPU support
./start.sh --profile default,developer,gpu

# Or just GPU services
./start.sh --profile default,gpu
```

## Services Overview

### Document Processor GPU
**Endpoint**: `http://localhost:8011`

GPU-accelerated document processing with sentence transformers:

```bash
# Process document with GPU acceleration
curl -X POST "http://localhost:8011/docs/upload" \
  -F "file=@document.pdf"

# Check GPU utilization
curl "http://localhost:8011/gpu/status"
```

**Performance**: 10-50x faster than CPU for embedding generation.

### LightRAG GPU
**Endpoint**: `http://localhost:8013`

Knowledge graph RAG with local AI models:

```bash
# Ingest document using local models
curl -X POST "http://localhost:8013/documents/ingest" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Your text here",
    "use_local_models": true
  }'

# Query with local LLM
curl -X POST "http://localhost:8013/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What are the main topics?",
    "mode": "hybrid",
    "use_local_models": true
  }'
```

**Models Available**:
- **Embeddings**: sentence-transformers models
- **LLM**: Hugging Face transformers, vLLM models
- **Fallback**: OpenAI API when local models unavailable

### GPU Monitor
**Endpoint**: `http://localhost:8014`

Real-time GPU monitoring and management:

```bash
# Get GPU information
curl "http://localhost:8014/gpu/info"

# List GPU processes
curl "http://localhost:8014/gpu/processes" 

# Prometheus metrics
curl "http://localhost:8014/metrics"
```

**Features**:
- Real-time utilization monitoring
- Memory usage tracking
- Temperature and power monitoring
- Process management
- Prometheus metrics export

## Performance Optimization

### Memory Management

Configure GPU memory allocation based on your hardware:

```bash
# For 24GB+ VRAM (RTX 3090, 4090, A100)
GPU_MEMORY_FRACTION=0.9

# For 12-16GB VRAM (RTX 3080, 4070 Ti)  
GPU_MEMORY_FRACTION=0.8

# For 8-10GB VRAM (RTX 3070, 4060 Ti)
GPU_MEMORY_FRACTION=0.7

# For 6-8GB VRAM (RTX 3060, 4060)
GPU_MEMORY_FRACTION=0.6
```

### Model Selection

Choose models based on your GPU memory:

```bash
# High-end GPUs (16GB+)
LIGHTRAG_GPU_LLM_MODEL=microsoft/DialoGPT-large
LIGHTRAG_GPU_EMBEDDING_MODEL=sentence-transformers/all-mpnet-base-v2

# Mid-range GPUs (8-16GB)
LIGHTRAG_GPU_LLM_MODEL=microsoft/DialoGPT-medium
LIGHTRAG_GPU_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2

# Entry-level GPUs (6-8GB)
LIGHTRAG_GPU_LLM_MODEL=distilgpt2
LIGHTRAG_GPU_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L12-v2
```

### Batch Processing

Optimize batch sizes for your GPU:

```python
# In service configuration
BATCH_SIZE_EMBEDDING=32    # For 16GB+ VRAM
BATCH_SIZE_EMBEDDING=16    # For 8-16GB VRAM  
BATCH_SIZE_EMBEDDING=8     # For 6-8GB VRAM

MAX_SEQUENCE_LENGTH=512    # Longer sequences = more VRAM
```

## Local Model Management

### Hugging Face Models

The GPU services automatically download models from Hugging Face:

```bash
# Pre-download models to speed up startup
docker exec n8n-lightrag-gpu python -c "
from transformers import AutoModel, AutoTokenizer
AutoModel.from_pretrained('microsoft/DialoGPT-medium')
AutoTokenizer.from_pretrained('microsoft/DialoGPT-medium')
"
```

### Custom Models

Mount local model directories:

```yaml
# In docker-compose.yml
volumes:
  - /path/to/your/models:/app/models
  - gpu_models_cache:/app/cache
```

### Model Caching

Models are cached in the `gpu_models_cache` volume to avoid re-downloading:

```bash
# Check cache usage
docker volume inspect n8n-ai-starter-kit_gpu_models_cache

# Clear model cache if needed
docker volume rm n8n-ai-starter-kit_gpu_models_cache
```

## Monitoring

### Grafana Integration

GPU metrics are automatically integrated into Grafana dashboards:

1. Access Grafana: `https://grafana.localhost`
2. Navigate to "GPU Dashboard"
3. Monitor in real-time:
   - GPU utilization %
   - Memory usage
   - Temperature
   - Power consumption
   - Service throughput

### Prometheus Metrics

Available GPU metrics:

```
gpu_utilization_percent{gpu_id="0", gpu_name="RTX 4090"}
gpu_memory_used_bytes{gpu_id="0", gpu_name="RTX 4090"} 
gpu_temperature_celsius{gpu_id="0", gpu_name="RTX 4090"}
gpu_power_draw_watts{gpu_id="0", gpu_name="RTX 4090"}
```

### Log Monitoring

Monitor GPU service logs:

```bash
# Follow all GPU service logs
docker logs -f n8n-lightrag-gpu
docker logs -f n8n-document-processor-gpu
docker logs -f n8n-gpu-monitor

# Check for GPU errors
docker logs n8n-gpu-monitor 2>&1 | grep ERROR
```

## Troubleshooting

### Common Issues

**1. NVIDIA Docker Not Working**
```bash
# Error: "nvidia-docker runtime not found"
sudo systemctl restart docker
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu22.04 nvidia-smi
```

**2. Out of Memory Errors**
```bash
# Reduce GPU_MEMORY_FRACTION in .env
GPU_MEMORY_FRACTION=0.6

# Or reduce batch sizes
DOC_PROCESSOR_BATCH_SIZE=8
```

**3. Model Download Failures**
```bash
# Check internet connection and Hugging Face access
curl -I https://huggingface.co

# Use local models instead
LIGHTRAG_GPU_LLM_MODEL=/app/models/local-model
```

**4. AMD GPU Issues**
```bash
# Check ROCm installation
rocm-smi
/opt/rocm/bin/rocminfo

# Verify Docker access
docker run -it --device=/dev/kfd --device=/dev/dri rocm/pytorch:latest rocm-smi
```

### Performance Issues

**1. Slow Model Loading**
- Pre-download models during build
- Use smaller models for faster startup
- Increase `start_period` in health checks

**2. Low GPU Utilization**
- Increase batch sizes if VRAM allows
- Use multiple worker processes
- Check for CPU bottlenecks

**3. Memory Leaks**
- Monitor memory usage over time
- Restart services periodically
- Use garbage collection in model code

### Debugging Commands

```bash
# Check GPU availability in containers
docker exec n8n-lightrag-gpu nvidia-smi

# Monitor GPU usage in real-time
watch -n 1 'docker exec n8n-gpu-monitor curl -s localhost:8014/gpu/info'

# Check Docker GPU runtime
docker info | grep -i nvidia

# Test GPU access
docker run --rm --gpus all pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime python -c "import torch; print(torch.cuda.is_available())"
```

## Best Practices

### Production Deployment

1. **Resource Planning**
   - Allocate 70-80% of VRAM to avoid OOM
   - Reserve system memory for OS operations
   - Plan for peak concurrent usage

2. **Model Management**
   - Use model versioning and tags
   - Implement model warming strategies
   - Monitor model performance metrics

3. **Scaling**
   - Use multiple GPU nodes for high load
   - Implement load balancing across GPUs
   - Consider model parallelism for large models

### Development

1. **Testing**
   - Test with different batch sizes
   - Benchmark model performance
   - Profile memory usage patterns

2. **Debugging**
   - Use CUDA profilers (nvprof, nsight)
   - Monitor PyTorch memory allocation
   - Log GPU utilization metrics

3. **Optimization**
   - Use mixed precision training (FP16)
   - Implement dynamic batching
   - Cache frequently used embeddings

## Cost Analysis

### Hardware Investment vs API Costs

**Example Calculation** (RTX 4090, $1600):

```
OpenAI API Costs:
- Embedding: $0.0001/1K tokens
- GPT-4: $0.03/1K tokens

Local GPU Costs:
- Hardware: $1600 one-time
- Electricity: ~$50/month (400W @ $0.15/kWh, 24/7)

Break-even: ~10 months of heavy API usage
```

### ROI Factors

✅ **Favor GPU when**:
- High document processing volumes
- Frequent embedding generation
- Privacy/security requirements
- Predictable workloads

✅ **Favor API when**:
- Low/sporadic usage
- Latest model access needed
- Minimal infrastructure management
- Variable workloads

## Conclusion

GPU acceleration transforms the N8N AI Starter Kit into a high-performance, self-contained AI platform. With proper setup and optimization, you can achieve:

- **10-100x performance** improvements
- **Reduced operational costs** over time
- **Enhanced data privacy** with local models
- **Improved reliability** without external dependencies

The investment in GPU infrastructure pays off for organizations with substantial AI workloads and privacy requirements.