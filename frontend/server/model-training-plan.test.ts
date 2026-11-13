import { afterEach, describe, expect, it, vi } from 'vitest';
import { planModelTraining, PLAN_FORWARDED_FIELDS, type ModelTrainingPlanDependencies } from './model-training-plan';
import { fetchOwnedModelSurface } from './model-surface-access';

const PROJECT = '11111111-1111-4111-8111-111111111111';
const FILE = '22222222-2222-4222-8222-222222222222';
const FILE_ROW = { id: FILE, name: 'expression.jsonl', s3_key: `projects/${PROJECT}/inputs/expression.jsonl` };
const PLAN = { workflow_ga: { name: 'subtype classification model', domain: 'ml_training', parameters: {} },
  nextflow_path: 'ml_training/chemprop_train.nf', compute_config: { container: 'img' } };

function deps(overrides: Partial<ModelTrainingPlanDependencies> = {}) {
  return {
    getProjectFile: vi.fn(async () => FILE_ROW),
    stageForBatch: vi.fn(async () => `s3://biomate-nextflow-work/uploads/project-${PROJECT}/expression.jsonl`),
    requestGalaxyPlan: vi.fn(async () => ({ status: 200, body: PLAN })),
    ...overrides,
  } satisfies ModelTrainingPlanDependencies;
}

afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); });

