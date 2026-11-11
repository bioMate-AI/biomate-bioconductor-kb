/** Read owned training activity without inferring registration or reading global campaigns. */
export interface TrainingActivityRun {
 id: string; userId?: string; projectId?: string; chatSessionId?: string; workflowName: string;
 workflowDefinition?: unknown;
 execution: { status: string; trainingLaunchParameters?: Record<string, unknown>; trainingSummary?: TrainingSummary | null;
   nextflowStatus?: { s3_output_files?: unknown[]; output_files?: unknown[] } | null; nextflowRunId?: string };
 inputBindings?: Array<{ name?: string; datasetId: string }>;
 createdAt: Date | string; updatedAt: Date | string;
}
/** The trained model's headline result, read from the run's metrics.json (written by the
 *  ml_training trainer: metrics + gate). Recorded once on the run, then shown in 训练运行. */
export interface TrainingSummary { metric: string; value: number; gate: 'pass' | 'fail' | null; threshold: number | null }
export interface ModelTrainingActivityDependencies {
 getUserProjects(userId: string): Promise<Array<{ id?: string | null }> | undefined>;
 getExecutionRuns(userId: string, projectId?: string): Promise<TrainingActivityRun[]>;
 /** Read the completed run's metrics.json (null when absent/unreadable). */
 loadTrainingMetrics?(run: TrainingActivityRun): Promise<unknown | null>;
 /** Persist the summary on the run so later reads don't re-fetch. */
 saveTrainingSummary?(runId: string, summary: TrainingSummary): Promise<void>;
}

