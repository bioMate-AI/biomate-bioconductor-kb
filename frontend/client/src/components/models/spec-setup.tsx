/**
 * SpecSetup — structured setup forms for the LLM and generative/diffusion
 * training families that the classification/regression ModelSetup form cannot
 * express.
 *
 * Replaces the "Set up in chat" punt in deep-learning-models.tsx: instead of
 * routing to a free-text chat draft, each of these families now gets a real
 * form whose fields + allowed values mirror the dataclasses in
 * `backend/lib/galaxy/ai/ml_training/config.py` (LLMSpec / DiffusionSpec /
 * SCDiffusionSpec) and the enums their `validate()` accepts. We NEVER offer a
 * value validate() would reject.
 *
 * Launch path is identical to ModelSetup: pick a project + dataset, collect the
 * spec fields, compose a reviewable draft that encodes model_type + task_type +
 * the spec params, preserve the active project, and hand the draft to chat via
 * the existing `modelSetupUrl` attachment bridge (onContinue / location.assign).
 * Nothing executes here — the draft is proposed for confirmation in the ordinary
 * workflow proposal flow (same framing ModelSetup uses: "propose for
 * confirmation before execution; do not claim training has started; do not
 * fabricate").
 *
 * Honest gating: frameworks that are not actually runnable are rendered as
 * disabled options with a note (protein: chroma/genie — only rfdiffusion runs;
 * scrna: cfgen — only scdiffusion is the implemented backbone), so the form can
 * never submit a broken configuration.
 */
import { useEffect, useMemo, useState } from 'react';
import { useActiveProjectSafe } from '@/contexts/active-project-context';
import { Button } from '@/components/ui/button';
import { tOr } from '@/lib/i18n';
import { modelSetupUrl } from './model-setup';

interface ProjectFile { id: string; name: string }

type Family = 'llm' | 'protein' | 'scrna';
const LLM_TYPES = ['ludwig_llm', 'trl_dpo', 'trl_grpo'];
function familyOf(type: string): Family {
  if (type === 'protein_diffusion') return 'protein';
  if (type === 'scrna_diffusion') return 'scrna';
  return 'llm';
}

/** Default field values per model_type — the dataclass defaults from config.py
 * (using the to_workflow_ga_params per-family defaults where they differ from the
 * raw Hyperparams defaults, e.g. LLM epochs=3, protein epochs=5, lr=1e-4). */
function defaultsFor(type: string): Record<string, string | number | boolean> {
  switch (type) {
    case 'protein_diffusion':
      return {
        framework: 'rfdiffusion', finetune: true, base_checkpoint: 'rfdiffusion/Base_ckpt.pt',
        target_pdb: '', hotspot_residues: '', motif_pdb: '', contig: '',
        length_min: 60, length_max: 100, num_designs: 8, diffusion_steps: 50,
        noise_schedule: 'linear', epochs: 5, learning_rate: 0.0001,
      };
    case 'scrna_diffusion':
      return {
        framework: 'scdiffusion', finetune: true, base_checkpoint: '', base_model: '',
        cell_type: '', condition_label: '', n_cells_to_generate: 1000, n_genes: 0,
        guidance_scale: 1.0, diffusion_steps: 1000, noise_schedule: 'cosine',
        epochs: 50, learning_rate: 0.0001,
      };
    default: // ludwig_llm | trl_dpo | trl_grpo
      return {
        base_model: 'HuggingFaceTB/SmolLM2-135M-Instruct', adapter: 'lora',
        max_sequence_length: 256, instruction_col: 'instruction', output_col: 'output',
        beta: 0.1, num_generations: 4, reward: 'length', reward_keyword: '',
        epochs: 3, learning_rate: 0.0001,
      };
  }
}

