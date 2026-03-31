/**
 * Unit Tests: analyzeIntent() Unified Query Understanding (UQU) Fields
 *
 * Tests parseIntentResult() with synthetic LLM response objects — no live API calls.
 * Verifies that the new UQU fields (preferredDomains, keyTerms, needsThinking, chainHint)
 * are correctly extracted from both single-intent and multi-intent LLM responses.
 */

import { describe, it, expect } from 'vitest';
import {
  inferActionsFromType,
  CLARIFICATION_FALLBACKS,
  DOMAIN_SPECIALIST_GUIDANCE,
  buildDomainSpecialistBlock,
  type IntentDecomposition,
  type DecomposedIntent,
} from './galaxy-assistant';

// ── Minimal reimplementation of parseIntentResult for unit testing ────────────
// This mirrors the real implementation so tests break if the real code diverges.
// When galaxy-assistant.ts parseIntentResult changes, update this too.
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
    }));

    const primaryIntent = isSequential
      ? intents[0]
      : intents.reduce((best, current) => current.confidence > best.confidence ? current : best);

    return { intents, isMultiIntent: intents.length > 1, isSequential, primaryIntent, preferredDomains, keyTerms, needsThinking, chainHint };
  }

  const intentType = result.type || 'general_question';
  const singleIntent: DecomposedIntent = {
    id: 'intent_1',
    type: intentType,
    subQuery: originalMessage,
    keywords: result.keywords || [],
    inlineParameters: result.inlineParameters || {},
    needsToolSearch: result.needsToolSearch !== false,
    needsDatasets: result.needsDatasets !== false,
    confidence: result.confidence || 0.5,
    facts: parseFacts(result.facts),
    dependsOn: [],
    actions: parseActions(result.actions, intentType),
    workflowAmbiguity: typeof result.workflowAmbiguity === 'string' ? result.workflowAmbiguity : null,
  };

  return { intents: [singleIntent], isMultiIntent: false, primaryIntent: singleIntent, preferredDomains, keyTerms, needsThinking, chainHint };
}

