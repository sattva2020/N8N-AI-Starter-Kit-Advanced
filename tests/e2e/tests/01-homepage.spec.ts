import { test, expect } from '@playwright/test';

test.describe('Homepage and Navigation Tests', () => {
  test('should load homepage and display navigation', async ({ page }) => {
    await page.goto('/');
    
    // Check title
    await expect(page).toHaveTitle(/N8N AI Starter Kit/);
    
    // Check navigation elements
    await expect(page.locator('nav')).toBeVisible();
    
    // Check main navigation links
    const navigationLinks = [
      { selector: 'a[href*="dashboard"]', text: 'Dashboard' },
      { selector: 'a[href*="documents"]', text: 'Documents' },
      { selector: 'a[href*="workflows"]', text: 'Workflows' }
    ];
    
    for (const link of navigationLinks) {
      await expect(page.locator(link.selector)).toBeVisible();
    }
  });

  test('should redirect to dashboard from root', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL(/.*dashboard/);
  });

  test('should navigate between main sections', async ({ page }) => {
    await page.goto('/dashboard');
    
    // Navigate to documents
    await page.click('a[href*="documents"]');
    await expect(page).toHaveURL(/.*documents/);
    
    // Navigate to workflows  
    await page.click('a[href*="workflows"]');
    await expect(page).toHaveURL(/.*workflows/);
    
    // Navigate back to dashboard
    await page.click('a[href*="dashboard"]');
    await expect(page).toHaveURL(/.*dashboard/);
  });
});