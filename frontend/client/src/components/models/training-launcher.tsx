/**
 * TrainingLauncher — configure and START a training run from the Models panel.
 *
 * No chat draft anywhere:
 *   project + project file → POST /api/perception/profile (real columns)
 *   → model type (filtered by what this file can actually train)
 *   → POST /api/model-training/plan (server stages the file; Galaxy validates
 *     the TrainingConfig and returns workflow_ga + container)
 *   → POST /api/workflows/execute (ordinary run: run record, SSE, billing,
 *     Run Manager) → inline run card polling the run status.
 *
 * family="general" is the 训练 tab (tabular ML/DL, LLM fine-tuning, scRNA /
 * protein diffusion); family="molecular" is the 分子学习 tab (SMILES models).
 * Every visible string comes from the models.* i18n namespace.
 */
import { useCallback, useEffect, useMemo, useState, type ChangeEvent } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useActiveProjectSafe } from '@/contexts/active-project-context';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Loader2, Play } from 'lucide-react';
import { t, tOr } from '@/lib/i18n';
import {
  availableModelTypes, backendModelType, columnValues, defaultModelName, detectSmilesColumns,
  fileKind, isDelimitedTable, isSupervised, LLM_TYPES, MIN_TRAIN_ROWS, metricIsCeiling, metricsFor, openRunManager, runStatusLabel, suggestTaskType, TERMINAL_STATUSES, unavailableReasonKey,
  type LauncherFamily, type PanelModelType, type TaskType,
} from './training-logic';
import { launchTraining, TrainingLaunchError, useRunStatus, type TrainingPlan } from './models-api';
import { SPEC_DEFAULTS, SPEC_FIELDS, specPayload, type SpecValues } from './training-specs';
import {
  buildDatasetOptions, encodeDatasetSelection, parseDatasetSelection, primaryTableForSelection,
  resolveSelectionToFileIds, type DatasetSelection,
} from './dataset-selection';

interface ProjectFile { id: string; name: string; s3_key: string; source?: string | null }

const FIELD = 'block w-full rounded border bg-background px-2 py-1.5 text-sm';

