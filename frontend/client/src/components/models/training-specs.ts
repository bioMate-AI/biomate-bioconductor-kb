/**
 * Spec-form fields for the LLM / diffusion training families.
 *
 * Mirrors LLMSpec / SCDiffusionSpec / DiffusionSpec in
 * backend/lib/galaxy/ai/ml_training/config.py: only fields those dataclasses
 * accept, and only values their validate() allows (so the form can never submit
 * a configuration the backend rejects). Frameworks that are not runnable are
 * simply not offered — scDiffusion and RFdiffusion are the implemented ones.
 */
import type { PanelModelType } from './training-logic';

export type SpecValues = Record<string, string | boolean>;
// 'column' renders as a dropdown of the dataset's REAL columns (the launcher
// passes them), so a role like instruction/output/target is never a free-text box.
export type SpecFieldKind = 'text' | 'number' | 'bool' | 'select' | 'column' | 'json';
// showWhen: render this field only when another field currently equals a value
// (e.g. reward_spec only for reward='composite') — so irrelevant knobs stay hidden.
export interface SpecField { key: string; kind: SpecFieldKind; options?: string[]; min?: number; showWhen?: { key: string; value: string } }

const LLM_COMMON: SpecField[] = [
  { key: 'base_model', kind: 'text' },
  { key: 'adapter', kind: 'select', options: ['lora', 'qlora', 'none'] },
  { key: 'max_sequence_length', kind: 'number', min: 1 },
];

export const SPEC_FIELDS: Partial<Record<PanelModelType, SpecField[]>> = {
  ludwig_llm: [...LLM_COMMON, { key: 'instruction_col', kind: 'column' }, { key: 'output_col', kind: 'column' }],
  trl_dpo: [...LLM_COMMON, { key: 'beta', kind: 'number', min: 0 }],
  trl_grpo: [...LLM_COMMON,
    { key: 'num_generations', kind: 'number', min: 2 },
    // 'composite' = rule-following: a JSON list of weighted scorers + gates the model
    // is optimized toward (interpreted safely, no eval — see trl_trainer.make_reward_fn).
    { key: 'reward', kind: 'select', options: ['length', 'keyword', 'numeric_answer', 'composite'] },
    { key: 'reward_keyword', kind: 'text', showWhen: { key: 'reward', value: 'keyword' } },
    { key: 'reward_spec', kind: 'json', showWhen: { key: 'reward', value: 'composite' } }],
  scrna_diffusion: [
    { key: 'finetune', kind: 'bool' },
    { key: 'base_checkpoint', kind: 'text' },
    { key: 'base_model', kind: 'text' },
    { key: 'cell_type', kind: 'text' },
    { key: 'condition_label', kind: 'text' },
    { key: 'n_cells_to_generate', kind: 'number', min: 1 },
    { key: 'guidance_scale', kind: 'number', min: 0 },
    { key: 'diffusion_steps', kind: 'number', min: 1 },
    { key: 'noise_schedule', kind: 'select', options: ['cosine', 'linear', 'sqrt'] },
  ],
  protein_diffusion: [
    { key: 'finetune', kind: 'bool' },
    { key: 'base_checkpoint', kind: 'text' },
    { key: 'target_pdb', kind: 'text' },
    { key: 'hotspot_residues', kind: 'text' },
    { key: 'contig', kind: 'text' },
    { key: 'length_min', kind: 'number', min: 1 },
    { key: 'length_max', kind: 'number', min: 1 },
    { key: 'num_designs', kind: 'number', min: 1 },
    { key: 'diffusion_steps', kind: 'number', min: 1 },
    { key: 'noise_schedule', kind: 'select', options: ['linear', 'cosine'] },
  ],
  // Generic tabular-data diffusion (TabDDPM / TabSyn): generate synthetic rows
  // from any feature matrix. target_column (optional) drives class-conditional
  // synthesis; empty = unconditional. Mirrors TabularDiffusionSpec.
  tabular_diffusion: [
    { key: 'framework', kind: 'select', options: ['tabddpm', 'tabsyn'] },
    { key: 'finetune', kind: 'bool' },
    { key: 'base_checkpoint', kind: 'text' },
    { key: 'target_column', kind: 'column' },
    { key: 'n_rows_to_generate', kind: 'number', min: 1 },
    { key: 'guidance_scale', kind: 'number', min: 0 },
    { key: 'diffusion_steps', kind: 'number', min: 1 },
    { key: 'noise_schedule', kind: 'select', options: ['cosine', 'linear', 'sqrt'] },
  ],
};

