/**
 * Known-workflow routing (doc 20261110_COLDSTART_EXAMPLES_LIVE_AUDIT §7.2 / §7.4).
 *
 *  §7.2 — a workflow the user picked (Workflows library "Run") arrives as structured
 *         context.selectedWorkflow; the server builds THAT workflow (backend selected_workflow)
 *         with no catalog search and no "Searching…" progress stage.
 *  §7.4 — with nf-core/rnaseq open in the panel, the reply "SRR1039508" fills that workflow;
 *         it is not re-routed to nf-core/differentialabundance, and the Step 6c guard never
 *         keeps a card that contradicts the open workflow.
 *
 * Drives the real GalaxyAssistant single-intent pipeline. Only the LLM calls (intent
 * classifier, response writer) and the Galaxy HTTP proxy are stubbed — the routing code under
 * test is the production code.
 */
import { describe, expect, it, vi } from 'vitest';
import {
  GalaxyAssistant,
  followUpFillsCurrentWorkflow,
  normalizeSelectedWorkflow,
  workflowIdentityOf,
  inferActionsFromType,
  type IntentDecomposition,
} from './galaxy-assistant';

const RNASEQ_PATH = 'biomni_workflows/nfcore/rnaseq/main.nf';
const card = (name: string, path: string, extra: Record<string, unknown> = {}) => ({
  success: true,
  source: 'template_reuse',
  workflow_type: 'nextflow',
  workflow_name: name,
  nextflow_path: path,
  candidate_workflows: [{ name, domain: 'transcriptomics', score: 9 }],
  workflow_ga: { name, nextflow_path: path, steps: {}, required_params: [], optional_params: [] },
  ...extra,
});
const RNASEQ = card('nf-core/rnaseq', RNASEQ_PATH);
const DIFFAB = card('nf-core/differentialabundance', 'biomni_workflows/nfcore/differentialabundance/main.nf', {
  candidate_workflows: [{ name: 'nf-core/differentialabundance', domain: 'transcriptomics', score: 5.4 }],
});

function decomposition(over: Partial<IntentDecomposition['primaryIntent']> = {}, multi = false): IntentDecomposition {
  const intent = {
    id: 'intent_1', type: 'workflow_generation', subQuery: 'SRR1039508', keywords: [],
    inlineParameters: { accession: 'SRR1039508' }, needsToolSearch: false, needsDatasets: false,
    confidence: 0.9, facts: [{ category: 'other', value: 'SRR1039508', confidence: 0.95 }], dependsOn: [],
    actions: inferActionsFromType('workflow_generation'), execution: 'pipeline' as const,
    ...over,
  };
  return { intents: multi ? [intent, { ...intent, id: 'intent_2' }] : [intent], isMultiIntent: multi, primaryIntent: intent };
}

/** Real pipeline; LLM + Galaxy HTTP stubbed. `searchResult` is what catalog search would return. */
function harness(opts: { decomposition: IntentDecomposition; searchResult: any; replyText: string }) {
  const a = Object.create(GalaxyAssistant.prototype) as any;
  const proxy = {
    generateWorkflow: vi.fn(async (req: any) => {
      if (req.selected_workflow) {
        const sel = req.selected_workflow;
        return sel.name === 'nf-core/rnaseq' || sel.nextflow_path === RNASEQ_PATH
          ? { ...RNASEQ, source: 'user_selected' }
          : { success: false, error: `selected_workflow_not_found: ${sel.name}` };
      }
      return opts.searchResult;
    }),
  };
  a._api = () => proxy;
  a.analyzeIntent = vi.fn(async () => opts.decomposition);
  a._inferDomainWithLLM = vi.fn(async () => 'rna_seq');
  a._reselectWorkflow = vi.fn(async () => null);
  a._lookupWorkflowByName = vi.fn(async (name: string) => (name === 'nf-core/rnaseq' ? { ...RNASEQ, source: 'llm_reselection' } : null));
  a.generateResponse = vi.fn(async () => ({ message: opts.replyText, suggestions: [] }));
  a.generateSuggestions = vi.fn(async () => []);
  return { a, proxy };
}