describe('POST /api/model-training/plan contract', () => {
  it('requires authentication and a project file id pair', async () => {
    const d = deps();
    expect((await planModelTraining({ userId: undefined, body: {} }, d)).status).toBe(401);
    expect((await planModelTraining({ userId: 'u', body: { projectId: PROJECT } }, d)).status).toBe(400);
    expect((await planModelTraining({ userId: 'u', body: [] }, d)).status).toBe(400);
    expect(d.getProjectFile).not.toHaveBeenCalled();
  });

  it('returns 404 for a file the user cannot read, without staging or calling Galaxy', async () => {
    const d = deps({ getProjectFile: vi.fn(async () => null) });
    const r = await planModelTraining({ userId: 'u', body: { projectId: PROJECT, fileId: FILE } }, d);
    expect(r.status).toBe(404);
    expect(d.stageForBatch).not.toHaveBeenCalled();
    expect(d.requestGalaxyPlan).not.toHaveBeenCalled();
  });

  it('resolves the dataset server-side and forwards only whitelisted structured fields', async () => {
    const d = deps();
    const r = await planModelTraining({ userId: 'owner-1', body: {
      projectId: PROJECT, fileId: FILE, model_type: 'sklearn_tabular', task_type: 'classification',
      target_col: 'subtype', metric: 'accuracy', gate_threshold: 0.7, model_name: '',
      dataset_s3_uri: 's3://attacker/other.csv', user_id: 'victim',
    } }, d);
    expect(r.status).toBe(200);
    expect(d.getProjectFile).toHaveBeenCalledWith(PROJECT, FILE, 'owner-1');
    const [owner, sent] = d.requestGalaxyPlan.mock.calls[0] as unknown as [string, Record<string, unknown>];
    expect(owner).toBe('owner-1');
    expect(sent).toEqual({
      dataset_s3_uri: `s3://biomate-nextflow-work/uploads/project-${PROJECT}/expression.jsonl`,
      dataset_name: 'expression.jsonl', project_id: PROJECT,
      model_type: 'sklearn_tabular', task_type: 'classification', target_col: 'subtype',
      metric: 'accuracy', gate_threshold: 0.7,
    });
    expect(Object.keys(sent).every(k => ['dataset_s3_uri', 'dataset_name', 'project_id', ...PLAN_FORWARDED_FIELDS].includes(k as any))).toBe(true);
    expect(r.body).toMatchObject({ ...PLAN, projectId: PROJECT, fileId: FILE });
  });

  it('surfaces the Galaxy validation message as the error', async () => {
    const d = deps({ requestGalaxyPlan: vi.fn(async () => ({ status: 400, body: { detail: 'target_col is required: choose the column to predict' } })) });
    const r = await planModelTraining({ userId: 'u', body: { projectId: PROJECT, fileId: FILE, model_type: 'sklearn_tabular' } }, d);
    expect(r).toEqual({ status: 400, body: { error: 'target_col is required: choose the column to predict' } });
  });

  it('fails closed when staging fails or Galaxy returns an invalid plan', async () => {
    const noStage = deps({ stageForBatch: vi.fn(async () => undefined) });
    expect((await planModelTraining({ userId: 'u', body: { projectId: PROJECT, fileId: FILE } }, noStage)).status).toBe(502);
    expect(noStage.requestGalaxyPlan).not.toHaveBeenCalled();
    const bad = deps({ requestGalaxyPlan: vi.fn(async () => ({ status: 200, body: { ok: true } })) });
    expect((await planModelTraining({ userId: 'u', body: { projectId: PROJECT, fileId: FILE } }, bad)).status).toBe(502);
  });

  it('the admin bridge allows exactly the plan path', async () => {
    vi.stubEnv('GALAXY_API_KEY', 'k'); vi.stubEnv('GALAXY_URL', 'http://backend');
    const fetcher = vi.fn(async () => ({ status: 200 })); vi.stubGlobal('fetch', fetcher);
    await fetchOwnedModelSurface('owner', '/api/model-training/plan', { method: 'POST', body: '{}' });
    expect(fetcher).toHaveBeenCalledWith('http://backend/api/model-training/plan', expect.objectContaining({ method: 'POST' }));
    await expect(fetchOwnedModelSurface('owner', '/api/model-training/register')).rejects.toMatchObject({ status: 400 });
  });

  it('accepts fileIds[] and stages every file, forwarding dataset_s3_uris', async () => {
    const FILE2 = '33333333-3333-4333-8333-333333333333';
    const ROW2 = { id: FILE2, name: 'extra.csv', s3_key: `projects/${PROJECT}/inputs/extra.csv` };
    const d = deps({
      getProjectFile: vi.fn(async (_p, id) => id === FILE ? FILE_ROW : id === FILE2 ? ROW2 : null),
      stageForBatch: vi.fn(async (file) => `s3://biomate-nextflow-work/uploads/project-${PROJECT}/${file.name}`),
    });
    const r = await planModelTraining({
      userId: 'u',
      body: { projectId: PROJECT, fileIds: [FILE, FILE2], model_type: 'sklearn_tabular', target_col: 'y', task_type: 'classification', metric: 'accuracy' },
    }, d);
    expect(r.status).toBe(200);
    expect(d.getProjectFile).toHaveBeenCalledTimes(2);
    expect(d.stageForBatch).toHaveBeenCalledTimes(2);
    const sent = d.requestGalaxyPlan.mock.calls[0][1] as Record<string, unknown>;
    expect(sent.dataset_s3_uri).toContain('expression.jsonl');
    expect(sent.dataset_s3_uris).toEqual([
      `s3://biomate-nextflow-work/uploads/project-${PROJECT}/expression.jsonl`,
      `s3://biomate-nextflow-work/uploads/project-${PROJECT}/extra.csv`,
    ]);
    expect(r.body.fileIds).toEqual([FILE, FILE2]);
  });

  it('accepts folderPath and lists every file under the folder', async () => {
    const F1 = { id: FILE, name: 'train/a.csv', s3_key: `projects/${PROJECT}/inputs/train/a.csv` };
    const F2 = { id: '33333333-3333-4333-8333-333333333333', name: 'train/b.csv', s3_key: `projects/${PROJECT}/inputs/train/b.csv` };
    const d = deps({
      listFolderFiles: vi.fn(async () => [F1, F2]),
      stageForBatch: vi.fn(async (file) => `s3://biomate-nextflow-work/uploads/project-${PROJECT}/${file.name.split('/').pop()}`),
    });
    const r = await planModelTraining({
      userId: 'u',
      body: { projectId: PROJECT, folderPath: 'train', model_type: 'protein_diffusion' },
    }, d);
    expect(r.status).toBe(200);
    expect(d.listFolderFiles).toHaveBeenCalledWith(PROJECT, 'train', 'u');
    expect(d.getProjectFile).not.toHaveBeenCalled();
    expect(d.stageForBatch).toHaveBeenCalledTimes(2);
    expect(r.body).toMatchObject({ folderPath: 'train', fileIds: [F1.id, F2.id], fileId: F1.id });
    const sent = d.requestGalaxyPlan.mock.calls[0][1] as Record<string, unknown>;
    expect(sent.dataset_s3_uris).toHaveLength(2);
  });
});
