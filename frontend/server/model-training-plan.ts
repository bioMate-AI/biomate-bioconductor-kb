/**
 * POST /api/model-training/plan — Models-panel structured training plan.
 *
 * The panel sends structured fields (project, project file, target column,
 * model type, metric, gate …). This route:
 *   1. requires an authenticated user who can read the project (owner/member);
 *   2. resolves the project file's S3 key from the DB (never from the client);
 *   3. stages it into the Batch-readable bucket (same helper the execute path
 *      uses for project files), because the project bucket is not readable by
 *      the training container on SaaS;
 *   4. forwards a whitelisted body to Galaxy POST /api/model-training/plan with
 *      the admin key + X-BioMate-User-Id (fetchOwnedModelSurface).
 * The client then submits the returned workflow_ga through the ordinary
 * POST /api/workflows/execute, so the run gets a run record, SSE, billing and
 * Run Manager visibility. Nothing is executed here.
 */
export interface PlanProjectFile { id: string; name: string; s3_key: string }

export interface ModelTrainingPlanDependencies {
  /** The file, only when it belongs to the project AND the user can read the project. */
  getProjectFile(projectId: string, fileId: string, userId: string): Promise<PlanProjectFile | null>;
  /** Copy the project file to a Batch-readable s3:// URI (undefined on failure). */
  stageForBatch(file: PlanProjectFile, projectId: string): Promise<string | undefined>;
  /** Admin-keyed Galaxy call. */
  requestGalaxyPlan(userId: string, body: Record<string, unknown>): Promise<{ status: number; body: any }>;
}

/** Fields the panel may set. Dataset location/identity is always server-resolved. */
export const PLAN_FORWARDED_FIELDS = [
  'model_type', 'task_type', 'target_col', 'smiles_col', 'featurizer', 'metric',
  'gate_threshold', 'model_name', 'epochs', 'learning_rate', 'llm', 'sc', 'diffusion',
] as const;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function planModelTraining(
  input: { userId?: string | null; body: unknown },
  deps: ModelTrainingPlanDependencies,
): Promise<{ status: number; body: any }> {
  const userId = input.userId ? String(input.userId) : '';
  if (!userId) return { status: 401, body: { error: 'Authentication required' } };
  const body = (input.body && typeof input.body === 'object' && !Array.isArray(input.body))
    ? input.body as Record<string, unknown> : null;
  if (!body) return { status: 400, body: { error: 'Request body must be an object' } };
  const projectId = typeof body.projectId === 'string' ? body.projectId.trim() : '';
  const fileId = typeof body.fileId === 'string' ? body.fileId.trim() : '';
  if (!UUID_RE.test(projectId) || !UUID_RE.test(fileId)) {
    return { status: 400, body: { error: 'projectId and fileId must identify a project file' } };
  }

  let file: PlanProjectFile | null;
  try {
    file = await deps.getProjectFile(projectId, fileId, userId);
  } catch {
    return { status: 503, body: { error: 'Could not read project files' } };
  }
  // 404 (not 403) so another user's project/file existence is not revealed.
  if (!file) return { status: 404, body: { error: 'Project file not found' } };

  const datasetUri = await deps.stageForBatch(file, projectId).catch(() => undefined);
  if (!datasetUri || !datasetUri.startsWith('s3://')) {
    return { status: 502, body: { error: 'Could not stage the dataset for training. No run was started.' } };
  }

  const forwarded: Record<string, unknown> = {
    dataset_s3_uri: datasetUri,
    dataset_name: file.name,
    project_id: projectId,
  };
  for (const key of PLAN_FORWARDED_FIELDS) {
    if (body[key] !== undefined && body[key] !== null && body[key] !== '') forwarded[key] = body[key];
  }

  let result: { status: number; body: any };
  try {
    result = await deps.requestGalaxyPlan(userId, forwarded);
  } catch (error: any) {
    const status = typeof error?.status === 'number' ? error.status : 502;
    return { status, body: { error: status === 502 ? 'Training service unavailable' : String(error?.message || 'Training service error') } };
  }
  if (result.status !== 200) {
    const detail = result.body?.detail ?? result.body?.error;
    return { status: result.status >= 400 && result.status < 600 ? result.status : 502,
      body: { error: typeof detail === 'string' ? detail : 'Training plan was rejected' } };
  }
  const plan = result.body;
  if (!plan || typeof plan !== 'object' || !plan.workflow_ga || typeof plan.nextflow_path !== 'string') {
    return { status: 502, body: { error: 'Training service returned an invalid plan' } };
  }
  return { status: 200, body: { ...plan, projectId, fileId } };
}
