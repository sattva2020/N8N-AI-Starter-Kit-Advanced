#!/usr/bin/env python3
"""
N8N AI Starter Kit - Document Processor Service
===============================================

FastAPI-based document processing service with SentenceTransformers integration.
Handles document ingestion, text extraction, chunking, embedding generation,
and vector storage in both Qdrant and PostgreSQL.
"""

import os
import logging
import asyncio
import io
import uuid
from contextlib import asynccontextmanager
from typing import List, Dict, Any, Optional, Union
from datetime import datetime
import traceback

import asyncpg
import structlog
from fastapi import FastAPI, HTTPException, Depends, File, UploadFile, BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import uvicorn

# Document processing imports
import PyPDF2
from docx import Document as DocxDocument
import aiofiles
from sentence_transformers import SentenceTransformer
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams, PointStruct, Filter, FieldCondition, MatchValue
import numpy as np

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Metrics
DOCUMENTS_PROCESSED = Counter('documents_processed_total', 'Total documents processed', ['status'])
EMBEDDINGS_GENERATED = Counter('embeddings_generated_total', 'Total embeddings generated')
PROCESSING_TIME = Histogram('document_processing_duration_seconds', 'Document processing duration')
ACTIVE_PROCESSES = Gauge('active_document_processes', 'Number of active document processing tasks')

# Configuration
class Settings(BaseModel):
    # Database settings
    postgres_host: str = Field(default="postgres", env="POSTGRES_HOST")
    postgres_port: int = Field(default=5432, env="POSTGRES_PORT")
    postgres_db: str = Field(default="n8n", env="POSTGRES_DB")
    postgres_user: str = Field(default="n8n_user", env="POSTGRES_USER")
    postgres_password: str = Field(env="POSTGRES_PASSWORD")
    
    # Qdrant settings
    qdrant_host: str = Field(default="qdrant", env="QDRANT_HOST")
    qdrant_port: int = Field(default=6333, env="QDRANT_PORT")
    qdrant_api_key: Optional[str] = Field(default=None, env="QDRANT_API_KEY")
    
    # Model settings
    sentence_transformers_model: str = Field(
        default="sentence-transformers/all-MiniLM-L6-v2",
        env="SENTENCE_TRANSFORMERS_MODEL"
    )
    embedding_dimension: int = Field(default=384)
    
    # Processing settings
    chunk_size: int = Field(default=500, env="CHUNK_SIZE")
    chunk_overlap: int = Field(default=50, env="CHUNK_OVERLAP")
    max_file_size: int = Field(default=10485760, env="MAX_FILE_SIZE")  # 10MB
    
    # Service settings
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    debug: bool = Field(default=False, env="DEBUG")

settings = Settings()

# Database and Vector DB managers
class DatabaseManager:
    def __init__(self):
        self.pool: Optional[asyncpg.Pool] = None
    
    async def connect(self):
        """Initialize database connection pool"""
        try:
            self.pool = await asyncpg.create_pool(
                host=settings.postgres_host,
                port=settings.postgres_port,
                database=settings.postgres_db,
                user=settings.postgres_user,
                password=settings.postgres_password,
                min_size=2,
                max_size=10,
            )
            logger.info("Database connection pool created")
        except Exception as e:
            logger.error("Failed to create database pool", error=str(e))
            raise
    
    async def disconnect(self):
        """Close database connection pool"""
        if self.pool:
            await self.pool.close()
            logger.info("Database connection pool closed")

class VectorDBManager:
    def __init__(self):
        self.client: Optional[QdrantClient] = None
        self.collection_name = "documents"
    
    async def connect(self):
        """Initialize Qdrant client and create collection if needed"""
        try:
            self.client = QdrantClient(
                host=settings.qdrant_host,
                port=settings.qdrant_port,
                api_key=settings.qdrant_api_key,
            )
            
            # Create collection if it doesn't exist
            collections = self.client.get_collections()
            if self.collection_name not in [c.name for c in collections.collections]:
                self.client.create_collection(
                    collection_name=self.collection_name,
                    vectors_config=VectorParams(
                        size=settings.embedding_dimension,
                        distance=Distance.COSINE,
                    ),
                )
                logger.info("Created Qdrant collection", collection=self.collection_name)
            
            logger.info("Qdrant client initialized")
        except Exception as e:
            logger.error("Failed to initialize Qdrant client", error=str(e))
            raise
    
    async def disconnect(self):
        """Close Qdrant client"""
        if self.client:
            self.client.close()
            logger.info("Qdrant client closed")

