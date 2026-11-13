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
    const res = await assistantWith(post)._tryDagPlan(FORK_JOIN, 'integrate', () => {}, new Map([['intent_1', 'routed/rna.nf']]));
    const [url, body] = (post.mock.calls[0] as any);
    expect(url).toBe('/api/ai_assistant/plan_dag');
    expect(body.tasks.map((t: any) => t.depends_on)).toEqual([[], [], [], [1, 2, 3]]); // interpretation intent is not a task
    expect(body.tasks[0].nextflow_path).toBe('routed/rna.nf'); // the turn's own routing, not a bare search
    expect(body.tasks[1].nextflow_path).toBeUndefined();
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

  it('numbers intents in dependency order (a combining step emitted first keeps its edges); unknown ids ignored', async () => {
    const post = vi.fn(async () => ({ data: { success: false } }));
    const joinFirst = { intents: [intent('join', 'integrate', ['a', 'zzz']), intent('a', 'first')] } as any;
    await assistantWith(post)._tryDagPlan(joinFirst, 'x', () => {});
    const sent = (post.mock.calls[0] as any)[1].tasks;
    expect(sent.map((t: any) => t.id)).toEqual(['a', 'join']);
    expect(sent.map((t: any) => t.depends_on)).toEqual([[], [1]]);
  });

  it('refuses a cyclic plan (per-intent cards) instead of silently dropping an edge', async () => {
    const post = vi.fn();
    const cyclic = { intents: [intent('a', 'first', ['b']), intent('b', 'second', ['a'])] } as any;
    expect(await assistantWith(post)._tryDagPlan(cyclic, 'x', () => {})).toBeNull();
    expect(post).not.toHaveBeenCalled();
  });
});

describe('dagPlanName', () => {
  it('names the plan after its integration step, never a placeholder', () => {
    expect(dagPlanName([{ description: 'rna de', depends_on: [] }, { description: 'protein de', depends_on: [] },
      { description: 'integrate RNA and protein differential results', depends_on: [1, 2] }])).toBe('Integrate RNA and protein differential results');
    expect(dagPlanName([{ description: 'x'.repeat(80), depends_on: [] }]).length).toBeLessThanOrEqual(60);
  });
});

it('says "independent" (not "combining step") when nothing depends on anything', async () => {
  const two = { intents: [intent('a', 'variant calling'), intent('b', 'rna de')] } as any;
  const card = { ...CARD, pipeline_steps: CARD.pipeline_steps.slice(0, 2), connections: [] };
  const post = vi.fn(async () => ({ data: { success: true, workflow: card } }));
  const res = await assistantWith(post)._tryDagPlan(two, 'x', () => {});
  expect(res.message).toContain('independent and run in parallel');
  expect(res.message).not.toContain('combining step');
});
it('explains an order-only fan-in (no typed wiring) without implying data is passed', async () => {
  const post = vi.fn(async () => ({ data: { success: true, order_only: true, workflow: { ...CARD, connections: [] },
    unwired_dependencies: [1, 2, 3].map(f => ({ from_step: f, to_step: 4 })) } }));
  const res = await assistantWith(post)._tryDagPlan(FORK_JOIN, 'x', () => {});
  expect(res.message).toMatch(/Step 4 runs after steps 1, 2, 3, but their result files are not connected/);
});

// Branch routing uses the LLM's task_spec (method + data type + input format, no design labels) and
// the branch's own domain: the sub-query "… SCC9 WT vs KO lysate proteomics (duplicates)" matched a
// CLIP-seq workflow whose inputs are named wt_/ko_ (dev, 2026-11-04).
describe('processSubIntent routing query', () => {
  const run = async (extra: any) => {
    const a = Object.create(GalaxyAssistant.prototype) as any;
    a.generateWorkflow = vi.fn(async () => ({ success: true }));
    await a.processSubIntent(
      intent('intent_2', 'Lysate proteomics differential abundance, KO vs WT (duplicates)', [], extra),
      'original message', {}, [], [], ['transcriptomics', 'proteomics'], [], []);
    return a.generateWorkflow.mock.calls[0];
  };
  it('searches with task_spec and puts the branch domain first', async () => {
    const [query, , , , domains] = await run({
      taskSpec: 'differential protein abundance on a processed DIA-NN protein-group matrix → log2FC, adjusted p',
      domain: 'proteomics',
    });
    expect(query).toContain('DIA-NN protein-group matrix');
    expect(query).not.toContain('KO vs WT');
    expect(domains).toEqual(['proteomics', 'transcriptomics']);
  });
  it('falls back to the sub-query when the LLM gave no task_spec', async () => {
    const [query, , , , domains] = await run({});
    expect(query).toContain('KO vs WT');
    expect(domains).toEqual(['transcriptomics', 'proteomics']);
  });
});