export function TrainingLauncher({ family, adaptOf, llmOnly }: { family: LauncherFamily; adaptOf?: string; llmOnly?: boolean }) {
  const context = useActiveProjectSafe();
  const queryClient = useQueryClient();
  const [project, setProject] = useState(context?.activeProjectId ?? '');
  const [files, setFiles] = useState<ProjectFile[]>([]);
  const [filesLoading, setFilesLoading] = useState(false);
  const [selectionValue, setSelectionValue] = useState('');
  const [columns, setColumns] = useState<string[]>([]);
  const [sampleRows, setSampleRows] = useState<unknown[][]>([]);
  const [profileState, setProfileState] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle');
  // Total data rows of the selected table (from the profile), null when unknown.
  const [rowCount, setRowCount] = useState<number | null>(null);
  const [modelType, setModelType] = useState<PanelModelType | ''>('');
  const [target, setTarget] = useState('');
  const [smilesCol, setSmilesCol] = useState('');
  const [task, setTask] = useState<TaskType>('classification');
  const [taskTouched, setTaskTouched] = useState(false);
  const [metric, setMetric] = useState('');
  const [gate, setGate] = useState('');
  const [modelName, setModelName] = useState('');
  const [nameTouched, setNameTouched] = useState(false);
  const [epochs, setEpochs] = useState('');
  const [spec, setSpec] = useState<SpecValues>({});
  const [busy, setBusy] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');
  const [runId, setRunId] = useState<string | null>(null);
  const [launched, setLaunched] = useState<TrainingPlan | null>(null);

  const selection: DatasetSelection | null = parseDatasetSelection(selectionValue);
  const file = primaryTableForSelection(files, selection, (n) => fileKind(n) === 'table');
  const selectedFileIds = resolveSelectionToFileIds(files, selection);
  const kind = file ? fileKind(file.name) : 'other';
  const datasetOptions = useMemo(() => buildDatasetOptions(files), [files]);

  // Load the project's files; returns them so callers (e.g. after an upload) can
  // select the one they just added.
  const loadFiles = useCallback(async (): Promise<ProjectFile[]> => {
    if (!project) { setFiles([]); setFilesLoading(false); return []; }
    setFilesLoading(true);
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(project)}/files`, { credentials: 'include' });
      if (!r.ok) throw new Error(t('models.setup_files_error'));
      const body = await r.json();
      const fs: ProjectFile[] = body.files ?? [];
      setFiles(fs);
      return fs;
    } catch (cause) {
      setError((cause as Error).message);
      return [];
    } finally {
      setFilesLoading(false);
    }
  }, [project]);

  // Sync the active project from context when the launcher has none yet — so a
  // user who just picked a project in the sidebar doesn't see an empty launcher
  // (never overrides an explicit choice they made here).
  useEffect(() => {
    if (context?.activeProjectId && !project) setProject(context.activeProjectId);
  }, [context?.activeProjectId]);  // eslint-disable-line react-hooks/exhaustive-deps

  // Project files.
  useEffect(() => {
    setFiles([]); setSelectionValue(''); setError('');
    loadFiles();
  }, [project, loadFiles]);

  // Upload a local dataset straight into the project and select it — so a user
  // starting from a file on disk never has to leave the panel to upload first.
  async function handleUpload(e: ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    e.target.value = '';  // allow re-selecting the same file later
    if (!f || !project) return;
    setUploading(true); setError('');
    try {
      const fd = new FormData();
      fd.append('file', f);
      fd.append('relativePath', f.name);
      const r = await fetch(`/api/projects/${encodeURIComponent(project)}/files/upload`, {
        method: 'POST', credentials: 'include', body: fd,
      });
      if (!r.ok) throw new Error(tOr('models.upload_error', 'Upload failed'));
      const fs = await loadFiles();
      const added = fs.find(x => x.name === f.name);
      if (added) setSelectionValue(encodeDatasetSelection({ kind: 'file', fileId: added.id }));
    } catch (cause) {
      setError((cause as Error).message);
    } finally {
      setUploading(false);
    }
  }

  // Real columns for the selected file / first table in a folder (tables only).
  useEffect(() => {
    setColumns([]); setSampleRows([]); setRowCount(null); setTarget(''); setSmilesCol(''); setModelType('');
    setTaskTouched(false); setNameTouched(false); setSpec({});
    if (!file) { setProfileState('idle'); return; }
    if (fileKind(file.name) !== 'table') { setProfileState('ready'); return; }
    const controller = new AbortController();
    setProfileState('loading');
    fetch('/api/perception/profile', {
      method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ datasetRef: file.s3_key }), signal: controller.signal,
    })
      .then(async r => { if (!r.ok) throw new Error(t('models.columns_error')); return r.json(); })
      .then(body => {
        if (controller.signal.aborted) return;
        const cols: string[] = Array.isArray(body?.columns) ? body.columns.map(String) : [];
        setColumns(cols);
        setSampleRows(Array.isArray(body?.sampleRows) ? body.sampleRows : []);
        // DataProfile.to_dict(): { shape: { rows, cols }, … } (backend ai/data_perception.py).
        const rows = body?.shape?.rows;
        setRowCount(typeof rows === 'number' && Number.isFinite(rows) ? rows : null);
        setProfileState(cols.length ? 'ready' : 'error');
      })
      .catch(cause => { if (!controller.signal.aborted) { setProfileState('error'); setError(cause.message); } });
    return () => controller.abort();
  }, [selectionValue, file?.id]);

  const smilesColumns = useMemo(() => detectSmilesColumns(columns, sampleRows), [columns, sampleRows]);
  const modelTypes = useMemo(
    () => {
      const avail = availableModelTypes(family, kind, columns, smilesColumns, sampleRows);
      // Fine-tuning an LLM base → only LLM methods (DPO/SFT/GRPO), never a tabular model.
      return llmOnly ? avail.filter((t) => LLM_TYPES.includes(t)) : avail;
    },
    [family, kind, columns, smilesColumns, sampleRows, llmOnly],
  );

  // Default the model type to the first one this dataset supports.
  useEffect(() => {
    if (modelTypes.length && !modelTypes.includes(modelType as PanelModelType)) setModelType(modelTypes[0]);
    if (!modelTypes.length) setModelType('');
  }, [modelTypes]);

  useEffect(() => {
    if (modelType && SPEC_DEFAULTS[modelType]) setSpec({ ...SPEC_DEFAULTS[modelType] });
    else setSpec({});
  }, [modelType]);

  useEffect(() => {
    if (smilesColumns.length && !smilesCol) setSmilesCol(smilesColumns[0]);
  }, [smilesColumns]);

  // Auto-suggest the task type from the chosen column's real values (editable).
  useEffect(() => {
    if (!target || taskTouched) return;
    setTask(suggestTaskType(columnValues(columns, sampleRows, target)));
  }, [target, columns, sampleRows, taskTouched]);

  const metrics = modelType && isSupervised(modelType) ? metricsFor(modelType, task) : [];
  useEffect(() => { if (metrics.length && !metrics.includes(metric)) setMetric(metrics[0]); }, [metrics.join()]);

  // Auto-fill the model name (user edits win).
  useEffect(() => {
    if (nameTouched || !file) return;
    setModelName(defaultModelName(file.name, isSupervised(modelType as PanelModelType) ? target : ''));
  }, [file, target, modelType, nameTouched]);

  const supervised = !!modelType && isSupervised(modelType);
  const unavailableKey = unavailableReasonKey(modelType);
  const needsSmiles = !!modelType && (family === 'molecular' || modelType === 'ludwig_molecular');
  const gateValue = gate.trim() === '' ? undefined : Number(gate);
  const gateValid = gateValue === undefined || Number.isFinite(gateValue);
  // Same floor the server enforces (galaxy.ai.ml_training.plan.MIN_TRAIN_ROWS).
  const tooFewRows = !!file && isDelimitedTable(file.name) && rowCount !== null && rowCount < MIN_TRAIN_ROWS;
  const valid = !!project && !!selection && selectedFileIds.length > 0 && !!file && !!modelType && gateValid && !tooFewRows
    && (!supervised || (!!target && !!metric))
    && (!needsSmiles || (!!smilesCol && smilesCol !== target))
    && (epochs.trim() === '' || Number(epochs) > 0)
    && !unavailableKey;  // don't allow launching a type whose container isn't provisioned

  const runStatus = useRunStatus(runId, s => TERMINAL_STATUSES.has(String(s).toLowerCase()));

  async function submit(event: { preventDefault: () => void }) {
    event.preventDefault();
    if (!valid || !file || !modelType || !selection) return;
    setBusy(true); setError(''); setRunId(null); setLaunched(null);
    try {
      const mapped = backendModelType(modelType);
      const datasetPayload = selection.kind === 'folder'
        ? { folderPath: selection.folderPath }
        : selectedFileIds.length > 1
          ? { fileIds: selectedFileIds }
          : { fileId: selectedFileIds[0] };
      const { runId: id, plan } = await launchTraining({
        projectId: project, ...datasetPayload,
        ...mapped,
        ...(supervised ? { task_type: task, target_col: target, metric } : {}),
        ...(needsSmiles ? { smiles_col: smilesCol } : {}),
        ...(gateValue !== undefined ? { gate_threshold: gateValue } : {}),
        ...(epochs.trim() ? { epochs: Number(epochs) } : {}),
        // Adapting forces the output name to the base model's (so it versions it),
        // so a user-typed name is only sent for a fresh training run.
        ...(!adaptOf && modelName.trim() ? { model_name: modelName.trim() } : {}),
        ...(adaptOf ? { adapt_of: adaptOf } : {}),
        ...specPayload(modelType, spec),
      });
      setRunId(id); setLaunched(plan);
      queryClient.invalidateQueries({ queryKey: ['/api/model-tracks/train'] });
    } catch (cause) {
      const stage = cause instanceof TrainingLaunchError ? cause.stage : 'plan';
      const detail = cause instanceof Error ? cause.message : String(cause);
      const small = /^dataset_too_small:(\d+):(\d+)/.exec(detail);
      if (small) { setError(t('models.launch_too_few_rows', { rows: Number(small[1]), min: Number(small[2]) })); return; }
      setError(stage === 'execute' ? t('models.launch_execute_failed', { detail }) : t('models.launch_plan_failed', { detail }));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="space-y-3 rounded border p-3" data-testid={`training-launcher-${family}`} onSubmit={submit}>
      <p className="text-sm font-semibold">
        {adaptOf
          ? t('models.adapt_launch_heading', { model: adaptOf })
          : family === 'molecular' ? t('models.launch_heading_molecular') : t('models.launch_heading_general')}
      </p>
      <p className="text-xs text-muted-foreground">
        {adaptOf ? t('models.adapt_launch_intro') : t('models.launch_intro')}
      </p>
      {family === 'molecular' && (
        <p className="text-fs-xs text-muted-foreground" data-testid="launcher-molecular-path-note">
          {t('models.launch_molecular_path_note')}
        </p>
      )}

      <label className="block text-xs">{t('models.setup_project')}
        <select className={FIELD} value={project} onChange={e => setProject(e.target.value)} required
          data-testid="launcher-project">
          <option value="">{t('models.setup_choose_project')}</option>
          {context?.projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
      </label>

      <label className="block text-xs">{t('models.setup_dataset')}
        <div className="flex items-center gap-2">
          <select className={FIELD} value={selectionValue} disabled={filesLoading || !project}
            onChange={e => setSelectionValue(e.target.value)} required data-testid="launcher-dataset">
            <option value="">{filesLoading ? t('models.setup_loading') : t('models.setup_choose_dataset')}</option>
            {datasetOptions.map(o => (
              <option key={o.value} value={o.value} data-kind={o.kind}>{o.label}</option>
            ))}
          </select>
          {/* Upload a local dataset into the project without leaving the panel. */}
          <label className={`shrink-0 cursor-pointer rounded border px-2 py-1 text-xs hover:bg-muted ${(!project || uploading) ? 'pointer-events-none opacity-50' : ''}`}
            data-testid="launcher-upload-label">
            {uploading ? tOr('models.uploading', 'Uploading…') : tOr('models.upload_dataset', 'Upload')}
            <input type="file" className="hidden" data-testid="launcher-upload" disabled={!project || uploading}
              onChange={handleUpload} />
          </label>
        </div>
        {selection?.kind === 'folder' && selectedFileIds.length > 0 && (
          <p className="mt-1 text-fs-xs text-muted-foreground" data-testid="launcher-folder-count">
            {t('models.setup_folder_files', { n: selectedFileIds.length })}
          </p>
        )}
      </label>
      {project && !filesLoading && !files.length && <p className="text-xs">{t('models.setup_no_files')}</p>}
      {profileState === 'loading' && <p role="status" className="text-xs">{t('models.columns_loading')}</p>}
      {profileState === 'error' && <p className="text-xs text-destructive">{t('models.columns_unavailable')}</p>}

      {tooFewRows && (
        <p className="text-xs text-destructive" data-testid="launcher-too-few-rows">
          {t('models.launch_too_few_rows', { rows: rowCount ?? 0, min: MIN_TRAIN_ROWS })}
        </p>
      )}

      {file && !modelTypes.length && profileState !== 'loading' && (
        <p className="text-xs text-destructive" data-testid="launcher-no-model-types">
          {family === 'molecular' ? t('models.launch_needs_smiles_file') : llmOnly ? t('models.launch_needs_llm_file') : t('models.launch_unsupported_file')}
        </p>
      )}

      {!!modelTypes.length && (
        <>
          <label className="block text-xs">{t('models.setup_type')}
            <select className={FIELD} value={modelType} onChange={e => setModelType(e.target.value as PanelModelType)}
              data-testid="launcher-model-type">
              {modelTypes.map(mt => <option key={mt} value={mt}>{t(`models.mt_${mt}`)}</option>)}
            </select>
          </label>
          <p className="text-fs-xs text-muted-foreground">{modelType && t(`models.mtd_${modelType}`)}</p>
          {/* The offered types depend on the data (SMILES→molecular, text→LLM,
              .h5ad→single-cell). Say so, so the shown subset isn't a mystery. */}
          {family === 'general' && (
            <p className="text-fs-xs text-muted-foreground/70" data-testid="launcher-modality-hint">
              {t('models.launch_modality_hint')}
            </p>
          )}
          {unavailableKey && (
            <p className="text-fs-xs text-destructive" data-testid="launcher-type-unavailable">
              {t(`models.${unavailableKey}`)}
            </p>
          )}

          {supervised && (
            <>
              <label className="block text-xs">{t('models.setup_target')}
                <select className={FIELD} value={target} onChange={e => setTarget(e.target.value)} required
                  data-testid="launcher-target">
                  <option value="">{t('models.choose_column')}</option>
                  {columns.map(c => <option key={c} value={c}>{c}</option>)}
                </select>
              </label>
              {needsSmiles && (
                <label className="block text-xs">{t('models.smiles_column')}
                  <select className={FIELD} value={smilesCol} onChange={e => setSmilesCol(e.target.value)} required
                    data-testid="launcher-smiles">
                    <option value="">{t('models.choose_column')}</option>
                    {columns.map(c => <option key={c} value={c}>{c}</option>)}
                  </select>
                </label>
              )}
              <label className="block text-xs">{t('models.setup_task')}
                <select className={FIELD} value={task} data-testid="launcher-task"
                  onChange={e => { setTaskTouched(true); setTask(e.target.value as TaskType); }}>
                  <option value="classification">{t('models.setup_classification')}</option>
                  <option value="regression">{t('models.setup_regression')}</option>
                </select>
              </label>
              <label className="block text-xs">{t('models.setup_metric')}
                <select className={FIELD} value={metric} onChange={e => setMetric(e.target.value)}
                  data-testid="launcher-metric">
                  {metrics.map(m => <option key={m} value={m}>{t(`models.metric_${m}`)}</option>)}
                </select>
              </label>
              <label className="block text-xs">
                {metricIsCeiling(metric) ? t('models.gate_max') : t('models.gate_min')}
                <input className={FIELD} type="number" step="any" value={gate} data-testid="launcher-gate"
                  onChange={e => setGate(e.target.value)} />
              </label>
              <p className="text-fs-xs text-muted-foreground">{t('models.gate_optional')}</p>
            </>
          )}

          {(SPEC_FIELDS[modelType as PanelModelType] ?? [])
            .filter(field => !field.showWhen || String(spec[field.showWhen.key] ?? '') === field.showWhen.value)
            .map(field => (
            <label key={field.key} className={field.kind === 'bool' ? 'flex items-center gap-2 text-xs' : 'block text-xs'}>
              {field.kind === 'bool' ? (
                <>
                  <input type="checkbox" checked={!!spec[field.key]} data-testid={`launcher-spec-${field.key}`}
                    onChange={e => setSpec(s => ({ ...s, [field.key]: e.target.checked }))} />
                  {t(`models.spec_${field.key}`)}
                </>
              ) : (
                <>
                  {t(`models.spec_${field.key}`)}
                  {field.kind === 'select' ? (
                    <select className={FIELD} value={String(spec[field.key] ?? '')} data-testid={`launcher-spec-${field.key}`}
                      onChange={e => setSpec(s => ({ ...s, [field.key]: e.target.value }))}>
                      {(field.options ?? []).map(o => <option key={o} value={o}>{o}</option>)}
                    </select>
                  ) : field.kind === 'column' ? (
                    // A role column (instruction/output/target) chosen from the
                    // dataset's REAL columns — never a free-text box.
                    <select className={FIELD} value={String(spec[field.key] ?? '')} data-testid={`launcher-spec-${field.key}`}
                      onChange={e => setSpec(s => ({ ...s, [field.key]: e.target.value }))}>
                      <option value="">{tOr('models.spec_column_none', '— none —')}</option>
                      {columns.map(c => <option key={c} value={c}>{c}</option>)}
                    </select>
                  ) : field.kind === 'json' ? (
                    // reward_spec for rule-following (composite) GRPO — a JSON rule list.
                    <textarea className={`${FIELD} font-mono`} rows={3} spellCheck={false}
                      placeholder={tOr('models.spec_reward_spec_ph', '[{"kind":"contains_any","weight":1,"terms":["safe"]},{"kind":"banned","weight":1,"terms":["toxic"]}]')}
                      value={String(spec[field.key] ?? '')} data-testid={`launcher-spec-${field.key}`}
                      onChange={e => setSpec(s => ({ ...s, [field.key]: e.target.value }))} />
                  ) : (
                    <input className={FIELD} type={field.kind === 'number' ? 'number' : 'text'}
                      step={field.kind === 'number' ? 'any' : undefined} min={field.min}
                      value={String(spec[field.key] ?? '')} data-testid={`launcher-spec-${field.key}`}
                      onChange={e => setSpec(s => ({ ...s, [field.key]: e.target.value }))} />
                  )}
                </>
              )}
            </label>
          ))}

          {/* Adapting versions the base model, so the output name is fixed (the base's);
              no name field. A fresh training run names its new model here. */}
          {!adaptOf && (
            <label className="block text-xs">{t('models.setup_name')}
              <input className={FIELD} value={modelName} data-testid="launcher-name"
                onChange={e => { setNameTouched(true); setModelName(e.target.value); }} />
            </label>
          )}
          <label className="block text-xs">{t('models.spec_epochs_optional')}
            <input className={FIELD} type="number" min="1" step="1" value={epochs} data-testid="launcher-epochs"
              onChange={e => setEpochs(e.target.value)} />
          </label>
          {LLM_TYPES.includes(modelType as PanelModelType) && (
            <p className="text-fs-xs text-muted-foreground">{t('models.llm_gpu_note')}</p>
          )}
        </>
      )}

      {error && <p role="alert" className="text-xs text-destructive break-words" data-testid="launcher-error">{error}</p>}

      <Button type="submit" disabled={!valid || busy} data-testid="launcher-submit">
        {busy ? <><Loader2 className="mr-1 h-3 w-3 animate-spin" />{t('models.launch_starting')}</>
          : <><Play className="mr-1 h-3 w-3" />{t('models.launch_start')}</>}
      </Button>

      {runId && (
        <div className="rounded border px-2 py-1.5 text-xs space-y-1" data-testid="launcher-run">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-semibold">{launched?.workflow_ga?.name}</span>
            <Badge variant="outline" className="text-fs-xs" data-testid="launcher-run-status">
              {runStatusLabel(String(runStatus.data?.status ?? 'queued'))}
            </Badge>
            <button type="button" className="ml-auto text-primary hover:underline" onClick={() => openRunManager()}
              data-testid="launcher-run-link">{t('models.open_in_run_manager')}</button>
          </div>
          <p className="text-fs-xs text-muted-foreground" data-testid="launcher-run-follow-hint">
            {t('models.open_run_manager_hint')}
          </p>
          <p className="font-mono text-fs-xs text-muted-foreground break-all">{runId}</p>
          {runStatus.data?.errorMessage && (
            <p className="text-destructive break-words" data-testid="launcher-run-error">{runStatus.data.errorMessage}</p>
          )}
        </div>
      )}
    </form>
  );
}
