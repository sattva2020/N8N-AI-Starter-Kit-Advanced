-- =============================================================================
-- N8N AI STARTER KIT - CLICKHOUSE INITIALIZATION
-- =============================================================================
-- This script initializes ClickHouse for analytics workloads

-- Create database for analytics
CREATE DATABASE IF NOT EXISTS n8n_analytics;

USE n8n_analytics;

-- Create table for workflow execution analytics
CREATE TABLE IF NOT EXISTS workflow_executions (
    id String,
    workflow_id String,
    execution_id String,
    status String,
    started_at DateTime64(3),
    finished_at DateTime64(3),
    duration_ms UInt32,
    metadata String,
    recorded_at DateTime64(3) DEFAULT now64()
) ENGINE = MergeTree()
ORDER BY (workflow_id, started_at)
PARTITION BY toYYYYMM(started_at);

-- Create table for document processing metrics
CREATE TABLE IF NOT EXISTS document_metrics (
    id String,
    document_id String,
    operation String,
    processing_time_ms UInt32,
    file_size_bytes UInt64,
    chunk_count UInt16,
    embedding_model String,
    metadata String,
    created_at DateTime64(3) DEFAULT now64()
) ENGINE = MergeTree()
ORDER BY (operation, created_at)
PARTITION BY toYYYYMM(created_at);

-- Create materialized view for workflow performance analytics
CREATE MATERIALIZED VIEW IF NOT EXISTS workflow_performance_daily AS
SELECT
    workflow_id,
    toDate(started_at) as execution_date,
    count() as execution_count,
    countIf(status = 'success') as success_count,
    countIf(status = 'error') as error_count,
    avg(duration_ms) as avg_duration_ms,
    max(duration_ms) as max_duration_ms,
    min(duration_ms) as min_duration_ms
FROM workflow_executions
WHERE started_at >= today() - 30
GROUP BY workflow_id, execution_date;

-- Create user for applications
CREATE USER IF NOT EXISTS 'app_user' IDENTIFIED WITH plaintext_password BY 'change_me_in_production';
GRANT SELECT, INSERT ON n8n_analytics.* TO 'app_user';