// P2 (2026-11-11): plan inputs + a title from the user's goal.
import { requestGoal, uploadedRefsFromMessage, dagInputStatus } from './galaxy-assistant';

describe('plan title from the request goal', () => {
  it('uses the goal of the user request, not the fan-in step', () => {
    const tasks = [{ description: 'dock the series', depends_on: [] }, { description: 'predict ADMET', depends_on: [] },
      { description: 'Integrate docking scores and ADMET/safety profiles', depends_on: [1, 2] }];
    const msg = 'Adapt the generative model to our chemical series.\n\nPrepared demo context:\nUse the 500 compounds…';
    expect(dagPlanName(tasks, msg)).toBe('Adapt the generative model to our chemical series');
  });
  it('skips bracketed context blocks and falls back when the goal is too short', () => {
    expect(requestGoal('[Prior conversation context]\nRun DE then GO enrichment. Human.')).toBe('Run DE then GO enrichment');
    expect(dagPlanName([{ description: 'integrate rna and protein', depends_on: [] }, { description: 'b', depends_on: [1] }], 'ok'))
      .toBe('B'); // too short a goal → previous behaviour (sink step)
  });
});

describe('plan inputs', () => {
  it('extracts only runnable uploads (with an s3_uri)', () => {
    const m = 'x\n[Uploaded datasets: counts.csv: dataset_id=a1, s3_uri=s3://b/counts.csv; notes.md: dataset_id=a2]';
    expect(uploadedRefsFromMessage(m)).toEqual([{ name: 'counts.csv', s3_uri: 's3://b/counts.csv' }]);
  });
  it('reports filled and still-needed inputs per step', () => {
    const lines = dagInputStatus([{ bound_from_uploads: ['matrix'], missing_inputs: ['contrast_variable'] },
      { bound_from_uploads: [], missing_inputs: [] }], false);
    expect(lines.join('\n')).toMatch(/Filled from your files: step 1 — matrix/);
    expect(lines.join('\n')).toMatch(/Still needed before running: step 1 — contrast_variable/);
    expect(lines.join("\n")).toMatch(/built-in sample data, not yours/);
  });
  it('never claims inputs are complete when the backend does not report them', () => {
    expect(dagInputStatus([{}, {}], false)[0]).toMatch(/Fill in each branch's input files/);
  });
  it('sends this turn\'s uploads to /plan_dag', async () => {
    const post = vi.fn(async () => ({ data: { success: false } }));
    await assistantWith(post)._tryDagPlan(FORK_JOIN, 'Integrate my data\n[Uploaded datasets: c.csv: s3_uri=s3://b/c.csv]', () => {});
    expect((post.mock.calls[0] as any)[1].uploaded_datasets).toEqual([{ name: 'c.csv', s3_uri: 's3://b/c.csv' }]);
  });
});

it('never leaks the internal engine path (nextflow_path) into the user-facing plan message', async () => {
  const post = vi.fn(async () => ({ data: { success: true, workflow: CARD } }));
  const res = await assistantWith(post)._tryDagPlan(FORK_JOIN, 'x', () => {});
  // The raw subworkflow paths must not appear anywhere in the message the user reads.
  expect(res.message).not.toContain('main.nf');
  expect(res.message).not.toContain('bioc/');
  expect(res.message).not.toMatch(/subworkflows\//);
  // The step is still named by its human description.
  expect(res.message).toContain('RNA-seq differential expression KO vs WT');
});

it('says when a step was switched to a workflow that takes the user\'s data', async () => {
  const steps = CARD.pipeline_steps.map((s: any, k: number) => k === 0
    ? { ...s, workflow_label: 'deseq2_counts', rerouted_from: 'salmon_quant_de', reroute_reason: 'accepts your counts_matrix.csv' } : s);
  const post = vi.fn(async () => ({ data: { success: true, workflow: { ...CARD, pipeline_steps: steps } } }));
  const res = await assistantWith(post)._tryDagPlan(FORK_JOIN, 'x', () => {});
  expect(res.message).toMatch(/switched from salmon_quant_de because it accepts your counts_matrix\.csv/);
});
