"""Multi-round frozen-parent protocol regressions; execute only in AWS QA."""
import json
from pathlib import Path
import pytest

from hybrid.run_stage1 import FrozenParentProtocol
from hybrid.test_learned_knowledge_inputs import provider
from orchestrator.loop import LoopConfig, run_loop
from pmo_harness import Verifier


class OnlineStore:
    def __init__(self):self.rows=[];self.queries=0
    def add(self,smiles,scores,**kwargs):self.rows.append((smiles,scores))
    def query(self,*args,**kwargs):
        self.queries+=1
        return list(reversed(self.rows))
    def state_dict(self):return {'rows':self.rows}
    def load_state_dict(self,state):self.rows=state['rows']


class RecordingGenerator:
    def __init__(self,inputs):self.inputs=inputs;self.parents=[];self.contexts=[]
    def sample(self,n,ctx,temperature,seed,constraint=None):
        assert not ctx.retrieved
        self.contexts.append(tuple(ctx.seed_smiles))
        chosen=ctx.seed_smiles[seed % len(ctx.seed_smiles)]
        self.parents.append(chosen)
        if self.inputs.arm!='off':
            memory=self.inputs(chosen)
            assert json.loads(memory.audit_json)['parent_ids']==[self.inputs.parent_map[chosen].id]
        return ['C'*(len(self.parents)+4)]
    def lora_state(self):return json.dumps(dict(parents=self.parents,contexts=self.contexts)).encode()
    def load_lora(self,path):
        saved=json.loads(Path(path).read_bytes())
        self.parents=saved['parents'];self.contexts=[tuple(v) for v in saved['contexts']]


def run(arm,checkpoint=None,stop_after=None):
    inputs=provider(arm=arm)
    protocol=FrozenParentProtocol(inputs)
    generator=RecordingGenerator(inputs);store=OnlineStore()
    cfg=LoopConfig(run_id='frozen-'+arm,seed=7,budget=4,n_per_round=1,rounds_max=4)
    result=run_loop(cfg,generator,Verifier('synthetic-length',lambda s:float(len(s)),role='train'),
        retriever=store,ctx_builder=protocol.context_builder(cfg),canon=lambda s:s,
        ckpt_dir=checkpoint,stop_after_rounds=stop_after)
    return result,generator,store,protocol


def test_actual_multiround_loop_never_promotes_novel_generated_parents():
    runs=[run(arm) for arm in ('off','null','on')]
    assert all(result['calls']==4 for result,_,_,_ in runs)
    assert runs[0][1].parents==runs[1][1].parents==runs[2][1].parents
    assert runs[0][3].config==runs[1][3].config==runs[2][3].config
    for result,generator,store,protocol in runs:
        assert len(store.rows)==4 and store.queries==0
        assert all(context==protocol.parents for context in generator.contexts)
        assert set(generator.parents)<=set(protocol.parents)
        assert not set(smiles for smiles,_ in store.rows)&set(protocol.parents)


def test_resumed_loop_retains_same_frozen_pool_and_parent_sequence(tmp_path):
    complete,full,_,_=run('on')
    partial,_,_,_=run('on',str(tmp_path),2)
    assert partial['interrupted']
    resumed,continued,store,protocol=run('on',str(tmp_path))
    assert resumed['oracle_log']==complete['oracle_log']
    assert continued.parents==full.parents and continued.contexts==full.contexts
    assert len(store.rows)==4 and store.queries==0
    assert all(context==protocol.parents for context in continued.contexts)


def test_pool_eligibility_is_metadata_based_and_identical_across_arms():
    configs=[]
    for arm in ('off','null','on'):
        inputs=provider(arm=arm,forbidden_compounds=['compound-P2'])
        protocol=FrozenParentProtocol(inputs)
        assert protocol.parents==('CCO',)
        assert protocol.config['excluded']==[dict(parent_id='P2',reason='compound_exclusion')]
        configs.append(protocol.config)
    assert configs[0]==configs[1]==configs[2]
    with pytest.raises(ValueError,match='no approved parents'):
        FrozenParentProtocol(provider(forbidden_compounds=['compound-P1','compound-P2']))


def test_unknown_parent_rejection_is_preserved_and_no_evidence_filter_changes_pool():
    inputs=provider(arm='null')
    protocol=FrozenParentProtocol(inputs)
    assert protocol.parents==('CCO','CCN')
    with pytest.raises(ValueError,match='approved mapping'):inputs('CCCCC')
    assert protocol.config['online_parent_promotion'] is False
    assert protocol.config['retrieval_parent_ranking'] is False


def test_bound_interface_retains_pool_without_mutating_detached_provider_config():
    from copy import deepcopy
    from hybrid.run_stage1 import FrozenParentInputs, validate_m1_evidence
    inputs=provider();original=inputs.config
    protocol=FrozenParentProtocol(inputs)
    bound=FrozenParentInputs(inputs,protocol)
    assert inputs.config==original and 'parent_protocol' not in inputs.config
    assert bound.config['parent_protocol']==protocol.config
    copied=bound.config;copied['parent_protocol']['parents'].clear()
    assert bound.config['parent_protocol']==protocol.config
    identity={'reference':'fixture'}
    evidence=dict(passed=True,real_model=True,initialization_identity=identity,
        learned_knowledge_interface=bound.config)
    validate_m1_evidence(evidence,identity,bound.config)
    altered=deepcopy(bound.config);altered['parent_protocol']['pool_sha256']='0'*64
    with pytest.raises(ValueError,match='learned knowledge interface'):
        validate_m1_evidence(evidence,identity,altered)
    bound.validate_memory(bound('CCO'))
    # Generator stores provider.config and compares the same binding on resume.
    from hybrid.test_knowledge_generator import tiny_generator
    generator=tiny_generator()
    generator.records={}
    schema=inputs.bundle['feature_schema']
    generator.configure_learned_knowledge(schema,inputs.config['payload_digests']['feature_schema'],[0],2)
    generator.set_knowledge_provider(bound)
    assert generator.learned_input_config==bound.config
    assert 'parent_protocol' in generator.learned_input_config
    import io
    import torch
    snapshot=generator.lora_state()
    saved=torch.load(io.BytesIO(snapshot),weights_only=True)
    assert saved['learned_input_config']==bound.config
    generator.load_lora(io.BytesIO(snapshot))
    altered_config=deepcopy(generator.learned_input_config)
    altered_config['parent_protocol']['pool_sha256']='0'*64
    generator.learned_input_config=altered_config
    with pytest.raises(ValueError,match='learned input configuration differs'):
        generator.load_lora(io.BytesIO(snapshot))