async function run(a: any, message: string, context: Record<string, unknown>) {
  const stages: string[] = [];
  const res = await a._processMessageInner(message, context, undefined, undefined, (s: string) => stages.push(s));
  return { res, stages };
}

describe('§7.2 explicit selection (context.selectedWorkflow)', () => {
  it('builds exactly the selected workflow — selected_workflow sent, no search progress, no domain inference', async () => {
    const { a, proxy } = harness({
      decomposition: decomposition({ subQuery: 'Run the nf-core/rnaseq workflow.', inlineParameters: {}, facts: [] }),
      searchResult: DIFFAB, // what a re-route would have found
      replyText: '**nf-core/rnaseq** — bulk RNA-seq quantification.',
    });
    const { res, stages } = await run(a, 'Run the nf-core/rnaseq workflow.', {
      selectedWorkflow: { name: 'nf-core/rnaseq', nextflow_path: RNASEQ_PATH, id: 42, source: 'nfcore', type: 'workflow' },
    });
    expect(proxy.generateWorkflow).toHaveBeenCalledTimes(1);
    expect(proxy.generateWorkflow.mock.calls[0][0].selected_workflow).toEqual({ name: 'nf-core/rnaseq', nextflow_path: RNASEQ_PATH, id: 42 });
    expect(a._inferDomainWithLLM).not.toHaveBeenCalled();
    expect(stages).not.toContain('search');
    expect(stages).toContain('matched');
    expect(res.generatedWorkflow.workflow_ga.name).toBe('nf-core/rnaseq');
  });

  it('a selection the catalog cannot resolve fails honestly — never routed to another workflow', async () => {
    const { a, proxy } = harness({
      decomposition: decomposition({ inlineParameters: {}, facts: [] }),
      searchResult: DIFFAB,
      replyText: 'The selected workflow is not available.',
    });
    const { res } = await run(a, 'Run the gone_workflow workflow.', { selectedWorkflow: { name: 'gone_workflow' } });
    expect(proxy.generateWorkflow).toHaveBeenCalledTimes(1);
    expect(res.generatedWorkflow?.success).toBe(false);
    expect(res.generatedWorkflow?.workflow_ga?.name).not.toBe('nf-core/differentialabundance');
  });
});

describe('§7.4 follow-up fills the open workflow', () => {
  const open = { workflow_name: 'nf-core/rnaseq', nextflow_path: RNASEQ_PATH, workflow_ga: { name: 'nf-core/rnaseq', nextflow_path: RNASEQ_PATH } };

  it('"SRR1039508" with nf-core/rnaseq open stays nf-core/rnaseq (the dev turn that went to differentialabundance)', async () => {
    const { a, proxy } = harness({
      decomposition: decomposition(),
      searchResult: DIFFAB,
      replyText: 'I will run **nf-core/rnaseq** on SRR1039508.',
    });
    const { res, stages } = await run(a, 'SRR1039508', { currentWorkflow: open });
    expect(proxy.generateWorkflow).toHaveBeenCalledTimes(1);
    expect(proxy.generateWorkflow.mock.calls[0][0].selected_workflow).toMatchObject({ name: 'nf-core/rnaseq', nextflow_path: RNASEQ_PATH });
    expect(proxy.generateWorkflow.mock.calls[0][0].user_intent).toContain('SRR1039508');
    expect(stages).not.toContain('search');
    expect(res.generatedWorkflow.workflow_ga.name).toBe('nf-core/rnaseq');
  });

  it('a turn stating a new analysis is routed normally', async () => {
    const { a, proxy } = harness({
      decomposition: decomposition({
        facts: [{ category: 'analysis_goal', value: 'differential abundance of counts', confidence: 0.95 }],
      }),
      searchResult: DIFFAB,
      replyText: '**nf-core/differentialabundance** — DESeq2 on your counts.',
    });
    const { res, stages } = await run(a, 'now run differential abundance on SRR1039508 counts', { currentWorkflow: open });
    expect(proxy.generateWorkflow.mock.calls[0][0].selected_workflow).toBeUndefined();
    expect(stages).toContain('search');
    expect(res.generatedWorkflow.workflow_ga.name).toBe('nf-core/differentialabundance');
  });

  it('Step 6c never keeps a card contradicting the open workflow the reply describes', async () => {
    // Not bound (the classifier saw a stated goal), search returns differentialabundance, but the
    // reply describes the OPEN workflow nf-core/rnaseq — the old "not a search candidate —
    // keeping differentialabundance" branch must not fire; the card follows to nf-core/rnaseq.
    const { a, proxy } = harness({
      decomposition: decomposition({
        facts: [{ category: 'analysis_goal', value: 'quantify expression', confidence: 0.95 }],
      }),
      searchResult: DIFFAB,
      replyText: 'I will run **nf-core/rnaseq** on SRR1039508 to quantify expression.',
    });
    const { res } = await run(a, 'quantify expression for SRR1039508', { currentWorkflow: open });
    expect(res.generatedWorkflow.workflow_ga.name).toBe('nf-core/rnaseq');
    // rebuilt through the structured selection, so it carries its OWN params for this turn
    expect(proxy.generateWorkflow.mock.calls.some((c: any[]) => c[0].selected_workflow?.name === 'nf-core/rnaseq')).toBe(true);
  });

  it('Step 6c still keeps the card when the reply names a workflow that is neither a candidate nor open', async () => {
    const { a } = harness({
      decomposition: decomposition({ facts: [{ category: 'analysis_goal', value: 'DE', confidence: 0.95 }] }),
      searchResult: DIFFAB,
      replyText: 'Consider **nf-core/sarek** for this.',
    });
    const { res } = await run(a, 'differential abundance please', { currentWorkflow: open });
    expect(res.generatedWorkflow.workflow_ga.name).toBe('nf-core/differentialabundance');
  });
});

