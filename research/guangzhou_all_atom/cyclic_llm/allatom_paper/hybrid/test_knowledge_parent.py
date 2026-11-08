"""Explicitly synthetic fixtures: tests the interface, not biological eligibility."""
import hashlib
import json
from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.knowledge_parent import ConditionalParentSelector,Parent,choose_parent

SCOPE=dict(property='synthetic_property',assay='synthetic_assay',scaffold='synthetic_scaffold',
           closure='synthetic_closure',solvent='synthetic_solvent',endpoint='observed')

class First:
    def integers(self,n):return 0


def fixture(tmp_path,mutate=lambda d:None):
    text='Synthetic evidence fixture only.'
    row=dict(id='SYNTHETIC-1',rule_id='SYNTHETIC-RULE',source_id='SYNTHETIC-SOURCE',
      source_families=['TRAIN_A'],permission='conditional_proposal',action='select_parent',
      review_status='approved_for_scoped_parent_selection',unresolved_flags=[],scope=dict(SCOPE),
      quote=text,quote_start=0,quote_end=len(text),approved_parent_ids=['p1'],
      extraction_run='synthetic',code_revision='synthetic',model_revision='synthetic',
      evidence_family='SYNTHETIC-FAMILY',tradeoffs=['synthetic opposing endpoint'])
    doc=dict(schema='conditional_parent_v1',synthetic=True,evidence=[row],sources={
      'SYNTHETIC-SOURCE':dict(url='https://example.invalid/synthetic',accessed='2026-10-29',
                            text=text,sha256=hashlib.sha256(text.encode()).hexdigest())})
    mutate(doc);path=tmp_path/'catalogue.json';path.write_text(json.dumps(doc))
    sha=hashlib.sha256(path.read_bytes()).hexdigest()
    return path,sha


def selector(tmp_path,mutate=lambda d:None):
    path,sha=fixture(tmp_path,mutate)
    return ConditionalParentSelector(path,sha,allowed_source_families=['TRAIN_A'],
        forbidden_source_families=['HELDOUT_B'],allow_synthetic=True)


def parents():
    return [Parent.from_record(dict(id=f'p{i}',smiles=s,compound_id=f'compound{i}',
        scaffold_id='train_scaffold',source_families=['TRAIN_A'],scope=SCOPE)) for i,s in enumerate(['CCO','CCN'])]


def test_eligible_synthetic_evidence_changes_parent_with_trace(tmp_path):
    sel=selector(tmp_path);pool=parents()
    off,trace0=sel.select(pool,SCOPE,First(),arm='off',round_seed=3)
    on,trace=sel.select(pool,SCOPE,First(),arm='on',round_seed=3)
    assert off.id=='p0' and on.id=='p1'
    assert trace['knowledge_used'] and trace['evidence'][0]['id']=='SYNTHETIC-1'
    assert trace['evidence'][0]['source_sha256'] and trace['evidence'][0]['tradeoffs']
    assert not trace0['knowledge_used']


def test_inapplicable_control_falls_back_without_changing_evidence(tmp_path):
    sel=selector(tmp_path)
    chosen,trace=sel.select(parents(),SCOPE,First(),arm='provenance-control',round_seed=3)
    assert chosen.id=='p0' and not trace['knowledge_used']
    assert trace['fallback']=='no_applicable_evidence'
    assert dict(sel.evidence[0].scope)['scaffold']=='synthetic_scaffold'


def test_altered_quote_rejected(tmp_path):
    with pytest.raises(ValueError,match='altered quotation'):
        selector(tmp_path,lambda d:d['evidence'][0].update(quote='Altered'))


def test_forbidden_source_removed_before_source_text_access(tmp_path):
    def mutate(d):
        d['evidence'][0]['source_families']=['HELDOUT_B'];d['sources']={}
    sel=selector(tmp_path,mutate)
    assert not sel.evidence and sel.denied==( ('SYNTHETIC-1','source_lineage_denied'), )
    _,trace=sel.select(parents(),SCOPE,First(),arm='on',round_seed=1)
    assert not trace['instantiated'] and not trace['knowledge_used']


def test_hash_mismatch_and_synthetic_study_rejected(tmp_path):
    path,sha=fixture(tmp_path)
    with pytest.raises(ValueError,match='manifest mismatch'):
        ConditionalParentSelector(path,'0'*64,allowed_source_families=['TRAIN_A'])
    with pytest.raises(ValueError,match='synthetic catalogue prohibited'):
        ConditionalParentSelector(path,sha,allowed_source_families=['TRAIN_A'])


