/**
 * Library / molecule-design multi-step routing (2026-11-13).
 *
 * Dual path — both must work; never force only one:
 *
 * 1. **Catalog mega-chain** — when a real `workflow_chains` row matches the
 *    intent (e.g. drug_discovery_admet_gated_screening), honour that chain
 *    via chainHint → Tier 2 curated card (pipeline_steps + chain_* metadata).
 *    Do NOT invent new catalog rows for ad-hoc compositions.
 *
 * 2. **Step-by-step sequential** — synthesise-now/park library triage (and
 *    similar multi-step asks with no catalog match) decompose into ordinary
 *    indexed workflows, emit workflow_type:'pipeline' + pipeline_steps, and
 *    let PipelineListView run them **task by task** (endAtStep: 0).
 *
 * Ranking / synthesise-now vs park integrator: omitted until a real chemistry
 * multi-criteria workflow exists (assay_ingestion_and_ranking id 12814 is
 * tabular-only and must stay demoted for molecule libraries).
 */

/** Minimal shape shared with IntentDecomposition — avoid circular import with galaxy-assistant. */
export type LibraryTriageIntent = {
  id: string;
  type: string;
  subQuery: string;
  keywords: string[];
  inlineParameters: Record<string, string>;
  needsToolSearch: boolean;
  needsDatasets: boolean;
  confidence: number;
  facts: Array<{ category: string; value: string; confidence: number }>;
  dependsOn: string[];
  actions: {
    needsToolSearch: boolean;
    needsWorkflowGeneration: boolean;
    needsWorkflowModification: boolean;
    needsResearchAgent: boolean;
    needsBenchmarkAgent: boolean;
    needsDatasetAccess: boolean;
    needsLLMReasoning: boolean;
    needsChainProposal: boolean;
  };
  execution: 'pipeline';
  inputKinds: string[];
  inputFromDescription?: string;
  outputDescription?: string;
};

export type LibraryMoleculePath = 'catalog_mega_chain' | 'sequential_step_by_step';

export type LibraryMoleculeRouting = {
  path: LibraryMoleculePath;
  /** Set only for catalog_mega_chain — must be a real workflow_chains.name. */
  chainHint: string | null;
  rationale: string;
};

export type LibraryTriageDecomposition = {
  intents: LibraryTriageIntent[];
  isMultiIntent: true;
  isSequential: true;
  primaryIntent: LibraryTriageIntent;
  preferredDomains: string[];
  penalizedDomains: string[];
  keyTerms: string[];
  inputKinds: string[];
  needsThinking: false;
  chainHint: string | null;
  /**
   * Skip Tier-1 single-workflow collapse so docking→ADMET→… does not bind
   * one Admet Pred card. Tier-2 curated chain still runs when chainHint is set
   * (see processSequentialPipeline).
   */
  skipPipelineCollapse: true;
  rationale: string;
  /** Which dual path produced this plan (for logs / tests). */
  libraryMoleculePath: LibraryMoleculePath;
};

/**
 * Real catalog chains that cover library / virtual-screening / molecule-design
 * multi-step intents. Matching these is the mega-chain path — never invent new names.
 */
export const LIBRARY_RELATED_CATALOG_CHAINS = [
  'drug_discovery_admet_gated_screening',
  'drug_discovery_screening',
  'admet_to_cipa_cardiac',
  'target_to_lead_full',
  'andv_inhibitor_track_v1',
] as const;

export type LibraryRelatedCatalogChain =
  (typeof LIBRARY_RELATED_CATALOG_CHAINS)[number];

const WF_ACTIONS = {
  needsToolSearch: true,
  needsWorkflowGeneration: true,
  needsWorkflowModification: false,
  needsResearchAgent: false,
  needsBenchmarkAgent: false,
  needsDatasetAccess: false,
  needsLLMReasoning: true,
  needsChainProposal: false,
};

