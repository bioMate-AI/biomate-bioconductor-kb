/**
 * POST /api/model-training/plan — Models-panel structured training plan.
 *
 * The panel sends structured fields (project, project file(s) or folder, target
 * column, model type, metric, gate …). This route:
 *   1. requires an authenticated user who can read the project (owner/member);
 *   2. resolves project file(s) from the DB (never from the client) — a single
 *      fileId, an explicit fileIds[], or a folderPath (all input files under
 *      that prefix);
 *   3. stages each file into the Batch-readable bucket (same helper the execute
 *      path uses for project files), because the project bucket is not readable
 *      by the training container on SaaS;
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
  /** Every input file under a folder path prefix (recursive), same auth as getProjectFile. */
  listFolderFiles?(projectId: string, folderPath: string, userId: string): Promise<PlanProjectFile[]>;
  /** Copy the project file to a Batch-readable s3:// URI (undefined on failure). */
  stageForBatch(file: PlanProjectFile, projectId: string): Promise<string | undefined>;
  /** Admin-keyed Galaxy call. */
  requestGalaxyPlan(userId: string, body: Record<string, unknown>): Promise<{ status: number; body: any }>;
}

/** Fields the panel may set. Dataset location/identity is always server-resolved. */
export const PLAN_FORWARDED_FIELDS = [
  'model_type', 'task_type', 'target_col', 'smiles_col', 'featurizer', 'metric',
  'gate_threshold', 'model_name', 'epochs', 'learning_rate', 'llm', 'sc', 'diffusion',
  // Adaptation: the registered model this run adapts (→ registers as its next version).
  // The backend validates it; dataset identity stays server-resolved.
  'adapt_of',
] as const;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function parseFileIds(body: Record<string, unknown>): string[] {
  if (Array.isArray(body.fileIds)) {
    return [...new Set(body.fileIds.map((x) => String(x).trim()).filter((id) => UUID_RE.test(id)))];
  }
  const single = typeof body.fileId === 'string' ? body.fileId.trim() : '';
  return UUID_RE.test(single) ? [single] : [];
}

function parseFolderPath(body: Record<string, unknown>): string | null {
  if (typeof body.folderPath !== 'string') return null;
  // Mirror project-folders.normalizeFolderPath lightly (no ".." / empty segments).
  const segs = body.folderPath.replace(/\\/g, '/').split('/').map((s) => s.trim()).filter((s) => s !== '' && s !== '.');
  if (segs.includes('..') || segs.length > 32) return null;
  if (segs[0] === 'inputs') segs.shift();
  return segs.join('/');
}

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
  if (!UUID_RE.test(projectId)) {
    return { status: 400, body: { error: 'projectId must identify a project' } };
  }

  const folderPath = parseFolderPath(body);
  const hasFolderField = typeof body.folderPath === 'string';
  if (hasFolderField && folderPath === null) {
    return { status: 400, body: { error: 'folderPath is invalid' } };
  }

  let files: PlanProjectFile[] = [];
  try {
    if (folderPath !== null && folderPath !== undefined && hasFolderField) {
      if (!deps.listFolderFiles) {
        return { status: 500, body: { error: 'Folder listing is not configured' } };
      }
      files = await deps.listFolderFiles(projectId, folderPath, userId);
      if (!files.length) return { status: 404, body: { error: 'Folder has no input files' } };
    } else {
      const fileIds = parseFileIds(body);
      if (!fileIds.length) {
        return { status: 400, body: { error: 'projectId and fileId (or fileIds / folderPath) must identify project file(s)' } };
      }
      for (const fileId of fileIds) {
        const file = await deps.getProjectFile(projectId, fileId, userId);
        if (!file) return { status: 404, body: { error: 'Project file not found' } };
        files.push(file);
      }
    }
  } catch {
    return { status: 503, body: { error: 'Could not read project files' } };
  }

  const staged: Array<{ file: PlanProjectFile; uri: string }> = [];
  for (const file of files) {
    const datasetUri = await deps.stageForBatch(file, projectId).catch(() => undefined);
    if (!datasetUri || !datasetUri.startsWith('s3://')) {
      return { status: 502, body: { error: 'Could not stage the dataset for training. No run was started.' } };
    }
    staged.push({ file, uri: datasetUri });
  }

  const primary = staged[0];
  const forwarded: Record<string, unknown> = {
    dataset_s3_uri: primary.uri,
    dataset_name: primary.file.name,
    project_id: projectId,
  };
  if (staged.length > 1) {
    forwarded.dataset_s3_uris = staged.map((s) => s.uri);
    forwarded.dataset_names = staged.map((s) => s.file.name);
  }
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
  const fileIds = files.map((f) => f.id);
  return {
    status: 200,
    body: {
      ...plan,
      projectId,
      fileId: fileIds[0],
      fileIds,
      ...(hasFolderField ? { folderPath } : {}),
    },
  };
}
