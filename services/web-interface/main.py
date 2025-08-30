#!/usr/bin/env python3
"""
N8N AI Starter Kit - Web Interface Service
===========================================

FastAPI-based web interface for managing and monitoring the N8N AI Starter Kit.
Provides a user-friendly dashboard and API endpoints for system management.
"""

import os
import logging
from contextlib import asynccontextmanager
from typing import Dict, Any, List, Optional

import asyncpg
import structlog
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import uvicorn

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
REQUEST_COUNT = Counter('web_interface_requests_total', 'Total requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('web_interface_request_duration_seconds', 'Request duration')

# Configuration
class Settings(BaseModel):
    postgres_host: str = Field(default="postgres", env="POSTGRES_HOST")
    postgres_port: int = Field(default=5432, env="POSTGRES_PORT")
    postgres_db: str = Field(default="n8n", env="POSTGRES_DB")
    postgres_user: str = Field(default="n8n_user", env="POSTGRES_USER")
    postgres_password: str = Field(env="POSTGRES_PASSWORD")
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    debug: bool = Field(default=False, env="DEBUG")

settings = Settings()

# Database connection
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
    
    async def get_connection(self):
        """Get database connection from pool"""
        if not self.pool:
            raise HTTPException(status_code=500, detail="Database not connected")
        return self.pool.acquire()

db_manager = DatabaseManager()

# Lifespan management
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await db_manager.connect()
    logger.info("Web interface service started")
    
    yield
    
    # Shutdown
    await db_manager.disconnect()
    logger.info("Web interface service stopped")

# FastAPI app
app = FastAPI(
    title="N8N AI Starter Kit - Web Interface",
    description="Web interface for managing and monitoring the N8N AI Starter Kit",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static files and templates
app.mount("/static", StaticFiles(directory="static", html=True), name="static")
templates = Jinja2Templates(directory="templates")

# Response models
class HealthResponse(BaseModel):
    status: str
    version: str
    timestamp: str

class SystemStatus(BaseModel):
    database: str
    services: Dict[str, str]
    metrics: Dict[str, Any]

class DocumentInfo(BaseModel):
    id: str
    filename: str
    status: str
    created_at: str
    processed_at: Optional[str] = None

# Middleware for metrics
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start_time = REQUEST_DURATION.time()
    
    response = await call_next(request)
    
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    
    start_time.observe()
    return response

# Health check endpoint
@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        timestamp=datetime.utcnow().isoformat()
    )

# System status endpoint
@app.get("/status", response_model=SystemStatus)
async def get_system_status():
    """Get detailed system status"""
    try:
        # Check database connection
        async with db_manager.get_connection() as conn:
            await conn.fetchval("SELECT 1")
            db_status = "healthy"
    except Exception as e:
        logger.error("Database health check failed", error=str(e))
        db_status = "unhealthy"
    
    # Mock service status (in production, implement actual service checks)
    services = {
        "n8n": "healthy",
        "qdrant": "healthy",
        "prometheus": "healthy",
        "grafana": "healthy"
    }
    
    metrics = {
        "uptime_seconds": 3600,  # Mock value
        "total_requests": 1000,  # Mock value
        "error_rate": 0.01       # Mock value
    }
    
    return SystemStatus(
        database=db_status,
        services=services,
        metrics=metrics
    )

# Metrics endpoint
@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

# Document management endpoints
@app.get("/api/v1/documents", response_model=List[DocumentInfo])
async def list_documents(limit: int = 50, offset: int = 0):
    """List documents in the system"""
    try:
        async with db_manager.get_connection() as conn:
            query = """
                SELECT id, filename, status, created_at, processed_at
                FROM documents.document_store
                ORDER BY created_at DESC
                LIMIT $1 OFFSET $2
            """
            rows = await conn.fetch(query, limit, offset)
            
            documents = []
            for row in rows:
                doc = DocumentInfo(
                    id=str(row['id']),
                    filename=row['filename'],
                    status=row['status'],
                    created_at=row['created_at'].isoformat(),
                    processed_at=row['processed_at'].isoformat() if row['processed_at'] else None
                )
                documents.append(doc)
            
            return documents
    
    except Exception as e:
        logger.error("Failed to fetch documents", error=str(e))
        raise HTTPException(status_code=500, detail="Failed to fetch documents")

@app.get("/api/v1/documents/{document_id}", response_model=DocumentInfo)
async def get_document(document_id: str):
    """Get specific document details"""
    try:
        async with db_manager.get_connection() as conn:
            query = """
                SELECT id, filename, status, created_at, processed_at
                FROM documents.document_store
                WHERE id = $1
            """
            row = await conn.fetchrow(query, document_id)
            
            if not row:
                raise HTTPException(status_code=404, detail="Document not found")
            
            return DocumentInfo(
                id=str(row['id']),
                filename=row['filename'],
                status=row['status'],
                created_at=row['created_at'].isoformat(),
                processed_at=row['processed_at'].isoformat() if row['processed_at'] else None
            )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to fetch document", document_id=document_id, error=str(e))
        raise HTTPException(status_code=500, detail="Failed to fetch document")

# Web interface routes
@app.get("/ui/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "title": "N8N AI Starter Kit Dashboard"
    })

@app.get("/ui/documents", response_class=HTMLResponse)
async def documents_page(request: Request):
    """Documents management page"""
    return templates.TemplateResponse("documents.html", {
        "request": request,
        "title": "Document Management"
    })

@app.get("/ui/workflows", response_class=HTMLResponse)
async def workflows_page(request: Request):
    """Workflows management page"""
    return templates.TemplateResponse("workflows.html", {
        "request": request,
        "title": "Workflow Management"
    })

# Root redirect
@app.get("/")
async def root():
    """Redirect root to dashboard"""
    return RedirectResponse(url="/ui/dashboard")

# Import at module level to avoid issues
from fastapi.responses import Response, RedirectResponse
from datetime import datetime

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        log_level=settings.log_level.lower(),
        reload=settings.debug
    )