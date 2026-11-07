import { describe, expect, it, vi } from 'vitest';
import { setFilePreviewSecurityHeaders } from './file-preview-security';
describe('active artifact previews', () => {
 it.each(['text/html','text/html; charset=utf-8','image/svg+xml'])('isolates %s even in a top-level tab', type => {
  const res={setHeader:vi.fn()};setFilePreviewSecurityHeaders(res,type);
  expect(res.setHeader).toHaveBeenCalledWith('X-Content-Type-Options','nosniff');
  const policy=res.setHeader.mock.calls.find(c=>c[0]==='Content-Security-Policy')?.[1];
  expect(policy).toContain('sandbox allow-scripts');
  expect(policy).not.toContain('allow-same-origin');
 });
 it('does not alter the rendering policy of ordinary text or tables', () => {
  const res={setHeader:vi.fn()};setFilePreviewSecurityHeaders(res,'text/csv');
  expect(res.setHeader).toHaveBeenCalledTimes(1);
 });
});
