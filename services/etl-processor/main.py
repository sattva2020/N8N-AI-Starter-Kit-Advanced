#!/usr/bin/env python3
"""
N8N AI Starter Kit - ETL Processor Service
==========================================

FastAPI-based ETL processing service with scheduling capabilities.
Handles data extraction, transformation, and loading operations for
analytics and monitoring data.
"""

import os
import logging
import asyncio
import json
from contextlib import asynccontextmanager
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta
import traceback

import asyncpg
import structlog
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import uvicorn

# Scheduling imports
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

# Data processing imports
import pandas as pd
import numpy as np
import httpx
import clickhouse_connect

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
ETL_JOBS_EXECUTED = Counter('etl_jobs_executed_total', 'Total ETL jobs executed', ['job_type', 'status'])
ETL_PROCESSING_TIME = Histogram('etl_processing_duration_seconds', 'ETL processing duration', ['job_type'])
ACTIVE_ETL_JOBS = Gauge('active_etl_jobs', 'Number of active ETL jobs')
SCHEDULED_JOBS = Gauge('scheduled_jobs_total', 'Total number of scheduled jobs')

# Configuration
class Settings(BaseModel):
    # PostgreSQL settings
    postgres_host: str = Field(default="postgres", env="POSTGRES_HOST")
    postgres_port: int = Field(default=5432, env="POSTGRES_PORT")
    postgres_db: str = Field(default="n8n", env="POSTGRES_DB")
    postgres_user: str = Field(default="n8n_user", env="POSTGRES_USER")
    postgres_password: str = Field(env="POSTGRES_PASSWORD")
    
    # ClickHouse settings
    clickhouse_host: str = Field(default="clickhouse", env="CLICKHOUSE_HOST")
    clickhouse_port: int = Field(default=8123, env="CLICKHOUSE_PORT")
    clickhouse_user: str = Field(default="default", env="CLICKHOUSE_USER")
    clickhouse_password: str = Field(default="", env="CLICKHOUSE_PASSWORD")
    clickhouse_database: str = Field(default="n8n_analytics", env="CLICKHOUSE_DATABASE")
    
    # N8N settings
    n8n_host: str = Field(default="n8n", env="N8N_HOST")
    n8n_port: int = Field(default=5678, env="N8N_PORT")
    n8n_protocol: str = Field(default="http", env="N8N_PROTOCOL")
    n8n_api_key: Optional[str] = Field(default=None, env="N8N_API_KEY")
    n8n_personal_access_token: Optional[str] = Field(default=None, env="N8N_PERSONAL_ACCESS_TOKEN")
    
    # Scheduler settings
    scheduler_timezone: str = Field(default="UTC", env="SCHEDULER_TIMEZONE")
    
    # Service settings
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    debug: bool = Field(default=False, env="DEBUG")

settings = Settings()

# Database managers
class PostgreSQLManager:
    def __init__(self):
        self.pool: Optional[asyncpg.Pool] = None
    
    async def connect(self):
        """Initialize PostgreSQL connection pool"""
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
            logger.info("PostgreSQL connection pool created")
        except Exception as e:
            logger.error("Failed to create PostgreSQL pool", error=str(e))
            raise
    
    async def disconnect(self):
        """Close PostgreSQL connection pool"""
        if self.pool:
            await self.pool.close()
            logger.info("PostgreSQL connection pool closed")

class ClickHouseManager:
    def __init__(self):
        self.client: Optional[clickhouse_connect.driver.Client] = None
    
    async def connect(self):
        """Initialize ClickHouse client"""
        try:
            loop = asyncio.get_event_loop()
            self.client = await loop.run_in_executor(
                None,
                clickhouse_connect.get_client,
                settings.clickhouse_host,
                settings.clickhouse_port,
                settings.clickhouse_user,
                settings.clickhouse_password,
                settings.clickhouse_database
            )
            logger.info("ClickHouse client initialized")
        except Exception as e:
            logger.error("Failed to initialize ClickHouse client", error=str(e))
            # Don't raise - ClickHouse is optional
            self.client = None
    
    async def disconnect(self):
        """Close ClickHouse client"""
        if self.client:
            self.client.close()
            logger.info("ClickHouse client closed")

