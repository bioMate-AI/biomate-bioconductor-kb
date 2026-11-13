/**
 * Library triage → sequential single-workflow plan (2026-11-13).
 *
 * Cold-start: "Triage this library into synthesise-now and park" with a SMILES
 * library + receptor (+ optional reference actives) must NOT bind a single
 * Admet Pred card, and must NOT invent a catalogued workflow_chains product.
 *
 * Correct model: decompose into ordinary indexed workflows, emit
 * workflow_type:'pipeline' + pipeline_steps, and let PipelineListView run them
 * **task by task** (endAtStep: 0). Each panel bind is one workflow.
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
  chainHint: null;
  skipPipelineCollapse: true;
  rationale: string;
};

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

/** Highly specific triage phrasing from the cold-start catalog / users. */
export function isLibraryTriageRequest(
  message: string,
  inputKinds?: string[] | null,
): boolean {
  const q = (message || '').toLowerCase();
  const synthesisePark =
    /\bsynthesi[sz]e[- ]?now\b/.test(q) && /\bpark\b/.test(q);
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
    // Never escalate to a curated workflow_chains row — steps are ordinary workflows.
    chainHint: null,
    skipPipelineCollapse: true,
    rationale:
      'Library triage (synthesise-now / park) needs docking, ADMET, and pharmacophore as separate runnable workflows — not one Admet Pred card and not a catalogued mega-chain.',
  };
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
