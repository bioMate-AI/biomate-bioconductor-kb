"""Synthetic runner-input and parent-specific memory contracts; AWS execution only."""
from copy import deepcopy
import json
import pytest
import torch
from hybrid.learned_knowledge_inputs import LearnedKnowledgeInputs
from hybrid.knowledge_memory import content_digest
from hybrid.test_knowledge_memory import fixture


def inputs():
    catalogue,schema,embeddings,scope=fixture()
    second=deepcopy(catalogue['evidence'][0]);second.update(id='E2',parent_ids=['P2'],embedding_parent_id='P2')
    catalogue['evidence'].append(second);embeddings['vectors']['P2']=[.7,.8]
    rows=[dict(id=pid,smiles=smiles,compound_id='compound-'+pid,scaffold_id='scaffold-'+pid,
        source_families=['TRAIN'],scope=dict(scope)) for pid,smiles in [('P1','CCO'),('P2','CCN')]]
    bundle=dict(schema='learned_knowledge_bundle_v1',catalogue=catalogue,feature_schema=schema,
        embeddings=embeddings,architecture=dict(layer_indices=[0],heads=2,category_width=8,
        type_width=4,hidden_width=16,max_slots=3))
    return bundle,rows,scope


def provider(bundle=None,rows=None,scope=None,**overrides):
    if bundle is None:bundle,rows,scope=inputs()
    kwargs=dict(bundle_sha256=content_digest(bundle),parent_map_sha256=content_digest(rows),
        task_sha256=content_digest(scope),arm='on',study=False,allowed_source_families=['TRAIN'],
        forbidden_source_families=['HELDOUT'],allow_synthetic=True)
    kwargs.update(overrides)
    return LearnedKnowledgeInputs(bundle,rows,scope,**kwargs)


def test_parent_specific_memory_contains_only_selected_parent_claim():
    p=provider();a=p('CCO');b=p('CCN')
    aa=json.loads(a.audit_json);bb=json.loads(b.audit_json)
    assert aa['parent_ids']==['P1'] and bb['parent_ids']==['P2']
    assert [r['id'] for r in aa['selected']]==['E1']
    assert [r['id'] for r in bb['selected']]==['E2']
    assert a.molecular[1]==(.1,.2) and b.molecular[1]==(.7,.8)
    p.validate_memory(a);p.validate_memory(b)


def test_synthetic_is_smoke_opt_in_only():
    with pytest.raises(ValueError):provider(allow_synthetic=False)
    with pytest.raises(ValueError):provider(study=True)


@pytest.mark.parametrize('excluded',[{'forbidden_compounds':['compound-P1']},
    {'forbidden_scaffolds':['scaffold-P1']},{'forbidden_source_families':['TRAIN']}])
def test_caller_resolved_exclusions_prevent_memory(excluded):
    with pytest.raises(ValueError):provider(**excluded)('CCO')


def test_target_and_conflicting_task_scope_are_rejected():
    bundle,rows,scope=inputs()
    rows[0]['scope']['target']='HELDOUT_TARGET'
    with pytest.raises(ValueError):provider(bundle,rows,scope,forbidden_targets=['HELDOUT_TARGET'])('CCO')
    bundle,rows,scope=inputs();scope=dict(scope,assay='different')
    with pytest.raises(ValueError):provider(bundle,rows,scope)('CCO')


def test_unknown_online_parent_fails_closed_for_null_and_on():
    for arm in ('null','on'):
        p=provider(arm=arm)
        with pytest.raises(ValueError):p('UNMAPPED_NEW_MOLECULE')


def test_null_keeps_parent_identity_but_has_only_null_attention():
    active=provider();null=provider(arm='null')
    for smiles in ('CCO','CCN'):
        a=active(smiles);b=null(smiles)
        assert json.loads(a.audit_json)['parent_ids']==json.loads(b.audit_json)['parent_ids']
        assert a.eligible==(True,True,False) and b.eligible==(True,False,False)
        assert a.digest!=b.digest


def test_changed_bundle_and_parent_identity_cannot_validate_saved_memory():
    original=provider();saved=original('CCO')
    bundle,rows,scope=inputs();bundle['embeddings']['vectors']['P1']=[.9,.8]
    changed=provider(bundle,rows,scope)
    assert changed.config!=original.config
    with pytest.raises(ValueError):changed.validate_memory(saved)
    bundle,rows,scope=inputs();rows[0]['id']='DIFFERENT_PARENT'
    altered=provider(bundle,rows,scope)
    with pytest.raises(ValueError):altered.validate_memory(saved)


