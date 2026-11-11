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

it('includes the owned adaptation handler training execution record', async () => {
 const d = deps([run({ workflowName: 'Adaptation retrain', workflowDefinition: { workflow_type: 'training' } })]);
 const result = await readModelTrainingActivity({ userId: 'owner' }, d);
 expect((result.body as any).runs[0].name).toBe('Adaptation retrain');
 expect((result.body as any).runs[0].family).toBe('adaptation');
 expect((result.body as any).runs[0]).not.toHaveProperty('modelId');
});

// Real metrics.json shape written by the ml_training trainer (dev run 32e60784, 2026-11-11).
const REAL_METRICS = {
  name: 'live-journey-tabular',
  metrics: { cv_accuracy_mean: 0.8958333333333334, accuracy: 0.8958333333333334, auc: 0.95, macro_f1: 0.8956497660306303 },
  gate: { gates: [{ name: 'accuracy', measured: 0.8958333333333334, threshold: 0.6, status: 'pass', direction: 'higher_is_better' }] },
};

describe('training result (score + gate) in 训练运行', () => {
  const completed = (over: Partial<TrainingActivityRun['execution']> = {}): TrainingActivityRun => ({
    id: 'run-1', userId: 'u1', workflowName: 'live-journey-tabular',
    workflowDefinition: { nextflow_path: 'ml_training/chemprop_train.nf' },
    execution: { status: 'completed', ...over }, createdAt: '2026-11-11T05:00:00Z', updatedAt: '2026-11-11T05:02:00Z',
  });

  it('summarizes the gate (preferred) from a real trainer metrics.json', async () => {
    const { summarizeTrainingMetrics } = await import('./model-training-activity');
    expect(summarizeTrainingMetrics(REAL_METRICS)).toEqual({ metric: 'accuracy', value: 0.8958333333333334, gate: 'pass', threshold: 0.6 });
    expect(summarizeTrainingMetrics({ metrics: { rmse: 1.2, r2: 0.7 } })).toEqual({ metric: 'r2', value: 0.7, gate: null, threshold: null });
    expect(summarizeTrainingMetrics(null)).toBeNull();
    expect(summarizeTrainingMetrics({ metrics: {} })).toBeNull();
  });

  it('backfills a completed run once and returns structured result fields', async () => {
    const run = completed();
    const load = vi.fn(async () => REAL_METRICS);
    const save = vi.fn(async () => undefined);
    const res: any = await readModelTrainingActivity({ userId: 'u1' }, {
      getUserProjects: async () => [], getExecutionRuns: async () => [run], loadTrainingMetrics: load, saveTrainingSummary: save,
    });
    expect(load).toHaveBeenCalledTimes(1);
    expect(save).toHaveBeenCalledWith('run-1', { metric: 'accuracy', value: 0.8958333333333334, gate: 'pass', threshold: 0.6 });
    const row = res.body.runs[0];
    expect(row).toMatchObject({ metricName: 'accuracy', gateStatus: 'pass', gateThreshold: 0.6, gate: 'pass' });
    expect(row.metric).toBe('accuracy 0.896');
  });

  it('does not re-read a run that already has a result, and leaves runs without metrics not recorded', async () => {
    const load = vi.fn(async () => null);
    const done = completed({ trainingSummary: { metric: 'auc', value: 0.95, gate: null, threshold: null } });
    const failed: TrainingActivityRun = { ...completed(), id: 'run-2', execution: { status: 'failed' } };
    const res: any = await readModelTrainingActivity({ userId: 'u1' }, {
      getUserProjects: async () => [], getExecutionRuns: async () => [done, failed], loadTrainingMetrics: load,
    });
    expect(load).not.toHaveBeenCalled();
    const byId = Object.fromEntries(res.body.runs.map((r: any) => [r.runId, r]));
    expect(byId['run-1'].metric).toBe('auc 0.950');
    expect(byId['run-2']).toMatchObject({ metric: 'Not recorded', gate: 'Not recorded' });
    expect(byId['run-2'].metricName).toBeUndefined();
  });
});