/** Cold-start / user phrasing for synthesise-now vs park bins. */
export function isSynthesiseNowParkRequest(message: string): boolean {
  const q = (message || '').toLowerCase();
  return /\bsynthesi[sz]e[- ]?now\b/.test(q) && /\bpark\b/.test(q);
}

/** Highly specific triage phrasing from the cold-start catalog / users. */
export function isLibraryTriageRequest(
  message: string,
  inputKinds?: string[] | null,
): boolean {
  const q = (message || '').toLowerCase();
  const synthesisePark = isSynthesiseNowParkRequest(q);
  const triageLibrary =
    /\btriage\b/.test(q) &&
    /\b(library|candidates?|compounds?|molecules?|ligands?)\b/.test(q);
  if (!synthesisePark && !triageLibrary) return false;

  // Pure assay-table ranking is NOT this path (12814).
  if (Array.isArray(inputKinds) && inputKinds.length > 0) {
    const chem =
      inputKinds.includes('molecules') || inputKinds.includes('structure');
    const tableOnly = inputKinds.includes('tabular') && !chem;
    if (tableOnly) return false;
  }
  return true;
}

function isKnownLibraryCatalogChain(
  name: string | null | undefined,
): name is LibraryRelatedCatalogChain {
  return (
    typeof name === 'string' &&
    (LIBRARY_RELATED_CATALOG_CHAINS as readonly string[]).includes(name)
  );
}

/**
 * True when the current message plausibly supports a catalog chain slug
 * (same spirit as Tier-2 stale-hint guard in galaxy-assistant).
 *
 * Tokens must match as whole words — `includes('drug')` falsely matched
 * "drug-like" and stole Generate-500 into ADMET-gated screening (2026-11-13).
 */
