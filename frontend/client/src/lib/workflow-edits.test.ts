/**
 * Unit tests for the Gap 2 reducer in workflow-edits.ts.
 * Pure / synchronous — no network, no DOM.
 */

import { describe, expect, it } from 'vitest';
import { applyWorkflowEdits, type WorkflowArtifact, type WorkflowEdit } from './workflow-edits';

function fixtureChain(): WorkflowArtifact {
  return {
    workflow_type: 'pipeline',
    pipeline_steps: [
      { id: 'step-1', workflow_path: 'rnaseq/main.nf', params: { genome: 'GRCh38' } },
      { id: 'step-2', workflow_path: 'differentialabundance/main.nf', params: {} },
    ],
  };
}

function fixtureSingle(): WorkflowArtifact {
  return {
    workflow_type: 'workflow',
    inline_parameters: { exhaustiveness: 8 },
  };
}

describe('applyWorkflowEdits — set_param', () => {
  it('updates an existing step parameter without mutating input', () => {
    const wf = fixtureChain();
    const snapshot = JSON.stringify(wf);
    const edits: WorkflowEdit[] = [{ op: 'set_param', stepId: 'step-1', paramName: 'genome', value: 'GRCm39' }];
    const r = applyWorkflowEdits(wf, edits);
    expect(JSON.stringify(wf)).toBe(snapshot); // input untouched
    expect(r.applied).toHaveLength(1);
    expect(r.rejected).toHaveLength(0);
    expect((r.next.pipeline_steps![0].params as any).genome).toBe('GRCm39');
  });

  it('rejects when stepId does not exist', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'set_param', stepId: 'nope', paramName: 'x', value: 1 },
    ]);
    expect(r.applied).toHaveLength(0);
    expect(r.rejected).toHaveLength(1);
    expect(r.rejected[0].reason).toContain('not found');
  });

  it('writes to inline_parameters for a single-workflow artifact', () => {
    const r = applyWorkflowEdits(fixtureSingle(), [
      { op: 'set_param', stepId: 'ignored', paramName: 'exhaustiveness', value: 16 },
    ]);
    expect((r.next.inline_parameters as any).exhaustiveness).toBe(16);
  });
});

describe('applyWorkflowEdits — add_step', () => {
  it('inserts after the named step', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'add_step', afterStepId: 'step-1', workflowPath: 'docking/vina_dock/main.nf' },
    ]);
    expect(r.applied).toHaveLength(1);
    expect(r.next.pipeline_steps).toHaveLength(3);
    expect(r.next.pipeline_steps![1].workflow_path).toBe('docking/vina_dock/main.nf');
    expect(r.next.pipeline_steps![1].workflow_name).toBe('vina_dock');
  });

  it('prepends when afterStepId is null', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'add_step', afterStepId: null, workflowPath: 'qc_preprocessing/main.nf' },
    ]);
    expect(r.next.pipeline_steps![0].workflow_path).toBe('qc_preprocessing/main.nf');
  });

  it('rejects when artifact has no chain', () => {
    const r = applyWorkflowEdits(fixtureSingle(), [
      { op: 'add_step', afterStepId: 'step-1', workflowPath: 'foo/main.nf' },
    ]);
    expect(r.applied).toHaveLength(0);
    expect(r.rejected[0].reason).toContain('not a chain');
  });

  it('generates non-colliding step ids', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'add_step', afterStepId: 'step-2', workflowPath: 'a/main.nf' },
      { op: 'add_step', afterStepId: 'step-2', workflowPath: 'b/main.nf' },
    ]);
    const ids = r.next.pipeline_steps!.map((s) => s.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});

describe('applyWorkflowEdits — remove_step', () => {
  it('drops the named step', () => {
    const r = applyWorkflowEdits(fixtureChain(), [{ op: 'remove_step', stepId: 'step-1' }]);
    expect(r.next.pipeline_steps).toHaveLength(1);
    expect(r.next.pipeline_steps![0].id).toBe('step-2');
  });
});

describe('applyWorkflowEdits — reorder', () => {
  it('moves a step before another', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'reorder', stepId: 'step-2', beforeStepId: 'step-1' },
    ]);
    expect(r.next.pipeline_steps!.map((s) => s.id)).toEqual(['step-2', 'step-1']);
  });

  it('is a no-op when src == dst', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'reorder', stepId: 'step-1', beforeStepId: 'step-1' },
    ]);
    expect(r.next.pipeline_steps!.map((s) => s.id)).toEqual(['step-1', 'step-2']);
  });
});

describe('applyWorkflowEdits — sequencing', () => {
  it('applies edits cumulatively (set then add sees both)', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'set_param', stepId: 'step-1', paramName: 'genome', value: 'GRCm39' },
      { op: 'add_step', afterStepId: 'step-1', workflowPath: 'docking/vina_dock/main.nf' },
    ]);
    expect(r.applied).toHaveLength(2);
    expect((r.next.pipeline_steps![0].params as any).genome).toBe('GRCm39');
    expect(r.next.pipeline_steps![1].workflow_path).toBe('docking/vina_dock/main.nf');
  });

  it('partial failure: bad op rejects without poisoning later ops', () => {
    const r = applyWorkflowEdits(fixtureChain(), [
      { op: 'set_param', stepId: 'nope', paramName: 'x', value: 1 },
      { op: 'remove_step', stepId: 'step-2' },
    ]);
    expect(r.applied).toHaveLength(1);
    expect(r.applied[0].op).toBe('remove_step');
    expect(r.rejected).toHaveLength(1);
    expect(r.next.pipeline_steps).toHaveLength(1);
  });
});
