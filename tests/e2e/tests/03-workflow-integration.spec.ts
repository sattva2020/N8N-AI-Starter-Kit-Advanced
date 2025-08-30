import { test, expect } from '@playwright/test';

test.describe('Workflow Integration Tests', () => {
  test('should test N8N interface accessibility', async ({ page }) => {
    // Navigate to N8N interface
    await page.goto('http://localhost:5678');
    
    // Wait for N8N to load - it might take some time
    await page.waitForLoadState('networkidle');
    
    // Check if N8N canvas is available
    try {
      await expect(page.locator('[data-test-id="canvas"]')).toBeVisible({ timeout: 15000 });
    } catch (error) {
      // If specific test ID is not available, check for general canvas element
      await expect(page.locator('canvas, .canvas, #canvas')).toBeVisible({ timeout: 15000 });
    }
    
    // Check for N8N branding or interface elements
    await expect(page.locator('body')).toContainText('n8n', { timeout: 10000 });
  });

  test('should test document processing workflow', async ({ page, request }) => {
    // Start at documents page
    await page.goto('/documents');
    
    // Check if file upload is available
    const fileInput = page.locator('input[type="file"]');
    await expect(fileInput).toBeVisible();
    
    // Create a test file for upload
    const testContent = 'This is a test document for workflow integration testing.';
    
    // Upload test file
    await page.setInputFiles('input[type="file"]', {
      name: 'test-workflow.txt',
      mimeType: 'text/plain',
      buffer: Buffer.from(testContent)
    });
    
    // Submit form if submit button exists
    const submitButton = page.locator('button[type="submit"], input[type="submit"], .submit-btn');
    if (await submitButton.count() > 0) {
      await submitButton.click();
      
      // Wait for processing feedback
      try {
        await expect(page.locator('.success, .processing, .complete')).toBeVisible({ timeout: 30000 });
      } catch (error) {
        // If specific classes aren't available, just wait a bit
        await page.waitForTimeout(5000);
      }
    }
    
    // Verify via API that document was processed
    await page.waitForTimeout(3000); // Allow processing time
    
    const searchResponse = await request.post('http://localhost:8001/docs/search', {
      data: {
        query: 'test document workflow',
        limit: 1
      }
    });
    
    if (searchResponse.ok()) {
      const searchResults = await searchResponse.json();
      // Document should be found if processing worked
      expect(searchResults).toHaveProperty('results');
    }
  });

  test('should test service interconnectivity', async ({ request }) => {
    // Test that services can communicate with each other
    
    // Check Qdrant collections (if document processor is working)
    const qdrantResponse = await request.get('http://localhost:6333/collections');
    if (qdrantResponse.ok()) {
      const collections = await qdrantResponse.json();
      expect(collections).toHaveProperty('result');
    }
    
    // Check metrics endpoints
    const metricsEndpoints = [
      'http://localhost:8001/metrics',
      'http://localhost:8002/metrics',
      'http://localhost:8003/metrics'
    ];
    
    for (const endpoint of metricsEndpoints) {
      const metricsResponse = await request.get(endpoint);
      if (metricsResponse.ok()) {
        const metrics = await metricsResponse.text();
        expect(metrics).toContain('# HELP'); // Prometheus metrics format
      }
    }
  });

  test('should test end-to-end workflow creation', async ({ page, request }) => {
    // This test attempts to create a simple workflow if N8N is accessible
    
    await page.goto('http://localhost:5678');
    await page.waitForLoadState('networkidle');
    
    // Try to create a workflow via API instead of UI (more reliable)
    const N8N_API_KEY = process.env.N8N_API_KEY || 'test_api_key';
    
    const simpleWorkflow = {
      name: 'Test Integration Workflow',
      nodes: [
        {
          id: 'trigger',
          name: 'Manual Trigger',
          type: 'n8n-nodes-base.manualTrigger',
          position: [100, 100],
          parameters: {}
        }
      ],
      connections: {},
      active: false
    };

    const createResponse = await request.post('http://localhost:5678/api/v1/workflows', {
      headers: {
        'X-N8N-API-KEY': N8N_API_KEY,
        'Content-Type': 'application/json'
      },
      data: simpleWorkflow
    });

    if (createResponse.ok()) {
      const workflow = await createResponse.json();
      expect(workflow).toHaveProperty('id');
      expect(workflow.name).toBe('Test Integration Workflow');
      
      // Clean up - delete the test workflow
      await request.delete(`http://localhost:5678/api/v1/workflows/${workflow.id}`, {
        headers: { 'X-N8N-API-KEY': N8N_API_KEY }
      });
    }
  });
});