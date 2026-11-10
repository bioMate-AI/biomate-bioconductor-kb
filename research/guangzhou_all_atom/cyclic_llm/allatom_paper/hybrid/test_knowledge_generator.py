"""Actual tiny Llama/PEFT generator integration; run only on authorised AWS.

No downloaded weights, molecular claims or mock policy forwards. Token strings
below identify synthetic completion records, not validated chemical structures.
"""
import copy
import io
from pathlib import Path
import sys
from types import SimpleNamespace
import numpy as np
import pytest
import torch
from transformers import LlamaConfig,LlamaForCausalLM
from peft import LoraConfig,get_peft_model
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.model import ChemFMGenerator
from hybrid.knowledge_memory import content_digest
from hybrid.test_knowledge_memory import fixture,pack


class SyntheticConstraint:
    eos=2
    def init_state(self,prefix):return list(prefix)
    def mask(self,state):
        allowed=np.ones(24,dtype=bool);allowed[0]=False
        return allowed
    def soft_logits(self,state):return np.zeros(24,dtype=np.float32)
    def advance(self,state,token):state.append(token);return True


def tiny_generator():
    torch.manual_seed(314)
    config=LlamaConfig(vocab_size=24,hidden_size=16,intermediate_size=24,
        num_hidden_layers=1,num_attention_heads=2,num_key_value_heads=2,
        max_position_embeddings=32,attention_dropout=0.0)
    config._attn_implementation='eager'
    base=LlamaForCausalLM(config).eval()
    model=get_peft_model(base,LoraConfig(r=2,lora_alpha=4,target_modules=['q_proj','v_proj'],
        lora_dropout=0.,bias='none',task_type='CAUSAL_LM'))
    g=ChemFMGenerator.__new__(ChemFMGenerator)
    g.model=model;g.device='cpu';g.seeds=('synthetic-parent',)
    g.frac=.5;g.batch=2;g.masked=True;g.max_tokens=16
    g.optimizer=torch.optim.AdamW([p for p in model.parameters() if p.requires_grad],lr=.001)
    g.records={'chosen':([1,3],[4,5,2]),'rejected':([1,3],[7,8,2])}
    g.last_stats={};g.con=SyntheticConstraint();g.temperature=1.;g.steps=0;g.extra_state={}
    g.deadline=float('inf');g.knowledge_selector=None;g.parent_map={};g.knowledge_task={}
    g.knowledge_arm='off';g.knowledge_config=None
    g.initialization_identity={'reference':'frozen_initial_base','fixture':'synthetic-random-314'}
    return g


def pair():return SimpleNamespace(chosen='chosen',rejected='rejected')


def tensors(state):
    return {key:value.detach().clone() for key,value in state.items() if isinstance(value,torch.Tensor)}


def assert_tensors_equal(before,after):
    for key,value in before.items():assert torch.equal(value,after[key]),key


def test_bridge_absent_preserves_actual_generator_dpo_and_legacy_checkpoint(tmp_path):
    g=tiny_generator()
    initial=g.logprobs(['chosen','rejected'],None)
    result=g.dpo_step([pair()],lr=.01,beta=.5)
    assert result['optimizer_steps']==1 and np.isfinite(result['loss'])
    assert g.logprobs(['chosen','rejected'],None)!=initial
    path=tmp_path/'legacy.pt';path.write_bytes(g.lora_state())
    restored=tiny_generator();restored.load_lora(path)
    assert restored.steps==1
    assert restored.logprobs(['chosen','rejected'],None)==pytest.approx(g.logprobs(['chosen','rejected'],None),abs=1e-7)


def bridge_generator():
    g=tiny_generator();g.records={}
    catalogue,schema,embeddings,scope=fixture();memory=pack(catalogue,schema,embeddings,scope)
    g.configure_learned_knowledge(schema,content_digest(schema),[0],2)
    g.set_round_knowledge(memory)
    bind_records(g)
    return g,memory


def bind_records(g):
    g.records={'chosen':([1,3],[4,5,2]),'rejected':([1,3],[7,8,2])}
    g._record_knowledge={name:g.learned_knowledge.digest for name in g.records}


def reference_logps(g):
    with g._reference_policy():return g.logprobs(['chosen','rejected'],None)


def frozen_reference_state(g):
    return {key:value.detach().clone() for key,value in g.learned_knowledge.state_dict().items()
            if isinstance(value,torch.Tensor) and (key.startswith('reference.') or '._reference.' in key)}


