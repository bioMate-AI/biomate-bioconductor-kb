/**
 * Routing authority — the intent classifier is the SINGLE authority for workflow-vs-not.
 *
 * History (docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md): ~20 English-regex overrides ran after the
 * classifier and flipped actions.needsWorkflowGeneration (target evidence, trial feasibility, pathway
 * enrichment, GWAS chain, multi-omics, macrophage, canonical fixtures, named docking, epitope/codon/
 * pocket, ADMET, HPO+ENSG, paper-question, data-attach, run_code detectors, parseActions
 * mustGenerateWorkflow, the inline-table short-circuit). Each discarded the classifier's decision for
 * any phrasing it did not anticipate (e.g. every Chinese follow-up, dev logs 2026-11-10). Their
 * knowledge now lives in the classifier prompt as examples (ROUTING_EXAMPLES_PROMPT) and, where it is
 * retrieval knowledge, in search HINTS applied here (key terms / preferred domains / subQuery) —
 * hints steer WHICH workflow is found; they never change WHETHER one is generated.
 *
 * What remains here that can still change the decision is limited to user-control and prerequisite
 * gates that are not intent decisions:
 *   - explicit prohibition ("do not run / 不要生成工作流"): consumes the classifier's user_constraint
 *     field; the deterministic EN/ZH regex is a secondary safety net for the same explicit instruction.
 *   - BOIN prerequisite: dose levels missing → ask for them (classifier still decided "workflow").
 */
import { isInterpretationOnlyRequest, prohibitsWorkflowExecution, prohibitsWorkflowGeneration } from './execution-intent-guard';

export type UserConstraint = 'no_workflow' | 'no_launch' | null;

export function parseUserConstraint(v: unknown): UserConstraint {
  return v === 'no_workflow' || v === 'no_launch' ? v : null;
}

export interface RoutingIntent {
  type: string;
  subQuery: string;
  execution?: 'pipeline' | 'direct_compute' | null;
  userConstraint?: UserConstraint;
  inlineParameters?: Record<string, any>;
  actions: {
    needsWorkflowGeneration: boolean;
    needsWorkflowModification?: boolean;
    needsResearchAgent?: boolean;
    needsLLMReasoning?: boolean;
    [k: string]: any;
  };
}

export interface RoutingDecomposition {
  keyTerms?: string[];
  preferredDomains?: string[];
  penalizedDomains?: string[];
}

/** The classifier's own execution mode is authoritative over its action flags: direct_compute means
 *  compute now with run_code, so no workflow card (a card disables run_code at the tool gate). This is
 *  consistency between two fields of ONE classifier answer, not an override of it.
 *
 *  The classifier's own contract for direct_compute is "the data is already in the conversation".
 *  A direct_compute label with NO data anywhere in the conversation contradicts that contract and is
 *  not honoured: dev 2026-11-11, "Run analyze_ebv_antibody_titers on its built-in … sample data" came
 *  back direct_compute ~2/3 times → no card, and the model told the user to search the Workflows panel.
 *  `conversationHasData` covers this message, earlier user turns and UI-selected datasets. */
export function reconcileExecutionMode(intent: RoutingIntent, conversationHasData: boolean): void {
  if (intent.execution === 'direct_compute' && intent.actions.needsWorkflowGeneration) {
    if (!conversationHasData) {
      console.log('[GalaxyAssistant] [routing] direct_compute label ignored: no data in the conversation — keeping workflow generation');
      return;
    }
    intent.actions.needsWorkflowGeneration = false;
    intent.actions.needsLLMReasoning = true;
  }
}

const push = (arr: string[], ...items: string[]) => { for (const t of items) if (!arr.includes(t)) arr.push(t); };

