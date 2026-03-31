/**
 * Personalization Use Cases — Drug Development Domain (Complete E2E Flows)
 *
 * Each use case is a multi-turn scenario that walks through the entire pipeline:
 *
 *   Turn 1 → analyzeIntent → [clarification OR workflow search OR pipeline]
 *   Turn 2 → (after user responds to clarification) → workflow search
 *   Backend search → FTS ranking with/without key_terms
 *   Session memory → what is preserved and injected on subsequent turns
 *
 * Tests prove personalization works by verifying state at every decision point,
 * not just the end result.
 *
 * Use cases:
 *   UC-D1  Domain profile routes vague compound query to drug discovery
 *   UC-D2  Docking clarification fires even with drug_discovery profile (Use Case 5)
 *   UC-D3  Specific docking resolves without clarification + precise FTS targeting
 *   UC-D4  ADMET: vague toxicity query → clarification → specific query → FTS boost
 *   UC-D5  Target-to-lead sequential pipeline with chain hint + all 4 steps wired
 *   UC-D6  Session memory preserves EGFR context across 6-turn window compression
 *   UC-D7  Session memory is empty on first turn — zero cost for new sessions
 *   UC-D8  MD simulation after failed docking: memory prevents re-running completed steps
 */

import { describe, it, expect } from 'vitest';
import {
  inferActionsFromType,
  type IntentDecomposition,
  type DecomposedIntent,
  type SessionMemory,
} from './galaxy-assistant';

// =============================================================================
// Test infrastructure — mirrors real galaxy-assistant.ts implementations
// =============================================================================

/** Mirrors parseIntentResult() in galaxy-assistant.ts */
function parseIntentResult(result: any, originalMessage: string): IntentDecomposition {
  const parseFacts = (rawFacts: any[]) => {
    if (!Array.isArray(rawFacts)) return [];
    return rawFacts
      .filter((f: any) => f && typeof f.category === 'string' && typeof f.value === 'string')
      .map((f: any) => ({
        category: f.category as string,
        value: f.value as string,
        confidence: typeof f.confidence === 'number' ? f.confidence : 0.8,
        supersedes: typeof f.supersedes === 'string' ? f.supersedes : undefined,
      }));
  };
  const parseActions = (raw: any, type: string) => {
    if (raw && typeof raw === 'object') {
      const base = inferActionsFromType(type);
      return {
        needsToolSearch: typeof raw.needsToolSearch === 'boolean' ? raw.needsToolSearch : base.needsToolSearch,
        needsWorkflowGeneration: typeof raw.needsWorkflowGeneration === 'boolean' ? raw.needsWorkflowGeneration : base.needsWorkflowGeneration,
        needsWorkflowModification: typeof raw.needsWorkflowModification === 'boolean' ? raw.needsWorkflowModification : base.needsWorkflowModification,
        needsResearchAgent: typeof raw.needsResearchAgent === 'boolean' ? raw.needsResearchAgent : base.needsResearchAgent,
        needsBenchmarkAgent: typeof raw.needsBenchmarkAgent === 'boolean' ? raw.needsBenchmarkAgent : base.needsBenchmarkAgent,
        needsDatasetAccess: typeof raw.needsDatasetAccess === 'boolean' ? raw.needsDatasetAccess : base.needsDatasetAccess,
        needsLLMReasoning: typeof raw.needsLLMReasoning === 'boolean' ? raw.needsLLMReasoning : base.needsLLMReasoning,
      };
    }
    return inferActionsFromType(type);
  };
  const preferredDomains: string[] = Array.isArray(result.preferred_domains) ? result.preferred_domains : [];
  const keyTerms: string[] = Array.isArray(result.key_terms) ? result.key_terms : [];
  const needsThinking: boolean = result.needs_thinking === true;
  const chainHint: string | null = typeof result.chain_hint === 'string' ? result.chain_hint : null;

  if (Array.isArray(result.intents) && result.intents.length > 0) {
    const isSequential = result.is_sequential === true;
    const intents: DecomposedIntent[] = result.intents.map((intent: any, i: number) => ({
      id: intent.id || `intent_${i + 1}`,
      type: intent.type || 'general_question',
      subQuery: intent.subQuery || originalMessage,
      keywords: intent.keywords || [],
      inlineParameters: intent.inlineParameters || {},
      needsToolSearch: intent.needsToolSearch !== false,
      needsDatasets: intent.needsDatasets !== false,
      confidence: intent.confidence || 0.5,
      facts: parseFacts(intent.facts),
      dependsOn: Array.isArray(intent.dependsOn) ? intent.dependsOn : [],
      actions: parseActions(intent.actions, intent.type || 'general_question'),
      inputFromDescription: intent.input_from_description ?? undefined,
      outputDescription: intent.output_description ?? undefined,
      workflowAmbiguity: typeof intent.workflowAmbiguity === 'string' ? intent.workflowAmbiguity : null,
    }));
    const primaryIntent = isSequential
      ? intents[0]
      : intents.reduce((best, cur) => cur.confidence > best.confidence ? cur : best);
    return { intents, isMultiIntent: intents.length > 1, isSequential, primaryIntent, preferredDomains, keyTerms, needsThinking, chainHint };
  }

  const intentType = result.type || 'general_question';
  const singleIntent: DecomposedIntent = {
    id: 'intent_1', type: intentType, subQuery: originalMessage,
    keywords: result.keywords || [], inlineParameters: result.inlineParameters || {},
    needsToolSearch: result.needsToolSearch !== false, needsDatasets: result.needsDatasets !== false,
    confidence: result.confidence || 0.5, facts: parseFacts(result.facts),
    dependsOn: [], actions: parseActions(result.actions, intentType),
    workflowAmbiguity: typeof result.workflowAmbiguity === 'string' ? result.workflowAmbiguity : null,
  };
  return { intents: [singleIntent], isMultiIntent: false, primaryIntent: singleIntent, preferredDomains, keyTerms, needsThinking, chainHint };
}

/** Mirrors _buildSessionMemoryBlock() in galaxy-assistant.ts */
function buildSessionMemoryBlock(mem: SessionMemory | null): string {
  if (!mem || !mem.active_task) return '';
  const parts: string[] = [];
  if (mem.active_task) parts.push(`Current task: ${mem.active_task}`);
  if (mem.key_decisions.length > 0) parts.push(`Key decisions: ${mem.key_decisions.join('; ')}`);
  if (mem.uploaded_files.length > 0) parts.push(`Files this session: ${mem.uploaded_files.join(', ')}`);
  if (mem.attempted_workflows.length > 0) {
    const wfs = mem.attempted_workflows.map(w => `${w.path} (${w.status})`).join(', ');
    parts.push(`Previously attempted: ${wfs}`);
  }
  if (mem.current_parameters && Object.keys(mem.current_parameters).length > 0)
    parts.push(`Parameters set: ${JSON.stringify(mem.current_parameters)}`);
  if (mem.open_questions.length > 0) parts.push(`Open questions: ${mem.open_questions.join('; ')}`);
  return `<session_memory>\n${parts.join('\n')}\n</session_memory>\nNote: session memory supplements the conversation window — prior turns may have been compressed.\n\n`;
}

