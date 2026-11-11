/** Offline probes of production functions, not a simulated product acceptance run.
 * From frontend/: node --import tsx ../evaluation/local_trial/probe_complex_task_boundaries.ts
 * Exit 1 means a reproduced contract gap; stdout is machine-readable evidence.
 */
import { isDeepStrictEqual } from 'node:util';
import { buildChainSubmitSteps, buildChainConnections } from '../../frontend/client/src/lib/chain-execution';
import { mapChainStepStatus, mapChainRunStatus } from '../../frontend/client/src/lib/chain-pipeline-sync';
import { scoreBenchmark } from '../../frontend/server/benchmark-orchestrator';

const results: Array<Record<string, unknown>> = [];
function probe(id: string, expected: unknown, run: () => unknown) {
  try {
    const actual = run();
    results.push({ id, passed: isDeepStrictEqual(actual, expected), expected, actual });
  } catch (error) {
    results.push({ id, passed: false, expected, error: String(error) });
  }
}
const cases = ['inhibitor_A', 'inhibitor_B'].flatMap(inhibitor =>
  ['target_A', 'target_B', 'target_C'].map(target => ({
    nextflow_path: 'fixture/shared_workflow.nf',
    step_key: `${inhibitor}:${target}`,
    depends_on: [], dimensions: { inhibitor, target }, params: { inhibitor, target },
  })));
probe('six_same_workflow_cases_preserve_parameters', cases.map(s => s.params), () =>
  buildChainSubmitSteps(cases).map(s => s.params));
probe('six_same_workflow_cases_preserve_identity', cases.map(s => s.step_key), () =>
  buildChainSubmitSteps(cases).map(s => s.step_key));
probe('six_cases_preserve_dimensions', cases.map(s => s.dimensions), () =>
  buildChainSubmitSteps(cases).map(s => (s as any).dimensions));
probe('diamond_graph_preserves_dependencies', [[], [1], [1], [2, 3]], () =>
  buildChainSubmitSteps([[], [1], [1], [2, 3]].map((depends_on, i) => ({
    nextflow_path: `fixture/${i}.nf`, depends_on,
  }))).map(s => (s as any).depends_on));
const contextRules = { organism: { from_run_param: 'genome', transform: 'genome_to_organism' } };
probe('handoff_preserves_context', contextRules, () =>
  (buildChainConnections({ connections: [{
    from_step: 1, to_step: 2, from_output: 'counts.tsv', to_input: 'counts',
    context_params: contextRules,
  }] })[0] as any).context_params);
probe('blocked_is_not_pending', 'blocked', () => mapChainStepStatus('blocked'));
probe('submitting_is_not_pending', 'submitting', () => mapChainStepStatus('submitting'));
probe('partial_is_terminal_not_running', 'partial', () => mapChainRunStatus('partial'));

const one = new Map([['sample1', 'cluster1']]);
probe('invalid_ground_truth_metrics_have_no_winner', null, () =>
  scoreBenchmark({ onlyMethod: one }, new Map([['sample1', 'truth1']])).winner);
probe('no_pairwise_comparison_has_no_winner', null, () =>
  scoreBenchmark({ onlyMethod: one }).winner);
probe('nonoverlapping_methods_have_no_winner', null, () =>
  scoreBenchmark({ first: one, second: new Map([['sample2', 'cluster2']]) }).winner);
probe('valid_ground_truth_comparison_still_selects_best', 'matching', () => {
  const labels = new Map([['s1', 'a'], ['s2', 'a'], ['s3', 'b'], ['s4', 'b']]);
  const mixed = new Map([['s1', 'a'], ['s2', 'b'], ['s3', 'a'], ['s4', 'b']]);
  return scoreBenchmark({ matching: labels, mixed }, labels).winner;
});

const failed = results.filter(r => !r.passed).length;
console.log(JSON.stringify({
  suite: 'complex_task_production_boundary_probes_v1',
  executed_at: new Date().toISOString(),
  scope: 'Real local production helpers with synthetic inputs; no LLM, server, tool job or scientific result.',
  summary: { total: results.length, passed: results.length - failed, failed },
  results,
}, (_key, value) => value === undefined ? { missing: true } : value, 2));
process.exitCode = failed ? 1 : 0;