def make_generator(p):
    from hybrid.test_knowledge_generator import tiny_generator,SyntheticVocabulary
    g=tiny_generator();g.records={}
    bundle,rows,scope=inputs()
    g.configure_learned_knowledge(bundle['feature_schema'],content_digest(bundle['feature_schema']),[0],2,
        category_width=8,type_width=4,hidden_width=16)
    g.set_knowledge_provider(p)
    g.parent_map=p.parent_map;g.knowledge_task=scope
    g.vocab=SyntheticVocabulary()
    selected=[]
    class Tokenizer:
        eos_token_id=2
        def __call__(self,text,add_special_tokens=True):
            selected.append(text)
            return {'input_ids':[1,3,6,7,8,2]}
    g.tok=Tokenizer()
    return g,selected


def test_actual_generator_null_on_preserve_same_parent_selection():
    from types import SimpleNamespace
    from hybrid.test_knowledge_generator import OneTokenThenEOS
    active,active_choices=make_generator(provider())
    null,null_choices=make_generator(provider(arm='null'))
    ctx=SimpleNamespace(retrieved=(('CCO',{}),('CCN',{})),seed_smiles=())
    active.sample(3,ctx,1.,17,OneTokenThenEOS())
    null.sample(3,ctx,1.,17,OneTokenThenEOS())
    assert active_choices==null_choices and len(active_choices)==1
    assert active.learned_knowledge.memory.eligible==(True,True,False)
    assert null.learned_knowledge.memory.eligible==(True,False,False)
    assert json.loads(active.learned_knowledge.memory.audit_json)['parent_ids']==json.loads(null.learned_knowledge.memory.audit_json)['parent_ids']


def test_checkpoint_restores_last_parent_memory_without_initial_memory(tmp_path):
    from types import SimpleNamespace
    from hybrid.test_knowledge_generator import OneTokenThenEOS
    p=provider();source,_=make_generator(p)
    source.sample(1,SimpleNamespace(retrieved=(('CCN',{}),),seed_smiles=()),1.,17,OneTokenThenEOS())
    path=tmp_path/'last-parent.pt';path.write_bytes(source.lora_state())
    target,_=make_generator(provider())
    assert target.learned_knowledge.memory is None
    target.load_lora(path)
    assert target.learned_knowledge.digest==source.learned_knowledge.digest
    target.knowledge_provider.validate_memory(target.learned_knowledge.memory)
    bundle,rows,scope=inputs();bundle['embeddings']['vectors']['P2']=[.5,.4]
    changed,_=make_generator(provider(bundle,rows,scope))
    before={k:v.clone() for k,v in changed.model.state_dict().items() if isinstance(v,torch.Tensor)}
    with pytest.raises(ValueError):changed.load_lora(path)
    for key,value in before.items():assert torch.equal(changed.model.state_dict()[key],value)


def test_runner_load_gate_rejects_changed_file_bytes_and_bad_hash(tmp_path):
    import hashlib
    from hybrid.run_stage1 import load_gate
    bundle,rows,scope=inputs();path=tmp_path/'bundle.json'
    path.write_text(json.dumps(bundle))
    sha=hashlib.sha256(path.read_bytes()).hexdigest()
    assert load_gate(path,sha)==bundle
    with pytest.raises(ValueError,match='SHA256'):load_gate(path,'0'*64)
    path.write_text(json.dumps(dict(bundle,schema='tampered')))
    with pytest.raises(ValueError,match='SHA256'):load_gate(path,sha)
    with pytest.raises(ValueError,match='SHA256'):provider(bundle_sha256='not-a-sha')


def test_study_on_requires_admitted_evidence_but_null_does_not():
    # Synthetic fixture representation of a real-data schema, never study evidence.
    bundle,rows,scope=inputs();bundle['catalogue']['synthetic']=False
    for row in bundle['catalogue']['evidence']:row['permission']='conditional_proposal'
    with pytest.raises(ValueError,match='requires eligible evidence'):
        provider(bundle,rows,scope,study=True,allow_synthetic=False)('CCO')
    memory=provider(bundle,rows,scope,study=True,allow_synthetic=False,arm='null')('CCO')
    assert memory.eligible==(True,False,False)


def test_raw_manifest_identity_is_part_of_provider_configuration():
    original=provider();changed=provider(bundle_sha256='0'*64)
    assert original.config!=changed.config
    assert original.config['bundle_sha256']!=changed.config['bundle_sha256']


