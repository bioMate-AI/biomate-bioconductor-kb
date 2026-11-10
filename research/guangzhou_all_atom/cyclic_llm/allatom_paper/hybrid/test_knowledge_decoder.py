"""Synthetic pinned-Llama hook regressions; run only on approved cloud compute."""
import hashlib

import pytest
import torch
from transformers import LlamaConfig, LlamaForCausalLM

from hybrid.knowledge_decoder import LlamaEvidenceHooks

DIGEST=hashlib.sha256(b'synthetic-pre-round-evidence').hexdigest()


def fixture(layers=2):
    torch.manual_seed(23)
    config=LlamaConfig(vocab_size=24,hidden_size=16,intermediate_size=24,
        num_hidden_layers=layers,num_attention_heads=2,num_key_value_heads=2,
        max_position_embeddings=32,attention_dropout=0.0)
    config._attn_implementation='eager'
    model=LlamaForCausalLM(config).eval()
    memory=torch.randn(1,3,16);memory[:,0]=0
    mask=torch.tensor([[True,True,False]])
    ids=torch.tensor([[1,4,7,9]])
    return model,memory,mask,ids


def activate(adapter):
    with torch.no_grad():
        for bridge in adapter.bridges.values():
            bridge.policy.output.weight.normal_(0,.15)
            bridge.policy.output.bias.fill_(.1)


def test_disabled_and_zero_initialisation_preserve_logits_exactly():
    model,memory,mask,ids=fixture()
    with torch.no_grad():baseline=model(ids,use_cache=False).logits
    hooks=LlamaEvidenceHooks(model,[0,1],2).attach()
    with torch.no_grad():
        assert torch.equal(model(ids,use_cache=False).logits,baseline)
        with hooks.condition(memory,mask,DIGEST):
            assert torch.equal(model(ids,use_cache=False).logits,baseline)
        activate(hooks)
        with hooks.condition(enabled=False):
            assert torch.equal(model(ids,use_cache=False).logits,baseline)
    hooks.remove()
    with torch.no_grad():assert torch.equal(model(ids,use_cache=False).logits,baseline)


def test_paired_hooks_match_manual_full_residual_insertion():
    model,memory,mask,_=fixture(layers=1)
    hooks=LlamaEvidenceHooks(model,[0],2).attach();activate(hooks)
    hidden=torch.randn(1,4,16)
    positions=torch.arange(4).unsqueeze(0)
    rope=model.model.rotary_emb(hidden,positions)
    causal=torch.zeros(1,1,4,4).masked_fill(torch.triu(torch.ones(4,4,dtype=torch.bool),diagonal=1),float('-inf'))
    layer=model.model.layers[0]
    with hooks.condition(memory,mask,DIGEST):
        actual=layer(hidden,attention_mask=causal,position_embeddings=rope,use_cache=False)[0]
    hooks.remove()
    attention,_=layer.self_attn(hidden_states=layer.input_layernorm(hidden),
        attention_mask=causal,position_embeddings=rope,use_cache=False)
    after_attention=hidden+attention
    changed=hooks.bridges['0'].policy(after_attention,memory,mask)
    expected=changed+layer.mlp(layer.post_attention_layernorm(changed))
    wrong_pre_hook_only=after_attention+layer.mlp(layer.post_attention_layernorm(changed))
    assert torch.allclose(actual,expected,atol=1e-6,rtol=1e-5)
    assert not torch.allclose(actual,wrong_pre_hook_only,atol=1e-6,rtol=1e-5)


def test_cached_and_full_decoding_agree_and_wrong_context_cache_rejected():
    model,memory,mask,ids=fixture()
    hooks=LlamaEvidenceHooks(model,[0,1],2).attach();activate(hooks)
    with torch.no_grad(),hooks.condition(memory,mask,DIGEST):
        full=model(ids,use_cache=False).logits
        cache=None;pieces=[]
        for t in range(ids.shape[1]):
            output=model(ids[:,t:t+1],past_key_values=cache,use_cache=True,
                         attention_mask=torch.ones(1,t+1,dtype=torch.long))
            pieces.append(output.logits);cache=output.past_key_values
        assert torch.allclose(torch.cat(pieces,1),full,atol=1e-6,rtol=1e-5)
    changed=memory.clone();changed[:,1]+=1
    with hooks.condition(changed,mask,DIGEST):
        with pytest.raises(ValueError,match='different evidence'):
            model(ids[:,:1],past_key_values=cache,use_cache=True)
    hooks.remove()


def test_future_tokens_cannot_change_earlier_logits_and_reference_is_fixed():
    model,memory,mask,ids=fixture()
    hooks=LlamaEvidenceHooks(model,[0,1],2).attach();activate(hooks)
    alternate=ids.clone();alternate[:,2:]=torch.tensor([[11,12]])
    with torch.no_grad():
        baseline=model(ids,use_cache=False).logits
        with hooks.condition(memory,mask,DIGEST):
            policy=model(ids,use_cache=False).logits
            future=model(alternate,use_cache=False).logits
        assert torch.allclose(policy[:,:2],future[:,:2],atol=1e-6,rtol=1e-5)
        assert not torch.allclose(policy,baseline)
        with hooks.condition(memory,mask,DIGEST,reference=True):
            assert torch.equal(model(ids,use_cache=False).logits,baseline)
    hooks.remove()


