"""
LightRAG Service - N8N AI Starter Kit Integration

This service provides LightRAG functionality for graph-based retrieval augmented generation,
integrated with the N8N AI Starter Kit ecosystem.

Features:
- Graph-based RAG with automatic entity extraction
- RESTful API for document ingestion and querying
- Integration with PostgreSQL for metadata storage
- Prometheus metrics for monitoring
- Health checks and proper error handling
"""

import os
import json
import logging
import asyncio
from pathlib import Path
from typing import List, Dict, Any, Optional
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI, HTTPException, UploadFile, File, Depends
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings
import aiofiles
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from lightrag import LightRAG, QueryParam
from lightrag.llm import gpt_4o_mini_complete, gpt_4o_complete
from lightrag.embed import openai_embedding
import asyncpg

# Import Ollama client
from ollama_client import create_ollama_llm_func, create_ollama_embedding_func, OllamaClient

# Configure structured logging
logging.basicConfig(level=logging.INFO)
logger = structlog.get_logger()

# Prometheus metrics
documents_processed = Counter('lightrag_documents_processed_total', 'Total processed documents')
queries_executed = Counter('lightrag_queries_executed_total', 'Total executed queries')
query_duration = Histogram('lightrag_query_duration_seconds', 'Query execution duration')
document_processing_duration = Histogram('lightrag_document_processing_duration_seconds', 'Document processing duration')


class Settings(BaseSettings):
    """Application settings from environment variables."""
    
    # Service configuration
    port: int = Field(default=8003, alias="LIGHTRAG_PORT")
    workers: int = Field(default=1, alias="LIGHTRAG_WORKERS")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    
    # LightRAG configuration
    lightrag_working_dir: str = Field(default="/app/data/lightrag", alias="LIGHTRAG_WORKING_DIR")
    openai_api_key: str = Field(alias="OPENAI_API_KEY")
    openai_api_base: Optional[str] = Field(default=None, alias="OPENAI_API_BASE")
    
    # Model configuration
    llm_model: str = Field(default="gpt-4o-mini", alias="LIGHTRAG_LLM_MODEL")
    embedding_model: str = Field(default="text-embedding-3-small", alias="LIGHTRAG_EMBEDDING_MODEL")
    
    # Model provider selection
    use_local_models: bool = Field(default=False, alias="USE_LOCAL_MODELS")
    model_provider: str = Field(default="openai", alias="MODEL_PROVIDER")  # openai, ollama
    
    # Ollama configuration
    ollama_base_url: str = Field(default="http://ollama:11434", alias="OLLAMA_BASE_URL")
    ollama_llm_model: str = Field(default="llama2:7b", alias="OLLAMA_DEFAULT_MODEL")
    ollama_embedding_model: str = Field(default="nomic-embed-text", alias="OLLAMA_EMBEDDING_MODEL")
    ollama_temperature: float = Field(default=0.7, alias="OLLAMA_TEMPERATURE")
    ollama_num_ctx: int = Field(default=4096, alias="OLLAMA_NUM_CTX")
    ollama_num_predict: int = Field(default=512, alias="OLLAMA_NUM_PREDICT")
    
    # Database configuration
    postgres_host: str = Field(alias="POSTGRES_HOST")
    postgres_port: int = Field(default=5432, alias="POSTGRES_PORT")
    postgres_db: str = Field(alias="POSTGRES_DB")
    postgres_user: str = Field(alias="POSTGRES_USER")
    postgres_password: str = Field(alias="POSTGRES_PASSWORD")
    
    # Performance settings
    max_tokens: int = Field(default=32768, alias="LIGHTRAG_MAX_TOKENS")
    chunk_size: int = Field(default=1200, alias="LIGHTRAG_CHUNK_SIZE")
    overlap_size: int = Field(default=100, alias="LIGHTRAG_OVERLAP_SIZE")
    
    class Config:
        env_file = ".env"


# Global variables
settings = Settings()
lightrag_instance: Optional[LightRAG] = None
db_pool: Optional[asyncpg.Pool] = None


# Pydantic models
class DocumentIngestRequest(BaseModel):
    content: str = Field(..., description="Document content to process")
    metadata: Optional[Dict[str, Any]] = Field(default=None, description="Additional metadata")
    source: Optional[str] = Field(default=None, description="Document source/URL")


class QueryRequest(BaseModel):
    query: str = Field(..., description="Query text")
    mode: str = Field(default="hybrid", description="Query mode: naive, local, global, hybrid")
    only_need_context: bool = Field(default=False, description="Return only context without LLM response")


class DocumentIngestResponse(BaseModel):
    success: bool
    message: str
    document_id: Optional[str] = None
    processing_time: float


