import { test, expect } from '@playwright/test';

test.describe('API Integration Tests', () => {
  test('should test all health endpoints', async ({ request }) => {
    const healthEndpoints = [
      { url: 'http://localhost:8000/health', name: 'Web Interface' },
      { url: 'http://localhost:8001/health', name: 'Document Processor' },
      { url: 'http://localhost:8002/health', name: 'ETL Processor' },
      { url: 'http://localhost:8003/health', name: 'LightRAG' }
    ];
    
    for (const endpoint of healthEndpoints) {
      const response = await request.get(endpoint.url);
      expect(response.ok(), `${endpoint.name} health check failed`).toBeTruthy();
      
      const healthData = await response.json();
      expect(healthData).toHaveProperty('status');
    }
  });

  test('should test N8N API endpoints', async ({ request }) => {
    const N8N_API_KEY = process.env.N8N_API_KEY || 'test_api_key';
    const N8N_BASE_URL = 'http://localhost:5678';

    // Test workflows endpoint
    const workflowsResponse = await request.get(`${N8N_BASE_URL}/api/v1/workflows`, {
      headers: { 'X-N8N-API-KEY': N8N_API_KEY }
    });
    
    if (workflowsResponse.ok()) {
      const workflows = await workflowsResponse.json();
      expect(workflows).toHaveProperty('data');
      expect(Array.isArray(workflows.data)).toBeTruthy();
    }

    // Test credentials endpoint
    const credentialsResponse = await request.get(`${N8N_BASE_URL}/api/v1/credentials`, {
      headers: { 'X-N8N-API-KEY': N8N_API_KEY }
    });
    
    if (credentialsResponse.ok()) {
      const credentials = await credentialsResponse.json();
      expect(credentials).toHaveProperty('data');
    }
  });

  test('should test document search API', async ({ request }) => {
    const searchResponse = await request.post('http://localhost:8001/docs/search', {
      data: {
        query: 'test search query',
        limit: 5
      }
    });

    expect(searchResponse.ok()).toBeTruthy();
    const searchResults = await searchResponse.json();
    expect(searchResults).toHaveProperty('results');
    expect(Array.isArray(searchResults.results)).toBeTruthy();
  });

  test('should test system status endpoints', async ({ request }) => {
    const statusResponse = await request.get('http://localhost:8000/api/status');
    expect(statusResponse.ok()).toBeTruthy();
    
    const status = await statusResponse.json();
    expect(status).toHaveProperty('status');
    expect(status).toHaveProperty('services');
  });
});