describe('followUpFillsCurrentWorkflow — the binding rule (classifier output only)', () => {
  it('binds a value-only pipeline turn', () => {
    expect(followUpFillsCurrentWorkflow(decomposition(), 'SRR1039508')).toBe(true);
  });
  it('a goal inferred from earlier turns (low confidence) does not block binding', () => {
    expect(followUpFillsCurrentWorkflow(decomposition({
      facts: [{ category: 'analysis_goal', value: 'RNA-seq quantification', confidence: 0.6 }],
    }), 'SRR1039508')).toBe(true);
  });
  it.each([
    ['multi-intent', decomposition({}, true)],
    ['stated analysis goal', decomposition({ facts: [{ category: 'analysis_goal', value: 'variant calling', confidence: 0.95 }] })],
    ['stated tool preference', decomposition({ facts: [{ category: 'tool_preference', value: 'DESeq2', confidence: 0.9 }] })],
    ['direct compute', decomposition({ execution: 'direct_compute' })],
    ['a question (no workflow action)', decomposition({ type: 'research_question', actions: inferActionsFromType('research_question') })],
    ['supplies nothing', decomposition({ inlineParameters: { domain_hint: 'rna_seq' }, facts: [] })],
  ])('does not bind: %s', (_label, d) => {
    expect(followUpFillsCurrentWorkflow(d, 'whatever')).toBe(false);
  });
});

describe('selection / identity normalization', () => {
  it('keeps catalog identity, drops chains and junk', () => {
    expect(normalizeSelectedWorkflow({ name: 'nf-core/rnaseq', id: 7, nextflow_path: RNASEQ_PATH, extra: 'x' }))
      .toEqual({ name: 'nf-core/rnaseq', id: 7, nextflow_path: RNASEQ_PATH });
    expect(normalizeSelectedWorkflow({ name: 'geo_to_limma', type: 'chain' })).toBeNull();
    expect(normalizeSelectedWorkflow({ id: 7 })).toBeNull();
    expect(normalizeSelectedWorkflow('nf-core/rnaseq')).toBeNull();
  });
  it('reads the open panel workflow from the card payload', () => {
    expect(workflowIdentityOf({ workflow_ga: { name: 'nf-core/rnaseq', nextflow_path: RNASEQ_PATH } }))
      .toEqual({ name: 'nf-core/rnaseq', nextflow_path: RNASEQ_PATH });
    expect(workflowIdentityOf({ workflow_type: 'chain', chain_name: 'x' })).toBeNull();
    expect(workflowIdentityOf(null)).toBeNull();
  });
});