class N8NClient:
    def __init__(self):
        self.base_url = f"{settings.n8n_protocol}://{settings.n8n_host}:{settings.n8n_port}"
        self.headers = self._get_auth_headers()
    
    def _get_auth_headers(self) -> Dict[str, str]:
        """Get authentication headers for N8N API"""
        headers = {"Content-Type": "application/json"}
        
        if settings.n8n_personal_access_token:
            headers["Authorization"] = f"Bearer {settings.n8n_personal_access_token}"
        elif settings.n8n_api_key:
            headers["X-N8N-API-KEY"] = settings.n8n_api_key
        
        return headers
    
    async def get_executions(self, limit: int = 100) -> List[Dict[str, Any]]:
        """Get workflow executions from N8N"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.base_url}/api/v1/executions",
                    headers=self.headers,
                    params={"limit": limit},
                    timeout=30.0
                )
                response.raise_for_status()
                return response.json().get("data", [])
        except Exception as e:
            logger.error("Failed to fetch N8N executions", error=str(e))
            return []
    
    async def get_workflows(self) -> List[Dict[str, Any]]:
        """Get workflows from N8N"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.base_url}/api/v1/workflows",
                    headers=self.headers,
                    timeout=30.0
                )
                response.raise_for_status()
                return response.json().get("data", [])
        except Exception as e:
            logger.error("Failed to fetch N8N workflows", error=str(e))
            return []

# Initialize managers
postgres_manager = PostgreSQLManager()
clickhouse_manager = ClickHouseManager()
n8n_client = N8NClient()
scheduler = AsyncIOScheduler(timezone=settings.scheduler_timezone)

