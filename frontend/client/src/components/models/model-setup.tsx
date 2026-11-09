import { useEffect, useState } from 'react';
import { useActiveProjectSafe } from '@/contexts/active-project-context';
import { Button } from '@/components/ui/button';
import { tOr } from '@/lib/i18n';

interface ProjectFile { id: string; name: string }
export function modelSetupUrl(projectId: string, fileId: string, draft: string, extraFileId?: string) {
  const params = new URLSearchParams({ project: projectId, attachFile: fileId, draft });
  if (extraFileId && extraFileId !== fileId) params.append('attachFile', extraFileId);
  return `/?${params.toString()}`;
}

/** Setup produces a reviewable chat draft using the existing attachment bridge.
 * Sending the draft still requires the ordinary workflow proposal/confirmation. */
export function ModelSetup({ rounds = false, onContinue }: { rounds?: boolean; onContinue?: (url: string) => void }) {
  const context = useActiveProjectSafe();
  const [project, setProject] = useState(context?.activeProjectId ?? '');
  const [files, setFiles] = useState<ProjectFile[]>([]);
  const [file, setFile] = useState('');
  const [candidate, setCandidate] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [target, setTarget] = useState('');
  const [type, setType] = useState('sklearn_tabular');
  const [task, setTask] = useState('classification');
  const [modelName, setModelName] = useState('');
  const [metric, setMetric] = useState('accuracy');
  const [gate, setGate] = useState('0.7');
  const [budget, setBudget] = useState('96');
  useEffect(() => {
    setFiles([]); setFile(''); setCandidate(''); setError('');
    if (!project) { setLoading(false); return; }
    const controller = new AbortController(); setLoading(true);
    fetch(`/api/projects/${encodeURIComponent(project)}/files`, { credentials: 'include', signal: controller.signal })
      .then(async response => { if (!response.ok) throw new Error(tOr('models.setup_files_error', 'Could not load project datasets.')); return response.json(); })
      .then(body => { if (!controller.signal.aborted) setFiles(body.files ?? []); })
      .catch(cause => { if (!controller.signal.aborted) setError(cause.message); })
      .finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [project]);
  const field = 'block w-full rounded border bg-background px-2 py-1.5 text-sm';
  const valid = project && file && target.trim() && (rounds ? candidate && Number.isInteger(Number(budget)) && Number(budget) > 0 : Number.isFinite(Number(gate)) && gate.trim() && (metric === 'r2' || Number(gate) >= 0) && Number(gate) <= 1);
  return <form className="space-y-3 rounded border p-3" data-testid={rounds ? 'rounds-setup' : 'training-setup'} onSubmit={event => {
    event.preventDefault(); if (!valid) return;
    const selected = files.find(item => item.id === file);
    const draft = rounds
      ? `Prepare a design–make–test–analyse loop for ${target.trim()}. Use project assay dataset ${selected?.name} (file ID ${file}) and candidate library ${files.find(item => item.id === candidate)?.name} (file ID ${candidate}). Proposal budget: ${budget} assays. Preserve measured/predicted distinctions and held-out data. Propose configuration for my confirmation; stop for real measurements, never fabricate assay results or mark a round started.`
      : `Prepare model training using project dataset ${selected?.name} (file ID ${file}). Target/label column: ${target.trim()}. target_col=${target.trim()}; model_type=${type}; model_name=${modelName.trim() || target.trim()}; task_type=${task}; metric=${metric}; gate_threshold=${gate}; split=${type === 'sklearn_tabular' ? 'kfold, cv_folds=5' : 'scaffold'}. Exclude sample identifiers from predictors and prevent label leakage. Requested acceptance criterion: held-out ${metric} >= ${gate}; explain whether this gate can be enforced and report actual validation evidence. Propose the workflow and input mapping for my confirmation before execution. Do not claim training has started or a model exists.`;
    context?.setActiveProjectId(project);
    const url = modelSetupUrl(project, file, draft, rounds ? candidate : undefined);
    if (onContinue) onContinue(url); else window.location.assign(url);
  }}>
    <p className="text-sm font-semibold">{rounds ? tOr('models.setup_rounds', 'Configure a design round') : tOr('models.setup_train', 'Configure training')}</p>
    <p className="text-xs text-muted-foreground">{tOr('models.setup_review', 'Continue to chat to review the request and confirm the workflow. Nothing starts here.')}</p>
    <label className="block text-xs">{tOr('models.setup_project', 'Project')}<select className={field} value={project} onChange={event => setProject(event.target.value)} required><option value="">{tOr('models.setup_choose_project', 'Choose a project')}</option>{context?.projects.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
    <label className="block text-xs">{tOr('models.setup_dataset', 'Dataset')}<select className={field} value={file} disabled={loading || !project} onChange={event => setFile(event.target.value)} required><option value="">{loading ? tOr('models.setup_loading', 'Loading datasets…') : tOr('models.setup_choose_dataset', 'Choose a project file')}</option>{files.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
    {project && !loading && !error && !files.length && <p className="text-xs">{tOr('models.setup_no_files', 'Add a dataset to this project in Files first.')}</p>}
    <label className="block text-xs">{rounds ? tOr('models.setup_objective', 'Design objective and target') : tOr('models.setup_target', 'Target / label column')}<input className={field} value={target} onChange={event => setTarget(event.target.value)} required /></label>
    {rounds ? <>
      <label className="block text-xs">{tOr('models.setup_candidates', 'Candidate library')}<select className={field} value={candidate} onChange={event => setCandidate(event.target.value)} required><option value="">{tOr('models.setup_choose_dataset', 'Choose a project file')}</option>{files.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label className="block text-xs">{tOr('models.setup_budget', 'Assay proposal budget')}<input className={field} type="number" min="1" step="1" value={budget} onChange={event => setBudget(event.target.value)} required /></label>
    </> : <>
      <label className="block text-xs">{tOr('models.setup_type', 'Model type')}<select className={field} value={type} onChange={event => setType(event.target.value)}><option value="sklearn_tabular">{tOr('models.setup_tabular', 'Tabular classifier / regressor (scikit-learn)')}</option><option value="sklearn_gbr">{tOr('models.setup_molecular_gbr', 'Molecular property baseline (RDKit descriptors + gradient boosting)')}</option><option value="ludwig_tabular">{tOr('models.setup_molecular_dl', 'Molecular deep-learning model (Ludwig neural net)')}</option></select></label>
      <label className="block text-xs">{tOr('models.setup_name', 'Model name')}<input className={field} value={modelName} placeholder={target} onChange={event => setModelName(event.target.value)} /></label>
      <label className="block text-xs">{tOr('models.setup_task', 'Task type')}<select className={field} value={task} onChange={event => { setTask(event.target.value); setMetric(event.target.value === 'regression' ? 'r2' : 'accuracy'); }}><option value="classification">{tOr('models.setup_classification', 'Classification')}</option><option value="regression">{tOr('models.setup_regression', 'Regression')}</option></select></label>
      <label className="block text-xs">{tOr('models.setup_metric', 'Validation metric')}<select className={field} value={metric} onChange={event => setMetric(event.target.value)}>{task === 'regression' ? <option value="r2">R²</option> : <><option value="accuracy">{tOr('models.setup_accuracy', 'Accuracy')}</option><option value="auc">ROC AUC</option><option value="f1">F1</option><option value="prc_auc">PR AUC</option></>}</select></label>
      <label className="block text-xs">{tOr('models.setup_gate', 'Minimum acceptable metric')}<input className={field} type="number" min={metric === 'r2' ? undefined : 0} max="1" step="any" value={gate} onChange={event => setGate(event.target.value)} required /></label>
    </>}
    {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
    <Button type="submit" disabled={!valid || loading}>{tOr('models.setup_continue', 'Review in chat')}</Button>
  </form>;
}