class ModelManager:
    def __init__(self):
        self.model: Optional[SentenceTransformer] = None
    
    async def load_model(self):
        """Load SentenceTransformers model"""
        try:
            loop = asyncio.get_event_loop()
            self.model = await loop.run_in_executor(
                None, 
                SentenceTransformer,
                settings.sentence_transformers_model
            )
            logger.info("SentenceTransformers model loaded", model=settings.sentence_transformers_model)
        except Exception as e:
            logger.error("Failed to load SentenceTransformers model", error=str(e))
            raise
    
    async def encode(self, texts: List[str]) -> np.ndarray:
        """Generate embeddings for texts"""
        if not self.model:
            raise HTTPException(status_code=500, detail="Model not loaded")
        
        loop = asyncio.get_event_loop()
        embeddings = await loop.run_in_executor(
            None,
            self.model.encode,
            texts
        )
        return embeddings

# Initialize managers
db_manager = DatabaseManager()
vector_manager = VectorDBManager()
model_manager = ModelManager()

# Document processor
class DocumentProcessor:
    @staticmethod
    async def extract_text(file_content: bytes, filename: str) -> str:
        """Extract text from various document formats"""
        file_ext = filename.lower().split('.')[-1] if '.' in filename else ''
        
        try:
            if file_ext == 'pdf':
                return await DocumentProcessor._extract_pdf_text(file_content)
            elif file_ext in ['docx', 'doc']:
                return await DocumentProcessor._extract_docx_text(file_content)
            elif file_ext in ['txt', 'md']:
                return file_content.decode('utf-8')
            else:
                # Try to decode as text
                try:
                    return file_content.decode('utf-8')
                except UnicodeDecodeError:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Unsupported file format: {file_ext}"
                    )
        except Exception as e:
            logger.error("Text extraction failed", filename=filename, error=str(e))
            raise HTTPException(status_code=400, detail=f"Failed to extract text: {str(e)}")
    
    @staticmethod
    async def _extract_pdf_text(file_content: bytes) -> str:
        """Extract text from PDF"""
        loop = asyncio.get_event_loop()
        
        def _extract():
            pdf_file = io.BytesIO(file_content)
            reader = PyPDF2.PdfReader(pdf_file)
            text = ""
            for page in reader.pages:
                text += page.extract_text() + "\n"
            return text
        
        return await loop.run_in_executor(None, _extract)
    
    @staticmethod
    async def _extract_docx_text(file_content: bytes) -> str:
        """Extract text from DOCX"""
        loop = asyncio.get_event_loop()
        
        def _extract():
            docx_file = io.BytesIO(file_content)
            doc = DocxDocument(docx_file)
            text = ""
            for paragraph in doc.paragraphs:
                text += paragraph.text + "\n"
            return text
        
        return await loop.run_in_executor(None, _extract)
    
    @staticmethod
    def chunk_text(text: str, chunk_size: int = 500, overlap: int = 50) -> List[Dict[str, Any]]:
        """Split text into overlapping chunks"""
        if not text.strip():
            return []
        
        sentences = text.split('.')
        chunks = []
        current_chunk = ""
        current_size = 0
        
        for i, sentence in enumerate(sentences):
            sentence = sentence.strip()
            if not sentence:
                continue
                
            sentence_size = len(sentence)
            
            # If adding this sentence exceeds chunk size, create a new chunk
            if current_size + sentence_size > chunk_size and current_chunk:
                chunks.append({
                    'text': current_chunk.strip(),
                    'index': len(chunks),
                    'start_sentence': i - len(current_chunk.split('.')),
                    'end_sentence': i
                })
                
                # Start new chunk with overlap
                overlap_text = '. '.join(current_chunk.split('.')[-overlap:])
                current_chunk = overlap_text + '. ' + sentence if overlap_text else sentence
                current_size = len(current_chunk)
            else:
                current_chunk += '. ' + sentence if current_chunk else sentence
                current_size = len(current_chunk)
        
        # Add the last chunk if it has content
        if current_chunk.strip():
            chunks.append({
                'text': current_chunk.strip(),
                'index': len(chunks),
                'start_sentence': len(sentences) - len(current_chunk.split('.')),
                'end_sentence': len(sentences)
            })
        
        return chunks

