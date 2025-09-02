-- =============================================================================
-- N8N AI STARTER KIT - POSTGRESQL INITIALIZATION
-- =============================================================================
-- This script initializes the PostgreSQL database with required extensions
-- and creates basic schema for the N8N AI Starter Kit

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Try to create pgvector extension, but don't fail if it's not available
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS "pgvector";
EXCEPTION
    WHEN undefined_file THEN
        RAISE NOTICE 'pgvector extension is not available, skipping vector functionality';
END
$$;

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS n8n;
CREATE SCHEMA IF NOT EXISTS documents;
CREATE SCHEMA IF NOT EXISTS analytics;

-- Set default schema
SET search_path TO n8n, public;

-- Create documents table for document processing
CREATE TABLE IF NOT EXISTS documents.document_store (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    filename VARCHAR(500) NOT NULL,
    content_type VARCHAR(100),
    file_size BIGINT,
    content TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) DEFAULT 'pending'
);

-- Create embeddings table for vector storage
DO $$
BEGIN
    -- Try to create table with vector column if pgvector is available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgvector') THEN
        CREATE TABLE IF NOT EXISTS documents.embeddings (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            document_id UUID REFERENCES documents.document_store(id) ON DELETE CASCADE,
            chunk_index INTEGER NOT NULL,
            chunk_text TEXT NOT NULL,
            chunk_metadata JSONB DEFAULT '{}',
            embedding VECTOR(384), -- Dimension for sentence-transformers/all-MiniLM-L6-v2
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    ELSE
        -- Create table without vector column if pgvector is not available
        CREATE TABLE IF NOT EXISTS documents.embeddings (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            document_id UUID REFERENCES documents.document_store(id) ON DELETE CASCADE,
            chunk_index INTEGER NOT NULL,
            chunk_text TEXT NOT NULL,
            chunk_metadata JSONB DEFAULT '{}',
            embedding_data TEXT, -- Store as text fallback
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    END IF;
END
$$;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_document_store_created_at ON documents.document_store(created_at);
CREATE INDEX IF NOT EXISTS idx_document_store_status ON documents.document_store(status);
CREATE INDEX IF NOT EXISTS idx_document_store_metadata ON documents.document_store USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_embeddings_document_id ON documents.embeddings(document_id);

-- Create vector index only if pgvector is available
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgvector') THEN
        CREATE INDEX IF NOT EXISTS idx_embeddings_embedding ON documents.embeddings USING ivfflat (embedding vector_cosine_ops);
    END IF;
END
$$;

-- Create analytics tables
CREATE TABLE IF NOT EXISTS analytics.workflow_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_id VARCHAR(255),
    execution_id VARCHAR(255),
    status VARCHAR(50),
    started_at TIMESTAMP WITH TIME ZONE,
    finished_at TIMESTAMP WITH TIME ZONE,
    duration_ms INTEGER,
    metadata JSONB DEFAULT '{}',
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_workflow_executions_workflow_id ON analytics.workflow_executions(workflow_id);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_started_at ON analytics.workflow_executions(started_at);

-- Create user for applications (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'change_me_in_production';
        GRANT USAGE ON SCHEMA documents TO app_user;
        GRANT USAGE ON SCHEMA analytics TO app_user;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA documents TO app_user;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA analytics TO app_user;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA documents TO app_user;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA analytics TO app_user;
    END IF;
END
$$;

-- Grant permissions on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA documents GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

COMMIT;