def test_base_only_m1_cannot_authorize_learned_interface():
    from hybrid.run_stage1 import validate_m1_evidence
    initialization={'reference':'synthetic-initial'}
    base=dict(passed=True,real_model=True,initialization_identity=initialization)
    interface=provider().config
    validate_m1_evidence(base,initialization)
    with pytest.raises(ValueError):validate_m1_evidence(base,initialization,interface)
    correct=dict(base,learned_knowledge_interface=interface)
    validate_m1_evidence(correct,initialization,interface)
    other=dict(interface,arm='null')
    with pytest.raises(ValueError):validate_m1_evidence(correct,initialization,other)


def test_denied_evidence_lineage_is_not_read_for_allowed_parent():
    bundle,rows,scope=inputs()
    bundle['catalogue']['evidence'][0]['source_families']=['HELDOUT']
    # The second record is inapplicable to P1, so neither source is dereferenced.
    bundle['catalogue']['sources']={}
    memory=provider(bundle,rows,scope)('CCO')
    assert memory.eligible==(True,False,False)


def test_same_reviewed_real_bundle_smoke_and_study_share_method_identity():
    # Synthetic fixture contents exercise the real-input contract; no scientific claim.
    bundle,rows,scope=inputs();bundle['catalogue']['synthetic']=False
    smoke=provider(bundle,rows,scope,study=False,allow_synthetic=False)
    study=provider(bundle,rows,scope,study=True,allow_synthetic=False)
    assert smoke.config==study.config
    assert smoke.study is False and study.study is True
    assert smoke('CCO')==study('CCO')
    assert 'study' not in smoke.config
    # Runtime gating remains stricter without changing the immutable interface.
    for row in bundle['catalogue']['evidence']:row['permission']='conditional_proposal'
    empty_smoke=provider(bundle,rows,scope,study=False,allow_synthetic=False)
    empty_study=provider(bundle,rows,scope,study=True,allow_synthetic=False)
    assert empty_smoke.config==empty_study.config
    assert empty_smoke('CCO').eligible==(True,False,False)
    with pytest.raises(ValueError,match='requires eligible evidence'):empty_study('CCO')


def test_replacing_parent_compound_identity_cannot_bypass_frozen_exclusions():
    from dataclasses import replace
    p=provider(forbidden_compounds=['forbidden-compound'])
    memory=p('CCO')
    p.parent_map['CCO']=replace(p.parent_map['CCO'],compound_id='forbidden-compound')
    for access in (lambda:p('CCO'),lambda:p.validate_memory(memory),lambda:p.config):
        with pytest.raises(ValueError,match='runtime state changed'):access()
    # Equally reject changing a forbidden compound into an apparently allowed one.
    p=provider(forbidden_compounds=['compound-P1'])
    p.parent_map['CCO']=replace(p.parent_map['CCO'],compound_id='new-allowed-identity')
    with pytest.raises(ValueError,match='runtime state changed'):p('CCO')


@pytest.mark.parametrize('field,value',[
    ('allowed',('TRAIN','UNREVIEWED')),('forbidden',()),
    ('forbidden_compounds',('changed-compound',)),('forbidden_scaffolds',('changed-scaffold',)),
    ('forbidden_targets',('changed-target',)),('task_scope',{'assay':'changed'}),
    ('arm','null'),('study',True),('allow_synthetic',False)])
def test_runtime_policy_changes_are_rejected_on_call_and_config(field,value):
    p=provider();setattr(p,field,value)
    with pytest.raises(ValueError,match='runtime state changed'):p('CCO')
    with pytest.raises(ValueError,match='runtime state changed'):_=p.config


def test_secondary_identity_map_bundle_architecture_and_hash_mutations_rejected():
    from dataclasses import replace
    for mutate in (
        lambda p:p._by_id.update(P1=replace(p._by_id['P1'],source_families=('UNREVIEWED',))),
        lambda p:p.bundle['embeddings']['vectors'].update(P1=[.3,.4]),
        lambda p:p.architecture.update(max_slots=99),
        lambda p:p._hashes.update(catalogue='0'*64),
        lambda p:p._config.update(arm='null')):
        p=provider();mutate(p)
        with pytest.raises(ValueError,match='runtime state changed'):p('CCO')


def test_returned_configuration_is_detached_without_changing_method_identity():
    p=provider();original=p.config;exported=p.config
    exported['architecture']['max_slots']=99
    exported['allowed_source_families'].append('UNREVIEWED')
    assert p.config==original
    assert p('CCO').eligible==(True,True,False)
