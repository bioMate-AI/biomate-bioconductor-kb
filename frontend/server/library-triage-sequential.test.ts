/**
 * Library triage → sequential single-workflow plan (not a catalogued chain).
 */
import { describe, expect, it } from 'vitest';
import {
  buildLibraryTriageSequentialDecomposition,
  isLibraryTriageRequest,
  libraryTriageStepRoles,
} from './library-triage-sequential';
import { isSingleBoundWorkflow, singleWorkflowGroundingDirective } from './single-workflow-grounding';

const COLD_START =
  'Triage this library into synthesise-now and park.';

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

    // Each step is an ordinary workflow_generation intent — not a chain product.
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