def test_unknown_scope_quarantines_and_unknown_online_parent_is_not_guessed(tmp_path):
    sel=selector(tmp_path,lambda d:d['evidence'][0]['scope'].pop('assay'))
    assert not sel.evidence and sel.denied[0][1]=='unknown_scope'
    sel=selector(tmp_path)
    chosen,trace=choose_parent(['UNKNOWN'],sel,{},SCOPE,First(),'on',0)
    assert chosen=='UNKNOWN' and trace['fallback']=='unknown_parent_metadata'
    assert not trace['knowledge_used']


def test_no_heldout_labels_or_parent_lineage_leakage(tmp_path):
    sel=selector(tmp_path)
    with pytest.raises(ValueError,match='unknown scope field'):
        sel.select(parents(),dict(SCOPE,heldout_score='1.0'),First(),arm='on',round_seed=0)
    bad=Parent.from_record(dict(id='bad',smiles='CCO',compound_id='x',scaffold_id='x',
        source_families=['HELDOUT_B'],scope=SCOPE))
    with pytest.raises(ValueError,match='source leakage'):
        sel.select([bad],SCOPE,First(),arm='on',round_seed=0)


def test_mixed_unknown_and_known_forbidden_never_bypasses_validation(tmp_path):
    sel=selector(tmp_path)
    bad=Parent.from_record(dict(id='bad',smiles='CCO',compound_id='x',scaffold_id='x',
        source_families=['HELDOUT_B'],scope=SCOPE))
    for arm in ('off','on','provenance-control'):
        with pytest.raises(ValueError,match='source leakage'):
            choose_parent(['UNKNOWN','CCO'],sel,{'CCO':bad},SCOPE,First(),arm,0)


def test_mixed_pool_keeps_applicable_known_parent_and_same_full_baseline(tmp_path):
    sel=selector(tmp_path);mapped={p.smiles:p for p in parents()}
    pool=['UNKNOWN','CCO','CCN']
    off,off_trace=choose_parent(pool,sel,mapped,SCOPE,First(),'off',0)
    on,on_trace=choose_parent(pool,sel,mapped,SCOPE,First(),'on',0)
    control,control_trace=choose_parent(pool,sel,mapped,SCOPE,First(),'provenance-control',0)
    assert off==control=='UNKNOWN' and on=='CCN'
    assert on_trace['knowledge_used'] and not off_trace['knowledge_used']
    assert off_trace['baseline_parent_sha256']==on_trace['baseline_parent_sha256']
    assert on_trace['unknown_parent_hashes'] and control_trace['fallback']=='no_applicable_evidence'


def test_unknown_pool_still_validates_task_and_arm(tmp_path):
    sel=selector(tmp_path)
    with pytest.raises(ValueError,match='unknown knowledge arm'):
        choose_parent(['UNKNOWN'],sel,{},SCOPE,First(),'invalid',0)
    with pytest.raises(ValueError,match='unknown scope field'):
        choose_parent(['UNKNOWN'],sel,{},dict(SCOPE,heldout_score='1'),First(),'on',0)


def test_parent_mapping_must_match_chemical_key(tmp_path):
    sel=selector(tmp_path)
    with pytest.raises(ValueError,match='identity mismatch'):
        choose_parent(['WRONG'],sel,{'WRONG':parents()[0]},SCOPE,First(),'on',0)


@pytest.mark.parametrize('blocked',['compound','scaffold','target'])
def test_mixed_pool_validates_all_known_exclusion_types(tmp_path,blocked):
    sel=selector(tmp_path);p=parents()[0]
    if blocked=='compound':sel.forbidden_compounds=frozenset([p.compound_id])
    elif blocked=='scaffold':sel.forbidden_scaffolds=frozenset([p.scaffold_id])
    else:
        sel.forbidden_targets=frozenset(['HELDOUT_TARGET'])
        p=Parent.from_record(dict(id=p.id,smiles=p.smiles,compound_id=p.compound_id,
            scaffold_id=p.scaffold_id,source_families=list(p.source_families),
            scope=dict(SCOPE,target='HELDOUT_TARGET')))
    with pytest.raises(ValueError,match='leakage'):
        choose_parent(['UNKNOWN',p.smiles],sel,{p.smiles:p},SCOPE,First(),'on',0)
