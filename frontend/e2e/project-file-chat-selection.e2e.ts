import { test, expect } from '@playwright/test';
import { loginAsFixture, BASE_URL } from './_fixture-login';

test('chat can select two exact files from the active project', async ({ page }) => {
  await loginAsFixture(page);
  const created = await page.request.post(`${BASE_URL}/api/projects`, {
    data: { name: `Chat references ${Date.now()}`, primaryDomain: 'genomics' },
  });
  expect(created.ok()).toBeTruthy();
  const project = await created.json();
  const projectId = project.project?.id ?? project.id;
  expect(projectId).toBeTruthy();

  for (const name of ['comparison-a.csv', 'comparison-b.csv']) {
    const upload = await page.request.post(`${BASE_URL}/api/projects/${projectId}/files/upload`, {
      multipart: { file: { name, mimeType: 'text/csv', buffer: Buffer.from('gene,value\nTP53,1\n') } },
    });
    expect(upload.ok(), `upload ${name} failed: ${await upload.text()}`).toBeTruthy();
  }

  // Dev can keep deferred resources open after the app shell is available;
  // do not wait for the browser's default full-load completion.
  await page.goto(BASE_URL, { waitUntil: 'commit' });
  await page.evaluate((id) => localStorage.setItem('biomate-active-project-id', id), projectId);
  await page.reload({ waitUntil: 'commit' });
  const browse = page.getByTitle('Browse BioMate datasets');
  await browse.click();
  await page.getByRole('button', { name: 'Project files' }).click();
  await expect(page.getByText('comparison-a.csv')).toBeVisible();
  await page.getByText('comparison-a.csv').locator('..').getByRole('button', { name: 'Use' }).click();
  await browse.click();
  await page.getByRole('button', { name: 'Project files' }).click();
  await expect(page.getByText('comparison-b.csv')).toBeVisible();
  await page.getByText('comparison-b.csv').locator('..').getByRole('button', { name: 'Use' }).click();
  await expect(page.getByText('comparison-a.csv')).toBeVisible();
  await expect(page.getByText('comparison-b.csv')).toBeVisible();
});
