import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildDisambiguationCorrection, submitCorrection } from './corrections';

describe('buildDisambiguationCorrection', () => {
  const candidates = [
    { name: 'rnaseq', display_name: 'nf-core/rnaseq', score: 9.0, source: 'nfcore' },
    { name: 'salmon', display_name: 'Salmon quant', score: 7.5, source: 'biomni_nextflow' },
    { name: 'star', display_name: 'STAR align', score: 6.0, source: 'biomni_nextflow' },
  ];

  it('returns a correction when the user picks a non-top candidate', () => {
    const c = buildDisambiguationCorrection(candidates, candidates[1], { sessionId: 's1' });
    expect(c).not.toBeNull();
    // suggested = the system's highest-scored guess; corrected = the user's pick
    expect(c!.suggestedApproach.workflow).toBe('nf-core/rnaseq');
    expect(c!.correctedApproach.workflow).toBe('Salmon quant');
    expect(c!.sessionId).toBe('s1');
    expect((c!.workflowContext as any).origin).toBe('disambiguation');
  });

  it('returns null when the user picks the top-scored candidate (not a correction)', () => {
    expect(buildDisambiguationCorrection(candidates, candidates[0])).toBeNull();
  });

  it('returns null with fewer than two candidates (no baseline to correct against)', () => {
    expect(buildDisambiguationCorrection([candidates[0]], candidates[0])).toBeNull();
    expect(buildDisambiguationCorrection(undefined as any, candidates[0])).toBeNull();
  });

  it('treats a missing score as the lowest, so an unscored pick over a scored one still records', () => {
    const cands = [
      { name: 'a', score: 5 },
      { name: 'b' }, // no score
    ];
    const c = buildDisambiguationCorrection(cands, cands[1]);
    expect(c).not.toBeNull();
    expect(c!.suggestedApproach.workflow).toBe('a');
    expect(c!.correctedApproach.workflow).toBe('b');
  });
});

describe('submitCorrection', () => {
  const realFetch = globalThis.fetch;
  beforeEach(() => { vi.restoreAllMocks(); });
  afterEach(() => { globalThis.fetch = realFetch; });

  it('POSTs the payload to the correction endpoint with credentials', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ id: 1 }) });
    globalThis.fetch = fetchMock as any;
    const res = await submitCorrection({
      suggestedApproach: { workflow: 'x' }, correctedApproach: { workflow: 'y' },
    });
    expect(res.success).toBe(true);
    expect(fetchMock).toHaveBeenCalledWith('/api/memory/user/corrections', expect.objectContaining({
      method: 'POST', credentials: 'include',
    }));
    const body = JSON.parse((fetchMock.mock.calls[0][1] as any).body);
    expect(body.correctedApproach.workflow).toBe('y');
  });

  it('never throws on a network error — returns success:false', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('offline')) as any;
    const res = await submitCorrection({
      suggestedApproach: { workflow: 'x' }, correctedApproach: { workflow: 'y' },
    });
    expect(res.success).toBe(false);
    expect(res.error).toBe('offline');
  });

  it('returns success:false on a non-ok response', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false, statusText: 'Unauthorized', json: async () => ({ message: 'nope' }),
    }) as any;
    const res = await submitCorrection({
      suggestedApproach: { workflow: 'x' }, correctedApproach: { workflow: 'y' },
    });
    expect(res.success).toBe(false);
    expect(res.error).toBe('nope');
  });
});