const PATHWAY_ENRICHMENT_RE = /\b(pathway\s+enrichment|run\s+pathway|enrichment\s+analysis|clusterprofiler|enrichgo|enrichkegg|gsea|gene\s+set\s+enrichment|enriched\s+pathways?|over.?representation\s+analysis|ora\b|fgsea|GO\s+(enrichment|terms?|biological\s+process)|gene\s+ontology\s+enrich)\b|富集/i;
const COMPLEMENT_RE = /\b(complement\s+(cascade|pathway|activation|gene[s]?|factor[s]?)|C3\b|C5\b|CFH\b|CFB\b|CFD\b|C3AR1\b|C5AR1\b|SERPING1\b|CD55\b|CD59\b|CR1\b|GO:0006958|hsa04610)/i;
const ADMET_RE = /\b(admet|herg|dili|ames|caco.?2|bbb|blood.brain.barrier|drug.like(ness)?|toxicity\s+(prediction|screening))\b|毒性|成药性/i;
const GWAS_CHAIN_RE = /\b(gwas.{0,30}eqtl|eqtl.{0,30}gwas|eqtl\s+colocali[sz]ation|indication\s+expansion|genetic\s+evidence.{0,30}across)\b|共定位/i;
const MULTI_OMICS_RE = /\b(multi.?omics?|mofa2?|cross.?omics|integrat\w*.{0,40}(proteom|metabolom|olink|atac|methylation))\b|多组学|联合分析|整合/i;
const MACROPHAGE_RE = /\b(macrophage|TREM2)\b|巨噬细胞/i;
const TARGET_TRIAL_RE = /\b(target\s+evidence|evidence\s+positioning|genetic\s+association[s]?\s+for|target\s+(tractability|prioriti[sz]ation)|recruitment\s+feasibility|patient\s+recruitment|rare\s+disease\s+power|indication\s+expansion|multi.?omics\s+integrat)\b/i;

/**
 * Retrieval hints for a workflow intent the CLASSIFIER already chose. Pure steering of the catalog
 * search (key terms / domains / subQuery) — never touches needsWorkflowGeneration.
 * Returns whether the pathway-enrichment hint fired (Step 6c text guardrail stands down for it).
 */
export function applyRetrievalHints(
  intent: RoutingIntent, decomposition: RoutingDecomposition, message: string,
): { pathwayEnrichment: boolean } {
  if (!intent.actions.needsWorkflowGeneration) return { pathwayEnrichment: false };
  const text = `${message}\n${intent.subQuery || ''}`;
  decomposition.keyTerms ??= [];
  decomposition.preferredDomains ??= [];
  decomposition.penalizedDomains ??= [];
  let pathwayEnrichment = false;
  if (PATHWAY_ENRICHMENT_RE.test(text)) {
    pathwayEnrichment = true;
    // A follow-up turn's subQuery can be a context summary ("I have your counts matrix…") that sends
    // the search to differentialabundance; the user's own words carry the enrichment request.
    intent.subQuery = message;
    push(decomposition.keyTerms, 'clusterprofiler', 'ORA', 'pathway enrichment', 'gene set', 'enrichGO', 'enrichKEGG', 'GO terms');
    decomposition.keyTerms = decomposition.keyTerms.filter(t => !/(differentialabundance|differential.abundance|nf.?core.*diff)/i.test(t));
    push(decomposition.preferredDomains, 'genomics');
    push(decomposition.penalizedDomains, 'transcriptomics');
    if (COMPLEMENT_RE.test(text)) push(decomposition.keyTerms, 'complement cascade', 'GO:0006958', 'complement activation', 'enrichGO complement', 'hsa04610');
  }
  if (ADMET_RE.test(text)) {
    // The backend ADMET fast-path matches the literal SMILES-bearing text; a rephrased subQuery can drop it.
    intent.subQuery = message;
    push(decomposition.preferredDomains, 'drug_discovery');
    intent.actions.needsResearchAgent = false;
  }
  if (GWAS_CHAIN_RE.test(text)) push(decomposition.preferredDomains, 'drug_discovery');
  if (MULTI_OMICS_RE.test(text)) push(decomposition.preferredDomains, 'multi_omics');
  if (MACROPHAGE_RE.test(text)) push(decomposition.preferredDomains, 'single_cell');
  // The workflow panel is the answer; a long research-agent reply would mask the card.
  if (TARGET_TRIAL_RE.test(text) || GWAS_CHAIN_RE.test(text) || MULTI_OMICS_RE.test(text) || MACROPHAGE_RE.test(text)) {
    intent.actions.needsResearchAgent = false;
  }
  return { pathwayEnrichment };
}