# ETL Jobs
class ETLProcessor:
    @staticmethod
    async def sync_workflow_executions():
        """Sync workflow execution data from N8N to analytics database"""
        ACTIVE_ETL_JOBS.inc()
        
        try:
            with ETL_PROCESSING_TIME.labels(job_type='workflow_executions').time():
                # Get executions from N8N
                executions = await n8n_client.get_executions(limit=1000)
                
                if not executions:
                    logger.info("No executions found in N8N")
                    return
                
                # Store in PostgreSQL
                async with postgres_manager.pool.acquire() as conn:
                    for execution in executions:
                        try:
                            await conn.execute("""
                                INSERT INTO analytics.workflow_executions 
                                (id, workflow_id, execution_id, status, started_at, finished_at, duration_ms, metadata)
                                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                                ON CONFLICT (execution_id) DO UPDATE SET
                                    status = EXCLUDED.status,
                                    finished_at = EXCLUDED.finished_at,
                                    duration_ms = EXCLUDED.duration_ms,
                                    metadata = EXCLUDED.metadata
                            """, 
                                str(execution.get('id')),
                                str(execution.get('workflowId', '')),
                                str(execution.get('id')),  # Use execution id as execution_id
                                execution.get('finished', False),
                                datetime.fromisoformat(execution.get('startedAt').replace('Z', '+00:00')) if execution.get('startedAt') else None,
                                datetime.fromisoformat(execution.get('stoppedAt').replace('Z', '+00:00')) if execution.get('stoppedAt') else None,
                                int((datetime.fromisoformat(execution.get('stoppedAt', '').replace('Z', '+00:00')) - 
                                    datetime.fromisoformat(execution.get('startedAt', '').replace('Z', '+00:00'))).total_seconds() * 1000) 
                                    if execution.get('startedAt') and execution.get('stoppedAt') else None,
                                json.dumps(execution)
                            )
                        except Exception as e:
                            logger.warning("Failed to insert execution", execution_id=execution.get('id'), error=str(e))
                            continue
                
                # Store in ClickHouse if available
                if clickhouse_manager.client:
                    try:
                        # Transform data for ClickHouse
                        ch_data = []
                        for execution in executions:
                            if execution.get('startedAt'):
                                ch_data.append([
                                    str(execution.get('id')),
                                    str(execution.get('workflowId', '')),
                                    str(execution.get('id')),
                                    'success' if execution.get('finished') else 'running',
                                    datetime.fromisoformat(execution.get('startedAt').replace('Z', '+00:00')),
                                    datetime.fromisoformat(execution.get('stoppedAt').replace('Z', '+00:00')) if execution.get('stoppedAt') else datetime.utcnow(),
                                    int((datetime.fromisoformat(execution.get('stoppedAt', '').replace('Z', '+00:00')) - 
                                        datetime.fromisoformat(execution.get('startedAt', '').replace('Z', '+00:00'))).total_seconds() * 1000) 
                                        if execution.get('startedAt') and execution.get('stoppedAt') else 0,
                                    json.dumps(execution),
                                    datetime.utcnow()
                                ])
                        
                        if ch_data:
                            clickhouse_manager.client.insert(
                                'workflow_executions',
                                ch_data,
                                column_names=['id', 'workflow_id', 'execution_id', 'status', 'started_at', 
                                            'finished_at', 'duration_ms', 'metadata', 'recorded_at']
                            )
                            logger.info("Stored executions in ClickHouse", count=len(ch_data))
                    
                    except Exception as e:
                        logger.error("Failed to store in ClickHouse", error=str(e))
                
                ETL_JOBS_EXECUTED.labels(job_type='workflow_executions', status='success').inc()
                logger.info("Workflow executions sync completed", count=len(executions))
        
        except Exception as e:
            logger.error("Workflow executions sync failed", error=str(e), traceback=traceback.format_exc())
            ETL_JOBS_EXECUTED.labels(job_type='workflow_executions', status='error').inc()
        
        finally:
            ACTIVE_ETL_JOBS.dec()
    
    @staticmethod
    async def process_document_metrics():
        """Process document processing metrics"""
        ACTIVE_ETL_JOBS.inc()
        
        try:
            with ETL_PROCESSING_TIME.labels(job_type='document_metrics').time():
                async with postgres_manager.pool.acquire() as conn:
                    # Get document processing stats
                    rows = await conn.fetch("""
                        SELECT 
                            ds.id,
                            ds.filename,
                            ds.file_size,
                            ds.status,
                            ds.created_at,
                            ds.processed_at,
                            COUNT(e.id) as chunk_count,
                            EXTRACT(EPOCH FROM (ds.processed_at - ds.created_at)) * 1000 as processing_time_ms
                        FROM documents.document_store ds
                        LEFT JOIN documents.embeddings e ON ds.id = e.document_id
                        WHERE ds.processed_at >= NOW() - INTERVAL '1 hour'
                        GROUP BY ds.id, ds.filename, ds.file_size, ds.status, ds.created_at, ds.processed_at
                    """)
                    
                    # Store metrics in ClickHouse if available
                    if clickhouse_manager.client and rows:
                        ch_data = []
                        for row in rows:
                            ch_data.append([
                                str(row['id']),
                                str(row['id']),  # document_id
                                'processing',
                                int(row['processing_time_ms']) if row['processing_time_ms'] else 0,
                                int(row['file_size']) if row['file_size'] else 0,
                                int(row['chunk_count']),
                                'sentence-transformers/all-MiniLM-L6-v2',  # Default model
                                json.dumps({
                                    'filename': row['filename'],
                                    'status': row['status'],
                                    'created_at': row['created_at'].isoformat()
                                }),
                                datetime.utcnow()
                            ])
                        
                        clickhouse_manager.client.insert(
                            'document_metrics',
                            ch_data,
                            column_names=['id', 'document_id', 'operation', 'processing_time_ms',
                                        'file_size_bytes', 'chunk_count', 'embedding_model', 
                                        'metadata', 'created_at']
                        )
                        logger.info("Stored document metrics in ClickHouse", count=len(ch_data))
                
                ETL_JOBS_EXECUTED.labels(job_type='document_metrics', status='success').inc()
                logger.info("Document metrics processing completed")
        
        except Exception as e:
            logger.error("Document metrics processing failed", error=str(e), traceback=traceback.format_exc())
            ETL_JOBS_EXECUTED.labels(job_type='document_metrics', status='error').inc()
        
        finally:
            ACTIVE_ETL_JOBS.dec()

