# LightRAG Service

LightRAG is a graph-based Retrieval Augmented Generation (RAG) service that provides intelligent document processing and querying capabilities for the N8N AI Starter Kit.

## Features

- **Graph-based RAG**: Automatically extracts entities and relationships from documents
- **Multiple Query Modes**: Supports naive, local, global, and hybrid query strategies
- **RESTful API**: Easy integration with N8N workflows and external applications
- **Document Management**: Ingest documents from text or files with metadata tracking
- **PostgreSQL Integration**: Stores document metadata and query history
- **Prometheus Metrics**: Built-in monitoring and observability
- **Health Checks**: Comprehensive health monitoring for production deployments
- **Ollama Support**: Run local LLM models with Ollama integration
- **Model Switching**: Dynamic switching between OpenAI API and local models

## API Endpoints

### Health & Monitoring
- `GET /health` - Service health check
- `GET /metrics` - Prometheus metrics
- `GET /stats` - Service statistics

### Document Management
- `POST /documents/ingest` - Ingest text content
- `POST /documents/ingest-file` - Ingest file content
- `GET /documents` - List stored documents
- `DELETE /documents/{document_id}` - Delete document metadata

### Query Interface
- `POST /query` - Query the knowledge graph

## Configuration

The service is configured through environment variables:

### Required Variables
- `OPENAI_API_KEY` - OpenAI API key for LLM and embeddings
- `POSTGRES_HOST`, `POSTGRES_DB`, etc. - Database connection settings

### Optional Variables
- `LIGHTRAG_LLM_MODEL` - LLM model (default: gpt-4o-mini)
- `LIGHTRAG_EMBEDDING_MODEL` - Embedding model (default: text-embedding-3-small)
- `LIGHTRAG_PORT` - Service port (default: 8003)
- `LIGHTRAG_CHUNK_SIZE` - Document chunk size (default: 1200)
- `LIGHTRAG_OVERLAP_SIZE` - Chunk overlap (default: 100)

### Ollama Configuration
- `USE_LOCAL_MODELS` - Enable local models (default: false)
- `MODEL_PROVIDER` - Model provider: openai, ollama (default: openai)
- `OLLAMA_BASE_URL` - Ollama server URL (default: http://ollama:11434)
- `OLLAMA_DEFAULT_MODEL` - Default Ollama LLM model (default: llama2:7b)
- `OLLAMA_EMBEDDING_MODEL` - Ollama embedding model (default: nomic-embed-text)

## Usage Examples

### Ingest a Document
```bash
curl -X POST "http://localhost:8003/documents/ingest" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Your document content here...",
    "metadata": {"source": "example.txt"},
    "source": "example.txt"
  }'
```

### Query the Knowledge Graph
```bash
curl -X POST "http://localhost:8003/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the main topic of the documents?",
    "mode": "hybrid"
  }'
```

### Upload a File
```bash
curl -X POST "http://localhost:8003/documents/ingest-file" \
  -F "file=@document.txt"
```

### Ollama Model Management

```bash
# List available models
curl "http://localhost:8003/models"

# Pull a new Ollama model
curl -X POST "http://localhost:8003/models/pull?model_name=llama2:13b"

# Check service health with model info
curl "http://localhost:8003/health"
```

## Query Modes

- **naive**: Simple semantic search without graph traversal
- **local**: Local graph search focusing on nearby entities
- **global**: Global graph analysis for comprehensive understanding
- **hybrid**: Combines local and global approaches (recommended)

## Integration with N8N

The LightRAG service is designed to integrate seamlessly with N8N workflows:

1. **Document Processing Workflows**: Automatically ingest documents from various sources
2. **Question Answering**: Create chatbots and QA systems using the knowledge graph
3. **Content Analysis**: Analyze and extract insights from large document collections
4. **Knowledge Management**: Build and maintain organizational knowledge bases

## Performance Considerations

- **Cold Start**: Initial model loading takes 1-2 minutes
- **Memory Usage**: Requires adequate RAM for embedding models (~2GB minimum)
- **Disk Space**: Graph storage grows with document volume
- **API Rate Limits**: Respects OpenAI API rate limits

## Monitoring

The service exposes Prometheus metrics for monitoring:
- Document processing counters
- Query execution metrics
- Response time histograms
- Error rates and health status

## Troubleshooting

### Common Issues

1. **Service won't start**: Check OpenAI API key and database connectivity
2. **Slow responses**: Consider using lighter models or adjusting chunk sizes
3. **High memory usage**: Monitor embedding model memory requirements
4. **API errors**: Verify OpenAI API quota and rate limits

### Logs

Check service logs for detailed error information:
```bash
docker logs n8n-lightrag
```

## Development

For local development:

1. Install dependencies: `pip install -r requirements.txt`
2. Set environment variables in `.env` file
3. Run: `python main.py`

The service will start on port 8003 with automatic reload enabled.