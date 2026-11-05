import { describe, expect, it, vi } from 'vitest';
import { GalaxyAssistant } from './galaxy-assistant';

// A text-driven card swap (Steps 6b / 6c / 6c-2) must not move the card to a workflow the backend judged
// unable to run on the request's data: on dev (2026-11-05) the reply recommended nf-core/proteomicslfq
// "for MaxQuant proteinGroups.txt" and the correct dep card was swapped onto the raw-spectra pipeline.
const assistant = (lookup: any) => {
  const a = Object.create(GalaxyAssistant.prototype) as any;
  a._lookupWorkflowByName = vi.fn(async () => lookup);
  return a;
};
const regenerate = vi.fn(async () => ({ success: true, workflow_name: 'nf-core/proteomicslfq' }));

describe('_cardForNamedWorkflow input guard', () => {
  it('refuses a workflow the backend marks input-incompatible, and passes the request to the lookup', async () => {
    const a = assistant({ success: true, workflow_name: 'nf-core/proteomicslfq', input_compatible: false });
    expect(await a._cardForNamedWorkflow('nf-core/proteomicslfq', 'MaxQuant proteinGroups.txt KO vs WT', regenerate)).toBeNull();
    expect(a._lookupWorkflowByName).toHaveBeenCalledWith('nf-core/proteomicslfq', 'MaxQuant proteinGroups.txt KO vs WT', undefined);
    expect(regenerate).not.toHaveBeenCalled();
  });

  it('builds the card when compatible or unknown', async () => {
    for (const ic of [true, null, undefined]) {
      const a = assistant({ success: true, workflow_name: 'nf-core/proteomicslfq', input_compatible: ic });
      expect(await a._cardForNamedWorkflow('nf-core/proteomicslfq', 'q', regenerate)).toEqual({ success: true, workflow_name: 'nf-core/proteomicslfq' });
    }
  });
});