const LLM_BASE = { base_model: 'HuggingFaceTB/SmolLM2-135M-Instruct', adapter: 'lora', max_sequence_length: '256' };

export const SPEC_DEFAULTS: Partial<Record<PanelModelType, SpecValues>> = {
  ludwig_llm: { ...LLM_BASE, instruction_col: 'instruction', output_col: 'output' },
  trl_dpo: { ...LLM_BASE, beta: '0.1' },
  trl_grpo: { ...LLM_BASE, num_generations: '4', reward: 'length', reward_keyword: '', reward_spec: '' },
  // finetune defaults to false: a warm-start needs staged weights the user must
  // name, and SCDiffusionSpec/DiffusionSpec.validate() rejects finetune without one.
  scrna_diffusion: {
    finetune: false, base_checkpoint: '', base_model: '', cell_type: '', condition_label: '',
    n_cells_to_generate: '1000', guidance_scale: '1.0', diffusion_steps: '1000', noise_schedule: 'cosine',
  },
  protein_diffusion: {
    finetune: true, base_checkpoint: 'rfdiffusion/Base_ckpt.pt', target_pdb: '', hotspot_residues: '',
    contig: '', length_min: '60', length_max: '100', num_designs: '8', diffusion_steps: '50',
    noise_schedule: 'linear',
  },
  // finetune defaults to false so a from-scratch run needs no checkpoint
  // (TabularDiffusionSpec.validate rejects finetune without base_checkpoint).
  tabular_diffusion: {
    framework: 'tabddpm', finetune: false, base_checkpoint: '', target_column: '',
    n_rows_to_generate: '1000', guidance_scale: '1.0', diffusion_steps: '1000', noise_schedule: 'cosine',
  },
};

/** Which plan body key carries each family's spec. */
const SPEC_KEY: Partial<Record<PanelModelType, 'llm' | 'sc' | 'diffusion' | 'tabular'>> = {
  ludwig_llm: 'llm', trl_dpo: 'llm', trl_grpo: 'llm',
  scrna_diffusion: 'sc', protein_diffusion: 'diffusion', tabular_diffusion: 'tabular',
};

/** Spec values → the typed sub-object the plan endpoint expects (numbers as numbers). */
export function specPayload(type: PanelModelType, values: SpecValues): Record<string, unknown> {
  const key = SPEC_KEY[type];
  const fields = SPEC_FIELDS[type];
  if (!key || !fields) return {};
  const spec: Record<string, unknown> = {};
  for (const field of fields) {
    // A field hidden by showWhen (e.g. reward_spec when reward≠composite) is never
    // sent — its value is irrelevant to the chosen mode and the user can't see it.
    if (field.showWhen && String(values[field.showWhen.key] ?? '') !== field.showWhen.value) continue;
    const raw = values[field.key];
    if (field.kind === 'bool') { spec[field.key] = !!raw; continue; }
    const text = typeof raw === 'string' ? raw.trim() : '';
    if (field.kind === 'json') {
      // reward_spec: a JSON list. Only sent when it parses to an array; invalid or
      // empty JSON is skipped (the backend validates composite rewards).
      if (text === '') continue;
      try { const parsed = JSON.parse(text); if (Array.isArray(parsed)) spec[field.key] = parsed; } catch { /* skip invalid */ }
      continue;
    }
    if (field.kind === 'number') {
      if (text === '') continue;
      const n = Number(text);
      if (Number.isFinite(n)) spec[field.key] = n;
      continue;
    }
    // Empty text is meaningful for optional conditioning fields (= unconditional),
    // but it must never blank a required one (base_model), so send it only when set.
    if (text !== '') spec[field.key] = text;
  }
  return { [key]: spec };
}
