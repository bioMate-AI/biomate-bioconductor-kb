import { describe, expect, it, vi } from 'vitest';
import { GalaxyAssistant } from './galaxy-assistant';

// A named end-to-end pipeline ("run the full target-to-lead pipeline") is often decomposed as ONE
// intent with chain_hint set; the curated chain was looked up only on the sequential multi-intent
// path, so the hint was ignored (2026-11-05). _curatedChainResponse now serves both paths.
const CHAIN = {
  name: 'target_to_lead', display_name: 'Target to Lead',
  steps: [{ workflow_name: 'target identification', role: 'targets' }, { workflow_name: 'docking screen', role: 'hits' }],
  connections: [{ from_step: 1, from_output: 'targets', to_step: 2 }],
};
const assistant = (chain: any) => {
  const a = Object.create(GalaxyAssistant.prototype) as any;
  a._fetchCuratedChain = vi.fn(async () => chain);
  a.processSubIntent = vi.fn(async (_i: any, q: string) => ({ generatedWorkflow: { workflow_name: q, nextflow_path: `wf/${q.split(' ')[0]}.nf` } }));
  return a;
};
const dec = (chainHint: string | null) => ({ isMultiIntent: false, chainHint, intents: [], preferredDomains: [], keyTerms: [], penalizedDomains: [] } as any);

describe('_curatedChainResponse', () => {
  it('builds the curated chain card for a single-intent request that names the pipeline', async () => {
    const a = assistant(CHAIN);
    const res = await a._curatedChainResponse(dec('target_to_lead'), 'run the full target-to-lead pipeline for KRAS', {}, () => {});
    expect(a._fetchCuratedChain).toHaveBeenCalledWith('target_to_lead');
    expect(res.generatedWorkflow.source).toBe('biomate_curated_chain');
    expect(res.generatedWorkflow.pipeline_steps.map((s: any) => s.nextflow_path)).toEqual(['wf/target.nf', 'wf/docking.nf']);
    expect(res.generatedWorkflow.pipeline_steps[1].input_from).toBe('chain_step_1');
  });

  it('drops a hint the current message does not support (inherited from earlier turns)', async () => {
    const a = assistant(CHAIN);
    const d = dec('target_to_lead');
    expect(await a._curatedChainResponse(d, 'ADMET screening of these SMILES', {}, () => {})).toBeNull();
    expect(d.chainHint).toBeNull();
    expect(a._fetchCuratedChain).not.toHaveBeenCalled();
  });

  it('returns null (caller continues normally) when the chain is unknown or empty', async () => {
    expect(await assistant(null)._curatedChainResponse(dec('target_to_lead'), 'full target-to-lead pipeline', {}, () => {})).toBeNull();
    expect(await assistant({ ...CHAIN, steps: [] })._curatedChainResponse(dec('target_to_lead'), 'target-to-lead pipeline', {}, () => {})).toBeNull();
  });
});
