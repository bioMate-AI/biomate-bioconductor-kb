import { describe, expect, it } from 'vitest';
import { extractWorkflowEdits } from './workflow-edits-extract';
import type { WorkflowArtifact } from './workflow-edits';

function chain(): WorkflowArtifact {
  return {
    pipeline_steps: [
      { id: 'step-1', workflow_path: 'rnaseq/main.nf', params: { genome: 'GRCh38', single_end: false } },
      { id: 'step-2', workflow_path: 'docking/vina_dock/main.nf', params: { exhaustiveness: 8 } },
    ],
  };
}

describe('extractWorkflowEdits', () => {
  it('matches "set X to Y"', () => {
    const e = extractWorkflowEdits('set exhaustiveness to 16', chain());
    expect(e).toEqual([{ op: 'set_param', stepId: 'step-2', paramName: 'exhaustiveness', value: 16 }]);
  });

  it('matches "change X to Y" with float coercion', () => {
    const e = extractWorkflowEdits('change exhaustiveness to 12.5', chain());
    expect(e[0].op).toBe('set_param');
    expect((e[0] as any).value).toBe(12.5);
  });

  it('matches "X = Y" with string', () => {
    const e = extractWorkflowEdits('genome = GRCm39', chain());
    expect(e).toEqual([{ op: 'set_param', stepId: 'step-1', paramName: 'genome', value: 'GRCm39' }]);
  });

  it('coerces true/false', () => {
    const e = extractWorkflowEdits('set single_end to true', chain());
    expect((e[0] as any).value).toBe(true);
  });

  it('respects the "on step X" qualifier', () => {
    const wf: WorkflowArtifact = {
      pipeline_steps: [
        { id: 'step-1', workflow_path: 'a/main.nf', params: { foo: 1 } },
        { id: 'step-2', workflow_path: 'b/main.nf', params: { foo: 2 } },
      ],
    };
    const e = extractWorkflowEdits('set foo to 99 on step step-2', wf);
    expect(e).toEqual([{ op: 'set_param', stepId: 'step-2', paramName: 'foo', value: 99 }]);
  });

  it('resolves step by workflow_path suffix', () => {
    const e = extractWorkflowEdits('set exhaustiveness to 32 for vina_dock', chain());
    expect((e[0] as any).stepId).toBe('step-2');
  });

  it('abstains when the param is ambiguous across multiple steps and no hint', () => {
    const wf: WorkflowArtifact = {
      pipeline_steps: [
        { id: 'step-1', workflow_path: 'a/main.nf', params: {} },
        { id: 'step-2', workflow_path: 'b/main.nf', params: {} },
      ],
    };
    const e = extractWorkflowEdits('set unknown_param to 5', wf);
    expect(e).toEqual([]);
  });

  it('returns [] on non-imperative messages', () => {
    expect(extractWorkflowEdits('what does exhaustiveness do?', chain())).toEqual([]);
    expect(extractWorkflowEdits('thanks!', chain())).toEqual([]);
    expect(extractWorkflowEdits('', chain())).toEqual([]);
  });

  it('writes to inline_parameters on a single-workflow artifact', () => {
    const single: WorkflowArtifact = { inline_parameters: { exhaustiveness: 8 } };
    const e = extractWorkflowEdits('set exhaustiveness to 16', single);
    expect(e).toHaveLength(1);
  });

  it('strips quotes from values', () => {
    const e = extractWorkflowEdits(`set genome to "GRCm39"`, chain());
    expect((e[0] as any).value).toBe('GRCm39');
  });

  it('does NOT invent a param from a SMILES "=" in a user message (CN1C bug)', () => {
    // A SMILES list contains "=" that the "<key>=<value>" pattern would otherwise
    // read as param "CN1C" = "NC2=…". The schema gate must reject it because the
    // ADMET workflow declares smiles_list / ADMET_model_type, not CN1C.
    const admet: WorkflowArtifact = {
      inline_parameters: { smiles_list: '[]' },
      required_params: [{ name: 'smiles_list' }, { name: 'ADMET_model_type' }] as any,
      optional_params: [{ name: 'admet_shard_size' }] as any,
    };
    const msg =
      'Screen these SMILES for ADMET liabilities and rank them by developability: ' +
      'CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, CC(C)Cc1ccc(cc1)C(C)C(=O)O';
    expect(extractWorkflowEdits(msg, admet)).toEqual([]);
  });

  it('still accepts a real declared param on a single-workflow artifact', () => {
    const admet: WorkflowArtifact = {
      optional_params: [{ name: 'admet_shard_size' }] as any,
    };
    expect(extractWorkflowEdits('set admet_shard_size to 50', admet)).toHaveLength(1);
  });

  it('falls through to legacy behaviour when no param metadata is present', () => {
    // No declared params anywhere → do not block (lazy-loaded workflow).
    const bare: WorkflowArtifact = {};
    expect(extractWorkflowEdits('exhaustiveness = 16', bare)).toHaveLength(1);
  });
});