/** Dataset label per model_type, mirroring config.to_workflow_ga_params() labels. */
function datasetLabel(type: string): string {
  switch (type) {
    case 'protein_diffusion':
      return tOr('models.dl_spec_dataset_pdb', 'Structure set (PDB/mmCIF backbones)');
    case 'scrna_diffusion':
      return tOr('models.dl_spec_dataset_h5ad', 'Single-cell data (h5ad AnnData)');
    case 'trl_dpo':
      return tOr('models.dl_spec_dataset_dpo', 'Preference data (JSONL/CSV: prompt, chosen, rejected)');
    case 'trl_grpo':
      return tOr('models.dl_spec_dataset_grpo', 'Prompts (JSONL/CSV: prompt)');
    default:
      return tOr('models.dl_spec_dataset_llm', 'Training data (JSONL/CSV: instruction, output)');
  }
}

/**
 * Structured setup panel for one LLM/diffusion model_type. Submits a reviewable
 * chat draft through the same `modelSetupUrl` bridge ModelSetup uses.
 */
export function SpecSetup({ initialType, onContinue }: { initialType: string; onContinue?: (url: string) => void }) {
  const context = useActiveProjectSafe();
  const family = familyOf(initialType);
  const [project, setProject] = useState(context?.activeProjectId ?? '');
  const [files, setFiles] = useState<ProjectFile[]>([]);
  const [file, setFile] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [modelName, setModelName] = useState('');
  const [vals, setVals] = useState<Record<string, string | number | boolean>>(() => defaultsFor(initialType));

  useEffect(() => {
    setFiles([]); setFile(''); setError('');
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
  const num = (k: string) => Number(vals[k]);
  const str = (k: string) => String(vals[k] ?? '').trim();
  const setStr = (k: string) => (e: { target: { value: string } }) => setVals(v => ({ ...v, [k]: e.target.value }));
  const setNum = (k: string) => (e: { target: { value: string } }) => setVals(v => ({ ...v, [k]: e.target.value }));
  const setBool = (k: string) => (e: { target: { checked: boolean } }) => setVals(v => ({ ...v, [k]: e.target.checked }));

  // Per-family validity, matching the dataclass validate() rules (never let the
  // form submit a configuration validate() would reject).
  const specValid = useMemo(() => {
    if (family === 'protein') {
      if (vals.finetune && !str('base_checkpoint')) return false;
      if (!(num('length_min') > 0) || !(num('length_max') > 0)) return false;
      if (num('length_min') > num('length_max')) return false;
      if (!(num('num_designs') > 0) || !(num('diffusion_steps') > 0)) return false;
      return true;
    }
    if (family === 'scrna') {
      // finetune=True requires a base_checkpoint OR base_model (SCDiffusionSpec.validate).
      if (vals.finetune && !str('base_checkpoint') && !str('base_model')) return false;
      if (!(num('n_cells_to_generate') > 0)) return false;
      if (num('n_genes') < 0) return false;
      if (!(num('guidance_scale') > 0) || !(num('diffusion_steps') > 0)) return false;
      return true;
    }
    // llm
    if (!str('base_model')) return false;
    if (!(num('max_sequence_length') > 0)) return false;
    if (initialType === 'trl_dpo' && !(num('beta') > 0)) return false;
    if (initialType === 'trl_grpo') {
      if (!(num('num_generations') >= 2)) return false;
      if (vals.reward === 'keyword' && !str('reward_keyword')) return false;
    }
    return true;
  }, [family, initialType, vals]);

  const commonValid = !!project && !!file && num('epochs') > 0 && num('learning_rate') > 0;
  const valid = commonValid && specValid;

  function submit(event: { preventDefault: () => void }) {
    event.preventDefault();
    if (!valid) return;
    const selected = files.find(item => item.id === file);
    const name = modelName.trim() || `${initialType}-${selected?.name ?? 'model'}`;
    // model_type + task_type + the spec params, encoded as key=value pairs the
    // chat proposal/prefill layer reads (param names match to_workflow_ga_params).
    const parts: string[] = [`model_type=${initialType}`, `model_name=${name}`];
    let taskType = 'text_generation';
    let framing = 'Do not claim training has started or a model exists; do not fabricate results.';
    if (family === 'protein') {
      taskType = 'structure_generation';
      framing = 'Do not fabricate structures; do not claim training or design has started.';
      parts.push(
        `task_type=structure_generation`, `framework=${vals.framework}`, `finetune=${!!vals.finetune}`,
        `base_checkpoint=${str('base_checkpoint')}`, `target_pdb=${str('target_pdb')}`,
        `hotspot_residues=${str('hotspot_residues')}`, `motif_pdb=${str('motif_pdb')}`,
        `contig=${str('contig')}`, `length_min=${num('length_min')}`, `length_max=${num('length_max')}`,
        `num_designs=${num('num_designs')}`, `diffusion_steps=${num('diffusion_steps')}`,
        `noise_schedule=${vals.noise_schedule}`, `epochs=${num('epochs')}`, `learning_rate=${num('learning_rate')}`,
      );
    } else if (family === 'scrna') {
      taskType = 'expression_generation';
      framing = 'Do not fabricate cells or expression profiles; do not claim training has started.';
      parts.push(
        `task_type=expression_generation`, `framework=${vals.framework}`, `finetune=${!!vals.finetune}`,
        `base_checkpoint=${str('base_checkpoint')}`, `base_model=${str('base_model')}`,
        `cell_type=${str('cell_type')}`, `condition_label=${str('condition_label')}`,
        `n_cells_to_generate=${num('n_cells_to_generate')}`, `n_genes=${num('n_genes')}`,
        `guidance_scale=${num('guidance_scale')}`, `diffusion_steps=${num('diffusion_steps')}`,
        `noise_schedule=${vals.noise_schedule}`, `epochs=${num('epochs')}`, `learning_rate=${num('learning_rate')}`,
      );
    } else {
      // LLM family: task_type=text_generation; split=random (a scaffold split is
      // invalid for text — TrainingConfig.validate rejects it).
      parts.push(
        `task_type=text_generation`, `base_model=${str('base_model')}`, `adapter=${vals.adapter}`,
        `max_sequence_length=${num('max_sequence_length')}`, `epochs=${num('epochs')}`,
        `learning_rate=${num('learning_rate')}`, `split=random`,
      );
      if (initialType === 'ludwig_llm') parts.push(`instruction_col=${str('instruction_col')}`, `output_col=${str('output_col')}`);
      if (initialType === 'trl_dpo') parts.push(`beta=${num('beta')}`);
      if (initialType === 'trl_grpo') {
        parts.push(`num_generations=${num('num_generations')}`, `reward=${vals.reward}`);
        if (vals.reward === 'keyword') parts.push(`reward_keyword=${str('reward_keyword')}`);
      }
    }
    const draft =
      `Prepare a ${initialType} training run using project dataset ${selected?.name} (file ID ${file}). ` +
      `${parts.join('; ')}. ` +
      `Propose the workflow and input mapping for my confirmation before execution. ${framing}`;
    context?.setActiveProjectId(project);
    const url = modelSetupUrl(project, file, draft);
    if (onContinue) onContinue(url); else window.location.assign(url);
    // taskType is embedded in `parts` above; referenced here to keep it explicit.
    void taskType;
  }

  const noiseOptions = family === 'protein'
    ? [['linear', 'linear'], ['cosine', 'cosine']]            // DiffusionSpec doc: linear|cosine
    : [['cosine', 'cosine'], ['linear', 'linear'], ['sqrt', 'sqrt']]; // SCDiffusionSpec: cosine|linear|sqrt

  return <form className="space-y-3 rounded border p-3" data-testid={`spec-setup-${initialType}`} onSubmit={submit}>
    <p className="text-sm font-semibold">{tOr('models.dl_setup_heading', 'Configure training')}</p>
    <p className="text-xs text-muted-foreground">{tOr('models.setup_review', 'Continue to chat to review the request and confirm the workflow. Nothing starts here.')}</p>

    <label className="block text-xs">{tOr('models.setup_project', 'Project')}
      <select className={field} value={project} onChange={e => setProject(e.target.value)} required>
        <option value="">{tOr('models.setup_choose_project', 'Choose a project')}</option>
        {context?.projects.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
      </select>
    </label>

    <label className="block text-xs">{datasetLabel(initialType)}
      <select className={field} value={file} disabled={loading || !project} onChange={e => setFile(e.target.value)} required>
        <option value="">{loading ? tOr('models.setup_loading', 'Loading datasets…') : tOr('models.setup_choose_dataset', 'Choose a project file')}</option>
        {files.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
      </select>
    </label>
    {project && !loading && !error && !files.length && <p className="text-xs">{tOr('models.setup_no_files', 'Add a dataset to this project in Files first.')}</p>}

    <label className="block text-xs">{tOr('models.setup_name', 'Model name')}
      <input className={field} value={modelName} placeholder={initialType} onChange={e => setModelName(e.target.value)} />
    </label>

    {/* ── LLM family ─────────────────────────────────────────────────────── */}
    {family === 'llm' && <>
      <label className="block text-xs">{tOr('models.dl_spec_base_model', 'Base model (HF id)')}
        <input className={field} value={String(vals.base_model)} onChange={setStr('base_model')} required />
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_adapter', 'Adapter')}
        <select className={field} value={String(vals.adapter)} onChange={setStr('adapter')}>
          <option value="lora">LoRA</option>
          <option value="qlora">QLoRA (4-bit, GPU)</option>
          <option value="none">{tOr('models.dl_spec_adapter_none', 'None (full fine-tune)')}</option>
        </select>
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_max_seq', 'Max sequence length')}
        <input className={field} type="number" min="1" step="1" value={String(vals.max_sequence_length)} onChange={setNum('max_sequence_length')} required />
      </label>
      {initialType === 'ludwig_llm' && <>
        <label className="block text-xs">{tOr('models.dl_spec_instruction_col', 'Instruction column')}
          <input className={field} value={String(vals.instruction_col)} onChange={setStr('instruction_col')} />
        </label>
        <label className="block text-xs">{tOr('models.dl_spec_output_col', 'Output column')}
          <input className={field} value={String(vals.output_col)} onChange={setStr('output_col')} />
        </label>
      </>}
      {initialType === 'trl_dpo' &&
        <label className="block text-xs">{tOr('models.dl_spec_beta', 'DPO beta (KL regularization)')}
          <input className={field} type="number" min="0" step="any" value={String(vals.beta)} onChange={setNum('beta')} required />
        </label>}
      {initialType === 'trl_grpo' && <>
        <label className="block text-xs">{tOr('models.dl_spec_num_generations', 'GRPO samples per prompt (group size)')}
          <input className={field} type="number" min="2" step="1" value={String(vals.num_generations)} onChange={setNum('num_generations')} required />
        </label>
        <label className="block text-xs">{tOr('models.dl_spec_reward', 'Reward function')}
          <select className={field} value={String(vals.reward)} onChange={setStr('reward')}>
            <option value="length">length</option>
            <option value="keyword">keyword</option>
            <option value="numeric_answer">numeric_answer</option>
            <option value="composite">composite</option>
          </select>
        </label>
        {vals.reward === 'keyword' &&
          <label className="block text-xs">{tOr('models.dl_spec_reward_keyword', 'Reward keyword')}
            <input className={field} value={String(vals.reward_keyword)} onChange={setStr('reward_keyword')} required />
          </label>}
        {vals.reward === 'composite' &&
          <p className="text-[11px] text-muted-foreground">{tOr('models.dl_spec_composite_note', 'A composite reward spec (weighted rule components) is defined in chat — continue to review and provide it there.')}</p>}
      </>}
    </>}

    {/* ── Protein diffusion ──────────────────────────────────────────────── */}
    {family === 'protein' && <>
      <label className="block text-xs">{tOr('models.dl_spec_framework', 'Framework')}
        <select className={field} value={String(vals.framework)} onChange={setStr('framework')}>
          <option value="rfdiffusion">RFdiffusion</option>
          <option value="chroma" disabled>Chroma — {tOr('models.dl_spec_not_runnable', 'not yet available')}</option>
          <option value="genie" disabled>Genie — {tOr('models.dl_spec_not_runnable', 'not yet available')}</option>
        </select>
      </label>
      <label className="flex items-center gap-2 text-xs">
        <input type="checkbox" checked={!!vals.finetune} onChange={setBool('finetune')} />
        {tOr('models.dl_spec_finetune', 'Fine-tune a released checkpoint (vs. train from scratch)')}
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_base_checkpoint', 'Base checkpoint (fine-tune warm-start)')}
        <input className={field} value={String(vals.base_checkpoint)} onChange={setStr('base_checkpoint')} required={!!vals.finetune} />
      </label>
      {vals.finetune && !str('base_checkpoint') &&
        <p role="alert" className="text-[11px] text-destructive">{tOr('models.dl_spec_ckpt_required', 'A base checkpoint is required when fine-tuning.')}</p>}
      <label className="block text-xs">{tOr('models.dl_spec_target_pdb', 'Target PDB (binder design, optional)')}
        <input className={field} value={String(vals.target_pdb)} onChange={setStr('target_pdb')} />
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_hotspots', 'Hotspot residues (e.g. A30,A33,A34)')}
        <input className={field} value={String(vals.hotspot_residues)} onChange={setStr('hotspot_residues')} />
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_motif_pdb', 'Motif PDB (scaffolding, optional)')}
        <input className={field} value={String(vals.motif_pdb)} onChange={setStr('motif_pdb')} />
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_contig', 'Contig / scaffold spec (e.g. 10-40/A20-30/10-40)')}
        <input className={field} value={String(vals.contig)} onChange={setStr('contig')} />
      </label>
      <div className="grid grid-cols-2 gap-2">
        <label className="block text-xs">{tOr('models.dl_spec_length_min', 'Length min (residues)')}
          <input className={field} type="number" min="1" step="1" value={String(vals.length_min)} onChange={setNum('length_min')} required />
        </label>
        <label className="block text-xs">{tOr('models.dl_spec_length_max', 'Length max (residues)')}
          <input className={field} type="number" min="1" step="1" value={String(vals.length_max)} onChange={setNum('length_max')} required />
        </label>
      </div>
      {num('length_min') > num('length_max') &&
        <p role="alert" className="text-[11px] text-destructive">{tOr('models.dl_spec_length_order', 'Length min must be ≤ length max.')}</p>}
      <div className="grid grid-cols-2 gap-2">
        <label className="block text-xs">{tOr('models.dl_spec_num_designs', 'Number of designs')}
          <input className={field} type="number" min="1" step="1" value={String(vals.num_designs)} onChange={setNum('num_designs')} required />
        </label>
        <label className="block text-xs">{tOr('models.dl_spec_diffusion_steps', 'Diffusion steps (T)')}
          <input className={field} type="number" min="1" step="1" value={String(vals.diffusion_steps)} onChange={setNum('diffusion_steps')} required />
        </label>
      </div>
      <label className="block text-xs">{tOr('models.dl_spec_noise_schedule', 'Noise schedule')}
        <select className={field} value={String(vals.noise_schedule)} onChange={setStr('noise_schedule')}>
          {noiseOptions.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </label>
    </>}

    {/* ── scRNA diffusion ────────────────────────────────────────────────── */}
    {family === 'scrna' && <>
      <label className="block text-xs">{tOr('models.dl_spec_framework', 'Framework')}
        <select className={field} value={String(vals.framework)} onChange={setStr('framework')}>
          <option value="scdiffusion">scDiffusion</option>
          <option value="cfgen" disabled>CFGen — {tOr('models.dl_spec_not_runnable', 'not yet available')}</option>
        </select>
      </label>
      <label className="flex items-center gap-2 text-xs">
        <input type="checkbox" checked={!!vals.finetune} onChange={setBool('finetune')} />
        {tOr('models.dl_spec_finetune_sc', 'Fine-tune a pretrained checkpoint (vs. train from scratch)')}
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_base_checkpoint_sc', 'Pretrained diffusion checkpoint (warm-start)')}
        <input className={field} value={String(vals.base_checkpoint)} onChange={setStr('base_checkpoint')} />
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_base_model_sc', 'Pretrained autoencoder/foundation weight (e.g. SCimilarity)')}
        <input className={field} value={String(vals.base_model)} onChange={setStr('base_model')} />
      </label>
      {vals.finetune && !str('base_checkpoint') && !str('base_model') &&
        <p role="alert" className="text-[11px] text-destructive">{tOr('models.dl_spec_sc_warmstart', 'Fine-tuning requires a checkpoint or foundation weight — or uncheck fine-tune to train from scratch.')}</p>}
      <label className="block text-xs">{tOr('models.dl_spec_cell_type', 'Condition on cell type (optional)')}
        <input className={field} value={String(vals.cell_type)} onChange={setStr('cell_type')} />
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_condition_label', 'Condition/perturbation obs column (optional)')}
        <input className={field} value={String(vals.condition_label)} onChange={setStr('condition_label')} />
      </label>
      <div className="grid grid-cols-2 gap-2">
        <label className="block text-xs">{tOr('models.dl_spec_n_cells', 'Cells to generate')}
          <input className={field} type="number" min="1" step="1" value={String(vals.n_cells_to_generate)} onChange={setNum('n_cells_to_generate')} required />
        </label>
        <label className="block text-xs">{tOr('models.dl_spec_n_genes', 'Number of genes (0 = infer)')}
          <input className={field} type="number" min="0" step="1" value={String(vals.n_genes)} onChange={setNum('n_genes')} required />
        </label>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <label className="block text-xs">{tOr('models.dl_spec_guidance_scale', 'Guidance scale')}
          <input className={field} type="number" min="0" step="any" value={String(vals.guidance_scale)} onChange={setNum('guidance_scale')} required />
        </label>
        <label className="block text-xs">{tOr('models.dl_spec_diffusion_steps', 'Diffusion steps (T)')}
          <input className={field} type="number" min="1" step="1" value={String(vals.diffusion_steps)} onChange={setNum('diffusion_steps')} required />
        </label>
      </div>
      <label className="block text-xs">{tOr('models.dl_spec_noise_schedule', 'Noise schedule')}
        <select className={field} value={String(vals.noise_schedule)} onChange={setStr('noise_schedule')}>
          {noiseOptions.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </label>
    </>}

    {/* ── shared training knobs ──────────────────────────────────────────── */}
    <div className="grid grid-cols-2 gap-2">
      <label className="block text-xs">{tOr('models.dl_spec_epochs', 'Epochs')}
        <input className={field} type="number" min="1" step="1" value={String(vals.epochs)} onChange={setNum('epochs')} required />
      </label>
      <label className="block text-xs">{tOr('models.dl_spec_learning_rate', 'Learning rate')}
        <input className={field} type="number" min="0" step="any" value={String(vals.learning_rate)} onChange={setNum('learning_rate')} required />
      </label>
    </div>

    {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
    <Button type="submit" disabled={!valid || loading}>{tOr('models.setup_continue', 'Review in chat')}</Button>
  </form>;
}
