import { buildNextflowLaunchParameters } from './nextflow-launch-params';
import { isModelTrainingRun, type TrainingActivityRun } from './model-training-activity';

export interface RegistrationRun extends TrainingActivityRun {
 execution: TrainingActivityRun['execution'] & { trainingLaunchParameters?: Record<string, unknown> };
}
export interface CanonicalTrainingOutput { s3Uri: string; name?: string }
export interface ModelRegistrationDependencies {
 listOutputs(runId: string): Promise<CanonicalTrainingOutput[]>;
 internalRequest(path: string, body?: unknown): Promise<{ status: number; body: any }>;
}
export class TrainingRegistrationError extends Error {
 constructor(public status: number, message: string) { super(message); }
}
const fail = (message: string): never => { throw new TrainingRegistrationError(409, message); };
function source(uri: string): { bucket: string; key: string } {
 const match = /^s3:\/\/([^/?#]+)\/([^?#\0]+)$/.exec(uri);
 if (!match) return fail('Training outputs must be canonical S3 references.');
 return { bucket: match[1], key: match[2] };
}
function checkOwner(userId: string | undefined | null, run: RegistrationRun): void {
 if (!userId) throw new TrainingRegistrationError(401, 'Authentication required');
 if (!run.userId || run.userId !== userId) throw new TrainingRegistrationError(403, 'Only the training run owner can register or inspect its model versions.');
}
export function buildTrainingRegistrationManifest(userId: string, run: RegistrationRun, outputs: CanonicalTrainingOutput[]) {
 checkOwner(userId, run);
 if (!isModelTrainingRun(run) || !['completed', 'failed'].includes(run.execution.status)) return fail('A terminal model-training run is required.');
 const snapshot = run.execution.trainingLaunchParameters;
 if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) return fail('The exact training launch parameters were not recorded for this run. Historical model settings cannot be inferred safely.');
 const params = buildNextflowLaunchParameters(undefined, snapshot);
 const required = (key: string): string => typeof params[key] === 'string' && String(params[key]).trim() ? String(params[key]) : fail(`Recorded training parameter ${key} is missing.`);
 const modelName = required('model_name'), modelType = required('model_type'), taskType = required('task_type'), metric = required('metric');
 const threshold = params.gate_threshold === undefined || params.gate_threshold === null ? null : Number(params.gate_threshold);
 if (threshold !== null && !Number.isFinite(threshold)) return fail('Recorded model gate threshold is invalid.');
 // Same explicit metric direction as training_job._metric_direction; unknown metrics must not be guessed.
 const lower = new Set(['mae', 'mse', 'rmse', 'loss', 'cross_entropy']);
 const higher = new Set(['auc', 'accuracy', 'f1', 'r2', 'prc_auc']);
 if (!lower.has(metric) && !higher.has(metric)) return fail('Recorded model gate metric direction is not supported.');
 const candidates = outputs.map(output => ({ output, ...source(output.s3Uri) }));
 const artifacts = candidates.filter(item => /(?:^|\/)artifact\/.+/.test(item.key));
 if (!artifacts.length) return fail('This run has no published model artifacts.');
 // Handle artifact/model.pkl at root without requiring a leading slash.
 const artifactBase = (key: string) => key.startsWith('artifact/') ? '' : key.slice(0, key.lastIndexOf('/artifact/') + 1);
 const bases = new Set(artifacts.map(item => `${item.bucket}/${artifactBase(item.key)}`));
 if (bases.size !== 1) return fail('Multiple model artifact trees are ambiguous.');
 const first = artifacts[0], base = artifactBase(first.key);
 const metrics = candidates.filter(item => item.bucket === first.bucket && item.key === `${base}metrics.json`);
 if (metrics.length !== 1) return fail('The exact model training metrics output is missing or ambiguous.');
 return {
  run: { run_id: run.id, owner_id: userId, project_id: run.projectId ?? null, status: run.execution.status,
   model_name: modelName, model_type: modelType, task_type: taskType, metric, gate_threshold: threshold, higher_is_better: higher.has(metric) },
  artifacts: artifacts.map(item => ({ s3_uri: item.output.s3Uri, relative_path: item.key.slice(base.length + 'artifact/'.length) })),
  metrics_s3_uri: metrics[0].output.s3Uri,
 };
}
export async function registerOwnedTrainingRun(userId: string | undefined | null, run: RegistrationRun, deps: ModelRegistrationDependencies) {
 checkOwner(userId, run);
 const manifest = buildTrainingRegistrationManifest(userId!, run, await deps.listOutputs(run.id));
 return deps.internalRequest('/api/internal/model-training/register', manifest);
}
export async function readOwnedTrainingVersions(userId: string | undefined | null, run: RegistrationRun, deps: Pick<ModelRegistrationDependencies, 'internalRequest'>) {
 checkOwner(userId, run);
 const query = new URLSearchParams({ owner_id: userId!, run_id: run.id });
 if (run.projectId) query.set('project_id', run.projectId);
 return deps.internalRequest(`/api/internal/model-training/versions?${query}`);
}
/** Privileged bridge: credentials come only from server configuration, never the user request. */
export async function requestInternalModelRegistry(path: string, body?: unknown): Promise<{status: number;body: any}> {
 const key = process.env.GALAXY_API_KEY;
 if (!key) throw new TrainingRegistrationError(503, "Saved models aren't set up on this environment yet.");
 const response = await fetch(`${process.env.GALAXY_URL || 'http://localhost:8081'}${path}`, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { 'X-API-Key': key, ...(body === undefined ? {} : {'Content-Type': 'application/json'}) },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(120000),
 });
 const result = await response.json().catch(() => ({ error: "Couldn't read the saved-models response — try again in a moment." }));
 return { status: response.status, body: result };
}