def test_actual_generator_bridge_zero_initialisation_and_two_step_learning():
    plain=tiny_generator();plain_logps=plain.logprobs(['chosen','rejected'],None)
    g,memory=bridge_generator()
    assert g.logprobs(['chosen','rejected'],None)==pytest.approx(plain_logps,abs=1e-7)
    reference_before=reference_logps(g);frozen=frozen_reference_state(g)
    base={k:v.detach().clone() for k,v in g.model.named_parameters() if not v.requires_grad}
    projector_before=tensors(g.learned_knowledge.policy.state_dict())
    optimizer_ids={id(p) for group in g.optimizer.param_groups for p in group['params']}
    assert all(id(p) in optimizer_ids for p in g.learned_knowledge.trainable_parameters())
    for _ in range(2):
        result=g.dpo_step([pair()],lr=.01,beta=.5)
        assert np.isfinite(result['loss']) and result['kl']>=0
    assert result['bridge_delta_l2']>0
    assert any(p.grad is not None and bool(torch.count_nonzero(p.grad))
               for p in g.learned_knowledge.policy.parameters())
    assert any(not torch.equal(value,g.learned_knowledge.policy.state_dict()[key]) for key,value in projector_before.items())
    assert g.logprobs(['chosen','rejected'],None)!=pytest.approx(reference_before,abs=1e-7)
    assert reference_logps(g)==pytest.approx(reference_before,abs=1e-7)
    assert_tensors_equal(frozen,g.learned_knowledge.state_dict())
    assert_tensors_equal(base,dict(g.model.named_parameters()))
    assert all(p.grad is None for p in g.learned_knowledge.reference.parameters())
    for bridge in g.learned_knowledge.hooks.bridges.values():
        assert all(p.grad is None for p in bridge._reference.parameters())


def test_checkpoint_restores_actual_bridge_optimizer_and_identical_next_step(tmp_path):
    uninterrupted,memory=bridge_generator()
    uninterrupted.dpo_step([pair()],lr=.01,beta=.5)
    path=tmp_path/'bridge.pt';path.write_bytes(uninterrupted.lora_state())
    saved=torch.load(path,map_location='cpu',weights_only=True)
    assert saved['learned_knowledge']['memory']['digest']==memory.digest
    assert len(saved['optimizer']['param_groups'])==2 and saved['optimizer']['state']
    restored,_=bridge_generator();restored.load_lora(path)
    assert restored.records=={} and restored.steps==1
    assert restored.learned_knowledge.digest==memory.digest
    bind_records(restored)
    assert restored.logprobs(['chosen','rejected'],None)==pytest.approx(uninterrupted.logprobs(['chosen','rejected'],None),abs=1e-7)
    assert reference_logps(restored)==pytest.approx(reference_logps(uninterrupted),abs=1e-7)
    a=uninterrupted.dpo_step([pair()],lr=.01,beta=.5)
    b=restored.dpo_step([pair()],lr=.01,beta=.5)
    assert a==pytest.approx(b,abs=1e-7)
    assert_tensors_equal(tensors(uninterrupted.learned_knowledge.state_dict()),restored.learned_knowledge.state_dict())
    assert_tensors_equal(tensors(uninterrupted.model.state_dict()),restored.model.state_dict())
    assert restored.steps==uninterrupted.steps==2


def test_candidate_digest_mismatch_fails_before_update_and_reference_scope_restores():
    g,memory=bridge_generator();g._record_knowledge['rejected']='wrong'
    before=tensors(g.learned_knowledge.state_dict())
    with pytest.raises(ValueError,match='conditioning differs'):
        g.dpo_step([pair()],lr=.01,beta=.5)
    assert g.steps==0
    assert_tensors_equal(before,g.learned_knowledge.state_dict())
    assert not g._knowledge_reference.get()
    bind_records(g)
    with pytest.raises(RuntimeError,match='synthetic'):
        with g._reference_policy():
            assert g._knowledge_reference.get()
            raise RuntimeError('synthetic')
    assert not g._knowledge_reference.get()
    assert np.isfinite(g._logp('chosen'))


def test_corrupt_memory_checkpoint_fails_before_mutating_live_parameters(tmp_path):
    g,memory=bridge_generator();g.dpo_step([pair()],lr=.01,beta=.5)
    state=torch.load(io.BytesIO(g.lora_state()),map_location='cpu',weights_only=True)
    state['learned_knowledge']['memory']['digest']='invalid'
    path=tmp_path/'bad.pt';torch.save(state,path)
    target,_=bridge_generator()
    model_before=tensors(target.model.state_dict());bridge_before=tensors(target.learned_knowledge.state_dict())
    with pytest.raises(ValueError,match='digest'):target.load_lora(path)
    assert_tensors_equal(model_before,target.model.state_dict())
    assert_tensors_equal(bridge_before,target.learned_knowledge.state_dict())
    assert target.steps==0


def test_bridge_enablement_mismatch_rejects_checkpoint(tmp_path):
    bridge,memory=bridge_generator();path=tmp_path/'bridge.pt';path.write_bytes(bridge.lora_state())
    plain=tiny_generator()
    with pytest.raises(ValueError,match='enablement differs'):plain.load_lora(path)
    plain_path=tmp_path/'plain.pt';plain_path.write_bytes(plain.lora_state())
    with pytest.raises(ValueError,match='enablement differs'):bridge.load_lora(plain_path)


