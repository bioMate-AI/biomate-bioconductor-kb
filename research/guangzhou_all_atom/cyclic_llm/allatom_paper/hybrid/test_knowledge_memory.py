"""Synthetic packer contracts. Execute only on authorised remote compute."""
import copy
import hashlib
from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.knowledge_memory import CATEGORIES,content_digest,pack_static_memory


def fixture():
    text='Synthetic evidence only.'
    scope={k:'synthetic' for k in CATEGORIES[:6]}
    cats={k:None for k in CATEGORIES};cats.update(scope)
    row=dict(id='E1',permission='learned_conditioning',review_status='approved_for_learned_conditioning',
        unresolved_flags=[],source_families=['TRAIN'],source_id='SOURCE',quote=text,quote_start=0,quote_end=len(text),
        scope=dict(scope),parent_ids=['P1'],embedding_parent_id='P1',categories=cats,position_specific=False,
        review_revision='synthetic-review',extraction_revision='synthetic-extraction',
        raw_record_sha256='a'*64,reviewer_id='synthetic-reviewer',reviewer_type='ai_assisted')
    catalogue=dict(schema='learned_conditioning_catalogue_v1',synthetic=True,review_status='FROZEN_REVIEWED',
        sources={'SOURCE':dict(text=text,sha256=hashlib.sha256(text.encode()).hexdigest(),url='https://example.invalid')},evidence=[row])
    schema=dict(schema='static_knowledge_features_v1',embedding_width=2,
        categories={k:['__missing__','__unknown__','synthetic'] for k in CATEGORIES})
    embeddings=dict(schema='approved_frozen_embeddings_v1',encoder_identity='synthetic-frozen-encoder',
        review_status='FROZEN_REVIEWED',vectors={'P1':[.1,.2]})
    return catalogue,schema,embeddings,scope


def pack(catalogue,schema,embeddings,scope,**kwargs):
    config=dict(catalogue_digest=content_digest(catalogue),schema_digest=content_digest(schema),
        embeddings_digest=content_digest(embeddings),task_scope=scope,parent_ids=['P1'],
        allowed_source_families=['TRAIN'],forbidden_source_families=['HELDOUT'],max_slots=3,allow_synthetic=True)
    config.update(kwargs)
    return pack_static_memory(catalogue,schema,embeddings,**config)


def test_shapes_null_padding_missing_and_determinism():
    args=fixture();memory=pack(*args)
    assert memory==pack(*args)
    assert memory.eligible==(True,True,False) and memory.slot_type==(0,1,0)
    assert memory.molecular==((0.,0.),(.1,.2),(0.,0.))
    assert memory.categorical[1][:6]==(2,)*6
    assert memory.categorical_present[1][6:]==(False,)*4
    assert memory.numeric==((),(),()) and memory.numeric_present==((),(),())


def test_parent_permission_not_promoted_and_empty_remains_null():
    c,s,e,t=fixture();c['evidence'][0]['permission']='conditional_proposal'
    assert pack(c,s,e,t).eligible==(True,False,False)
    c['evidence']=[]
    assert pack(c,s,e,t).eligible==(True,False,False)


def test_excluded_source_not_dereferenced_and_scope_rejects_before_vector():
    c,s,e,t=fixture();c['evidence'][0]['source_families']=['HELDOUT'];c['sources']={}
    assert pack(c,s,e,t).eligible==(True,False,False)
    c,s,e,t=fixture();c['evidence'][0]['scope']=dict(t,assay='different');e['vectors']['P1']=['invalid']
    assert pack(c,s,e,t).eligible==(True,False,False)


def test_disabled_memory_does_not_consume_payload():
    c,s,e,t=fixture();e['vectors']['P1']=['invalid'];c['sources']={}
    assert pack(c,s,e,t,enabled=False).eligible==(True,False,False)


