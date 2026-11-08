/** Read owned training activity without inferring registration or reading global campaigns. */
export interface TrainingActivityRun {
 id: string; userId?: string; projectId?: string; chatSessionId?: string; workflowName: string;
 workflowDefinition?: unknown; execution: { status: string; trainingLaunchParameters?: Record<string, unknown> };
 inputBindings?: Array<{ name?: string; datasetId: string }>;
 createdAt: Date | string; updatedAt: Date | string;
}
export interface ModelTrainingActivityDependencies {
 getUserProjects(userId: string): Promise<Array<{ id?: string | null }> | undefined>;
 getExecutionRuns(userId: string, projectId?: string): Promise<TrainingActivityRun[]>;
}
export interface ModelTrainingActivityRow {
 runId: string; chatSessionId?: string; projectId?: string; name: string; family: 'ml_training' | 'adaptation';
 when: string; createdAt: string | null; updatedAt: string | null; status: string;
 gate: string; metric: string; dataset: string; registrationEligible: boolean;
}
export function isModelTrainingRun(run: TrainingActivityRun): boolean {
 const wf = run.workflowDefinition as Record<string, unknown> | undefined;
 if (!wf || typeof wf !== 'object' || Array.isArray(wf)) return false;
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
  // Resource/runtime metrics do not establish training quality or registry identity.
  gate: 'Not recorded', metric: 'Not recorded',
  registrationEligible: !!run.execution.trainingLaunchParameters && ['completed', 'failed'].includes(run.execution.status),
  dataset: run.inputBindings?.map(b => b.name || b.datasetId).join(', ') || 'Not recorded' };
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
  return { status: 200, body: { runs: owned.map(toModelTrainingActivityRow) } };
 } catch { return { status: 503, body: { error: 'Could not load model training activity' } }; }
}