const METRIC_PRIORITY = ['accuracy', 'auc', 'macro_f1', 'f1', 'r2', 'rmse', 'mae', 'pr_auc'];
/** Headline metric + gate from a trainer metrics.json ({metrics:{…}, gate:{gates:[…]}}). */
export function summarizeTrainingMetrics(doc: unknown): TrainingSummary | null {
 if (!doc || typeof doc !== 'object') return null;
 const d = doc as Record<string, any>;
 const gate = Array.isArray(d.gate?.gates) ? d.gate.gates.find((g: any) => g && typeof g.measured === 'number') : null;
 if (gate) {
  const status = gate.status === 'pass' ? 'pass' : gate.status === 'fail' ? 'fail' : null;
  return { metric: String(gate.name), value: gate.measured, gate: status, threshold: typeof gate.threshold === 'number' ? gate.threshold : null };
 }
 const metrics = d.metrics && typeof d.metrics === 'object' ? d.metrics as Record<string, unknown> : null;
 if (!metrics) return null;
 const name = METRIC_PRIORITY.find((k) => typeof metrics[k] === 'number') ?? Object.keys(metrics).find((k) => typeof metrics[k] === 'number');
 return name ? { metric: name, value: metrics[name] as number, gate: null, threshold: null } : null;
}
export interface ModelTrainingActivityRow {
 runId: string; chatSessionId?: string; projectId?: string; name: string; family: 'ml_training' | 'adaptation';
 when: string; createdAt: string | null; updatedAt: string | null; status: string;
 gate: string; metric: string; dataset: string; registrationEligible: boolean;
 /** Structured result for the panel to format in the active language (absent → not recorded). */
 metricName?: string; metricValue?: number; gateStatus?: 'pass' | 'fail' | null; gateThreshold?: number | null;
}
function isAdaptationCompileRun(wf: Record<string, unknown>): boolean {
 if (wf.workflow_type === 'adaptation') return true;
 const steps = wf.steps && typeof wf.steps === 'object' ? Object.values(wf.steps as Record<string, any>) : [];
 return steps.some(step => step && typeof step === 'object' && step.tool_id === 'adapt_compile');
}
export function isModelTrainingRun(run: TrainingActivityRun): boolean {
 const wf = run.workflowDefinition as Record<string, unknown> | undefined;
 if (!wf || typeof wf !== 'object' || Array.isArray(wf)) return false;
 // House-style "Adaptation retrain" (prompt-rules compile over edit pairs) was
 // registered as workflow_type 'training' but trains no model and writes no
 // metrics — it only ever showed "Not recorded" here. It stays in Run Manager.
 if (isAdaptationCompileRun(wf)) return false;
 if (wf.workflow_type === 'training') return true;
 if (wf.domain === 'ml_training' || wf.workflow_domain === 'ml_training') return true;
 return typeof wf.nextflow_path === 'string' && !/[?#\0]/.test(wf.nextflow_path) && /(?:^|\/)ml_training\/[^/]+\.nf$/.test(wf.nextflow_path);
}
function iso(value: Date | string): string | null {
 const date = value instanceof Date ? value : new Date(value);
 return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}
export function toModelTrainingActivityRow(run: TrainingActivityRun): ModelTrainingActivityRow {
 const createdAt = iso(run.createdAt);
 return { runId: run.id, ...(run.chatSessionId ? { chatSessionId: run.chatSessionId } : {}),
  ...(run.projectId ? { projectId: run.projectId } : {}), name: run.workflowName, family: (run.workflowDefinition as any)?.workflow_type === 'training' && (run.workflowDefinition as any)?.domain !== 'ml_training' ? 'adaptation' : 'ml_training',
  when: createdAt ?? 'Not recorded', createdAt, updatedAt: iso(run.updatedAt), status: run.execution.status,
  // Resource/runtime metrics do not establish training quality; the trainer's own metrics.json does.
  gate: run.execution.trainingSummary?.gate ?? 'Not recorded',
  metric: run.execution.trainingSummary ? `${run.execution.trainingSummary.metric} ${run.execution.trainingSummary.value.toFixed(3)}` : 'Not recorded',
  ...(run.execution.trainingSummary ? {
   metricName: run.execution.trainingSummary.metric, metricValue: run.execution.trainingSummary.value,
   gateStatus: run.execution.trainingSummary.gate, gateThreshold: run.execution.trainingSummary.threshold,
  } : {}),
  registrationEligible: !!run.execution.trainingLaunchParameters && ['completed', 'failed'].includes(run.execution.status),
  dataset: run.inputBindings?.map(b => b.name || b.datasetId).join(', ')
   // Panel-launched runs bind their dataset as a staged s3 param; the plan records the project file name.
   || (typeof (run.workflowDefinition as any)?.source_dataset_name === 'string' && (run.workflowDefinition as any).source_dataset_name)
   || 'Not recorded' };
}
export async function readModelTrainingActivity(
 input: { userId?: string | null; project?: unknown }, dependencies: ModelTrainingActivityDependencies,
): Promise<{ status: number; body: { runs: ModelTrainingActivityRow[] } | { error: string } }> {
 const { userId } = input;
 if (!userId) return { status: 401, body: { error: 'Authentication required' } };
 if (input.project !== undefined && (typeof input.project !== 'string' || !input.project.trim())) return { status: 400, body: { error: 'Invalid project' } };
 const project = input.project as string | undefined;
 try {
  if (project) {
   const projects = await dependencies.getUserProjects(userId);
   if (!projects?.some(p => p.id === project)) return { status: 403, body: { error: 'Project access denied' } };
  }
  const runs = await dependencies.getExecutionRuns(userId, project);
  // Verify ownership again in case an adapter or cache fails to apply its filters.
  const owned = runs.filter(r => r.userId === userId && (!project || r.projectId === project) && isModelTrainingRun(r));
  owned.sort((a, b) => (iso(b.createdAt) ?? '').localeCompare(iso(a.createdAt) ?? ''));
  // Backfill the result for completed runs once (bounded per request), then it's on the run.
  if (dependencies.loadTrainingMetrics) {
   const pending = owned.filter(r => r.execution.status === 'completed' && r.execution.trainingSummary === undefined).slice(0, 8);
   await Promise.all(pending.map(async (r) => {
    const doc = await dependencies.loadTrainingMetrics!(r).catch((error) => {
     // Not fatal for the list, but never silent: a failing reader hid every score.
     console.warn(`[model-training-activity] metrics for run ${r.id} unreadable:`, error instanceof Error ? error.message : error);
     return null;
    });
    const summary = summarizeTrainingMetrics(doc);
    if (!summary) return;
    r.execution = { ...r.execution, trainingSummary: summary };
    await dependencies.saveTrainingSummary?.(r.id, summary).catch(() => undefined);
   }));
  }
  return { status: 200, body: { runs: owned.map(toModelTrainingActivityRow) } };
 } catch { return { status: 503, body: { error: 'Could not load model training activity' } }; }
}
