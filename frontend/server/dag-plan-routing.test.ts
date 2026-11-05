import { describe, expect, it, vi } from 'vitest';
import { GalaxyAssistant, dagPlanName } from './galaxy-assistant';

// Fork/join requests (bulk RNA-seq + DIA proteomics integration, external user 2026-11-03) were
// split into per-intent cards and the dependency structure was dropped. _tryDagPlan sends the
// workflow intents with their edges to /api/ai_assistant/plan_dag and returns one DAG card.
const intent = (id: string, subQuery: string, dependsOn: string[] = [], extra: any = {}) => ({
  id, type: 'workflow_generation', subQuery, keywords: [], inlineParameters: {}, needsToolSearch: true,
  needsDatasets: true, confidence: 0.9, facts: [], dependsOn,
  actions: { needsWorkflowGeneration: true } as any, ...extra,
});
const FORK_JOIN = {
  isMultiIntent: true,
  intents: [
    intent('intent_1', 'RNA-seq differential expression KO vs WT'),
    intent('intent_2', 'lysate proteomics differential abundance'),
    intent('intent_3', 'secretome proteomics differential abundance'),
    intent('intent_4', 'Integrate RNA and protein differential results', ['intent_1', 'intent_2', 'intent_3']),
    { ...intent('intent_5', 'interpret the integrated results'), type: 'data_interpretation', actions: { needsWorkflowGeneration: false } },
  ],
} as any;
const CARD = {
  workflow_type: 'pipeline', execution_mode: 'dag', name: 'Integrate RNA and protein differential results', max_parallel: 3,
  connections: [{ from_step: 1, from_output: 'csv', to_step: 4, to_input: 'csv' }],
  pipeline_steps: [
    { id: 'intent_1', description: 'RNA-seq differential expression KO vs WT', nextflow_path: 'bioc/deseq2/main.nf', depends_on: [] },
    { id: 'intent_2', description: 'lysate proteomics differential abundance', nextflow_path: 'bioc/limma/main.nf', depends_on: [] },
    { id: 'intent_3', description: 'secretome proteomics differential abundance', nextflow_path: 'bioc/limma/main.nf', depends_on: [] },
    { id: 'intent_4', description: 'Integrate RNA and protein differential results', nextflow_path: 'bioc/mixomics/main.nf', depends_on: [1, 2, 3] },
  ],
};
const assistantWith = (post: any) => {
  const a = Object.create(GalaxyAssistant.prototype) as any;
  a._api = () => ({ client: { post } });
  return a;
};

describe('_tryDagPlan', () => {
  it('sends the workflow intents with 1-based edges and returns one DAG card', async () => {
    const post = vi.fn(async () => ({ data: { success: true, workflow: CARD, unwired_dependencies: [{ from_step: 2, to_step: 4 }, { from_step: 3, to_step: 4 }] } }));
    const res = await assistantWith(post)._tryDagPlan(FORK_JOIN, 'integrate', () => {});
    const [url, body] = (post.mock.calls[0] as any);
    expect(url).toBe('/api/ai_assistant/plan_dag');
    expect(body.tasks.map((t: any) => t.depends_on)).toEqual([[], [], [], [1, 2, 3]]); // interpretation intent is not a task
    expect(res.generatedWorkflow.workflow_type).toBe('pipeline');
    expect(res.generatedWorkflow.execution_mode).toBe('dag');
    expect(res.generatedWorkflow.pipeline_steps).toHaveLength(4);
    expect(res.message).toContain('runs in parallel');
    expect(res.message).toContain('uses the results of steps 1, 2, 3');
    expect(res.message).toMatch(/map the inputs of step 4.*steps 2, 3/);
  });

  it('falls back (null) when the backend refuses, and does not plan single or ad-hoc work', async () => {
    const refuse = vi.fn(async () => ({ data: { success: false, reason: 'unresolved_task' } }));
    expect(await assistantWith(refuse)._tryDagPlan(FORK_JOIN, 'x', () => {})).toBeNull();
    const never = vi.fn();
    expect(await assistantWith(never)._tryDagPlan({ intents: [intent('a', 'one workflow')] } as any, 'x', () => {})).toBeNull();
    const adhoc = { intents: [intent('a', 'fold change', [], { execution: 'direct_compute' }), intent('b', 'plot', [], { execution: 'direct_compute' })] } as any;
    expect(await assistantWith(never)._tryDagPlan(adhoc, 'x', () => {})).toBeNull();
    expect(never).not.toHaveBeenCalled();
  });

  it('drops forward or unknown edges (only earlier steps can be dependencies)', async () => {
    const post = vi.fn(async () => ({ data: { success: false } }));
    const odd = { intents: [intent('a', 'first', ['b']), intent('b', 'second', ['a', 'zzz'])] } as any;
    await assistantWith(post)._tryDagPlan(odd, 'x', () => {});
    expect((post.mock.calls[0] as any)[1].tasks.map((t: any) => t.depends_on)).toEqual([[], [1]]);
  });
});

describe('dagPlanName', () => {
  it('names the plan after its integration step, never a placeholder', () => {
    expect(dagPlanName([{ description: 'rna de', depends_on: [] }, { description: 'protein de', depends_on: [] },
      { description: 'integrate RNA and protein differential results', depends_on: [1, 2] }])).toBe('Integrate RNA and protein differential results');
    expect(dagPlanName([{ description: 'x'.repeat(80), depends_on: [] }]).length).toBeLessThanOrEqual(60);
  });
});