def test_missing_embedding_is_zero_with_explicit_presence_flag():
    c,s,e,t=fixture();e['vectors']={}
    memory=pack(c,s,e,t)
    assert memory.molecular[1]==(0.,0.) and memory.molecular_present[1] is False
    assert memory.eligible[1] is True


def test_unseen_category_unknown_is_not_an_applicability_wildcard():
    c,s,e,t=fixture();c['evidence'][0]['categories']['direction']='new_relation'
    assert pack(c,s,e,t).categorical[1][CATEGORIES.index('direction')]==1
    c['evidence'][0]['scope']['assay']='new_assay'
    assert pack(c,s,e,t).eligible==(True,False,False)


@pytest.mark.parametrize('change',[{'current_score':1.0},{'numeric_prior':.5},{'heldout_score':1.0}])
def test_outcomes_and_numeric_priors_are_schema_errors(change):
    c,s,e,t=fixture();c['evidence'][0].update(change)
    with pytest.raises(ValueError,match='unknown fields'):pack(c,s,e,t)


def test_source_identity_is_audit_only_not_feature():
    c,s,e,t=fixture();first=pack(c,s,e,t)
    c['sources']['OTHER']=c['sources'].pop('SOURCE');c['evidence'][0]['source_id']='OTHER'
    second=pack(c,s,e,t)
    assert first.molecular==second.molecular and first.categorical==second.categorical
    assert first.digest!=second.digest


def test_shape_digest_and_quote_guards():
    c,s,e,t=fixture()
    with pytest.raises(ValueError,match='digest'):pack(c,s,e,t,catalogue_digest='bad')
    e['vectors']['P1']=[1.0]
    with pytest.raises(ValueError,match='shape'):pack(c,s,e,t)
    c,s,e,t=fixture();c['evidence'][0]['quote']='wrong'
    with pytest.raises(ValueError,match='quotation'):pack(c,s,e,t)


def test_deterministic_capacity_and_duplicate_ids():
    c,s,e,t=fixture();r=copy.deepcopy(c['evidence'][0]);r['id']='E0';c['evidence'].append(r)
    a=pack(c,s,e,t,max_slots=2);c['evidence'].reverse();b=pack(c,s,e,t,max_slots=2)
    assert a.molecular==b.molecular and a.categorical==b.categorical
    assert '"dropped_ids":["E1"]' in a.audit_json
    c['evidence'][1]['id']='E0'
    with pytest.raises(ValueError,match='duplicate'):pack(c,s,e,t)


def test_nonfinite_payload_rejected_and_synthetic_requires_opt_in():
    c,s,e,t=fixture()
    with pytest.raises(ValueError,match='synthetic'):pack(c,s,e,t,allow_synthetic=False)
    e['vectors']['P1']=[float('nan'),.2]
    with pytest.raises(ValueError):pack(c,s,e,t)


@pytest.mark.parametrize('field,value',[('raw_record_sha256','A'*64),('raw_record_sha256','abc'),
    ('reviewer_id',''),('reviewer_type','extraction_model')])
def test_immutable_lineage_and_review_identity_required(field,value):
    c,s,e,t=fixture();c['evidence'][0][field]=value
    with pytest.raises(ValueError):pack(c,s,e,t)


def test_review_lineage_audit_and_resolved_parent_exclusions():
    c,s,e,t=fixture();memory=pack(c,s,e,t)
    assert '"raw_record_sha256":"'+'a'*64+'"' in memory.audit_json
    assert '"reviewer_id":"synthetic-reviewer"' in memory.audit_json
    with pytest.raises(ValueError,match='group contains forbidden parent'):
        pack(c,s,e,t,forbidden_parent_ids=['P1'])
    c['evidence'][0]['parent_ids']=['P1','P2']
    c['evidence'][0]['embedding_parent_id']='P2'
    with pytest.raises(ValueError,match='embedding parent is forbidden'):
        pack(c,s,e,t,forbidden_parent_ids=['P2'])