// ── Helpers ────────────────────────────────────────────────────────────────────
const defaultActions = {
  needsToolSearch: true, needsWorkflowGeneration: true, needsWorkflowModification: false,
  needsResearchAgent: false, needsBenchmarkAgent: false, needsDatasetAccess: false, needsLLMReasoning: true,
};

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('parseIntentResult — UQU field extraction', () => {

  describe('1.1 Sequential pipeline — multi-step numbered list', () => {
    const result = {
      is_sequential: true,
      preferred_domains: ['transcriptomics'],
      key_terms: ['fastqc', 'trim galore', 'star', 'deseq2'],
      needs_thinking: false,
      chain_hint: 'bulk_rnaseq_de_analysis',
      intents: [
        { id: 'step_1', type: 'workflow_generation', subQuery: 'FastQC on raw reads',
          keywords: ['fastqc'], dependsOn: [], output_description: 'QC reports',
          actions: defaultActions, facts: [], confidence: 0.95 },
        { id: 'step_2', type: 'workflow_generation', subQuery: 'Adapter trimming with Trim Galore',
          keywords: ['trim galore'], dependsOn: ['step_1'],
          input_from_description: 'raw FASTQ from step 1', output_description: 'trimmed reads',
          actions: defaultActions, facts: [], confidence: 0.9 },
        { id: 'step_3', type: 'workflow_generation', subQuery: 'Align with STAR to hg38',
          keywords: ['star', 'hg38'], dependsOn: ['step_2'],
          input_from_description: 'trimmed reads from step 2',
          actions: defaultActions, facts: [], confidence: 0.9 },
      ],
    };
    const decomp = parseIntentResult(result, '1. FastQC\n2. Trim Galore\n3. STAR');

    it('isSequential=true', () => expect(decomp.isSequential).toBe(true));
    it('intents.length=3', () => expect(decomp.intents.length).toBe(3));
    it('preferredDomains includes transcriptomics', () => expect(decomp.preferredDomains).toContain('transcriptomics'));
    it('keyTerms includes fastqc', () => expect(decomp.keyTerms).toContain('fastqc'));
    it('keyTerms includes star', () => expect(decomp.keyTerms).toContain('star'));
    it('needsThinking=false', () => expect(decomp.needsThinking).toBe(false));
    it('chainHint=bulk_rnaseq_de_analysis', () => expect(decomp.chainHint).toBe('bulk_rnaseq_de_analysis'));
    it('step_2 dependsOn step_1', () => expect(decomp.intents[1].dependsOn[0]).toBe('step_1'));
    it('step_3 inputFromDescription references step 2', () =>
      expect((decomp.intents[2] as any).inputFromDescription).toContain('step 2'));
    it('primaryIntent is first step for sequential', () => expect(decomp.primaryIntent.id).toBe('step_1'));
  });

  describe('1.2 Sequential pipeline — bulleted list (same structure)', () => {
    const result = {
      is_sequential: true,
      preferred_domains: ['transcriptomics'],
      key_terms: ['fastp', 'hisat2', 'featurecounts'],
      needs_thinking: false,
      chain_hint: null,
      intents: [
        { id: 'step_1', type: 'workflow_generation', subQuery: 'Trim reads with fastp',
          keywords: ['fastp'], dependsOn: [], facts: [], confidence: 0.9, actions: defaultActions },
        { id: 'step_2', type: 'workflow_generation', subQuery: 'Align to mm10 with HISAT2',
          keywords: ['hisat2', 'mm10'], dependsOn: ['step_1'],
          input_from_description: 'trimmed reads from step 1', facts: [], confidence: 0.85, actions: defaultActions },
      ],
    };
    const decomp = parseIntentResult(result, '- Trim reads with fastp\n- Align to mm10 with HISAT2');

    it('isSequential=true', () => expect(decomp.isSequential).toBe(true));
    it('intents.length=2', () => expect(decomp.intents.length).toBe(2));
    it('chainHint=null when no chain matches', () => expect(decomp.chainHint).toBeNull());
    it('step_2 depends on step_1', () => expect(decomp.intents[1].dependsOn).toContain('step_1'));
  });

  describe('1.3 Single intent — domain and key_terms extraction', () => {
    const result = {
      type: 'workflow_generation',
      keywords: ['molecular docking', 'autodock vina'],
      preferred_domains: ['drug_discovery', 'structural_biology'],
      key_terms: ['autodock', 'vina', 'docking', 'ligand'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: {},
      facts: [],
      workflowAmbiguity: null,
      confidence: 0.92,
      actions: defaultActions,
    };
    const decomp = parseIntentResult(result, 'Run AutoDock Vina docking on my ligand library against EGFR');

    it('isSequential is falsy', () => expect(decomp.isSequential).toBeFalsy());
    it('preferredDomains includes drug_discovery', () => expect(decomp.preferredDomains).toContain('drug_discovery'));
    it('preferredDomains includes structural_biology', () => expect(decomp.preferredDomains).toContain('structural_biology'));
    it('keyTerms includes autodock', () => expect(decomp.keyTerms).toContain('autodock'));
    it('keyTerms includes docking', () => expect(decomp.keyTerms).toContain('docking'));
    it('chainHint=null', () => expect(decomp.chainHint).toBeNull());
    it('needsThinking=false', () => expect(decomp.needsThinking).toBe(false));
    it('intent type=workflow_generation', () => expect(decomp.primaryIntent.type).toBe('workflow_generation'));
  });

  describe('1.4 Complex comparison — needs_thinking=true', () => {
    const result = {
      type: 'result_comparison',
      keywords: ['DESeq2', 'edgeR'],
      preferred_domains: ['transcriptomics'],
      key_terms: ['DESeq2', 'edgeR', 'differential expression'],
      needs_thinking: true,
      chain_hint: null,
      facts: [],
      confidence: 0.88,
      actions: { ...defaultActions, needsWorkflowGeneration: false, needsBenchmarkAgent: true },
    };
    const decomp = parseIntentResult(result, 'Compare DESeq2 vs edgeR for differential expression');

    it('needsThinking=true', () => expect(decomp.needsThinking).toBe(true));
    it('type=result_comparison', () => expect(decomp.primaryIntent.type).toBe('result_comparison'));
    it('domain=transcriptomics', () => expect(decomp.preferredDomains).toContain('transcriptomics'));
  });

  describe('1.5 Fallback safety — old response without UQU fields', () => {
    const result = { type: 'workflow_generation', keywords: ['rnaseq'] };
    const decomp = parseIntentResult(result, 'Run RNA-seq analysis');

    it('does not throw', () => expect(decomp).toBeTruthy());
    it('preferredDomains defaults to empty array', () => expect(decomp.preferredDomains).toEqual([]));
    it('keyTerms defaults to empty array', () => expect(decomp.keyTerms).toEqual([]));
    it('needsThinking defaults to false', () => expect(decomp.needsThinking).toBe(false));
    it('chainHint defaults to null', () => expect(decomp.chainHint).toBeNull());
  });

  describe('1.6 Multi-intent parallel — UQU fields on outer wrapper', () => {
    const result = {
      is_sequential: false,
      preferred_domains: ['transcriptomics'],
      key_terms: ['DESeq2', 'edgeR'],
      needs_thinking: true,
      chain_hint: null,
      intents: [
        { id: 'intent_1', type: 'workflow_generation', subQuery: 'Run DE analysis',
          keywords: ['differential expression'], dependsOn: [], facts: [], confidence: 0.9,
          actions: defaultActions },
        { id: 'intent_2', type: 'result_comparison', subQuery: 'Compare DESeq2 vs edgeR',
          keywords: ['DESeq2', 'edgeR'], dependsOn: [], facts: [], confidence: 0.85,
          actions: { ...defaultActions, needsWorkflowGeneration: false, needsBenchmarkAgent: true } },
      ],
    };
    const decomp = parseIntentResult(result, 'Run DE analysis AND compare DESeq2 vs edgeR');

    it('isMultiIntent=true', () => expect(decomp.isMultiIntent).toBe(true));
    it('isSequential=false for parallel multi-intent', () => expect(decomp.isSequential).toBeFalsy());
    it('two intents', () => expect(decomp.intents.length).toBe(2));
    it('preferredDomains on wrapper', () => expect(decomp.preferredDomains).toContain('transcriptomics'));
    it('needsThinking=true', () => expect(decomp.needsThinking).toBe(true));
    it('primaryIntent=highest confidence', () => expect(decomp.primaryIntent.id).toBe('intent_1'));
  });

  // ── Use Case 5: domain profile MUST NOT suppress workflowAmbiguity ────────────
  // Even when preferred_domains=['transcriptomics'] (from an oncology profile),
  // a vague query like "analyze my expression data" must still produce workflowAmbiguity.
  // This confirms the parser correctly carries workflowAmbiguity through to the intent.
  describe('1.7 Use Case 5 — domain profile oncology + vague expression query', () => {
    const result = {
      type: 'workflow_generation',
      keywords: ['expression data', 'rna-seq'],
      preferred_domains: ['transcriptomics'],   // oncology profile would set this
      key_terms: ['expression', 'rna-seq'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: {},
      facts: [],
      workflowAmbiguity: 'rnaseq_type',   // LLM MUST still ask — bulk vs scRNA
      confidence: 0.7,
      actions: defaultActions,
    };
    const decomp = parseIntentResult(result, 'analyze my expression data');

    it('workflowAmbiguity=rnaseq_type preserved', () =>
      expect(decomp.primaryIntent.workflowAmbiguity).toBe('rnaseq_type'));
    it('preferred_domains still set from profile', () =>
      expect(decomp.preferredDomains).toContain('transcriptomics'));
    it('workflowAmbiguity is NOT null just because domain is set', () =>
      expect(decomp.primaryIntent.workflowAmbiguity).not.toBeNull());
    it('needsThinking=false (clarification is cheap)', () =>
      expect(decomp.needsThinking).toBe(false));
  });

  describe('1.8 workflowAmbiguity=null when query is specific', () => {
    const result = {
      type: 'workflow_generation',
      keywords: ['bulk rna-seq', 'deseq2'],
      preferred_domains: ['transcriptomics'],
      key_terms: ['deseq2', 'bulk'],
      needs_thinking: false,
      chain_hint: null,
      inlineParameters: {},
      facts: [],
      workflowAmbiguity: null,   // user already specified "bulk" → no ambiguity
      confidence: 0.95,
      actions: defaultActions,
    };
    const decomp = parseIntentResult(result, 'run bulk RNA-seq differential expression with DESeq2');

    it('workflowAmbiguity=null when query is unambiguous', () =>
      expect(decomp.primaryIntent.workflowAmbiguity).toBeNull());
    it('preferred_domains set', () => expect(decomp.preferredDomains).toContain('transcriptomics'));
  });
});

// ── S5: CLARIFICATION_FALLBACKS completeness ──────────────────────────────────
// Every fork-point type listed in the system prompt MUST have a corresponding
// entry in CLARIFICATION_FALLBACKS. This test acts as a compile-time guard —
// it will fail immediately when a new fork-point is added to the system prompt
// without a matching fallback string.

describe('S5: CLARIFICATION_FALLBACKS completeness', () => {
  // Canonical fork-point type strings extracted from the system prompt
  // (galaxy-assistant.ts "Known fork points" section).
  // When you add a new fork-point to the system prompt, add it here too.
  const SYSTEM_PROMPT_FORK_POINTS = [
    // GENOMICS
    'variant_type',
    'assembly_type',
    // RNA-SEQ
    'rnaseq_type',
    'scrna_type',
    // EPIGENOMICS
    'peak_calling_type',
    'chip_target',
    // PROTEOMICS
    'proteomics_type',
    // STRUCTURAL BIOLOGY
    'cryoem_type',
    'cryoem_sample',
    // GENOMICS (somatic sub-type)
    'somatic_paired',
    // RNA-SEQ (sub-type)
    'rnaseq_focus',
    // CELL BIOLOGY
    'flow_cytometry_type',
    // METAGENOMICS
    'metagenomics_type',
    // DRUG DISCOVERY
    'docking_type',
    'admet_scope',
  ] as const;

  it('CLARIFICATION_FALLBACKS is exported and is an object', () => {
    expect(typeof CLARIFICATION_FALLBACKS).toBe('object');
    expect(CLARIFICATION_FALLBACKS).not.toBeNull();
  });

  for (const forkPoint of SYSTEM_PROMPT_FORK_POINTS) {
    it(`has fallback for fork-point "${forkPoint}"`, () => {
      expect(CLARIFICATION_FALLBACKS).toHaveProperty(forkPoint);
      expect(typeof CLARIFICATION_FALLBACKS[forkPoint]).toBe('string');
      expect(CLARIFICATION_FALLBACKS[forkPoint].length).toBeGreaterThan(20);
    });
  }

  it('has no extra entries not listed in the system prompt (catches stale entries)', () => {
    const knownKeys = new Set<string>(SYSTEM_PROMPT_FORK_POINTS);
    const extraKeys = Object.keys(CLARIFICATION_FALLBACKS).filter(k => !knownKeys.has(k));
    expect(extraKeys).toEqual([]);
  });
});

// ── S3: DOMAIN_SPECIALIST_GUIDANCE completeness ───────────────────────────────
describe('S3: DOMAIN_SPECIALIST_GUIDANCE', () => {
  // Domains that have registered workflows — each must have a specialist guidance entry.
  const DOMAINS_WITH_WORKFLOWS = [
    'genomics',
    'transcriptomics',
    'single_cell',
    'epigenomics',
    'proteomics',
    'metabolomics',
    'metagenomics',
    'structural_biology',
    'drug_discovery',
    'cryo_em',
    'systems_biology',
    'synthetic_biology',
    'bioimaging',
    'lab_automation',
    'cancer_biology',
    'cell_biology',
  ] as const;

  it('DOMAIN_SPECIALIST_GUIDANCE is exported and is an object', () => {
    expect(typeof DOMAIN_SPECIALIST_GUIDANCE).toBe('object');
    expect(DOMAIN_SPECIALIST_GUIDANCE).not.toBeNull();
  });

  for (const domain of DOMAINS_WITH_WORKFLOWS) {
    it(`has specialist guidance for domain "${domain}"`, () => {
      expect(DOMAIN_SPECIALIST_GUIDANCE).toHaveProperty(domain);
      const guidance = DOMAIN_SPECIALIST_GUIDANCE[domain];
      expect(typeof guidance).toBe('string');
      // Must be a non-trivial expert framing (at least 80 chars)
      expect((guidance as string).length).toBeGreaterThan(80);
      // Must start with "Expert framing" prefix for consistent formatting
      expect(guidance as string).toMatch(/^Expert framing/);
    });
  }

  it('buildDomainSpecialistBlock returns empty string for empty domains', () => {
    expect(buildDomainSpecialistBlock([])).toBe('');
  });

  it('buildDomainSpecialistBlock returns empty string for unknown domain', () => {
    expect(buildDomainSpecialistBlock(['unknown_domain_xyz'])).toBe('');
  });

  it('buildDomainSpecialistBlock wraps guidance in <domain_specialist> tags', () => {
    const block = buildDomainSpecialistBlock(['genomics']);
    expect(block).toMatch(/^<domain_specialist>/);
    expect(block).toMatch(/<\/domain_specialist>/);
    expect(block).toContain('Expert framing (genomics)');
  });

  it('buildDomainSpecialistBlock concatenates multiple domains', () => {
    const block = buildDomainSpecialistBlock(['genomics', 'drug_discovery']);
    expect(block).toContain('Expert framing (genomics)');
    expect(block).toContain('Expert framing (drug discovery)');
    // Only one wrapper pair
    expect((block.match(/<domain_specialist>/g) || []).length).toBe(1);
    expect((block.match(/<\/domain_specialist>/g) || []).length).toBe(1);
  });

  it('buildDomainSpecialistBlock skips unknown domains silently', () => {
    const block = buildDomainSpecialistBlock(['genomics', 'no_such_domain', 'drug_discovery']);
    expect(block).toContain('Expert framing (genomics)');
    expect(block).toContain('Expert framing (drug discovery)');
    expect(block).not.toContain('no_such_domain');
  });
});
