import { describe, expect, it, vi } from 'vitest';
import { readModelTrainingActivity, type TrainingActivityRun, isModelTrainingRun } from './model-training-activity';
const run = (overrides: Partial<TrainingActivityRun> = {}): TrainingActivityRun => ({
 id: 'run-1', userId: 'owner', projectId: 'p1', chatSessionId: 'chat-1', workflowName: 'Subtype classifier',
 workflowDefinition: { domain: 'ml_training' }, execution: { status: 'completed' },
 createdAt: new Date('2026-11-01T10:00:00Z'), updatedAt: new Date('2026-11-01T10:05:00Z'),
 inputBindings: [{ datasetId: 'data-1', name: 'tumor.csv' }], ...overrides,
});
const deps = (runs = [run()]) => ({ getUserProjects: vi.fn(async () => [{ id: 'p1' }]), getExecutionRuns: vi.fn(async () => runs) });
describe('owned model training activity', () => {
 it('requires authentication before storage reads', async () => {
  const d = deps(); expect((await readModelTrainingActivity({ project: 'p1' }, d)).status).toBe(401);
  expect(d.getUserProjects).not.toHaveBeenCalled(); expect(d.getExecutionRuns).not.toHaveBeenCalled();
 });
 it('denies unauthorized projects before run reads', async () => {
  const d = deps(); expect((await readModelTrainingActivity({ userId: 'owner', project: 'other' }, d)).status).toBe(403);
  expect(d.getExecutionRuns).not.toHaveBeenCalled();
 });
 it('preserves actual identity, times and status without invented registry or quality evidence', async () => {
  const d = deps(); const result = await readModelTrainingActivity({ userId: 'owner', project: 'p1' }, d);
  expect(d.getExecutionRuns).toHaveBeenCalledWith('owner', 'p1');
  expect(result).toMatchObject({ status: 200, body: { runs: [{ runId: 'run-1', chatSessionId: 'chat-1', createdAt: '2026-11-01T10:00:00.000Z', updatedAt: '2026-11-01T10:05:00.000Z', status: 'completed', dataset: 'tumor.csv', metric: 'Not recorded', gate: 'Not recorded' }] } });
  const row = (result.body as any).runs[0]; expect(row).not.toHaveProperty('modelId'); expect(row).not.toHaveProperty('version');
 });
 it('filters foreign and unrelated records even if storage returns them', async () => {
  const d = deps([run(), run({ id: 'foreign', userId: 'stranger' }), run({ id: 'wrong-project', projectId: 'p2' }), run({ id: 'not-training', workflowName: 'Model analysis', workflowDefinition: { domain: 'transcriptomics' } })]);
  const result = await readModelTrainingActivity({ userId: 'owner', project: 'p1' }, d);
  expect((result.body as any).runs.map((r: any) => r.runId)).toEqual(['run-1']);
 });
 it('includes owned account runs across projects and preserves failed/queued states', async () => {
  const d = deps([run({ id: 'failed', execution: { status: 'failed' } }), run({ id: 'queued', projectId: 'p2', execution: { status: 'queued' } })]);
  const result = await readModelTrainingActivity({ userId: 'owner' }, d);
  expect(d.getUserProjects).not.toHaveBeenCalled();
  expect((result.body as any).runs.map((r: any) => r.status)).toEqual(['failed', 'queued']);
 });
 it('returns an error rather than an empty success on storage failure', async () => {
  const d = deps(); d.getExecutionRuns.mockRejectedValue(new Error('database unavailable'));
  expect((await readModelTrainingActivity({ userId: 'owner' }, d)).status).toBe(503);
 });
 it('rejects malformed project parameters', async () => {
  const d = deps(); expect((await readModelTrainingActivity({ userId: 'owner', project: ['p1'] }, d)).status).toBe(400);
  expect(d.getExecutionRuns).not.toHaveBeenCalled();
 });
});
it('requires exact training domain/path rather than loose model names', () => {
 expect(isModelTrainingRun(run({ workflowDefinition: { nextflow_path: '/workflows/ml_training/chemprop_train.nf' } }))).toBe(true);
 expect(isModelTrainingRun(run({ workflowDefinition: { workflow_domain: 'ml_training' } }))).toBe(true);
 for (const path of ['/not_ml_training/model.nf', '/model.nf?path=ml_training/train.nf', '/ml_training/../private.nf']) expect(isModelTrainingRun(run({ workflowDefinition: { nextflow_path: path } }))).toBe(false);
});

// Register the authenticated bridge before the broad Galaxy proxy.
it('routes Train through owned workflow activity before the legacy wildcard', async () => {
 const fs = await import('node:fs'); const path = await import('node:path');
 const source = fs.readFileSync(path.join(__dirname, 'routes.ts'), 'utf8');
 const start = source.indexOf('app.get("/api/model-tracks/train", authenticateToken');
 expect(start).toBeGreaterThan(-1);
 expect(start).toBeLessThan(source.indexOf('app.all("/api/model-tracks/*"'));
 expect(source.slice(start, source.indexOf('app.post("/api/model-tracks/adapt/retrain"', start))).toContain('storage.getExecutionRuns(uid, project');
});

it('retains owned adaptation retrains recorded as training execution runs', async () => {
 const d = deps([run({ workflowName: 'Adaptation retrain', workflowDefinition: { workflow_type: 'training' } })]);
 const result = await readModelTrainingActivity({ userId: 'owner' }, d);
 expect(result).toMatchObject({ status: 200, body: { runs: [{ runId: 'run-1', name: 'Adaptation retrain' }] } });
});