# Response models
class DocumentUploadResponse(BaseModel):
    document_id: str
    filename: str
    status: str
    message: str

class ProcessingStatus(BaseModel):
    document_id: str
    status: str
    progress: float
    chunks_processed: int
    total_chunks: int

class SearchRequest(BaseModel):
    query: str
    limit: int = Field(default=10, ge=1, le=100)
    threshold: float = Field(default=0.7, ge=0.0, le=1.0)

class SearchResult(BaseModel):
    document_id: str
    filename: str
    chunk_text: str
    similarity_score: float
    metadata: Dict[str, Any]

# Lifespan management
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await db_manager.connect()
    await vector_manager.connect()
    await model_manager.load_model()
    logger.info("Document processor service started")
    
    yield
    
    # Shutdown
    await db_manager.disconnect()
    await vector_manager.disconnect()
    logger.info("Document processor service stopped")

# FastAPI app
app = FastAPI(
    title="N8N AI Starter Kit - Document Processor",
    description="Document processing service with SentenceTransformers and vector storage",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Check database connection
        async with db_manager.pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        
        # Check Qdrant connection
        vector_manager.client.get_collections()
        
        # Check model
        if not model_manager.model:
            raise Exception("Model not loaded")
        
        return {
            "status": "healthy",
            "version": "1.0.0",
            "timestamp": datetime.utcnow().isoformat(),
            "model": settings.sentence_transformers_model
        }
    
    except Exception as e:
        logger.error("Health check failed", error=str(e))
        raise HTTPException(status_code=503, detail=f"Service unavailable: {str(e)}")

# Metrics endpoint
@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    from fastapi.responses import Response
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

# Document upload and processing
@app.post("/docs/upload", response_model=DocumentUploadResponse)
async def upload_document(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...)
):
    """Upload and process a document"""
    # Validate file size
    if file.size and file.size > settings.max_file_size:
        raise HTTPException(
            status_code=413,
            detail=f"File too large. Maximum size: {settings.max_file_size} bytes"
        )
    
    # Generate document ID
    document_id = str(uuid.uuid4())
    
    try:
        # Read file content
        file_content = await file.read()
        
        # Store document in database
        async with db_manager.pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO documents.document_store 
                (id, filename, content_type, file_size, status, created_at)
                VALUES ($1, $2, $3, $4, $5, $6)
            """, document_id, file.filename, file.content_type, len(file_content), 'processing', datetime.utcnow())
        
        # Schedule background processing
        background_tasks.add_task(
            process_document_background,
            document_id,
            file.filename,
            file_content
        )
        
        DOCUMENTS_PROCESSED.labels(status='submitted').inc()
        
        return DocumentUploadResponse(
            document_id=document_id,
            filename=file.filename,
            status="processing",
            message="Document upload successful, processing started"
        )
    
    except Exception as e:
        logger.error("Document upload failed", filename=file.filename, error=str(e))
        DOCUMENTS_PROCESSED.labels(status='error').inc()
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

async def process_document_background(document_id: str, filename: str, file_content: bytes):
    """Background task for document processing"""
    ACTIVE_PROCESSES.inc()
    
    try:
        with PROCESSING_TIME.time():
            # Extract text
            text = await DocumentProcessor.extract_text(file_content, filename)
            
            # Chunk text
            chunks = DocumentProcessor.chunk_text(
                text, 
                settings.chunk_size, 
                settings.chunk_overlap
            )
            
            if not chunks:
                raise Exception("No text content found in document")
            
            # Generate embeddings
            chunk_texts = [chunk['text'] for chunk in chunks]
            embeddings = await model_manager.encode(chunk_texts)
            
            # Store in database and vector store
            async with db_manager.pool.acquire() as conn:
                async with conn.transaction():
                    # Update document with extracted text
                    await conn.execute("""
                        UPDATE documents.document_store 
                        SET content = $2, processed_at = $3, status = $4
                        WHERE id = $1
                    """, document_id, text, datetime.utcnow(), 'processed')
                    
                    # Store embeddings
                    for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
                        embedding_id = str(uuid.uuid4())
                        
                        # Store in PostgreSQL
                        await conn.execute("""
                            INSERT INTO documents.embeddings 
                            (id, document_id, chunk_index, chunk_text, chunk_metadata, embedding)
                            VALUES ($1, $2, $3, $4, $5, $6)
                        """, embedding_id, document_id, i, chunk['text'], chunk, embedding.tolist())
            
            # Store in Qdrant
            points = []
            for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
                points.append(PointStruct(
                    id=str(uuid.uuid4()),
                    vector=embedding.tolist(),
                    payload={
                        'document_id': document_id,
                        'filename': filename,
                        'chunk_index': i,
                        'chunk_text': chunk['text'],
                        'metadata': chunk
                    }
                ))
            
            vector_manager.client.upsert(
                collection_name=vector_manager.collection_name,
                points=points
            )
            
            EMBEDDINGS_GENERATED.inc(len(embeddings))
            DOCUMENTS_PROCESSED.labels(status='success').inc()
            
            logger.info("Document processed successfully", 
                       document_id=document_id, 
                       filename=filename, 
                       chunks=len(chunks))
    
    except Exception as e:
        logger.error("Document processing failed", 
                    document_id=document_id, 
                    filename=filename, 
                    error=str(e),
                    traceback=traceback.format_exc())
        
        # Update status in database
        try:
            async with db_manager.pool.acquire() as conn:
                await conn.execute("""
                    UPDATE documents.document_store 
                    SET status = $2, processed_at = $3
                    WHERE id = $1
                """, document_id, 'error', datetime.utcnow())
        except Exception as db_error:
            logger.error("Failed to update error status", error=str(db_error))
        
        DOCUMENTS_PROCESSED.labels(status='error').inc()
    
    finally:
        ACTIVE_PROCESSES.dec()

# Document search
@app.post("/docs/search", response_model=List[SearchResult])
async def search_documents(request: SearchRequest):
    """Search documents using vector similarity"""
    try:
        # Generate query embedding
        query_embedding = await model_manager.encode([request.query])
        
        # Search in Qdrant
        search_results = vector_manager.client.search(
            collection_name=vector_manager.collection_name,
            query_vector=query_embedding[0].tolist(),
            limit=request.limit,
            score_threshold=request.threshold
        )
        
        # Format results
        results = []
        for result in search_results:
            results.append(SearchResult(
                document_id=result.payload['document_id'],
                filename=result.payload['filename'],
                chunk_text=result.payload['chunk_text'],
                similarity_score=result.score,
                metadata=result.payload.get('metadata', {})
            ))
        
        return results
    
    except Exception as e:
        logger.error("Search failed", query=request.query, error=str(e))
        raise HTTPException(status_code=500, detail=f"Search failed: {str(e)}")

# Processing status
@app.get("/docs/{document_id}/status", response_model=ProcessingStatus)
async def get_processing_status(document_id: str):
    """Get document processing status"""
    try:
        async with db_manager.pool.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT status, created_at, processed_at
                FROM documents.document_store
                WHERE id = $1
            """, document_id)
            
            if not row:
                raise HTTPException(status_code=404, detail="Document not found")
            
            # Count processed chunks
            chunk_count = await conn.fetchval("""
                SELECT COUNT(*)
                FROM documents.embeddings
                WHERE document_id = $1
            """, document_id)
            
            # Calculate progress (mock calculation)
            progress = 1.0 if row['status'] == 'processed' else 0.0 if row['status'] == 'pending' else 0.5
            
            return ProcessingStatus(
                document_id=document_id,
                status=row['status'],
                progress=progress,
                chunks_processed=chunk_count or 0,
                total_chunks=chunk_count or 0  # In real implementation, this would be stored separately
            )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get processing status", document_id=document_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to get status: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8001,
        log_level=settings.log_level.lower(),
        reload=settings.debug
    )