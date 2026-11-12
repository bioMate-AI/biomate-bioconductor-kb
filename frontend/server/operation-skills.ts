/**
 * operation-skills.ts — a small registry of OPERATION skills for the decomposer.
 *
 * Part of the skills architecture (docs/20261111_SKILLS_ARCHITECTURE_TASK_HANDLING.md):
 * operation skills describe "what kind of work this is" so the decomposer infers the
 * right capability by MEANING (not keyword gates), emits the right decomposition SHAPE,
 * and routes to the right engine with the right presentation — instead of forcing every
 * molecular/generative request into the drug-discovery dock/ADMET workflow template.
 *
 * Selection is inference over each skill's `whenToUse` description; adding a capability is
 * adding a registry entry (open registry). This mirrors the Python-side
 * backend/lib/galaxy/ai/skills/*.md operation skills (e.g. generator-adaptation.md), which
 * are the source of truth; this registry is the Node decomposer's view of them until a
 * shared loader exists (migration step 3).
 *
 * DISCIPLINE: inert by default. `renderOperationSkillsBlock()` returns '' unless
 * OPERATION_SKILLS_IN_DECOMP === '1', so wiring it into the decomposition prompt CANNOT
 * change live routing until the flag is set and the change is measured offline on the
 * decomposition benchmark (scripts/routing_eval/decomp_model_bench.ts). Same convention as
 * pattern_router (BIOMATE_PATTERN_ROUTER_ENABLED) and ml_training (ML_TRAINING_ROUTING).
 */

export interface OperationSkill {
  /** Skill id (matches the backend skills/*.md `name`). */
  name: string;
  /** When this skill applies — written as meaning, for inference selection (not keywords). */
  whenToUse: string;
  /** The decomposition shape this operation takes (grounded in the chain pattern library). */
  shape: string;
  /** How the decomposer should route it (which engine / module), not a Nextflow catalog search. */
  route: string;
  /** The card type the result renders as (per each skill's presentation contract). */
  presentation: string;
  /** Guards — what this skill is explicitly NOT, to prevent mis-selection. */
  notThis: string;
}

/**
 * The registry. Keep each entry aligned with its backend skills/*.md source of truth.
 * First entry: generator-adaptation (the 2026-11-10 demo misroute; documented
 * Models→Adapt direction, BD doc §5.4/§7.2/§7.3).
 */
export const OPERATION_SKILLS: OperationSkill[] = [
  {
    name: 'generator-adaptation',
    whenToUse:
      'The user wants to ADAPT or fine-tune an existing GENERATIVE model (molecule / peptide / ' +
      'protein generator) on their own data — e.g. "adapt the generative model to our chemical ' +
      'series", "fine-tune the molecule generator on our compounds", "continue-train the peptide ' +
      'designer on our actives". This is the documented Models→Adapt capability (generator adaptation).',
    shape:
      'A single workflow_generation intent targeting reinvent4_finetune_rl — NOT a dock+ADMET ' +
      'fork/join fan-out. It only becomes multi-step if the user explicitly chains it ' +
      '("adapt the generator, THEN screen its outputs").',
    route:
      'The executor already exists — route to the NAMED workflow `reinvent4_finetune_rl` ' +
      '(run_type=transfer_learning, stage=transfer; fine-tunes the REINVENT4 prior on the user\'s ' +
      'train_smiles series → *_finetuned.model, on reinvent4-nf). This is workflow_generation with ' +
      'the exact target reinvent4_finetune_rl — NOT nearest-catalog retrieval (misroutes to ' +
      'dock/ADMET) and NOT reinvent4_lead_design (that only samples a frozen prior = inference).',
    presentation:
      'A model-version card over the reinvent4_finetune_rl outputs: base prior + adaptation SMILES ' +
      'series, before/after adaptation metrics, the produced *_finetuned.model checkpoint as a new ' +
      'model version, reviewer-gated promotion. NOT an empty/dock-ADMET pipeline card.',
    notThis:
      'NOT docking / ADMET / virtual screening (those are their own operations); NOT de-novo ' +
      'generation from scratch with no adaptation data; NOT a property-PREDICTOR retrain ' +
      '(that is predictor-retraining); NOT merely running an existing model (that is inference).',
  },
];

/** True when operation skills should be injected into the decomposition prompt. Default OFF. */
export function operationSkillsEnabled(): boolean {
  return process.env.OPERATION_SKILLS_IN_DECOMP === '1';
}

/**
 * Render the operation-skills section for the decomposition system prompt.
 * Returns '' when the flag is off (inert) — so wiring this into the prompt is a no-op by default.
 */
export function renderOperationSkillsBlock(): string {
  if (!operationSkillsEnabled() || OPERATION_SKILLS.length === 0) return '';
  const entries = OPERATION_SKILLS.map(s =>
    `- **${s.name}** — When: ${s.whenToUse}\n  Shape: ${s.shape}\n  Route: ${s.route}\n  ` +
    `Presentation: ${s.presentation}\n  Not this: ${s.notThis}`
  ).join('\n');
  return (
    '\n## Operation skills (infer by meaning; do NOT force into the drug-discovery workflow template)\n\n' +
    'Some requests are a specific KIND of work with their own route and presentation, not a ' +
    'nearest-catalog Nextflow workflow. When a request matches one of these operation skills by ' +
    'MEANING, decompose it as that skill\'s Shape and mark its intent accordingly — do not fan it ' +
    'out into unrelated workflow steps. When none matches, proceed normally.\n\n' +
    entries + '\n'
  );
}
