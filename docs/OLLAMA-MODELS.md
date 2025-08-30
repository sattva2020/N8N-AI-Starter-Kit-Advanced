# Ollama Models Quick Reference

## Model Selection Cheat Sheet

| Use Case | Recommended Models | VRAM | Notes |
|----------|-------------------|------|-------|
| **General Chat** | `llama3.3:8b`, `llama3.2:3b` | 4-6GB | Balanced performance |
| **Coding** | `qwen2.5-coder:7b`, `codellama:7b` | 4-6GB | Specialized for code |
| **Math & Logic** | `neumind-math:7b`, `deepseek-r1:7b` | 4-6GB | Mathematical reasoning |
| **Long Context** | `mistral-nemo:12b` | 8GB | 128k context window |
| **Fast Response** | `llama3.2:1b`, `smollm2:1.7b` | <1GB | Ultra-lightweight |
| **High Quality** | `llama3.3:70b`, `deepseek-v3:67b` | 40GB+ | Best capabilities |
| **Embeddings** | `nomic-embed-text` | <1GB | Semantic search |

## Hardware Requirements

### Minimum System (2-4GB VRAM)
```bash
# Best options for entry-level hardware
ollama pull llama3.2:1b        # Ultra-fast, minimal resources
ollama pull smollm2:1.7b       # Lightweight general use
ollama pull phi3:3.8b          # Microsoft's efficient model
```

### Standard System (4-8GB VRAM)
```bash
# Recommended for most users
ollama pull llama3.3:8b        # Latest general purpose
ollama pull qwen2.5-coder:7b   # Advanced coding
ollama pull neumind-math:7b    # Mathematical tasks
ollama pull nomic-embed-text   # Embeddings
```

### Performance System (8-16GB VRAM)
```bash
# High-quality models
ollama pull mistral-nemo:12b   # Long context processing
ollama pull qwen2.5-coder:32b  # Enterprise coding
ollama pull codellama:13b      # Advanced code generation
```

### Enthusiast System (16GB+ VRAM)
```bash
# Maximum capability models
ollama pull llama3.3:70b       # Best overall model
ollama pull deepseek-v3:67b    # Advanced reasoning
ollama pull dolphin-mixtral:8x7b # Complex tasks
```

## Quick Setup Commands

### For General Use
```bash
# Set in .env file
MODEL_PROVIDER=ollama
OLLAMA_DEFAULT_MODEL=llama3.3:8b
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
```

### For Coding Projects
```bash
# Set in .env file
MODEL_PROVIDER=ollama
OLLAMA_DEFAULT_MODEL=qwen2.5-coder:7b
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
```

### For Math/Science
```bash
# Set in .env file
MODEL_PROVIDER=ollama
OLLAMA_DEFAULT_MODEL=neumind-math:7b
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
```

### For Resource-Constrained Systems
```bash
# Set in .env file
MODEL_PROVIDER=ollama
OLLAMA_DEFAULT_MODEL=llama3.2:1b
OLLAMA_EMBEDDING_MODEL=nomic-embed-text
```

## Model Pulling Commands

```bash
# Start services first
./start.sh --profile default,developer,gpu

# Pull models via LightRAG API
curl -X POST "http://localhost:8013/models/pull?model_name=llama3.3:8b"
curl -X POST "http://localhost:8013/models/pull?model_name=qwen2.5-coder:7b"
curl -X POST "http://localhost:8013/models/pull?model_name=nomic-embed-text"

# Or directly via Ollama
docker exec n8n-ollama ollama pull llama3.3:8b
docker exec n8n-ollama ollama pull qwen2.5-coder:7b
```

## Performance Comparison

| Model | Size | Speed | Quality | Use Case |
|-------|------|-------|---------|----------|
| `llama3.2:1b` | 0.7GB | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Quick responses |
| `llama3.2:3b` | 2GB | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Balanced |
| `llama3.3:8b` | 4.7GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | General purpose |
| `qwen2.5-coder:7b` | 4.2GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Coding |
| `mistral-nemo:12b` | 6.8GB | ⭐⭐ | ⭐⭐⭐⭐⭐ | Long context |
| `llama3.3:70b` | 39GB | ⭐ | ⭐⭐⭐⭐⭐ | Maximum quality |

## Testing Your Setup

```bash
# Test current configuration
./scripts/test-ollama.sh

# Check available models
curl http://localhost:8013/models

# Test specific model
curl -X POST http://localhost:8013/query \
  -H "Content-Type: application/json" \
  -d '{"query": "Hello, how are you?", "mode": "local"}'
```

For detailed setup instructions, see [OLLAMA-GUIDE.md](./OLLAMA-GUIDE.md)