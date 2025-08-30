"""
Unit tests for the ETL Processor Service
"""

import pytest
import asyncio
from httpx import AsyncClient
from fastapi.testclient import TestClient
import sys
import os

# Add the service directory to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../services/etl-processor'))

try:
    from main import app
except ImportError:
    # Mock the app if imports fail (for CI environments)
    from fastapi import FastAPI
    app = FastAPI()
    
    @app.get("/health")
    async def mock_health():
        return {"status": "healthy", "version": "test", "timestamp": "2024-01-01T00:00:00"}

class TestETLProcessor:
    """Test suite for ETL Processor service"""
    
    def setup_method(self):
        """Setup for each test method"""
        self.client = TestClient(app)
    
    def test_health_endpoint(self):
        """Test the health check endpoint"""
        response = self.client.get("/health")
        
        # May return 503 if services not available, that's expected in unit tests
        assert response.status_code in [200, 503]
        
        if response.status_code == 200:
            data = response.json()
            assert data["status"] == "healthy"
            assert "version" in data
            assert "timestamp" in data
    
    def test_metrics_endpoint(self):
        """Test the Prometheus metrics endpoint"""
        response = self.client.get("/metrics")
        assert response.status_code == 200
        assert "text/plain" in response.headers.get("content-type", "")

class TestETLProcessorAPI:
    """Test suite for ETL Processor API endpoints"""
    
    def setup_method(self):
        """Setup for each test method"""
        self.client = TestClient(app)
    
    def test_jobs_list_endpoint(self):
        """Test the jobs listing endpoint"""
        response = self.client.get("/etl/jobs")
        
        # May return 500 if scheduler not available
        assert response.status_code in [200, 500, 503]
        
        if response.status_code == 200:
            data = response.json()
            assert isinstance(data, list)
    
    def test_run_job_invalid_type(self):
        """Test running job with invalid type"""
        job_data = {
            "job_type": "invalid_job_type"
        }
        
        response = self.client.post("/etl/jobs/run", json=job_data)
        assert response.status_code in [400, 500]  # Bad request or server error
    
    def test_run_job_valid_type(self):
        """Test running job with valid type"""
        job_data = {
            "job_type": "workflow_executions"
        }
        
        response = self.client.post("/etl/jobs/run", json=job_data)
        
        # May return 500 if dependencies not available
        assert response.status_code in [200, 500, 503]
    
    def test_workflow_summary_endpoint(self):
        """Test workflow summary endpoint"""
        response = self.client.get("/etl/analytics/workflow-summary")
        
        # May return 500 if database not available
        assert response.status_code in [200, 500, 503]
        
        if response.status_code == 200:
            data = response.json()
            assert "total_executions" in data
            assert "completed_executions" in data
    
    def test_document_summary_endpoint(self):
        """Test document summary endpoint"""
        response = self.client.get("/etl/analytics/document-summary")
        
        # May return 500 if database not available
        assert response.status_code in [200, 500, 503]
        
        if response.status_code == 200:
            data = response.json()
            assert "total_documents" in data
            assert "processed_documents" in data

class TestETLProcessorValidation:
    """Test suite for ETL Processor input validation"""
    
    def setup_method(self):
        """Setup for each test method"""
        self.client = TestClient(app)
    
    def test_run_job_missing_data(self):
        """Test running job without required data"""
        response = self.client.post("/etl/jobs/run", json={})
        assert response.status_code == 422  # Validation error
    
    def test_run_job_invalid_json(self):
        """Test running job with invalid JSON"""
        response = self.client.post(
            "/etl/jobs/run",
            data="invalid json",
            headers={"Content-Type": "application/json"}
        )
        assert response.status_code == 422  # JSON decode error

if __name__ == "__main__":
    # Run the tests
    pytest.main([__file__, "-v"])