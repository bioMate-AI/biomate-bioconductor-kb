import { describe, it, expect, vi } from 'vitest';
import { cleanSequence, foldFasta, planModelFold, BOLTZ_FOLD_NEXTFLOW_PATH } from './model-fold';

describe('cleanSequence', () => {
  it('strips FASTA headers and whitespace and upper-cases', () => {
    const r = cleanSequence('>sp|P0\nmkt ayiak\nQRQ');
    expect(r).toEqual({ seq: 'MKTAYIAKQRQ' });
  });
  it('rejects empty, too short, too long, and non-amino-acid input', () => {
    expect(cleanSequence('')).toHaveProperty('error');
    expect(cleanSequence('MKT')).toHaveProperty('error'); // < 10
    expect(cleanSequence('A'.repeat(1001))).toHaveProperty('error'); // > 1000
    expect(cleanSequence('MKTAYIAK12')).toHaveProperty('error'); // digits
    expect(cleanSequence(42 as unknown)).toHaveProperty('error');
  });
  it('accepts a valid single chain with X', () => {
    expect(cleanSequence('MKTAYIAKXRQ')).toEqual({ seq: 'MKTAYIAKXRQ' });
  });
});

describe('foldFasta', () => {
  it('writes one query record', () => {
    expect(foldFasta('MKTAYIAK')).toBe('>query\nMKTAYIAK\n');
  });
});

describe('planModelFold', () => {
  const okDeps = { stageFasta: vi.fn(async () => 's3://biomate-nextflow-work/uploads/fold-x/query.fasta') };

  it('requires auth and an object body', async () => {
    expect((await planModelFold({ userId: '', body: {} }, okDeps)).status).toBe(401);
    expect((await planModelFold({ userId: 'u', body: null }, okDeps)).status).toBe(400);
  });

  it('rejects a bad sequence before staging', async () => {
    const deps = { stageFasta: vi.fn(async () => 's3://b/x') };
    const r = await planModelFold({ userId: 'u', body: { sequence: 'MKT' } }, deps);
    expect(r.status).toBe(400);
    expect(deps.stageFasta).not.toHaveBeenCalled();
  });

  it('502 when staging fails (no run started)', async () => {
    const deps = { stageFasta: vi.fn(async () => undefined) };
    const r = await planModelFold({ userId: 'u', body: { sequence: 'MKTAYIAKQRQ' } }, deps);
    expect(r.status).toBe(502);
  });

  it('returns a boltz_structure_prediction launch request on our own Batch', async () => {
    const r = await planModelFold({ userId: 'u', body: { sequence: 'mkt ayiak qrq', name: 'my fold' } }, okDeps);
    expect(r.status).toBe(200);
    expect(okDeps.stageFasta).toHaveBeenCalledWith('>query\nMKTAYIAKQRQ\n', 'query.fasta');
    expect(r.body.workflow_ga.nextflow_path).toBe(BOLTZ_FOLD_NEXTFLOW_PATH);
    expect(r.body.workflow_ga.parameters.input_fasta).toMatch(/^s3:\/\//);
    expect(r.body.workflow_ga.name).toBe('my fold');
    expect(r.body.workflow_ga.domain).toBe('structural_biology');
  });
});

describe('fold route registration', () => {
  it('registers POST /api/models/fold/plan BEFORE the /api/models/* catch-all (else it proxies to Galaxy)', async () => {
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const src = readFileSync(resolve(__dirname, 'routes.ts'), 'utf8');
    const fold = src.indexOf('app.post("/api/models/fold/plan"');
    const catchAll = src.indexOf('app.all("/api/models/*"');
    expect(fold).toBeGreaterThan(-1);
    expect(catchAll).toBeGreaterThan(-1);
    expect(fold).toBeLessThan(catchAll);
  });
});
