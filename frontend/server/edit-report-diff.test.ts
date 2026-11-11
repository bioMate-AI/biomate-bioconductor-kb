import { describe, expect, it } from 'vitest';
import { summarizeReportEdit } from './galaxy-assistant';

// summarizeReportEdit is the pure core of the edit_report tool: it turns (base, next)
// report markdown into the added/removed counts + preview the chat shows the user
// BEFORE anything is saved. The store side (append / v0-fork) is covered by
// report-version-store.test.ts; this guards the diff the user is asked to approve.
describe('summarizeReportEdit', () => {
  it('reports no change for identical content', () => {
    const s = summarizeReportEdit('# Report\n\nSummary.', '# Report\n\nSummary.');
    expect(s.unchanged).toBe(true);
    expect(s.added).toBe(0);
    expect(s.removed).toBe(0);
    expect(s.preview).toBe('');
  });

  it('counts a replaced line as one removed + one added', () => {
    const base = '# Report\n\nThe IC50 was 1.0 uM.';
    const next = '# Report\n\nThe IC50 was 0.5 uM.';
    const s = summarizeReportEdit(base, next);
    expect(s.unchanged).toBe(false);
    expect(s.added).toBe(1);
    expect(s.removed).toBe(1);
    expect(s.preview).toContain('- The IC50 was 1.0 uM.');
    expect(s.preview).toContain('+ The IC50 was 0.5 uM.');
  });

  it('counts a pure addition with no removals', () => {
    const base = '# Report\n\nSummary.';
    const next = '# Report\n\nSummary.\n\n## Limitations\n\nSmall n.';
    const s = summarizeReportEdit(base, next);
    expect(s.added).toBeGreaterThanOrEqual(3);
    expect(s.removed).toBe(0);
    expect(s.preview).toContain('+ ## Limitations');
  });

  it('counts a pure deletion with no additions', () => {
    const base = 'a\nb\nc\nd';
    const next = 'a\nd';
    const s = summarizeReportEdit(base, next);
    expect(s.added).toBe(0);
    expect(s.removed).toBe(2);
    expect(s.preview).toContain('- b');
    expect(s.preview).toContain('- c');
  });

  it('truncates a very long preview', () => {
    const base = '';
    const next = Array.from({ length: 100 }, (_, i) => 'line ' + i).join('\n');
    const s = summarizeReportEdit(base, next, 10);
    expect(s.added).toBe(100);
    expect(s.preview).toContain('… (preview truncated)');
    // Preview holds the cap (10) plus the truncation marker line.
    expect(s.preview.split('\n').length).toBeLessThanOrEqual(11);
  });

  it('falls back to a count-only summary for very large inputs (no O(m*n) table)', () => {
    const base = Array.from({ length: 2500 }, (_, i) => 'x' + i).join('\n');
    const next = base + '\nextra line';
    const s = summarizeReportEdit(base, next);
    expect(s.added).toBe(1);
    expect(s.removed).toBe(0);
    expect(s.preview).toContain('too large');
  });
});