class QueryResponse(BaseModel):
    success: bool
    query: str
    mode: str
    response: Optional[str] = None
    context: Optional[List[str]] = None
    processing_time: float


async def init_database():
    """Initialize database connection pool."""
    global db_pool
    try:
        db_pool = await asyncpg.create_pool(
            host=settings.postgres_host,
            port=settings.postgres_port,
            database=settings.postgres_db,
            user=settings.postgres_user,
            password=settings.postgres_password,
            min_size=1,
            max_size=10
        )
        
        # Create lightrag_documents table if not exists
        async with db_pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS lightrag_documents (
                    id SERIAL PRIMARY KEY,
                    document_id VARCHAR(255) UNIQUE NOT NULL,
                    source VARCHAR(1000),
                    content_hash VARCHAR(64),
                    metadata JSONB,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS lightrag_queries (
                    id SERIAL PRIMARY KEY,
                    query_text TEXT NOT NULL,
                    query_mode VARCHAR(50),
                    response_text TEXT,
                    processing_time FLOAT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
        logger.info("Database initialized successfully")
        
    except Exception as e:
        logger.error("Failed to initialize database", error=str(e))
        raise


async def init_lightrag():
    """Initialize LightRAG instance with configurable model providers."""
    global lightrag_instance
    
    try:
        # Create working directory
        working_dir = Path(settings.lightrag_working_dir)
        working_dir.mkdir(parents=True, exist_ok=True)
        
        # Determine model provider
        use_ollama = settings.use_local_models or settings.model_provider.lower() == "ollama"
        
        if use_ollama:
            logger.info("Initializing LightRAG with Ollama models")
            
            # Test Ollama connectivity
            ollama_client = OllamaClient(base_url=settings.ollama_base_url)
            if not await ollama_client.health_check():
                logger.warning("Ollama server not available, falling back to OpenAI")
                use_ollama = False
            await ollama_client._client.aclose()
        
        if use_ollama:
            # Configure Ollama LLM function
            llm_model_func = await create_ollama_llm_func(
                base_url=settings.ollama_base_url,
                model=settings.ollama_llm_model,
                temperature=settings.ollama_temperature,
                max_tokens=settings.ollama_num_predict,
                num_ctx=settings.ollama_num_ctx
            )
            
            # Configure Ollama embedding function
            embedding_func = await create_ollama_embedding_func(
                base_url=settings.ollama_base_url,
                model=settings.ollama_embedding_model
            )
            
            logger.info(
                "Using Ollama models",
                llm_model=settings.ollama_llm_model,
                embedding_model=settings.ollama_embedding_model
            )
        else:
            # Configure OpenAI LLM function
            async def llm_model_func(prompt, system_prompt=None, history_messages=[], **kwargs) -> str:
                if settings.llm_model == "gpt-4o":
                    return await gpt_4o_complete(prompt, system_prompt, history_messages, **kwargs)
                else:
                    return await gpt_4o_mini_complete(prompt, system_prompt, history_messages, **kwargs)
            
            # Use OpenAI embedding function
            embedding_func = openai_embedding
            
            logger.info(
                "Using OpenAI models",
                llm_model=settings.llm_model,
                embedding_model=settings.embedding_model
            )
        
        # Initialize LightRAG
        lightrag_instance = LightRAG(
            working_dir=str(working_dir),
            llm_model_func=llm_model_func,
            embedding_func=embedding_func,
            embedding_batch_num=10,
            embedding_func_max_async=5,
        )
        
        logger.info("LightRAG initialized successfully", working_dir=str(working_dir))
        
    except Exception as e:
        logger.error("Failed to initialize LightRAG", error=str(e))
        raise


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle."""
    # Startup
    logger.info("Starting LightRAG service")
    await init_database()
    await init_lightrag()
    logger.info("LightRAG service started successfully")
    
    yield
    
    # Shutdown
    logger.info("Shutting down LightRAG service")
    if db_pool:
        await db_pool.close()
    logger.info("LightRAG service shutdown complete")


# Create FastAPI app
app = FastAPI(
    title="LightRAG Service",
    description="Graph-based Retrieval Augmented Generation service for N8N AI Starter Kit",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    # Determine current model provider
    use_ollama = settings.use_local_models or settings.model_provider.lower() == "ollama"
    current_provider = "ollama" if use_ollama else "openai"
    
    # Test Ollama connectivity if using Ollama
    ollama_available = False
    if use_ollama:
        try:
            ollama_client = OllamaClient(base_url=settings.ollama_base_url)
            ollama_available = await ollama_client.health_check()
            await ollama_client._client.aclose()
        except:
            pass
    
    return {
        "status": "healthy",
        "service": "lightrag",
        "version": "1.0.0",
        "lightrag_initialized": lightrag_instance is not None,
        "database_connected": db_pool is not None,
        "model_provider": current_provider,
        "ollama_available": ollama_available if use_ollama else None,
        "models": {
            "llm": settings.ollama_llm_model if use_ollama else settings.llm_model,
            "embedding": settings.ollama_embedding_model if use_ollama else settings.embedding_model
        }
    }


@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/models")
async def list_available_models():
    """List available models based on current provider."""
    use_ollama = settings.use_local_models or settings.model_provider.lower() == "ollama"
    
    if use_ollama:
        try:
            ollama_client = OllamaClient(base_url=settings.ollama_base_url)
            models = await ollama_client.list_models()
            await ollama_client._client.aclose()
            
            return {
                "provider": "ollama",
                "available_models": [model.name for model in models],
                "current_llm": settings.ollama_llm_model,
                "current_embedding": settings.ollama_embedding_model
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to get Ollama models: {str(e)}")
    else:
        return {
            "provider": "openai",
            "available_models": ["gpt-4o", "gpt-4o-mini", "text-embedding-3-small", "text-embedding-3-large"],
            "current_llm": settings.llm_model,
            "current_embedding": settings.embedding_model
        }


@app.post("/models/pull")
async def pull_model(model_name: str):
    """Pull/download a model (Ollama only)."""
    use_ollama = settings.use_local_models or settings.model_provider.lower() == "ollama"
    
    if not use_ollama:
        raise HTTPException(status_code=400, detail="Model pulling only available with Ollama provider")
    
    try:
        ollama_client = OllamaClient(base_url=settings.ollama_base_url)
        success = await ollama_client.pull_model(model_name)
        await ollama_client._client.aclose()
        
        if success:
            return {"status": "success", "message": f"Model {model_name} pulled successfully"}
        else:
            raise HTTPException(status_code=500, detail=f"Failed to pull model {model_name}")
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to pull model: {str(e)}")


@app.post("/documents/ingest", response_model=DocumentIngestResponse)
async def ingest_document(request: DocumentIngestRequest):
    """Ingest a document into LightRAG knowledge graph."""
    if not lightrag_instance:
        raise HTTPException(status_code=500, detail="LightRAG not initialized")
    
    start_time = asyncio.get_event_loop().time()
    
    try:
        # Generate document ID
        import hashlib
        content_hash = hashlib.sha256(request.content.encode()).hexdigest()
        document_id = f"doc_{content_hash[:16]}"
        
        # Store document metadata in database
        if db_pool:
            async with db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO lightrag_documents (document_id, source, content_hash, metadata)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (document_id) DO UPDATE SET
                        updated_at = CURRENT_TIMESTAMP,
                        metadata = $4
                """, document_id, request.source, content_hash, 
                json.dumps(request.metadata) if request.metadata else None)
        
        # Process document with LightRAG
        await lightrag_instance.ainsert(request.content)
        
        processing_time = asyncio.get_event_loop().time() - start_time
        
        # Update metrics
        documents_processed.inc()
        document_processing_duration.observe(processing_time)
        
        logger.info("Document ingested successfully", 
                   document_id=document_id, 
                   processing_time=processing_time)
        
        return DocumentIngestResponse(
            success=True,
            message="Document ingested successfully",
            document_id=document_id,
            processing_time=processing_time
        )
        
    except Exception as e:
        logger.error("Failed to ingest document", error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to ingest document: {str(e)}")


@app.post("/documents/ingest-file")
async def ingest_file(file: UploadFile = File(...)):
    """Ingest a file into LightRAG knowledge graph."""
    if not lightrag_instance:
        raise HTTPException(status_code=500, detail="LightRAG not initialized")
    
    try:
        # Read file content
        content = await file.read()
        
        # Basic text extraction (can be enhanced with more sophisticated parsers)
        if file.content_type == "text/plain":
            text_content = content.decode('utf-8')
        elif file.content_type == "application/json":
            json_data = json.loads(content.decode('utf-8'))
            text_content = json.dumps(json_data, indent=2)
        else:
            # For other file types, try to decode as text
            try:
                text_content = content.decode('utf-8')
            except UnicodeDecodeError:
                raise HTTPException(status_code=400, detail="Unsupported file format")
        
        # Create ingest request
        request = DocumentIngestRequest(
            content=text_content,
            metadata={"filename": file.filename, "content_type": file.content_type},
            source=file.filename
        )
        
        return await ingest_document(request)
        
    except Exception as e:
        logger.error("Failed to ingest file", error=str(e), filename=file.filename)
        raise HTTPException(status_code=500, detail=f"Failed to ingest file: {str(e)}")


@app.post("/query", response_model=QueryResponse)
async def query_knowledge_graph(request: QueryRequest):
    """Query the LightRAG knowledge graph."""
    if not lightrag_instance:
        raise HTTPException(status_code=500, detail="LightRAG not initialized")
    
    start_time = asyncio.get_event_loop().time()
    
    try:
        # Validate query mode
        valid_modes = ["naive", "local", "global", "hybrid"]
        if request.mode not in valid_modes:
            raise HTTPException(status_code=400, detail=f"Invalid mode. Must be one of: {valid_modes}")
        
        # Execute query
        with query_duration.time():
            response = await lightrag_instance.aquery(
                request.query,
                param=QueryParam(mode=request.mode, only_need_context=request.only_need_context)
            )
        
        processing_time = asyncio.get_event_loop().time() - start_time
        
        # Store query in database
        if db_pool:
            async with db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO lightrag_queries (query_text, query_mode, response_text, processing_time)
                    VALUES ($1, $2, $3, $4)
                """, request.query, request.mode, response, processing_time)
        
        # Update metrics
        queries_executed.inc()
        
        logger.info("Query executed successfully", 
                   query=request.query, 
                   mode=request.mode,
                   processing_time=processing_time)
        
        # Parse response if it contains context information
        context = None
        if request.only_need_context and isinstance(response, list):
            context = response
            response = None
        
        return QueryResponse(
            success=True,
            query=request.query,
            mode=request.mode,
            response=response,
            context=context,
            processing_time=processing_time
        )
        
    except Exception as e:
        logger.error("Failed to execute query", error=str(e), query=request.query)
        raise HTTPException(status_code=500, detail=f"Failed to execute query: {str(e)}")


@app.get("/stats")
async def get_stats():
    """Get service statistics."""
    stats = {
        "service": "lightrag",
        "status": "running",
        "lightrag_working_dir": settings.lightrag_working_dir,
        "models": {
            "llm": settings.llm_model,
            "embedding": settings.embedding_model
        }
    }
    
    # Add database stats if available
    if db_pool:
        try:
            async with db_pool.acquire() as conn:
                doc_count = await conn.fetchval("SELECT COUNT(*) FROM lightrag_documents")
                query_count = await conn.fetchval("SELECT COUNT(*) FROM lightrag_queries")
                
                stats["database"] = {
                    "documents_stored": doc_count,
                    "queries_executed": query_count
                }
        except Exception as e:
            logger.warning("Failed to get database stats", error=str(e))
    
    return stats


@app.delete("/documents/{document_id}")
async def delete_document(document_id: str):
    """Delete a document from the system (metadata only, graph cleanup requires full rebuild)."""
    if not db_pool:
        raise HTTPException(status_code=500, detail="Database not available")
    
    try:
        async with db_pool.acquire() as conn:
            result = await conn.execute(
                "DELETE FROM lightrag_documents WHERE document_id = $1",
                document_id
            )
            
            if result == "DELETE 0":
                raise HTTPException(status_code=404, detail="Document not found")
        
        logger.info("Document deleted", document_id=document_id)
        
        return {
            "success": True,
            "message": f"Document {document_id} deleted from metadata storage",
            "note": "Graph data requires full rebuild to remove completely"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to delete document", error=str(e), document_id=document_id)
        raise HTTPException(status_code=500, detail=f"Failed to delete document: {str(e)}")


@app.get("/documents")
async def list_documents(offset: int = 0, limit: int = 100):
    """List stored documents."""
    if not db_pool:
        raise HTTPException(status_code=500, detail="Database not available")
    
    try:
        async with db_pool.acquire() as conn:
            documents = await conn.fetch("""
                SELECT document_id, source, metadata, created_at, updated_at
                FROM lightrag_documents
                ORDER BY created_at DESC
                OFFSET $1 LIMIT $2
            """, offset, limit)
            
            total_count = await conn.fetchval("SELECT COUNT(*) FROM lightrag_documents")
        
        return {
            "documents": [
                {
                    "document_id": doc["document_id"],
                    "source": doc["source"],
                    "metadata": json.loads(doc["metadata"]) if doc["metadata"] else None,
                    "created_at": doc["created_at"].isoformat(),
                    "updated_at": doc["updated_at"].isoformat()
                }
                for doc in documents
            ],
            "total_count": total_count,
            "offset": offset,
            "limit": limit
        }
        
    except Exception as e:
        logger.error("Failed to list documents", error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to list documents: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=settings.port,
        workers=settings.workers,
        log_level=settings.log_level.lower()
    )