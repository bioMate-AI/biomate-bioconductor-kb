import { test, expect } from '@playwright/test';

test.describe('Landing Page Responsiveness', () => {
  test('should display correctly on desktop and mobile', async ({ page }) => {
    // Navigate to landing page
    await page.goto('/home');

    // --- Desktop View ---
    await page.setViewportSize({ width: 1280, height: 800 });
    await expect(page).toHaveTitle(/BioMate/i);

    // Check main sections are visible
    const heroSection = page.locator('section').first();
    await expect(heroSection).toBeVisible();

    // Check for the "Right Column - Visual" which was previously hidden on mobile
    // It contains the BioHero component or its container
    // We target the "Speedup" label in the overlay card within the first section (Hero)
    const overlayLabel = page.getByText('Speedup');
    await expect(overlayLabel).toBeVisible();

    // Check grid layout on desktop
    const textColumn = page.getByText('Chat Your Way to');
    
    const textBox = await textColumn.boundingBox();
    const overlayBox = await overlayLabel.boundingBox();

    if (textBox && overlayBox) {
      // In desktop, they should be roughly on the same vertical level or side-by-side
      // The visual is to the right of text
      expect(overlayBox.x).toBeGreaterThan(textBox.x);
    }

    // --- Mobile View ---
    await page.setViewportSize({ width: 375, height: 667 });
    
    // Check elements are still visible
    await expect(textColumn).toBeVisible();
    
    // The overlay is hidden on very small screens (hidden sm:block), so we check for the canvas or container visibility
    // Or we check that the visual column is stacked below.
    // Let's check for the "No credit card" text which is below the main buttons
    // Scoped to first section to avoid ambiguity with footer CTA
    const noCreditCard = page.locator('section').first().getByText('No credit card');
    await expect(noCreditCard).toBeVisible();

    // Check for horizontal overflow
    const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);
    
    // scrollWidth should not be significantly larger than clientWidth (allow for small pixel differences)
    expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 1);
  });
});