# Response models
class JobStatus(BaseModel):
    job_id: str
    job_type: str
    status: str
    last_run: Optional[str]
    next_run: Optional[str]

class ETLJobRequest(BaseModel):
    job_type: str = Field(..., description="Type of ETL job to run")
    schedule: Optional[str] = Field(None, description="Cron schedule for recurring jobs")

class ETLJobResponse(BaseModel):
    job_id: str
    status: str
    message: str

# Lifespan management
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await postgres_manager.connect()
    await clickhouse_manager.connect()
    
    # Setup scheduled jobs
    setup_scheduled_jobs()
    scheduler.start()
    
    logger.info("ETL processor service started")
    
    yield
    
    # Shutdown
    scheduler.shutdown()
    await postgres_manager.disconnect()
    await clickhouse_manager.disconnect()
    logger.info("ETL processor service stopped")

def setup_scheduled_jobs():
    """Setup default scheduled ETL jobs"""
    # Sync workflow executions every 5 minutes
    scheduler.add_job(
        ETLProcessor.sync_workflow_executions,
        trigger=IntervalTrigger(minutes=5),
        id="sync_workflow_executions",
        name="Sync Workflow Executions",
        replace_existing=True
    )
    
    # Process document metrics every 15 minutes
    scheduler.add_job(
        ETLProcessor.process_document_metrics,
        trigger=IntervalTrigger(minutes=15),
        id="process_document_metrics",
        name="Process Document Metrics",
        replace_existing=True
    )
    
    # Update scheduled jobs gauge
    SCHEDULED_JOBS.set(len(scheduler.get_jobs()))
    
    logger.info("Scheduled ETL jobs configured")

# FastAPI app
app = FastAPI(
    title="N8N AI Starter Kit - ETL Processor",
    description="ETL processing service with scheduling capabilities",
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
        # Check PostgreSQL connection
        async with postgres_manager.pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        
        # Check scheduler
        scheduler_running = scheduler.running
        
        return {
            "status": "healthy",
            "version": "1.0.0",
            "timestamp": datetime.utcnow().isoformat(),
            "scheduler_running": scheduler_running,
            "scheduled_jobs": len(scheduler.get_jobs()),
            "clickhouse_available": clickhouse_manager.client is not None
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

# Job management endpoints
@app.get("/etl/jobs", response_model=List[JobStatus])
async def list_jobs():
    """List all scheduled ETL jobs"""
    jobs = []
    for job in scheduler.get_jobs():
        jobs.append(JobStatus(
            job_id=job.id,
            job_type=job.name,
            status="scheduled" if job.next_run_time else "paused",
            last_run=str(job.next_run_time - job.trigger.interval) if hasattr(job.trigger, 'interval') and job.next_run_time else None,
            next_run=str(job.next_run_time) if job.next_run_time else None
        ))
    
    return jobs

@app.post("/etl/jobs/run", response_model=ETLJobResponse)
async def run_etl_job(background_tasks: BackgroundTasks, request: ETLJobRequest):
    """Manually trigger an ETL job"""
    job_id = f"manual_{request.job_type}_{int(datetime.utcnow().timestamp())}"
    
    try:
        # Map job types to functions
        job_functions = {
            "workflow_executions": ETLProcessor.sync_workflow_executions,
            "document_metrics": ETLProcessor.process_document_metrics
        }
        
        if request.job_type not in job_functions:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown job type: {request.job_type}"
            )
        
        # Schedule the job
        if request.schedule:
            # Add as scheduled job
            try:
                trigger = CronTrigger.from_crontab(request.schedule)
                scheduler.add_job(
                    job_functions[request.job_type],
                    trigger=trigger,
                    id=job_id,
                    name=f"Manual {request.job_type}",
                    replace_existing=True
                )
                SCHEDULED_JOBS.set(len(scheduler.get_jobs()))
                
                return ETLJobResponse(
                    job_id=job_id,
                    status="scheduled",
                    message=f"Job scheduled with cron: {request.schedule}"
                )
            except Exception as e:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid cron schedule: {str(e)}"
                )
        else:
            # Run immediately as background task
            background_tasks.add_task(job_functions[request.job_type])
            
            return ETLJobResponse(
                job_id=job_id,
                status="running",
                message="Job started in background"
            )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to run ETL job", job_type=request.job_type, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to run job: {str(e)}")