def test_exception_cleans_layer_frames_and_nested_context_restores(monkeypatch):
    model,memory,mask,ids=fixture()
    hooks=LlamaEvidenceHooks(model,[0],2).attach();activate(hooks)
    with torch.no_grad():baseline=model(ids,use_cache=False).logits
    original=model.model.layers[0].mlp.forward
    def failure(*args,**kwargs):raise RuntimeError('synthetic MLP failure')
    with hooks.condition(memory,mask,DIGEST):
        with hooks.condition(enabled=False):
            with torch.no_grad():assert torch.equal(model(ids,use_cache=False).logits,baseline)
        monkeypatch.setattr(model.model.layers[0].mlp,'forward',failure)
        with pytest.raises(RuntimeError,match='synthetic MLP failure'):model(ids,use_cache=False)
        monkeypatch.setattr(model.model.layers[0].mlp,'forward',original)
        assert all(not frames.get() for frames in hooks._frames.values())
        assert not hooks._calls.get()
        with torch.no_grad():assert not torch.equal(model(ids,use_cache=False).logits,baseline)
    with torch.no_grad():assert torch.equal(model(ids,use_cache=False).logits,baseline)
    hooks.remove()


def test_hook_ownership_and_gradient_checkpointing_fail_closed():
    model,memory,mask,ids=fixture()
    calls=[]
    observer=model.model.layers[0].register_forward_hook(lambda *args:calls.append('external'))
    hooks=LlamaEvidenceHooks(model,[0],2).attach()
    other=LlamaEvidenceHooks(model,[0],2)
    with pytest.raises(RuntimeError,match='owner'):other.attach()
    with pytest.raises(RuntimeError,match='already attached'):hooks.attach()
    model.gradient_checkpointing_enable()
    with pytest.raises(ValueError,match='gradient checkpointing'):
        with hooks.condition(memory,mask,DIGEST):pass
    model.gradient_checkpointing_disable()
    hooks.remove();hooks.remove()
    with torch.no_grad():model(ids,use_cache=False)
    assert calls==['external']
    observer.remove()
    for indices in ([0,0],[-1],[2],[],[1,0]):
        with pytest.raises(ValueError):LlamaEvidenceHooks(model,indices,2)


def test_context_snapshots_values_preserves_projection_gradient_and_digest():
    model,memory,mask,ids=fixture()
    hooks=LlamaEvidenceHooks(model,[0],2).attach();activate(hooks)
    projected=memory.clone().requires_grad_()
    with hooks.condition(projected,mask,DIGEST) as digest:
        assert len(digest)==64 and digest!=DIGEST
        output=model(ids,use_cache=False).logits
        output.square().sum().backward()
    assert projected.grad is not None and torch.isfinite(projected.grad).all()
    assert torch.count_nonzero(projected.grad[:,1])>0
    assert torch.count_nonzero(projected.grad[:,2])==0
    with torch.no_grad(),hooks.condition(memory,mask,DIGEST):
        before=model(ids,use_cache=False).logits
        memory.add_(100);mask[:]=False
        assert torch.equal(model(ids,use_cache=False).logits,before)
    hooks.remove()


def test_checkpoint_configuration_rejected_before_parameter_mutation():
    model,_,_,_=fixture()
    hooks=LlamaEvidenceHooks(model,[0],2)
    activate(hooks)
    state=hooks.state_dict()
    compatible=LlamaEvidenceHooks(model,[0],2)
    compatible.load_state_dict(state)
    for other in (LlamaEvidenceHooks(model,[0],4), LlamaEvidenceHooks(model,[1],2)):
        before={key:value.clone() for key,value in other.named_parameters()}
        with pytest.raises(ValueError,match='configuration mismatch'):
            other.load_state_dict(state,strict=False)
        assert all(torch.equal(value,before[key]) for key,value in other.named_parameters())
    missing=dict(state);missing.pop('_extra_state')
    with pytest.raises(ValueError,match='configuration mismatch'):
        compatible.load_state_dict(missing,strict=False)


def test_precheck_failure_cleans_own_frame_and_preserves_outer_frame():
    model,memory,mask,ids=fixture()
    hooks=LlamaEvidenceHooks(model,[0],2).attach()
    outer=('outer-sentinel',None)
    token=hooks._calls.set((outer,))
    try:
        with pytest.raises(ValueError,match='positionally'):
            model(ids,torch.ones_like(ids))
        assert hooks._calls.get()==(outer,)
    finally:
        hooks._calls.reset(token)
    with hooks.condition(memory,mask,DIGEST,reference=True):
        assert not model(ids,use_cache=False).logits.requires_grad
    assert not hooks._calls.get()
    hooks.remove()