/**
 * Explicit user prohibition. Source of truth = the classifier's user_constraint (any language); the
 * EN/ZH regex in execution-intent-guard is a secondary net for the same explicit instruction.
 * "no_launch" (draft the plan, don't run it) keeps the draft card — launching needs Confirm & Run.
 */
export function applyUserConstraintGate(intent: RoutingIntent, message: string): 'none' | 'draft' | 'suppressed' {
  if (!intent.actions.needsWorkflowGeneration) return 'none';
  const regexProhibits = prohibitsWorkflowExecution(message);
  const interpretationOnly = regexProhibits && isInterpretationOnlyRequest(message);
  const generationProhibited = intent.userConstraint === 'no_workflow'
    || (regexProhibits && (interpretationOnly || prohibitsWorkflowGeneration(message)));
  if (generationProhibited) {
    intent.actions.needsWorkflowGeneration = false;
    intent.actions.needsWorkflowModification = false;
    intent.actions.needsLLMReasoning = true;
    if (intent.execution === 'direct_compute' && !interpretationOnly) return 'suppressed'; // run_code path
    intent.actions.needsResearchAgent = true;
    intent.type = interpretationOnly ? 'data_interpretation' : 'research_question';
    return 'suppressed';
  }
  if (intent.userConstraint === 'no_launch' || regexProhibits) return 'draft';
  return 'none';
}

const BOIN_RE = /\b(boin|phase\s*i\s*(dose\s*escalation|trial)|dose.escalation.trial|dose.finding.trial|mtd.estimation|bayesian.optimal.interval|clinical.dose.escalation|phase.i.oncology|dlt.based.escalation)\b|剂量递增|剂量爬坡/i;

/** BOIN prerequisite (not an intent decision): a dose-escalation design needs dose levels. Detection
 *  uses the classifier's English subQuery as well as the raw message, so it is not English-only. */
export function boinDoseLevelsMissing(intent: RoutingIntent, message: string): boolean {
  if (!intent.actions.needsWorkflowGeneration) return false;
  if (!BOIN_RE.test(`${message}\n${intent.subQuery || ''}`)) return false;
  const p = intent.inlineParameters || {};
  if (Object.keys(p).some(k => /dose/i.test(k) && p[k] != null && String(p[k]).trim() !== '')) return false;
  const hasDoseLevels = /\[\s*\d[\d,\s.]+\]/.test(message)
    || /\b(dose[- ]levels?|doses?)[:\s]+[\d[,]/i.test(message)
    || /剂量(水平)?[：:\s]*[[(（]?\s*\d/.test(message)
    || /\bstarting.dose\b.+\bmax.dose\b/i.test(message);
  return !hasDoseLevels;
}

/**
 * Models Optimise / DMTA loop intents — campaign Bayesian propose/refit, not REINVENT4
 * generative lead design. Matches cold-start Optimise seeds and natural follow-ups.
 * The first paragraph (task statement) is used so Prepared-demo context cannot poison
 * a non-DMTA ask that merely mentions assays in scaffolding.
 */
const DMTA_LOOP_RE = /\bdesign[-–—\s]*make[-–—\s]*test\b|\bdmta\b|\bbayesian\s+optim|\b96[-\s]?assay\b|\bassay\s+budget\b|\bpropos\w*\s+the\s+next\s+round\b|\bnext\s+round\b.{0,40}\brefit\b|\brefit\b.{0,40}\b(results?|round|propos)/i;

export function isDmtaLoopQuery(message: string, subQuery?: string): boolean {
  const own = String(message || '').split(/\n\s*\[(?:Memory context|Inline parameters:|Prepared)/i)[0]
    .trim().split(/\n\n/)[0];
  const blob = `${own}\n${subQuery || ''}`;
  return DMTA_LOOP_RE.test(blob);
}

/** Deep-link target for DMTA / Optimise — Models Molecular Rounds (CRO Library route is disabled). */
export const MODELS_DMTA_HREF = '/models?tab=molecular';
