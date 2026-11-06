import { describe, expect, it } from 'vitest';
import { additionalIntentWorkflows, workflowIntent } from './multi-intent-workflows';

describe('multi-intent execution coverage', () => {
  it('retains six inhibitor-target requests using the same workflow', () => {
    const results = ['A', 'B'].flatMap(inhibitor => ['X', 'Y', 'Z'].map(target => ({
      generatedWorkflow: { nextflow_path: 'docking/main.nf', params: { inhibitor, target } },
    })));
    const extra = additionalIntentWorkflows(results, results[0], w => Boolean(w?.nextflow_path));
    expect(extra).toHaveLength(5);
    expect(extra[4].params).toEqual({ inhibitor: 'B', target: 'Z' });
  });
  it('routes each task rather than repeating the full multi-tool request', () => {
    expect(workflowIntent('Run edgeR on these counts', 'Compare DESeq2 and edgeR'))
      .toBe('Run edgeR on these counts');
    expect(workflowIntent(' ', 'Original request')).toBe('Original request');
  });
  it('keeps unresolved results out of runnable cards', () => {
    const primary = { generatedWorkflow: { nextflow_path: 'one.nf' } };
    expect(additionalIntentWorkflows([primary, { generatedWorkflow: null }], primary,
      w => Boolean(w?.nextflow_path))).toEqual([]);
  });
});