class SyntheticTokenizer:
    eos_token_id=2
    def __call__(self,text,add_special_tokens=True):
        assert text=='synthetic-parent' and add_special_tokens
        return {'input_ids':[1,3,6,7,8,2]}


class SyntheticVocabulary:
    def decode(self,ids):return 'synthetic:'+','.join(map(str,ids))


class OneTokenThenEOS(SyntheticConstraint):
    def init_state(self,prefix):return {'generated':0}
    def mask(self,state):
        allowed=np.zeros(24,dtype=bool)
        allowed[4 if state['generated']==0 else self.eos]=True
        return allowed
    def advance(self,state,token):state['generated']+=1;return True


def prepare_sampler(g):
    from hybrid.knowledge_parent import Parent
    _,_,_,scope=fixture()
    g.tok=SyntheticTokenizer();g.vocab=SyntheticVocabulary()
    g.parent_map={'synthetic-parent':Parent.from_record(dict(id='P1',smiles='synthetic-parent',
        compound_id='synthetic-compound',scaffold_id='synthetic-scaffold',source_families=['TRAIN'],scope=scope))}
    g.knowledge_task=dict(scope)
    return SimpleNamespace(retrieved=(),seed_smiles=('synthetic-parent',))


def test_actual_sample_broadcasts_memory_full_and_last_batch_with_live_kv_cache():
    g,memory=bridge_generator();ctx=prepare_sampler(g)
    # Activate the real attention branch so its cached forwards are exercised.
    with torch.no_grad():
        for bridge in g.learned_knowledge.hooks.bridges.values():
            bridge.policy.output.weight.normal_(0,.05)
            bridge.policy.output.bias.fill_(.03)
    forwards=[];projected=[]
    def observe_forward(module,args,kwargs):
        ids=kwargs['input_ids']
        forwards.append((tuple(ids.shape),kwargs.get('past_key_values') is not None))
    def observe_projection(module,args,result):
        projected.append((tuple(result[0].shape),result[1].detach().clone()))
    handle=g.model.register_forward_pre_hook(observe_forward,with_kwargs=True)
    projection_handle=g.learned_knowledge.policy.register_forward_hook(observe_projection)
    try:
        output=g.sample(3,ctx,temperature=1.,seed=17,constraint=OneTokenThenEOS())
    finally:
        handle.remove();projection_handle.remove()
    assert output==['synthetic:1,3,6,4']*3
    assert forwards==[((2,3),False),((2,1),True),((1,3),False),((1,1),True)]
    assert [shape for shape,mask in projected]==[(2,3,16),(1,3,16)]
    for shape,mask in projected:assert mask.tolist()==[[True,True,False]]*shape[0]
    assert g.last_stats['completed']==3 and g.last_stats['outcomes']=={'ok':3}
    assert g.last_stats['knowledge_memory_digest']==memory.digest
    assert g._record_knowledge=={output[0]:memory.digest}
    assert g.records[output[0]]==([1,3,6],[4,2])
    # Re-scoring consumes the identical snapshot and forced-token distributions.
    assert g.logprobs([output[0]],None)==pytest.approx([0.],abs=1e-7)


def test_sample_rejects_unapproved_or_scope_mismatched_parent_before_tokenization():
    from dataclasses import replace
    g,memory=bridge_generator();ctx=prepare_sampler(g)
    def forbidden_tokenizer(*args,**kwargs):raise AssertionError('tokenizer must not be reached')
    g.tok=forbidden_tokenizer
    parent=g.parent_map['synthetic-parent']
    g.parent_map={}
    with pytest.raises(ValueError,match='parent is not approved'):
        g.sample(1,ctx,1.,17,OneTokenThenEOS())
    altered=dict(parent.scope);altered['assay']='different'
    g.parent_map={'synthetic-parent':replace(parent,scope=tuple(sorted(altered.items())))}
    with pytest.raises(ValueError,match='scope conflicts'):
        g.sample(1,ctx,1.,17,OneTokenThenEOS())


def test_resume_rejects_different_preinstalled_round_memory_without_mutation(tmp_path):
    source,memory=bridge_generator();source.dpo_step([pair()],lr=.01,beta=.5)
    path=tmp_path/'source.pt';path.write_bytes(source.lora_state())
    target,_=bridge_generator()
    catalogue,schema,embeddings,scope=fixture();embeddings['vectors']['P1']=[.9,.8]
    changed=pack(catalogue,schema,embeddings,scope)
    target.set_round_knowledge(changed)
    before=tensors(target.learned_knowledge.state_dict());model_before=tensors(target.model.state_dict())
    with pytest.raises(ValueError,match='round knowledge memory differs'):
        target.load_lora(path)
    assert target.learned_knowledge.digest==changed.digest and target.steps==0
    assert_tensors_equal(before,target.learned_knowledge.state_dict())
    assert_tensors_equal(model_before,target.model.state_dict())
