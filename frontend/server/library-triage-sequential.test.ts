/**
 * Library / molecule-design dual path: catalog mega-chain OR sequential step-by-step.
 */
import { describe, expect, it } from 'vitest';
import {
  applyLibraryMoleculeDualPath,
  buildCatalogMegaChainDecomposition,
  buildLibraryTriageSequentialDecomposition,
  isLibraryTriageRequest,
  libraryTriageStepRoles,
  matchLibraryRelatedCatalogChain,
  selectLibraryMoleculeRouting,
} from './library-triage-sequential';
import { isSingleBoundWorkflow, singleWorkflowGroundingDirective } from './single-workflow-grounding';
import { awaitsWorkflowInput, hasGeneratedWorkflow } from '../shared/workflow-response-state';

const COLD_START =
  'Triage this library into synthesise-now and park.';

const ADMET_GATED =
  'Screen this library against the target, filter by ADMET first, then dock';

const ADMET_THEN_DOCK =
  'Run ADMET screening then molecular docking on this compound library';

describe('isLibraryTriageRequest', () => {
  it('matches the cold-start synthesise-now / park prompt', () => {
    expect(isLibraryTriageRequest(COLD_START, ['molecules', 'structure'])).toBe(true);
    expect(isLibraryTriageRequest(COLD_START, undefined)).toBe(true);
  });

  it('matches generic library triage phrasing', () => {
    expect(
      isLibraryTriageRequest('Please triage this compound library for synthesis priority', [
        'molecules',
      ]),
    ).toBe(true);
  });

  it('rejects pure tabular assay ranking (12814 path)', () => {
    expect(
      isLibraryTriageRequest('Triage these compounds from my assay CSV', ['tabular']),
    ).toBe(false);
  });

  it('rejects unrelated prompts', () => {
    expect(isLibraryTriageRequest('Run ADMET on aspirin', ['molecules'])).toBe(false);
    expect(isLibraryTriageRequest('Dock these ligands with Vina', ['molecules', 'structure'])).toBe(
      false,
    );
  });
});

describe('selectLibraryMoleculeRouting — dual path', () => {
  it('selects step-by-step for synthesise-now / park (no fake mega-chain)', () => {
    const sel = selectLibraryMoleculeRouting(COLD_START, ['molecules', 'structure']);
    expect(sel?.path).toBe('sequential_step_by_step');
    expect(sel?.chainHint).toBeNull();
  });

  it('does not steal synthesise-now/park into drug_discovery_screening via weak fingerprints', () => {
    // Mentions library + triage only — must stay sequential.
    const sel = selectLibraryMoleculeRouting(COLD_START, ['molecules'], 'drug_discovery_screening');
    expect(sel?.path).toBe('sequential_step_by_step');
    expect(sel?.chainHint).toBeNull();
  });

  it('selects catalog mega-chain for ADMET-gated screening phrasing', () => {
    const sel = selectLibraryMoleculeRouting(ADMET_GATED, ['molecules', 'structure']);
    expect(sel?.path).toBe('catalog_mega_chain');
    expect(sel?.chainHint).toBe('drug_discovery_admet_gated_screening');
  });

  it('selects catalog mega-chain for ADMET then docking screening', () => {
    expect(matchLibraryRelatedCatalogChain(ADMET_THEN_DOCK)).toBe('drug_discovery_screening');
    const sel = selectLibraryMoleculeRouting(ADMET_THEN_DOCK, ['molecules']);
    expect(sel?.path).toBe('catalog_mega_chain');
    expect(sel?.chainHint).toBe('drug_discovery_screening');
  });

  it('honours a classifier chain_hint when the message supports it', () => {
    const sel = selectLibraryMoleculeRouting(
      'Run the ADMET-gated virtual screening pipeline on my library',
      ['molecules'],
      'drug_discovery_admet_gated_screening',
    );
    expect(sel?.path).toBe('catalog_mega_chain');
    expect(sel?.chainHint).toBe('drug_discovery_admet_gated_screening');
  });

  it('returns null for single-workflow ADMET (leave normal routing alone)', () => {
    expect(selectLibraryMoleculeRouting('Run ADMET on aspirin', ['molecules'])).toBeNull();
  });
});

describe('applyLibraryMoleculeDualPath', () => {
  it('builds sequential decomposition for cold-start triage', () => {
    const plan = applyLibraryMoleculeDualPath(COLD_START, ['molecules', 'structure']);
    expect(plan?.libraryMoleculePath).toBe('sequential_step_by_step');
    expect(plan?.chainHint).toBeNull();
    expect(plan?.skipPipelineCollapse).toBe(true);
    expect(libraryTriageStepRoles(plan!)).toEqual(['docking', 'admet', 'pharmacophore']);
  });

  it('builds catalog mega-chain decomposition with chainHint set', () => {
    const plan = applyLibraryMoleculeDualPath(ADMET_GATED, ['molecules', 'structure']);
    expect(plan?.libraryMoleculePath).toBe('catalog_mega_chain');
    expect(plan?.chainHint).toBe('drug_discovery_admet_gated_screening');
    expect(plan?.skipPipelineCollapse).toBe(true); // still skip Tier-1 Admet collapse
    expect(plan?.isSequential).toBe(true);
    expect(plan?.isMultiIntent).toBe(true);
  });
});

