import copy
import sys
from pathlib import Path
import pytest
sys.path.insert(0, str(Path(__file__).parents[1] / 'lib'))
from galaxy.chain.dag import run_plan, validate_plan, bind_inputs


def step(deps=None, **kwargs):
    return dict(nextflow_path='fixture.nf', depends_on=deps or [], status='pending', params={}, **kwargs)


def run(steps, failed=None):
    launched, events, snapshots = [], [], []
    state = {'steps': steps, 'max_parallel': 3}
    def submit(s, p):
        n = next(i for i, node in enumerate(steps) if node is s) + 1
        launched.append(n); events.append(('submit', n)); return str(n)
    def poll(rid):
        events.append(('poll', int(rid)))
        return {'status': 'failed' if int(rid) == failed else 'succeeded',
                'output_files': [{'path': '/result/' + rid}]}
    run_plan(state, submit, poll, lambda s: snapshots.append(copy.deepcopy(s)),
             lambda s, i: s['steps'][i]['params'], sleep=lambda _: None)
    return state, launched, events


def test_fanout_joins_only_after_both_parents_succeed():
    state, launched, events = run([step(), step(), step([1, 2])])
    assert events[:2] == [('submit', 1), ('submit', 2)]
    assert events.index(('submit', 3)) > events.index(('poll', 2))
    assert state['report']['complete']


def test_failed_branch_blocks_descendant_but_preserves_other_results():
    state, launched, _ = run([step(), step(), step([1]), step([2])], failed=1)
    assert launched == [1, 2, 4]
    assert state['steps'][2]['status'] == 'blocked'
    assert state['report']['expected'] == 4 and state['report']['succeeded'] == 2
    assert state['status'] == 'failed'


def test_inhibitor_target_matrix_keeps_all_six_pairs():
    nodes = [step(dimensions={'inhibitor': a, 'target': b}) for a in ['A','B'] for b in ['X','Y','Z']]
    state, launched, _ = run(nodes)
    assert len(launched) == state['report']['expected'] == 6
    assert len({tuple(sorted(r['dimensions'].items())) for r in state['report']['rows']}) == 6


def test_recovery_polls_recorded_runs_and_never_resubmits():
    node = step(); node.update(status='running', run_id='1', submitted_at_epoch=0)
    state, launched, _ = run([node, step([1])])
    assert launched == [2] and state['status'] == 'succeeded'


def test_uncertain_submission_fails_without_relaunch():
    node = step(); node['status'] = 'submitting'
    state, launched, _ = run([node, step([1])])
    assert launched == [] and state['steps'][1]['status'] == 'blocked'


@pytest.mark.parametrize('nodes', [[step([2]), step([1])], [step([3])], [dict(nextflow_path='x')]])
def test_invalid_graph_rejected(nodes):
    with pytest.raises(ValueError): validate_plan(nodes, [], 3)


def test_handoff_rejects_ambiguity_and_uses_declared_parent_context():
    source=step(); source.update(run_id='1', params={'genome':'hg38'})
    state={'steps':[source, step([1])], 'connections':[
        {'from_step':1,'to_step':2,'from_output':'counts.tsv','to_input':'counts'}]}
    value=lambda f:f['path']
    ctx=lambda c,p:{'genome':p['genome']}
    files=[{'filename':'counts.tsv','path':'/one/counts.tsv'}]
    assert bind_inputs(state,1,lambda _:files,value,ctx)=={'counts':'/one/counts.tsv','genome':'hg38'}
    files.append({'filename':'counts.tsv','path':'/two/counts.tsv'})
    with pytest.raises(ValueError): bind_inputs(state,1,lambda _:files,value,ctx)


def test_missing_pair_cannot_be_reported_as_complete_plan():
    from galaxy.chain.dag import validate_coverage
    axes={'inhibitor':['A','B'],'target':['X','Y','Z']}
    nodes=[step(dimensions={'inhibitor':a,'target':b}) for a in axes['inhibitor'] for b in axes['target']]
    validate_coverage(nodes,axes)
    with pytest.raises(ValueError, match='Incomplete case coverage'):
        validate_coverage(nodes[:-1],axes)


def test_all_tools_scope_requires_every_declared_tool():
    from galaxy.chain.dag import validate_coverage
    with pytest.raises(ValueError, match='Incomplete case coverage'):
        validate_coverage([step(dimensions={'tool':'edgeR'})], {'tool':['DESeq2','edgeR']})
