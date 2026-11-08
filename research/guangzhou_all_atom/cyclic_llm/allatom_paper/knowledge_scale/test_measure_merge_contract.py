"""Synthetic contract fixtures; run on isolated Spot CPU, not on the laptop."""
import copy
import json
import ast
from pathlib import Path
import subprocess

from merge import merge
from measure import recall_vs_gold


def rule(i='r1', **kw):
    row = dict(rule_id=i, property='permeability', substructure_class='n_methylation',
               direction='increases', scope='cyclic hexapeptide at position 2', assay='PAMPA',
               statement='Selective methylation improves membrane permeability of cyclic peptides',
               quote='Selective methylation improves membrane permeability of cyclic peptides',
               citation=dict(doi='10.1/A', pmcid='PMC1'), evidence_tier='T1', confidence=0.8,
               proxy_entailment='YES', topic='sar_rule')
    row.update(kw)
    return row


def gold(**kw):
    row = dict(id='g1', statement=rule()['statement'], quote=rule()['quote'], kind='rule',
               property='permeability', substructure_class='n_methylation', source=dict(doi='10.1/A', pmcid='PMC1'))
    row.update(kw)
    return row


def recall(gs, rs):
    return recall_vs_gold(gs, rs, {'PMC1'}, {'10.1/a'})


def test_recall_requires_both_classes_even_identical_quote():
    assert recall([gold()], [rule()])['found'] == 1
    assert recall([gold()], [rule(property='solubility')])['found'] == 0
    assert recall([gold()], [rule(substructure_class='ring_size_topology')])['found'] == 0
    assert recall([gold()], [rule(property='solubility', substructure_class='ring_size_topology')])['found'] == 0


def test_unclassified_gold_is_not_silently_success_or_complete_metric():
    g = gold(); del g['substructure_class']
    out = recall([g], [rule()])
    assert out['found'] == 0 and out['gold_in_corpus'] == 1
    assert out['unclassified_in_corpus'] == 1 and out['recall_of_in_corpus'] is None
    assert out['status'] == 'INCONCLUSIVE'
    reviewed = {'g1': dict(property='permeability', substructure_class='n_methylation')}
    out = recall_vs_gold([g], [rule()], {'PMC1'}, {'10.1/a'}, reviewed)
    assert out['recall_of_in_corpus'] == 1


def test_same_paper_required_without_empty_doi_cross_match():
    g = gold(source=dict(pmcid='PMC1'))
    r = rule(citation=dict(pmcid='PMC2'))
    assert recall([g], [r])['found'] == 0


def test_same_scope_merge_preserves_raw_members_and_determinism():
    a, b = rule(), rule('r2', citation=dict(doi='10.1/B', pmcid='PMC2'), proxy_entailment='NO')
    merged, conflicts = merge([a,b], [])
    assert len(merged) == 1 and not conflicts
    assert merged[0]['member_rule_ids'] == ['r1','r2']
    assert merged[0]['member_rules'] == [a,b]
    assert merge([b,a], []) == (merged,conflicts)
    assert merged[0]['representative_only'] is True
    merged[0]['member_rules'][0]['statement'] = 'changed'
    assert a['statement'] != 'changed'


def test_scope_assay_target_and_topic_do_not_merge():
    for changes in [dict(scope='cyclic hexapeptide at position 3'), dict(assay='MDCK'),
                    dict(target='pdl1'), dict(topic='prior_work')]:
        out, _ = merge([rule(),rule('r2',**changes)], [])
        assert len(out) == 2


def test_missing_scope_is_not_equivalence():
    out,_ = merge([rule(scope=''),rule('r2',scope='')],[])
    assert len(out)==2


def test_conflicts_scope_specific_and_identical_support_sets_still_conflict():
    rows=[rule('a1'),rule('a2',direction='decreases'),
          rule('b1',citation=dict(doi='10.1/B',pmcid='PMC2')),
          rule('b2',direction='decreases',citation=dict(doi='10.1/B',pmcid='PMC2'))]
    out, conflicts=merge(rows,[])
    assert len(conflicts)==1 and all(r['direction_conflict_in_scope'] for r in out)
    out,conflicts=merge([rule(),rule('r2',direction='decreases',scope='other scaffold',citation=dict(doi='10.1/B',pmcid='PMC2'))],[])
    assert not conflicts
    out,conflicts=merge([rule(),rule('r2',direction='decreases')],[])
    assert not conflicts and all(r['within_scope_opposing_evidence'] for r in out)


def test_recall_sees_member_source_not_just_representative():
    a,b=rule(citation=dict(doi='10.1/B',pmcid='PMC2')),rule('r2')
    out,_=merge([a,b],[])
    assert out[0]['citation']['pmcid']=='PMC2'
    assert recall([gold()],out)['found']==1


def test_launcher_drivers_syntax_and_fail_closed(tmp_path):
    ap=Path(__file__).resolve().parents[1]
    for filename in [ap/'knowledge_scale/launch_k2.py',ap/'patent_mining/launch_gpu.py']:
        tree=ast.parse(filename.read_text())
        ud=next(n.value.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='UD' for t in n.targets))
        driver=tmp_path/(filename.stem+'.sh');driver.write_text(ud)
        subprocess.run(['bash','-n',str(driver)],check=True)
        assert 'set -Eeuo pipefail' in ud and 'trap finish EXIT' in ud
        # Execute only the isolated terminal handler with /w redirected to tmp.
        # No real cloud, shutdown, extraction or installation command is run.
        start=ud.index('finish() {');end=ud.index('trap finish EXIT',start)
        out=tmp_path/filename.stem;out.mkdir(); (out/'done.flag').write_text('stale')
        fragment=ud[start:end].replace('/w/out',str(out))
        for status, sync_status in [(7,0),(0,0),(0,9),(7,9)]:
            script='set -Eeuo pipefail\nP=fixture\naws(){ return '+str(sync_status)+'; }\nshutdown(){ return 0; }\n'+fragment+'trap finish EXIT\nexit '+str(status)+'\n'
            result=subprocess.run(['bash','-c',script])
            expected=status or sync_status
            assert result.returncode==expected
            assert json.loads((out/'terminal_status.json').read_text())['exit_code']==expected
            assert (out/'done.flag').exists()==(expected==0)