describe('buildLibraryTriageSequentialDecomposition', () => {
  it('emits ≥3 sequential steps with docking + ADMET + pharmacophore roles', () => {
    const plan = buildLibraryTriageSequentialDecomposition(COLD_START, [
      'molecules',
      'structure',
    ]);
    expect(plan.isMultiIntent).toBe(true);
    expect(plan.isSequential).toBe(true);
    expect(plan.skipPipelineCollapse).toBe(true);
    expect(plan.chainHint).toBeNull();
    expect(plan.intents.length).toBeGreaterThanOrEqual(3);

    const roles = libraryTriageStepRoles(plan);
    expect(roles).toEqual(['docking', 'admet', 'pharmacophore']);

    for (const intent of plan.intents) {
      expect(intent.type).toBe('workflow_generation');
      expect(intent.actions.needsWorkflowGeneration).toBe(true);
      expect(intent.subQuery.length).toBeGreaterThan(20);
    }

    expect(plan.intents[0].inputKinds).toContain('molecules');
    expect(plan.intents[0].inputKinds).toContain('structure');
  });

  it('does not name a catalogued Library Triage mega-chain', () => {
    const plan = buildLibraryTriageSequentialDecomposition(COLD_START);
    expect(JSON.stringify(plan)).not.toMatch(/workflow_chains/);
    expect(plan.chainHint).toBeNull();
    expect(plan.rationale.toLowerCase()).toMatch(/not a catalogued mega-chain|not one admet/);
  });
});

describe('buildCatalogMegaChainDecomposition', () => {
  it('carries a real chainHint for Tier-2 curated lookup', () => {
    const plan = buildCatalogMegaChainDecomposition(
      'drug_discovery_admet_gated_screening',
      ADMET_GATED,
      ['molecules'],
    );
    expect(plan.chainHint).toBe('drug_discovery_admet_gated_screening');
    expect(plan.libraryMoleculePath).toBe('catalog_mega_chain');
    expect(plan.skipPipelineCollapse).toBe(true);
  });
});

describe('grounding + pipeline payload shape', () => {
  it('pipeline payload is NOT a single-bound workflow (grounding stays quiet)', () => {
    const plan = buildLibraryTriageSequentialDecomposition(COLD_START, [
      'molecules',
      'structure',
    ]);
    const pipelinePayload = {
      success: true,
      workflow_type: 'pipeline' as const,
      name: 'Library Triage (3 steps — task by task)',
      pipeline_steps: plan.intents.map((i, idx) => ({
        id: i.id,
        step_number: idx + 1,
        workflow_name: i.subQuery,
        nextflow_path: null,
        status: 'pending',
      })),
    };
    expect(isSingleBoundWorkflow(pipelinePayload)).toBe(false);
    expect(singleWorkflowGroundingDirective(pipelinePayload)).toBe('');
  });

  it('Admet Pred alone still gets grounding when it is the sole bind', () => {
    const d = singleWorkflowGroundingDirective(
      { success: true, workflow_ga: { name: 'Admet Pred' } },
      'Admet Pred',
    );
    expect(d).toMatch(/Admet Pred/);
    expect(d).toMatch(/Do NOT narrate a multi-step/);
  });
});

describe('FE hasProposal — both paths remain panel-bindable', () => {
  it('sequential pipeline_steps is a generated proposal', () => {
    const wf = {
      success: true,
      workflow_type: 'pipeline',
      pipeline_steps: [{ id: 'a' }, { id: 'b' }],
      source: 'library_triage_sequential',
    };
    expect(awaitsWorkflowInput(wf)).toBe(false);
    expect(hasGeneratedWorkflow(wf)).toBe(true);
  });

  it('catalog mega-chain (pipeline + chain_*) is a generated proposal even with needs_user_feedback', () => {
    const wf = {
      success: true,
      workflow_type: 'pipeline',
      pipeline_steps: [{ id: 1 }, { id: 2 }, { id: 3 }],
      source: 'biomate_curated_chain',
      chain_name: 'drug_discovery_admet_gated_screening',
      chain_display_name: 'ADMET-Gated Virtual Screening',
      needs_user_feedback: true,
    };
    expect(awaitsWorkflowInput(wf)).toBe(false);
    expect(hasGeneratedWorkflow(wf)).toBe(true);
  });

  it('legacy workflow_type chain + chain_steps still rebinds the panel', () => {
    const wf = {
      success: true,
      workflow_type: 'chain',
      chain_steps: [{ id: 1 }],
      needs_user_feedback: true,
    };
    expect(hasGeneratedWorkflow(wf)).toBe(true);
  });
});