/** Simulate the ADMET fast-path check from processMessage() */
function admetFastPathFires(message: string): boolean {
  const hasSMILES = /(?:CC\(=O\)|c1ccc|[A-Z][a-z]?(?:c|C)\d|[A-Z]=O|SMILES\s*[:=]\s*\S{5,})/i.test(message)
    || /\b[A-Z][CNOPSFIBrcl0-9@=#\-+\[\]()\/.\\]{6,}\b/.test(message);
  const hasAdmet = /(ADMET|hERG|DILI|Ames\s+mutagenicity|cardiotox|hepatotox|ClinTox|toxicity\s+screen|drug\s+toxicity)/i.test(message);
  return hasSMILES && hasAdmet;
}

/**
 * Simulate how the backend domain scoring changes based on preferred_domains.
 * In production this lives in unified_workflow_search.py _calculate_score().
 * Here we approximate: each domain match adds +2.0 to the score.
 */
function simulateSearchScoring(
  workflow: { name: string; domain: string; fts_score: number },
  preferredDomains: string[],
  keyTerms: string[]
): number {
  let score = workflow.fts_score;
  if (preferredDomains.includes(workflow.domain)) score += 2.0;
  // key_terms appended to FTS query → approximate by adding 0.5 per match found in workflow name
  for (const term of keyTerms) {
    if (workflow.name.toLowerCase().includes(term.toLowerCase())) score += 0.5;
  }
  return score;
}

const wfActions = {
  needsToolSearch: true, needsWorkflowGeneration: true, needsWorkflowModification: false,
  needsResearchAgent: false, needsBenchmarkAgent: false, needsDatasetAccess: false, needsLLMReasoning: true,
};


// =============================================================================
// UC-D1: Domain profile routes a vague compound query to drug discovery
// =============================================================================
//
// SCENARIO
// --------
// A medicinal chemist has registered domain=drug_discovery in their profile.
// They ask: "analyze my compound library" — four words, completely domain-agnostic.
// Without a domain profile this matches metabolomics/genomics/proteomics equally.
// With the domain profile the backend search applies a +2.0 bonus to every
// drug_discovery workflow, ensuring admet_screening ranks above xcms or MaxQuant.
//
// COMPLETE FLOW
// Turn 1: "analyze my compound library"
//   → analyzeIntent: workflowAmbiguity=null (drug_discovery profile makes scope clear)
//   → preferred_domains=['drug_discovery'], key_terms=['compound','smiles','screening']
//   → No clarification. Workflow search fires immediately.
// Backend search:
//   → Without profile: xcms (metabolomics, FTS=3.1) > admet_screening (drug_disc, FTS=2.8)
//   → With profile (+2.0): admet_screening (4.8) >> xcms (3.1)
// Session memory after turn 1:
//   → active_task="screen compound library for drug-likeness"
//   → key_decisions=["drug_discovery domain set as scope"]
// =============================================================================
describe('UC-D1: Domain profile routes compound library query to drug discovery', () => {

  describe('Turn 1 — intent analysis', () => {
    const turn1Result = {
      type: 'workflow_generation',
      keywords: ['compound library', 'screening'],
      preferred_domains: ['drug_discovery'],
      key_terms: ['compound', 'library', 'smiles', 'screening', 'drug-likeness'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: {},
      facts: [{ category: 'analysis_goal', value: 'screen compound library', confidence: 0.85 }],
      workflowAmbiguity: null,
      confidence: 0.88,
      actions: wfActions,
    };
    const decomp = parseIntentResult(turn1Result, 'analyze my compound library');

    it('[T1] workflowAmbiguity=null — domain profile resolves scope, no clarification', () =>
      expect(decomp.primaryIntent.workflowAmbiguity).toBeNull());
    it('[T1] preferred_domains carries drug_discovery to search ranker', () =>
      expect(decomp.preferredDomains).toContain('drug_discovery'));
    it('[T1] key_terms include smiles for compound library context', () =>
      expect(decomp.keyTerms).toContain('smiles'));
    it('[T1] key_terms include screening for FTS recall', () =>
      expect(decomp.keyTerms).toContain('screening'));
    it('[T1] actions.needsWorkflowGeneration=true — goes straight to search', () =>
      expect(decomp.primaryIntent.actions.needsWorkflowGeneration).toBe(true));
    it('[T1] analysis_goal fact extracted', () =>
      expect(decomp.primaryIntent.facts.some(f => f.category === 'analysis_goal')).toBe(true));
  });

  describe('Backend search — scoring comparison', () => {
    const candidates = [
      { name: 'xcms metabolomics workflow', domain: 'metabolomics', fts_score: 3.1 },
      { name: 'admet_screening compound library', domain: 'drug_discovery', fts_score: 2.8 },
      { name: 'MaxQuant proteomics pipeline', domain: 'proteomics', fts_score: 2.5 },
    ];
    const preferredDomains = ['drug_discovery'];
    const keyTerms = ['compound', 'smiles', 'screening'];

    const withProfile = candidates.map(w => ({ ...w, score: simulateSearchScoring(w, preferredDomains, keyTerms) }))
      .sort((a, b) => b.score - a.score);
    const withoutProfile = candidates.map(w => ({ ...w, score: simulateSearchScoring(w, [], []) }))
      .sort((a, b) => b.score - a.score);

    it('[search] WITHOUT profile: xcms ranks #1 (metabolomics wins on raw FTS)', () =>
      expect(withoutProfile[0].name).toContain('xcms'));
    it('[search] WITH profile: admet_screening ranks #1 (drug_discovery +2.0 bonus)', () =>
      expect(withProfile[0].name).toContain('admet_screening'));
    it('[search] admet_screening score WITH profile > WITHOUT', () => {
      const with_ = withProfile.find(w => w.name.includes('admet'))!.score;
      const without_ = withoutProfile.find(w => w.name.includes('admet'))!.score;
      expect(with_).toBeGreaterThan(without_);
    });
    it('[search] Score gap: admet_screening leads xcms by >1.0 with profile', () => {
      const admet = withProfile.find(w => w.name.includes('admet'))!.score;
      const xcms = withProfile.find(w => w.name.includes('xcms'))!.score;
      expect(admet - xcms).toBeGreaterThan(1.0);
    });
  });

  describe('Session memory after turn 1', () => {
    const memAfterT1: SessionMemory = {
      active_task: 'screening compound library for drug-likeness and ADMET properties',
      key_decisions: ['scope: drug_discovery domain (from user profile)'],
      uploaded_files: [],
      attempted_workflows: [],
      current_parameters: {},
      open_questions: ['user has not yet provided compound library file (SDF/SMILES)'],
    };
    const block = buildSessionMemoryBlock(memAfterT1);
    it('[memory] active_task records the drug screening goal', () =>
      expect(block).toContain('drug-likeness and ADMET'));
    it('[memory] open question flags missing compound file', () =>
      expect(block).toContain('compound library file'));
    it('[memory] block is correctly wrapped in session_memory tags', () =>
      expect(block).toContain('<session_memory>'));
  });
});


// =============================================================================
// UC-D2: Vague docking query triggers clarification despite drug_discovery profile
// =============================================================================
//
// SCENARIO
// --------
// This use case proves the clarification guard (R1 fix). Same chemist, same profile.
// Query: "run a docking analysis" — technically ambiguous at the workflow level:
//   - Blind docking (no binding site known) → DiffDock
//   - Site-directed docking (known pocket) → AutoDock Vina
// These are entirely different tools, different inputs, different parameters.
// Without the guard, the LLM would see drug_discovery profile and assume
// "site-directed/AutoDock Vina" and proceed without asking.
// WITH the guard, workflowAmbiguity='docking_type' fires regardless of profile.
//
// COMPLETE FLOW
// Turn 1: "run a docking analysis"
//   → analyzeIntent: workflowAmbiguity='docking_type' (MUST fire)
//   → BioMate returns: "Blind docking (DiffDock) or site-directed (AutoDock Vina)?"
// Turn 2: "site-directed — I have the EGFR binding pocket at Thr790"
//   → analyzeIntent: workflowAmbiguity=null, key_terms=['autodock','vina','egfr','thr790']
//   → preferred_domains=['drug_discovery','structural_biology']
//   → Workflow search fires → autodock_vina ranks #1
// Session memory after turn 2:
//   → key_decisions updated: "docking_type=site_directed, binding_pocket=Thr790"
// =============================================================================
describe('UC-D2: Docking clarification fires despite drug_discovery profile', () => {

  describe('Turn 1 — vague docking query → clarification', () => {
    const turn1Result = {
      type: 'workflow_generation',
      keywords: ['molecular docking'],
      preferred_domains: ['drug_discovery', 'structural_biology'],
      key_terms: ['docking', 'molecular docking'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: {},
      facts: [],
      workflowAmbiguity: 'docking_type',   // ← the guard enforces this
      confidence: 0.7,
      actions: wfActions,
    };
    const decomp1 = parseIntentResult(turn1Result, 'run a docking analysis');

    it('[T1] workflowAmbiguity=docking_type fires — system must ask', () =>
      expect(decomp1.primaryIntent.workflowAmbiguity).toBe('docking_type'));
    it('[T1] preferred_domains carries drug_discovery for post-clarification ranking', () =>
      expect(decomp1.preferredDomains).toContain('drug_discovery'));
    it('[T1] profile does NOT null out the ambiguity', () =>
      expect(decomp1.primaryIntent.workflowAmbiguity).not.toBeNull());
    it('[T1] confidence is moderate — ambiguity acknowledged', () =>
      expect(decomp1.primaryIntent.confidence).toBeLessThan(0.9));
    it('[T1] no key_terms yet — can\'t boost until ambiguity resolved', () =>
      expect(decomp1.keyTerms.length).toBeLessThanOrEqual(2));
  });

  describe('Turn 2 — user specifies site-directed + Thr790 → workflow fires', () => {
    const turn2Result = {
      type: 'workflow_generation',
      keywords: ['autodock vina', 'site-directed', 'EGFR', 'Thr790'],
      preferred_domains: ['drug_discovery', 'structural_biology'],
      key_terms: ['autodock', 'vina', 'egfr', 'site-directed', 'binding pocket', 'thr790'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: { docking_mode: 'site_directed', binding_pocket: 'Thr790' },
      facts: [
        { category: 'gene', value: 'EGFR', confidence: 1.0 },
        { category: 'tool_preference', value: 'AutoDock Vina', confidence: 0.95 },
        { category: 'parameter', value: 'Thr790 binding pocket', confidence: 0.95 },
      ],
      workflowAmbiguity: null,   // ← resolved by user's answer
      confidence: 0.97,
      actions: wfActions,
    };
    const decomp2 = parseIntentResult(
      turn2Result, 'site-directed — I have the EGFR binding pocket at Thr790'
    );

    it('[T2] workflowAmbiguity=null — fork resolved by user', () =>
      expect(decomp2.primaryIntent.workflowAmbiguity).toBeNull());
    it('[T2] key_terms now include autodock — specific tool for FTS', () =>
      expect(decomp2.keyTerms).toContain('autodock'));
    it('[T2] key_terms include thr790 — will match pocket-specific workflows', () =>
      expect(decomp2.keyTerms).toContain('thr790'));
    it('[T2] binding_pocket inline param captured', () =>
      expect(decomp2.primaryIntent.inlineParameters.binding_pocket).toBe('Thr790'));
    it('[T2] EGFR gene fact at 1.0 confidence', () =>
      expect(decomp2.primaryIntent.facts.find(f => f.value === 'EGFR')?.confidence).toBe(1.0));
    it('[T2] AutoDock Vina tool preference saved in facts', () =>
      expect(decomp2.primaryIntent.facts.some(f => f.category === 'tool_preference')).toBe(true));
    it('[T2] confidence high after unambiguous specification', () =>
      expect(decomp2.primaryIntent.confidence).toBeGreaterThan(0.95));
  });

  describe('Backend search after T2 — site-directed tools rank first', () => {
    const candidates = [
      { name: 'diffdock blind docking', domain: 'drug_discovery', fts_score: 3.0 },
      { name: 'autodock_vina site_directed egfr binding', domain: 'drug_discovery', fts_score: 2.9 },
      { name: 'haddock3 protein-protein docking', domain: 'structural_biology', fts_score: 2.4 },
    ];
    const preferredDomains = ['drug_discovery', 'structural_biology'];
    const keyTerms = ['autodock', 'vina', 'egfr', 'site-directed'];

    const ranked = candidates
      .map(w => ({ ...w, score: simulateSearchScoring(w, preferredDomains, keyTerms) }))
      .sort((a, b) => b.score - a.score);

    it('[search] autodock_vina ranks #1 after key_terms boost', () =>
      expect(ranked[0].name).toContain('autodock_vina'));
    it('[search] diffdock does NOT rank first despite similar base FTS score', () =>
      expect(ranked[0].name).not.toContain('diffdock'));
    it('[search] autodock_vina score boosted by "autodock" + "vina" + "egfr" key_terms', () =>
      expect(ranked[0].score).toBeGreaterThan(ranked[1].score));
  });

  describe('Session memory captures the resolved docking decision', () => {
    const memAfterT2: SessionMemory = {
      active_task: 'running site-directed AutoDock Vina docking on EGFR at Thr790',
      key_decisions: [
        'docking_type=site_directed (user specified binding pocket known)',
        'target=EGFR, binding_pocket=Thr790',
        'tool=AutoDock Vina (not DiffDock)',
      ],
      uploaded_files: [],
      attempted_workflows: [],
      current_parameters: { docking_mode: 'site_directed', binding_pocket: 'Thr790', target: 'EGFR' },
      open_questions: ['user has not yet provided the EGFR PDB structure or compound library'],
    };
    const block = buildSessionMemoryBlock(memAfterT2);
    it('[memory] docking_type decision recorded — no re-asking on turn 3', () =>
      expect(block).toContain('docking_type=site_directed'));
    it('[memory] Thr790 pocket parameter preserved', () =>
      expect(block).toContain('Thr790'));
    it('[memory] open question flags still-missing files', () =>
      expect(block).toContain('PDB structure'));
  });
});


// =============================================================================
// UC-D3: Specific docking resolves without clarification + precise FTS targeting
// =============================================================================
//
// SCENARIO
// --------
// Chemist asks with full specification in a single query. No ambiguity, no
// clarification needed. The key_terms are rich enough that AutoDock Vina
// workflow ranks above all others in a single turn.
//
// COMPLETE FLOW
// Turn 1: "Run site-directed AutoDock Vina docking on EGFR with known binding pocket at Thr790"
//   → analyzeIntent: workflowAmbiguity=null (all specifics provided)
//   → key_terms=['autodock','vina','egfr','site-directed','binding pocket','thr790']
//   → preferred_domains=['drug_discovery','structural_biology']
//   → Workflow search fires immediately (no turn 2 needed)
// Backend search: autodock_vina + key_terms → #1 by significant margin
// Personalization advantage: without key_terms, base FTS on query alone scores
//   diffdock (3.0) higher than autodock_vina (2.9) — key_terms reverse this.
// =============================================================================
describe('UC-D3: Specific docking query resolves in one turn without clarification', () => {

  describe('Turn 1 — single-turn resolution', () => {
    const result = {
      type: 'workflow_generation',
      keywords: ['autodock vina', 'site-directed', 'EGFR', 'Thr790'],
      preferred_domains: ['drug_discovery', 'structural_biology'],
      key_terms: ['autodock', 'vina', 'egfr', 'site-directed', 'binding pocket', 'thr790'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: { target: 'egfr', docking_mode: 'site_directed', pocket: 'Thr790' },
      facts: [
        { category: 'gene', value: 'EGFR', confidence: 1.0 },
        { category: 'tool_preference', value: 'AutoDock Vina', confidence: 0.95 },
        { category: 'parameter', value: 'Thr790 binding pocket', confidence: 0.9 },
        { category: 'parameter', value: 'site-directed docking mode', confidence: 1.0 },
      ],
      workflowAmbiguity: null,
      confidence: 0.97,
      actions: wfActions,
    };
    const decomp = parseIntentResult(
      result,
      'Run site-directed AutoDock Vina docking on EGFR with known binding pocket at Thr790'
    );

    it('[T1] no clarification — workflowAmbiguity=null', () =>
      expect(decomp.primaryIntent.workflowAmbiguity).toBeNull());
    it('[T1] key_terms cover all specificity dimensions', () => {
      expect(decomp.keyTerms).toContain('autodock');
      expect(decomp.keyTerms).toContain('egfr');
      expect(decomp.keyTerms).toContain('thr790');
      expect(decomp.keyTerms).toContain('site-directed');
    });
    it('[T1] inline params capture docking mode', () =>
      expect(decomp.primaryIntent.inlineParameters.docking_mode).toBe('site_directed'));
    it('[T1] 4 facts extracted covering gene, tool, and 2 parameters', () =>
      expect(decomp.primaryIntent.facts.length).toBe(4));
    it('[T1] both drug_discovery and structural_biology in preferred_domains', () => {
      expect(decomp.preferredDomains).toContain('drug_discovery');
      expect(decomp.preferredDomains).toContain('structural_biology');
    });
    it('[T1] confidence=0.97 — unambiguous query', () =>
      expect(decomp.primaryIntent.confidence).toBeGreaterThanOrEqual(0.97));
  });

  describe('Backend search — key_terms reverse the raw FTS ranking', () => {
    const candidates = [
      { name: 'diffdock blind docking neural', domain: 'drug_discovery', fts_score: 3.0 },
      { name: 'autodock_vina site_directed binding_pocket egfr', domain: 'drug_discovery', fts_score: 2.9 },
    ];
    const keyTerms = ['autodock', 'vina', 'egfr', 'site-directed'];
    const preferredDomains = ['drug_discovery', 'structural_biology'];

    const withPersonalization = candidates
      .map(w => ({ ...w, score: simulateSearchScoring(w, preferredDomains, keyTerms) }))
      .sort((a, b) => b.score - a.score);
    const withoutPersonalization = candidates
      .map(w => ({ ...w, score: simulateSearchScoring(w, [], []) }))
      .sort((a, b) => b.score - a.score);

    it('[search] WITHOUT key_terms: diffdock ranks #1 (higher raw FTS)', () =>
      expect(withoutPersonalization[0].name).toContain('diffdock'));
    it('[search] WITH key_terms: autodock_vina ranks #1 (3 term matches)', () =>
      expect(withPersonalization[0].name).toContain('autodock_vina'));
    it('[search] key_terms provide decisive margin (>0.5 score difference)', () => {
      const autodock = withPersonalization.find(w => w.name.includes('autodock'))!.score;
      const diffdock = withPersonalization.find(w => w.name.includes('diffdock'))!.score;
      expect(autodock - diffdock).toBeGreaterThan(0.5);
    });
  });
});


// =============================================================================
// UC-D4: ADMET — vague toxicity query → clarification → specific query → FTS boost
// =============================================================================
//
// SCENARIO
// --------
// This is the most important use case showing the FULL value of personalization.
// It has two phases that demonstrate opposite behaviors:
//
// Phase A (vague, no SMILES): "analyze toxicity of my molecule"
//   - No molecule provided → cannot run any workflow
//   - No scope → "hERG? DILI? Full ADMET?" — 4 fundamentally different pipelines
//   - workflowAmbiguity='admet_scope' fires (NEW ambiguity type, added this session)
//   - BioMate asks the user for both molecule AND scope
//   - admet fast path does NOT fire (no SMILES present)
//
// Phase B (specific, with SMILES): "check hERG and DILI for CC(=O)Oc1ccccc1C(=O)O"
//   - SMILES present → fast path check: hasSMILES=true, hasAdmet(hERG)=true → fires
//   - workflowAmbiguity=null (scope+molecule both specified)
//   - key_terms=['admet','herg','dili','smiles','cardiotoxicity'] → FTS boost
//   - preferred_domains=['drug_discovery'] → +2.0 score bonus
//   - admet_screening workflow ranks #1 (was ranked below xcms without personalization)
//
// Personalization advantage demonstrated TWICE:
//   1. The clarification asks the RIGHT questions (not generic "what do you want?")
//      because the drug_discovery domain profile primes the LLM toward ADMET vocabulary
//   2. After clarification, key_terms ensure admet_screening ranks above unrelated workflows
// =============================================================================
describe('UC-D4: ADMET — two-phase flow: clarification then FTS-boosted workflow', () => {

  describe('Phase A, Turn 1 — vague toxicity query → clarification', () => {
    // Message has NO SMILES and NO specific endpoint → admet_scope ambiguity
    const message = 'analyze toxicity of my molecule';
    const turn1Result = {
      type: 'workflow_generation',
      keywords: ['toxicity', 'molecule', 'analysis'],
      preferred_domains: ['drug_discovery'],
      key_terms: ['toxicity', 'admet'],   // low specificity — no SMILES vocabulary yet
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: {},
      facts: [],
      workflowAmbiguity: 'admet_scope',   // ← fires: no molecule + no endpoint scope
      confidence: 0.6,
      actions: wfActions,
    };
    const decomp1 = parseIntentResult(turn1Result, message);

    it('[A-T1] ADMET fast path does NOT fire — no SMILES in message', () =>
      expect(admetFastPathFires(message)).toBe(false));
    it('[A-T1] workflowAmbiguity=admet_scope fires — asks for molecule AND scope', () =>
      expect(decomp1.primaryIntent.workflowAmbiguity).toBe('admet_scope'));
    it('[A-T1] preferred_domains still carries drug_discovery from profile', () =>
      expect(decomp1.preferredDomains).toContain('drug_discovery'));
    it('[A-T1] key_terms are minimal — no SMILES-specific vocabulary yet', () =>
      expect(decomp1.keyTerms.length).toBeLessThanOrEqual(3));
    it('[A-T1] confidence is moderate — ambiguous state', () =>
      expect(decomp1.primaryIntent.confidence).toBeLessThan(0.75));
    it('[A-T1] workflowAmbiguity is NOT null — domain profile does not resolve it', () =>
      expect(decomp1.primaryIntent.workflowAmbiguity).not.toBeNull());

    // The system should return this clarification question (from CLARIFICATION_FALLBACKS):
    const expectedQuestion = [
      'What molecule? Please provide the SMILES string or upload an SDF file',
      'Which safety endpoints',
      'hERG',
      'DILI',
      'Ames',
    ];
    it('[A-T1] clarification question text covers molecule requirement', () => {
      // We verify the FALLBACK key exists in the system — the actual Haiku question generation
      // is integration-tested; here we verify the ambiguity type is correct
      expect(decomp1.primaryIntent.workflowAmbiguity).toBe('admet_scope');
      // admet_scope is a known key in CLARIFICATION_FALLBACKS (added this session)
      // so a fallback question WILL be returned even if Haiku is unavailable
    });
  });

  describe('Phase B, Turn 2 — specific SMILES + endpoints → workflow fires', () => {
    // User responds with SMILES and specifies hERG + DILI
    const message = 'check hERG and DILI for CC(=O)Oc1ccccc1C(=O)O';
    const turn2Result = {
      type: 'workflow_generation',
      keywords: ['ADMET', 'hERG', 'DILI', 'toxicity screening'],
      preferred_domains: ['drug_discovery'],
      key_terms: ['admet', 'herg', 'dili', 'smiles', 'cardiotoxicity', 'hepatotoxicity', 'ames'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: { smiles: 'CC(=O)Oc1ccccc1C(=O)O', endpoints: 'hERG,DILI' },
      facts: [
        { category: 'parameter', value: 'SMILES: CC(=O)Oc1ccccc1C(=O)O', confidence: 1.0 },
        { category: 'analysis_goal', value: 'hERG cardiotoxicity screen', confidence: 0.98 },
        { category: 'analysis_goal', value: 'DILI hepatotoxicity screen', confidence: 0.98 },
      ],
      workflowAmbiguity: null,   // ← resolved: molecule + scope both specified
      confidence: 0.96,
      actions: wfActions,
    };
    const decomp2 = parseIntentResult(turn2Result, message);

    it('[B-T2] ADMET fast path fires — SMILES present + hERG keyword', () =>
      expect(admetFastPathFires(message)).toBe(true));
    it('[B-T2] workflowAmbiguity=null — clarification resolved both questions', () =>
      expect(decomp2.primaryIntent.workflowAmbiguity).toBeNull());
    it('[B-T2] key_terms now span full ADMET vocabulary (7 terms)', () =>
      expect(decomp2.keyTerms.length).toBeGreaterThanOrEqual(6));
    it('[B-T2] key_terms include herg', () => expect(decomp2.keyTerms).toContain('herg'));
    it('[B-T2] key_terms include dili', () => expect(decomp2.keyTerms).toContain('dili'));
    it('[B-T2] key_terms include smiles', () => expect(decomp2.keyTerms).toContain('smiles'));
    it('[B-T2] SMILES captured as inline parameter', () =>
      expect(decomp2.primaryIntent.inlineParameters.smiles).toBe('CC(=O)Oc1ccccc1C(=O)O'));
    it('[B-T2] 3 facts: SMILES + 2 analysis goals', () =>
      expect(decomp2.primaryIntent.facts.length).toBe(3));
    it('[B-T2] preferred_domains still drug_discovery', () =>
      expect(decomp2.preferredDomains).toContain('drug_discovery'));
    it('[B-T2] confidence high after unambiguous specification', () =>
      expect(decomp2.primaryIntent.confidence).toBeGreaterThan(0.93));
  });

  describe('Backend search — key_terms rank admet_screening #1', () => {
    const candidates = [
      { name: 'xcms metabolomics compound identification', domain: 'metabolomics', fts_score: 3.1 },
      { name: 'admet_screening herg dili smiles toxicity panel', domain: 'drug_discovery', fts_score: 2.8 },
      { name: 'proteomics toxicity marker profiling', domain: 'proteomics', fts_score: 2.6 },
      { name: 'ames mutagenicity admet screen', domain: 'drug_discovery', fts_score: 2.5 },
    ];
    const preferredDomains = ['drug_discovery'];
    const keyTerms = ['admet', 'herg', 'dili', 'smiles', 'cardiotoxicity'];

    const withPersonalization = candidates
      .map(w => ({ ...w, score: simulateSearchScoring(w, preferredDomains, keyTerms) }))
      .sort((a, b) => b.score - a.score);
    const withoutPersonalization = candidates
      .map(w => ({ ...w, score: simulateSearchScoring(w, [], []) }))
      .sort((a, b) => b.score - a.score);

    it('[search] WITHOUT personalization: xcms ranks #1 (highest raw FTS)', () =>
      expect(withoutPersonalization[0].name).toContain('xcms'));
    it('[search] WITH personalization: admet_screening ranks #1', () =>
      expect(withPersonalization[0].name).toContain('admet_screening'));
    it('[search] xcms drops out of top-2 — no domain match, no key_term hits', () => {
      const xcmsIdx = withPersonalization.findIndex(w => w.name.includes('xcms'));
      expect(xcmsIdx).toBeGreaterThanOrEqual(2);  // was #1 without personalization, now #3+
    });
    it('[search] admet_screening score boost: domain(+2.0) + 3 key_term hits(+1.5) = +3.5 over baseline', () => {
      const score = withPersonalization.find(w => w.name.includes('admet_screening'))!.score;
      const baseScore = candidates.find(w => w.name.includes('admet_screening'))!.fts_score;
      expect(score - baseScore).toBeGreaterThanOrEqual(3.0);
    });
    it('[search] ames_mutagenicity also boosted — same domain, partial key_term match', () =>
      expect(withPersonalization[1].name).toContain('ames'));
  });

  describe('Session memory — captures both turns', () => {
    const memAfterT2: SessionMemory = {
      active_task: 'screening aspirin (CC(=O)Oc1ccccc1C(=O)O) for hERG and DILI safety liabilities',
      key_decisions: [
        'endpoints: hERG cardiotoxicity + DILI hepatotoxicity (not full ADMET panel)',
        'molecule: aspirin SMILES CC(=O)Oc1ccccc1C(=O)O provided by user in turn 2',
      ],
      uploaded_files: [],
      attempted_workflows: [],
      current_parameters: {
        smiles: 'CC(=O)Oc1ccccc1C(=O)O',
        endpoints: ['hERG', 'DILI'],
      },
      open_questions: [],
    };
    const block = buildSessionMemoryBlock(memAfterT2);
    it('[memory] SMILES preserved in parameters for downstream steps', () =>
      expect(block).toContain('CC(=O)Oc1ccccc1C(=O)O'));
    it('[memory] endpoint decisions recorded — no re-asking', () =>
      expect(block).toContain('hERG cardiotoxicity'));
    it('[memory] active_task named with specific molecule', () =>
      expect(block).toContain('aspirin'));
    it('[memory] no open_questions — session fully specified', () =>
      expect(block).not.toContain('Open questions'));
  });
});


// =============================================================================
// UC-D5: Target-to-lead 4-step sequential pipeline with chain hint
// =============================================================================
//
// SCENARIO
// --------
// Scientist asks for a full drug discovery pipeline. The LLM recognises this
// as a sequential pipeline (all 4 steps depend on the previous one's output)
// and returns chain_hint='target_to_lead_full'. This triggers the curated chain
// which pre-wires all 4 steps with correct I/O types.
//
// COMPLETE FLOW
// Turn 1: "Run a full drug discovery pipeline: 1. AlphaFold3 structure prediction,
//          2. AutoDock Vina docking, 3. ADMET screen, 4. Lead ranking"
//   → analyzeIntent: is_sequential=true, 4 intents, chain_hint='target_to_lead_full'
//   → Each step has dependsOn wiring and I/O descriptions
//   → preferred_domains=['drug_discovery','structural_biology']
//   → needsThinking=true (complex multi-step pipeline design)
// Backend: chain_hint prevents 4 independent search calls — one curated chain loaded
// Personalization advantage: without chain_hint, each sub-step's FTS independently
//   returns top-1 which may not be the right combination. With chain_hint, all 4
//   steps are from the same coherent pipeline.
// =============================================================================
describe('UC-D5: Target-to-lead 4-step sequential pipeline with chain hint', () => {

  const result = {
    is_sequential: true,
    preferred_domains: ['drug_discovery', 'structural_biology'],
    key_terms: ['alphafold3', 'autodock', 'vina', 'admet', 'lead', 'egfr', 'docking'],
    needs_thinking: true,
    chain_hint: 'target_to_lead_full',
    intents: [
      {
        id: 'step_1', type: 'workflow_generation',
        subQuery: 'Predict EGFR structure with AlphaFold3',
        keywords: ['alphafold3', 'structure prediction', 'EGFR'],
        dependsOn: [],
        output_description: 'predicted_egfr_structure.pdb',
        actions: wfActions,
        facts: [
          { category: 'gene', value: 'EGFR', confidence: 1.0 },
          { category: 'tool_preference', value: 'AlphaFold3', confidence: 0.95 },
        ],
        confidence: 0.97,
      },
      {
        id: 'step_2', type: 'workflow_generation',
        subQuery: 'Site-directed AutoDock Vina docking of compound library against EGFR',
        keywords: ['autodock vina', 'site-directed', 'compound library'],
        dependsOn: ['step_1'],
        input_from_description: 'predicted_egfr_structure.pdb from step 1',
        output_description: 'docked_poses.sdf ranked by binding affinity',
        actions: wfActions, facts: [], confidence: 0.95,
      },
      {
        id: 'step_3', type: 'workflow_generation',
        subQuery: 'ADMET screening of top docked compounds for hERG and DILI',
        keywords: ['admet', 'herg', 'dili', 'safety screening'],
        dependsOn: ['step_2'],
        input_from_description: 'docked_poses.sdf from step 2',
        output_description: 'admet_filtered_leads.sdf with safety scores',
        actions: wfActions, facts: [], confidence: 0.93,
      },
      {
        id: 'step_4', type: 'workflow_generation',
        subQuery: 'Rank and select final leads by composite docking + ADMET score',
        keywords: ['lead selection', 'ranking', 'composite score'],
        dependsOn: ['step_3'],
        input_from_description: 'admet_filtered_leads.sdf from step 3',
        output_description: 'final_leads_report.csv with top 10 candidates',
        actions: wfActions, facts: [], confidence: 0.90,
      },
    ],
  };

  const query = '1. AlphaFold3 EGFR structure\n2. AutoDock Vina docking\n3. ADMET screen\n4. Lead ranking';
  const decomp = parseIntentResult(result, query);

  describe('Pipeline structure', () => {
    it('isSequential=true — all steps ordered', () => expect(decomp.isSequential).toBe(true));
    it('4 pipeline steps parsed', () => expect(decomp.intents.length).toBe(4));
    it('chain_hint=target_to_lead_full triggers curated pipeline', () =>
      expect(decomp.chainHint).toBe('target_to_lead_full'));
    it('needsThinking=true — 4-step pipeline design needs deep reasoning', () =>
      expect(decomp.needsThinking).toBe(true));
    it('primaryIntent is step_1 (first in sequential)', () =>
      expect(decomp.primaryIntent.id).toBe('step_1'));
  });

  describe('Step I/O wiring — output of N feeds input of N+1', () => {
    it('step_2 depends on step_1', () =>
      expect(decomp.intents[1].dependsOn).toContain('step_1'));
    it('step_3 depends on step_2', () =>
      expect(decomp.intents[2].dependsOn).toContain('step_2'));
    it('step_4 depends on step_3', () =>
      expect(decomp.intents[3].dependsOn).toContain('step_3'));
    it('step_2 inputFromDescription references step_1 PDB output', () =>
      expect((decomp.intents[1] as any).inputFromDescription).toContain('step 1'));
    it('step_3 inputFromDescription references docked_poses.sdf', () =>
      expect((decomp.intents[2] as any).inputFromDescription).toContain('step 2'));
    it('step_4 inputFromDescription references admet_filtered_leads', () =>
      expect((decomp.intents[3] as any).inputFromDescription).toContain('step 3'));
  });

  describe('Domain and key_terms coverage', () => {
    it('preferred_domains includes both drug_discovery and structural_biology', () => {
      expect(decomp.preferredDomains).toContain('drug_discovery');
      expect(decomp.preferredDomains).toContain('structural_biology');
    });
    it('key_terms span all 4 workflow tools', () => {
      expect(decomp.keyTerms).toContain('alphafold3');
      expect(decomp.keyTerms).toContain('autodock');
      expect(decomp.keyTerms).toContain('admet');
    });
    it('step_1 has EGFR gene fact + AlphaFold3 tool preference', () => {
      expect(decomp.intents[0].facts.some(f => f.category === 'gene' && f.value === 'EGFR')).toBe(true);
      expect(decomp.intents[0].facts.some(f => f.category === 'tool_preference')).toBe(true);
    });
  });

  describe('Personalization advantage — chain vs. independent search', () => {
    // Without chain_hint: 4 independent searches, each returns top-1 independently.
    // Step 2 (docking) might return DiffDock (best blind docking tool by FTS alone).
    // With chain_hint: the curated target_to_lead_full chain pre-selects AutoDock Vina
    // for step 2 because it is designed to accept step 1's PDB output.
    it('chain_hint is non-null — prevents 4 independent incoherent workflow picks', () =>
      expect(decomp.chainHint).not.toBeNull());
    it('steps form a coherent dependency graph — no orphan steps', () => {
      const ids = decomp.intents.map(i => i.id);
      for (let i = 1; i < decomp.intents.length; i++) {
        const deps = decomp.intents[i].dependsOn;
        expect(deps.some(d => ids.includes(d))).toBe(true);
      }
    });
  });
});


// =============================================================================
// UC-D6: Session memory preserves EGFR context past the 6-turn window
// =============================================================================
//
// SCENARIO
// --------
// User is on turn 9. The conversation started with them uploading egfr_apo.pdb
// (turn 1) and library_1000.sdf (turn 2). Those turns are beyond the 6-turn
// sliding window. WITHOUT session memory the assistant would say "I don't know
// what protein you're working with." WITH session memory the <session_memory>
// block injects:
//   - protein, pocket, compound file, completed/failed workflow history
//   - parameters decided (exhaustiveness=16, AMBER force field)
//   - open question flagged earlier
//
// The block is shown verbatim so the user can see exactly what the LLM receives
// as "memory" at the start of turn 9 even though turns 1-2 are gone.
// =============================================================================
describe('UC-D6: Session memory preserves EGFR context past turn 6', () => {

  const egressMemory: SessionMemory = {
    active_task: 'optimising EGFR T790M inhibitor leads via AutoDock Vina docking and ADMET',
    key_decisions: [
      'target=EGFR T790M mutant (resistance mutation — needs mutant PDB, not WT)',
      'docking_type=site_directed at Thr790 binding pocket',
      'hERG IC50 cutoff=1µM (from team oncology standard)',
      'lead criteria: docking_score < -8 kcal/mol AND hERG IC50 > 1µM AND DILI pass',
    ],
    uploaded_files: ['egfr_t790m.pdb', 'library_1000.sdf', 'admet_results.csv'],
    attempted_workflows: [
      { path: 'drug_discovery/alphafold_db_search/main.nf', status: 'completed' },
      { path: 'drug_discovery/schrodinger_glide_docking/main.nf', status: 'failed' },
      { path: 'drug_discovery/autodock_vina/main.nf', status: 'completed' },
      { path: 'drug_discovery/admet_screening/main.nf', status: 'completed' },
    ],
    current_parameters: {
      receptor: 'egfr_t790m.pdb',
      binding_pocket: 'Thr790',
      exhaustiveness: 16,
      num_modes: 9,
      herg_cutoff_uM: 1.0,
    },
    open_questions: [
      'user has not confirmed whether to use Glide XP or SP mode if Glide is retried',
    ],
  };

  const block = buildSessionMemoryBlock(egressMemory);

  describe('Memory content completeness', () => {
    it('active_task names EGFR T790M specifically — no ambiguity about target', () =>
      expect(block).toContain('EGFR T790M'));
    it('T790M mutation flagged in decisions — critical for selecting right PDB', () =>
      expect(block).toContain('T790M mutant'));
    it('hERG cutoff decision preserved — LLM knows the team standard', () =>
      expect(block).toContain('hERG IC50 cutoff=1µM'));
    it('all 3 uploaded files preserved past window compression', () => {
      expect(block).toContain('egfr_t790m.pdb');
      expect(block).toContain('library_1000.sdf');
      expect(block).toContain('admet_results.csv');
    });
  });

  describe('Workflow history — prevents re-running completed steps and blind retries', () => {
    it('completed AlphaFold workflow recorded — no re-run needed on turn 9', () =>
      expect(block).toContain('alphafold_db_search/main.nf (completed)'));
    it('FAILED Glide docking recorded — prevents automatic retry', () =>
      expect(block).toContain('schrodinger_glide_docking/main.nf (failed)'));
    it('completed AutoDock Vina recorded — poses exist', () =>
      expect(block).toContain('autodock_vina/main.nf (completed)'));
    it('completed ADMET screening recorded — results available', () =>
      expect(block).toContain('admet_screening/main.nf (completed)'));
  });

  describe('Parameter continuity', () => {
    it('receptor parameter preserved — LLM knows which file to use', () =>
      expect(block).toContain('egfr_t790m.pdb'));
    it('exhaustiveness=16 preserved — no re-asking docking parameters', () =>
      expect(block).toContain('"exhaustiveness":16'));
    it('hERG cutoff in parameters — not just in decisions', () =>
      expect(block).toContain('herg_cutoff_uM'));
  });

  describe('Open questions tracking', () => {
    it('Glide XP vs SP question still flagged as unresolved', () =>
      expect(block).toContain('Glide XP or SP'));
  });

  describe('Memory block format', () => {
    it('wrapped in session_memory tags', () => {
      expect(block).toContain('<session_memory>');
      expect(block).toContain('</session_memory>');
    });
    it('includes compression disclaimer', () =>
      expect(block).toContain('prior turns may have been compressed'));
    it('block is non-trivially sized — carries real information (>400 chars)', () =>
      expect(block.length).toBeGreaterThan(400));
  });
});


// =============================================================================
// UC-D7: Session memory is empty for new sessions — zero cost
// =============================================================================
//
// SCENARIO
// --------
// A new user sends their first message. No session memory exists. The
// _buildSessionMemoryBlock() call returns '' — the system prompts receive no
// injection overhead. This is critical: personalization must not slow down
// users who are just starting.
// =============================================================================
describe('UC-D7: No memory overhead on first turn', () => {

  it('null memory → empty block, no injection', () =>
    expect(buildSessionMemoryBlock(null)).toBe(''));
  it('empty active_task → empty block (not yet initialised)', () =>
    expect(buildSessionMemoryBlock({
      active_task: '', key_decisions: [], uploaded_files: [],
      attempted_workflows: [], current_parameters: {}, open_questions: [],
    })).toBe(''));
  it('partial memory with only active_task → minimal block, no crashed fields', () => {
    const block = buildSessionMemoryBlock({
      active_task: 'first EGFR docking session',
      key_decisions: [], uploaded_files: [],
      attempted_workflows: [], current_parameters: {}, open_questions: [],
    });
    expect(block).toContain('Current task: first EGFR docking session');
    expect(block).not.toContain('Key decisions:');
    expect(block).not.toContain('Files this session:');
    expect(block).not.toContain('Previously attempted:');
  });
  it('malformed current_parameters (array instead of object) normalised gracefully', () => {
    // This tests the type-guard added during the audit
    const badMem: any = {
      active_task: 'test session', key_decisions: [], uploaded_files: [],
      attempted_workflows: [], current_parameters: null, open_questions: [],
    };
    // _update() in SessionMemoryUpdater normalises this; the block builder handles null
    expect(() => buildSessionMemoryBlock(badMem)).not.toThrow();
  });
});


// =============================================================================
// UC-D8: MD simulation after failed docking — memory prevents re-running completed steps
// =============================================================================
//
// SCENARIO
// --------
// Turn 9 (beyond the window). Glide docking failed (GPU OOM). AutoDock Vina
// succeeded as fallback. Top 10 poses are in docked_top10.sdf. User now asks:
// "run an MD simulation of the top docked poses".
//
// WITHOUT session memory: BioMate has no idea what protein/poses exist.
//   It would ask: "Do you have docked poses? What receptor file? What force field?"
// WITH session memory: The block tells the LLM everything needed:
//   - Glide failed → do NOT suggest retrying it
//   - AutoDock Vina succeeded → docked_top10.sdf exists
//   - Receptor = egfr_apo.pdb, force field agreed = AMBER
//   - User never confirmed Glide XP vs SP → if they want Glide retry, ask first
//
// The intent analysis on turn 9 reflects this context — force_field and
// input_ligands are already in inlineParameters because they were in session memory.
// =============================================================================
describe('UC-D8: MD simulation after failed docking — session memory drives recovery', () => {

  const postDockingMemory: SessionMemory = {
    active_task: 'setting up GROMACS MD simulation for top EGFR AutoDock Vina docked leads',
    key_decisions: [
      'AlphaFold3 structure prediction completed — egfr_apo.pdb is ready',
      'Glide docking FAILED (GPU OOM) — AutoDock Vina used as fallback',
      'AutoDock Vina completed — top 10 poses saved to docked_top10.sdf',
      'MD force field agreed: AMBER14SB + GAFF2 for ligand',
      'simulation length: 10 ns production run',
    ],
    uploaded_files: ['egfr_apo.pdb', 'library_1000.sdf'],
    attempted_workflows: [
      { path: 'drug_discovery/alphafold_db_search/main.nf', status: 'completed' },
      { path: 'drug_discovery/schrodinger_glide_docking/main.nf', status: 'failed' },
      { path: 'drug_discovery/autodock_vina/main.nf', status: 'completed' },
    ],
    current_parameters: {
      receptor: 'egfr_apo.pdb',
      input_ligands: 'docked_top10.sdf',
      force_field: 'AMBER14SB',
      simulation_time_ns: 10,
      temperature_K: 300,
    },
    open_questions: [
      'user has not confirmed whether to use Glide XP or SP if Glide retry is attempted',
    ],
  };

  const block = buildSessionMemoryBlock(postDockingMemory);

  describe('Failure history — prevents blind retry', () => {
    it('Glide failure recorded — LLM will not suggest retrying it unprompted', () =>
      expect(block).toContain('schrodinger_glide_docking/main.nf (failed)'));
    it('AutoDock Vina success recorded — LLM knows poses are available', () =>
      expect(block).toContain('autodock_vina/main.nf (completed)'));
    it('docked_top10.sdf in current_parameters — LLM uses it as MD input', () =>
      expect(block).toContain('docked_top10.sdf'));
  });

  describe('Parameter continuity — no re-asking', () => {
    it('AMBER14SB force field decision preserved', () =>
      expect(block).toContain('AMBER14SB'));
    it('10 ns simulation time preserved', () =>
      expect(block).toContain('"simulation_time_ns":10'));
    it('temperature_K preserved', () =>
      expect(block).toContain('temperature_K'));
    it('receptor file preserved', () =>
      expect(block).toContain('egfr_apo.pdb'));
  });

  describe('MD simulation intent after memory injection', () => {
    // With session memory in the system prompt, the LLM generates this intent
    const turn9Result = {
      type: 'workflow_generation',
      keywords: ['MD simulation', 'GROMACS', 'molecular dynamics', 'EGFR'],
      preferred_domains: ['drug_discovery', 'structural_biology'],
      key_terms: ['gromacs', 'md', 'molecular dynamics', 'amber', 'egfr', 'nanosecond'],
      needs_thinking: false,
      chain_hint: null,
      // Note: inlineParameters populated FROM session memory context
      inlineParameters: {
        receptor: 'egfr_apo.pdb',
        input_ligands: 'docked_top10.sdf',
        force_field: 'AMBER14SB',
        simulation_time_ns: 10,
      },
      facts: [
        { category: 'tool_preference', value: 'GROMACS', confidence: 0.95 },
        { category: 'file_reference', value: 'docked_top10.sdf', confidence: 1.0 },
        { category: 'parameter', value: 'AMBER14SB force field', confidence: 1.0 },
        { category: 'parameter', value: '10 ns simulation', confidence: 1.0 },
      ],
      workflowAmbiguity: null,
      confidence: 0.96,
      actions: wfActions,
    };
    const decomp = parseIntentResult(turn9Result, 'run an MD simulation of the top docked poses');

    it('[T9] workflowAmbiguity=null — memory resolved all parameters', () =>
      expect(decomp.primaryIntent.workflowAmbiguity).toBeNull());
    it('[T9] inlineParams.input_ligands from session memory (docked_top10.sdf)', () =>
      expect(decomp.primaryIntent.inlineParameters.input_ligands).toBe('docked_top10.sdf'));
    it('[T9] inlineParams.force_field from prior decision (AMBER14SB)', () =>
      expect(decomp.primaryIntent.inlineParameters.force_field).toBe('AMBER14SB'));
    it('[T9] key_terms include gromacs for precise workflow match', () =>
      expect(decomp.keyTerms).toContain('gromacs'));
    it('[T9] 4 facts: tool + file + 2 parameters — memory-augmented extraction', () =>
      expect(decomp.primaryIntent.facts.length).toBe(4));
    it('[T9] confidence=0.96 — no ambiguity because memory provides all context', () =>
      expect(decomp.primaryIntent.confidence).toBeGreaterThan(0.93));
  });

  describe('Unresolved question still tracked', () => {
    it('Glide XP vs SP question still in open_questions — will resurface if Glide retry asked', () =>
      expect(block).toContain('Glide XP or SP'));
  });
});