@app.delete("/etl/jobs/{job_id}")
async def delete_job(job_id: str):
    """Delete a scheduled job"""
    try:
        scheduler.remove_job(job_id)
        SCHEDULED_JOBS.set(len(scheduler.get_jobs()))
        return {"message": f"Job {job_id} deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Job not found: {str(e)}")

# Analytics endpoints
@app.get("/etl/analytics/workflow-summary")
async def get_workflow_summary():
    """Get workflow execution summary"""
    try:
        async with postgres_manager.pool.acquire() as conn:
            summary = await conn.fetchrow("""
                SELECT 
                    COUNT(*) as total_executions,
                    COUNT(CASE WHEN finished_at IS NOT NULL THEN 1 END) as completed_executions,
                    AVG(duration_ms) as avg_duration_ms,
                    MAX(started_at) as last_execution
                FROM analytics.workflow_executions
                WHERE started_at >= NOW() - INTERVAL '24 hours'
            """)
            
            return {
                "total_executions": summary['total_executions'] or 0,
                "completed_executions": summary['completed_executions'] or 0,
                "avg_duration_ms": float(summary['avg_duration_ms']) if summary['avg_duration_ms'] else 0,
                "last_execution": summary['last_execution'].isoformat() if summary['last_execution'] else None
            }
    
    except Exception as e:
        logger.error("Failed to get workflow summary", error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to get summary: {str(e)}")

@app.get("/etl/analytics/document-summary")
async def get_document_summary():
    """Get document processing summary"""
    try:
        async with postgres_manager.pool.acquire() as conn:
            summary = await conn.fetchrow("""
                SELECT 
                    COUNT(*) as total_documents,
                    COUNT(CASE WHEN status = 'processed' THEN 1 END) as processed_documents,
                    COUNT(CASE WHEN status = 'error' THEN 1 END) as failed_documents,
                    SUM(file_size) as total_file_size,
                    MAX(created_at) as last_upload
                FROM documents.document_store
                WHERE created_at >= NOW() - INTERVAL '24 hours'
            """)
            
            embedding_count = await conn.fetchval("""
                SELECT COUNT(*) 
                FROM documents.embeddings e
                JOIN documents.document_store ds ON e.document_id = ds.id
                WHERE ds.created_at >= NOW() - INTERVAL '24 hours'
            """)
            
            return {
                "total_documents": summary['total_documents'] or 0,
                "processed_documents": summary['processed_documents'] or 0,
                "failed_documents": summary['failed_documents'] or 0,
                "total_file_size_bytes": summary['total_file_size'] or 0,
                "total_embeddings": embedding_count or 0,
                "last_upload": summary['last_upload'].isoformat() if summary['last_upload'] else None
            }
    
    except Exception as e:
        logger.error("Failed to get document summary", error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to get summary: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8002,
        log_level=settings.log_level.lower(),
        reload=settings.debug
    )