export function messageSupportsCatalogChainHint(
  message: string,
  chainHint: string,
): boolean {
  const msgLc = (message || '').toLowerCase();
  // Length ≥5 drops ambiguous 4-letter stems ("drug" ⊂ "drug-like"). Also refuse
  // a match when the token is only the left side of a hyphenated compound.
  const hintTokens = String(chainHint)
    .toLowerCase()
    .split(/[_\-\s]+/)
    .filter((t) => t.length >= 5);
  return (
    /\b(chain|pipeline|then|followed by|and then|multi-?step|end[- ]?to[- ]?end|screen|screening|triage)\b/.test(
      msgLc,
    ) ||
    hintTokens.some((t) =>
      new RegExp(`\\b${escapeRegExp(t)}(?!-)\\b`, 'i').test(msgLc),
    )
  );
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Generative molecule design ("generate N candidates…", REINVENT, de novo) —
 * must NOT route to library-screening mega-chains (ADMET-gated virtual screening).
 */
export function isMoleculeGenerateRequest(message: string): boolean {
  const q = (message || '').toLowerCase();
  if (!q.trim()) return false;
  if (/\b(reinvent|reinvent4|de[- ]novo|scaffold[- ]hop|generative)\b/.test(q)) return true;
  // "generate 500 candidates" / "design drug-like molecules" — generate|design + candidates/molecules
  // without explicit screen/dock/filter library phrasing.
  const generateIntent =
    /\b(generat(?:e|ing|ion)|design(?:ing)?|invent)\b/.test(q) &&
    /\b(candidates?|analogs?|analogues?|molecules?|compounds?|ligands?)\b/.test(q);
  if (!generateIntent) return false;
  const screeningIntent =
    /\b(screen|screening|dock|docking|virtual screening|filter(?:ing)? by admet|admet[- ]gated)\b/.test(
      q,
    );
  return !screeningIntent;
}

/**
 * Fingerprint match against known catalog example-query shapes.
 * Order matters: more specific chains first.
 */
export function matchLibraryRelatedCatalogChain(
  message: string,
): LibraryRelatedCatalogChain | null {
  const q = (message || '').toLowerCase();
  if (!q.trim()) return null;

  // Explicit slug / display-name mentions win.
  if (/\bdrug_discovery_admet_gated_screening\b/.test(q) || /admet[- ]gated/.test(q)) {
    return 'drug_discovery_admet_gated_screening';
  }
  if (/\bdrug_discovery_screening\b/.test(q)) {
    return 'drug_discovery_screening';
  }
  if (/\badmet_to_cipa_cardiac\b/.test(q) || (/\bcipa\b/.test(q) && /admet/.test(q))) {
    return 'admet_to_cipa_cardiac';
  }
  if (
    /\btarget_to_lead_full\b/.test(q) ||
    /target[- ]to[- ]lead/.test(q) ||
    (/end[- ]to[- ]end/.test(q) && /drug discovery/.test(q))
  ) {
    return 'target_to_lead_full';
  }
  if (/\bandv_inhibitor_track_v1\b/.test(q) || /\bandv\b/.test(q) || /andes virus/.test(q)) {
    return 'andv_inhibitor_track_v1';
  }

  // Example-query style: ADMET before docking / pharmacophore→ADMET→dock.
  if (
    (/admet/.test(q) && /dock/.test(q) && /\b(before|first|upfront|prior)\b/.test(q)) ||
    (/pharmacophore/.test(q) && /admet/.test(q) && /dock/.test(q)) ||
    (/filter/.test(q) && /admet/.test(q) && /dock/.test(q)) ||
    (/upfront/.test(q) && /(admet|toxicity)/.test(q) && /(screen|dock|library)/.test(q))
  ) {
    return 'drug_discovery_admet_gated_screening';
  }

  // Screen + ADMET + docking without pharmacophore-first / before-dock ordering.
  if (
    /admet/.test(q) &&
    /dock/.test(q) &&
    /\b(screen|screening|pipeline|rank)\b/.test(q) &&
    !/pharmacophore/.test(q) &&
    !/\b(before|first|upfront)\b/.test(q)
  ) {
    return 'drug_discovery_screening';
  }

  return null;
}

/**
 * Dual-path selector for library / molecule-design multi-step turns.
 *
 * Precedence:
 * 1. Classifier (or message) names a real library-related catalog chain → mega-chain
 * 2. Strong fingerprint match to a catalog chain (and not synthesise-now/park) → mega-chain
 * 3. Library triage / synthesise-now-park phrasing → sequential step-by-step
 * 4. Otherwise → null (leave normal routing alone)
 */
export function selectLibraryMoleculeRouting(
  message: string,
  inputKinds?: string[] | null,
  classifierChainHint?: string | null,
): LibraryMoleculeRouting | null {
  const synthesisePark = isSynthesiseNowParkRequest(message);

  // Generate / de-novo design is NOT a screening mega-chain. Leave normal routing
  // alone so reinvent4_lead_design (or honest disambiguation) can win — never
  // honour a leaked ADMET-gated chain_hint via "drug"⊂"drug-like".
  if (isMoleculeGenerateRequest(message)) {
    return null;
  }

  // Honour a classifier hint only when it is a real related catalog chain and
  // the current message supports it (avoid prior-turn leak).
  if (
    isKnownLibraryCatalogChain(classifierChainHint) &&
    messageSupportsCatalogChainHint(message, classifierChainHint) &&
    // synthesise-now/park has no catalog product — only honour if user named the chain.
    (!synthesisePark ||
      (message || '').toLowerCase().includes(classifierChainHint.toLowerCase()))
  ) {
    return {
      path: 'catalog_mega_chain',
      chainHint: classifierChainHint,
      rationale: `Catalog mega-chain path: honour chain_hint "${classifierChainHint}" (real workflow_chains row).`,
    };
  }

  const fingerprint = matchLibraryRelatedCatalogChain(message);
  // synthesise-now/park must stay sequential unless the user explicitly named a chain
  // (handled above via slug include). Weak fingerprints must not steal that cold-start.
  if (fingerprint && !synthesisePark) {
    return {
      path: 'catalog_mega_chain',
      chainHint: fingerprint,
      rationale: `Catalog mega-chain path: message matches curated chain "${fingerprint}".`,
    };
  }

  if (isLibraryTriageRequest(message, inputKinds)) {
    return {
      path: 'sequential_step_by_step',
      chainHint: null,
      rationale:
        'Step-by-step path: library triage / synthesise-now-park with no matching catalog mega-chain — ordinary single workflows task by task.',
    };
  }

  return null;
}

function step(
  id: string,
  subQuery: string,
  keywords: string[],
  inputKinds: string[],
  opts: {
    dependsOn?: string[];
    inputFrom?: string | null;
    outputDescription?: string;
  } = {},
): LibraryTriageIntent {
  return {
    id,
    type: 'workflow_generation',
    subQuery,
    keywords,
    inlineParameters: {},
    needsToolSearch: true,
    needsDatasets: false,
    confidence: 0.95,
    facts: [],
    dependsOn: opts.dependsOn || [],
    actions: { ...WF_ACTIONS },
    execution: 'pipeline',
    inputKinds,
    inputFromDescription: opts.inputFrom ?? undefined,
    outputDescription: opts.outputDescription,
  };
}

/**
 * Ordered tasks: docking → ADMET → pharmacophore. Each subQuery is written so
 * catalog search resolves to a single real nextflow workflow — not a chain row.
 */
export function buildLibraryTriageSequentialDecomposition(
  message: string,
  inputKinds?: string[] | null,
): LibraryTriageDecomposition {
  const kinds =
    Array.isArray(inputKinds) && inputKinds.length > 0
      ? [...inputKinds]
      : ['molecules', 'structure'];
  const moleculeKinds = kinds.filter(
    (k) => k === 'molecules' || k === 'structure',
  );
  const dockKinds = (moleculeKinds.length ? moleculeKinds : ['molecules']).includes(
    'structure',
  )
    ? moleculeKinds.length
      ? moleculeKinds
      : ['molecules', 'structure']
    : [...(moleculeKinds.length ? moleculeKinds : ['molecules']), 'structure'];
  const admetKinds = moleculeKinds.includes('molecules')
    ? moleculeKinds.filter((k) => k === 'molecules' || k === 'structure')
    : ['molecules'];

  const intents: LibraryTriageIntent[] = [
    step(
      'triage_docking',
      'Dock the compound library SMILES against the target receptor PDB with AutoDock Vina molecular docking (docking_autodock_vina)',
      ['docking', 'autodock', 'vina', 'receptor', 'ligand', 'smiles'],
      dockKinds,
      {
        dependsOn: [],
        inputFrom: null,
        outputDescription: 'docking scores and poses per compound',
      },
    ),
    step(
      'triage_admet',
      'Predict ADMET properties (hERG, DILI, ClinTox, solubility) for the compound library with predict_admet_properties',
      ['admet', 'herg', 'dili', 'toxicity', 'predict_admet_properties'],
      admetKinds.includes('molecules') ? admetKinds : ['molecules'],
      {
        dependsOn: ['triage_docking'],
        inputFrom:
          'compound library (same SMILES); optionally filter to docked poses',
        outputDescription: 'ADMET flags and passed_compounds',
      },
    ),
    step(
      'triage_pharmacophore',
      'Pharmacophore filtering of the compound library using reference actives SMILES (pharmacophore_filtering — build model from actives and screen library)',
      [
        'pharmacophore',
        'pharmacophore_filtering',
        'reference actives',
        'library screen',
      ],
      ['molecules'],
      {
        dependsOn: ['triage_admet'],
        inputFrom: 'library SMILES + pilot_reference_actives (or known actives)',
        outputDescription: 'pharmacophore-matched compounds',
      },
    ),
  ];

  return {
    intents,
    isMultiIntent: true,
    isSequential: true,
    primaryIntent: intents[0],
    preferredDomains: ['drug_discovery', 'pharmacology'],
    penalizedDomains: [],
    keyTerms: [
      'library triage',
      'synthesise-now',
      'docking',
      'ADMET',
      'pharmacophore',
      'AutoDock Vina',
    ],
    inputKinds: kinds,
    needsThinking: false,
    // No curated product for synthesise-now/park — steps are ordinary workflows.
    chainHint: null,
    skipPipelineCollapse: true,
    libraryMoleculePath: 'sequential_step_by_step',
    rationale:
      'Library triage (synthesise-now / park) needs docking, ADMET, and pharmacophore as separate runnable workflows — not one Admet Pred card and not a catalogued mega-chain.',
  };
}

/**
 * Decomposition that enters processSequentialPipeline with a real catalog
 * chainHint. skipPipelineCollapse skips Tier-1 Admet collapse; Tier-2 still
 * runs because chainHint is set.
 */
export function buildCatalogMegaChainDecomposition(
  chainName: LibraryRelatedCatalogChain | string,
  message: string,
  inputKinds?: string[] | null,
): LibraryTriageDecomposition {
  const kinds =
    Array.isArray(inputKinds) && inputKinds.length > 0
      ? [...inputKinds]
      : ['molecules', 'structure'];

  // Placeholder intents so multi-intent / sequential gates fire; Tier-2 replaces
  // them with the curated chain's steps when lookup succeeds.
  const intents: LibraryTriageIntent[] = [
    step(
      'catalog_chain_entry',
      message || `Run curated chain ${chainName}`,
      [chainName, 'pipeline', 'screening'],
      kinds,
      {
        dependsOn: [],
        outputDescription: `curated chain ${chainName} (step 1+)`,
      },
    ),
    step(
      'catalog_chain_follow',
      `Continue curated workflow chain ${chainName}`,
      [chainName, 'pipeline'],
      kinds,
      {
        dependsOn: ['catalog_chain_entry'],
        inputFrom: 'prior chain step outputs',
        outputDescription: `curated chain ${chainName} (remaining steps)`,
      },
    ),
  ];

  return {
    intents,
    isMultiIntent: true,
    isSequential: true,
    primaryIntent: intents[0],
    preferredDomains: ['drug_discovery', 'pharmacology'],
    penalizedDomains: [],
    keyTerms: [chainName, 'drug discovery', 'virtual screening'],
    inputKinds: kinds,
    needsThinking: false,
    chainHint: chainName,
    skipPipelineCollapse: true,
    libraryMoleculePath: 'catalog_mega_chain',
    rationale: `Use catalog mega-chain "${chainName}" (real workflow_chains row) — not an ad-hoc sequential invent, not a single Admet Pred bind.`,
  };
}

/**
 * Apply dual-path routing: returns a decomposition override, or null when
 * normal analyzeIntent routing should stand.
 */
export function applyLibraryMoleculeDualPath(
  message: string,
  inputKinds?: string[] | null,
  classifierChainHint?: string | null,
): LibraryTriageDecomposition | null {
  const selection = selectLibraryMoleculeRouting(
    message,
    inputKinds,
    classifierChainHint,
  );
  if (!selection) return null;
  if (selection.path === 'catalog_mega_chain' && selection.chainHint) {
    return buildCatalogMegaChainDecomposition(
      selection.chainHint,
      message,
      inputKinds,
    );
  }
  return buildLibraryTriageSequentialDecomposition(message, inputKinds);
}

/** Roles expected in a correct triage sequential plan (for tests). */
export function libraryTriageStepRoles(
  decomposition: { intents: Array<{ subQuery?: string }> },
): string[] {
  return decomposition.intents.map((i) => {
    const q = (i.subQuery || '').toLowerCase();
    if (/dock|vina/.test(q)) return 'docking';
    if (/admet/.test(q)) return 'admet';
    if (/pharmacoph/.test(q)) return 'pharmacophore';
    return 'other';
  });
}
