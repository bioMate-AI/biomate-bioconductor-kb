"""Synthetic frozen-reference restore regressions. Execute on AWS only."""
from copy import deepcopy
import pytest
import torch
from hybrid.knowledge_memory import content_digest
from hybrid.test_knowledge_memory import fixture,pack
from hybrid.test_knowledge_generator import bridge_generator,tiny_generator,pair


def snapshots(module):
    return {key:value.detach().clone() for key,value in module.state_dict().items() if isinstance(value,torch.Tensor)}


def unchanged(module,before):
    for key,value in before.items():assert torch.equal(module.state_dict()[key],value),key


@pytest.mark.parametrize('channel',['projection','attention'])
def test_finite_reference_poisoning_rejected_before_live_mutation(channel):
    source,_=bridge_generator();target,_=bridge_generator()
    source.dpo_step([pair()],lr=.01,beta=.5)
    payload=deepcopy(source.learned_knowledge.checkpoint())
    candidates=[key for key,value in payload['state'].items() if isinstance(value,torch.Tensor)
        and (key.startswith('reference.') if channel=='projection' else '._reference.' in key)]
    key=next(key for key in candidates if key.endswith('weight'))
    payload['state'][key].add_(.125)  # valid dimensions/dtype/finite values
    before=snapshots(target.learned_knowledge);memory=target.learned_knowledge.digest
    with pytest.raises(ValueError,match='reference identity differs'):
        target.learned_knowledge.restore(payload)
    unchanged(target.learned_knowledge,before)
    assert target.learned_knowledge.digest==memory
    with pytest.raises(ValueError,match='reference identity differs'):
        target.learned_knowledge.load_state_dict(payload['state'],strict=False)
    unchanged(target.learned_knowledge,before)
    container=torch.nn.ModuleDict({'bridge':target.learned_knowledge})
    nested={'bridge.'+key:value for key,value in payload['state'].items()}
    with pytest.raises(ValueError,match='reference identity differs'):container.load_state_dict(nested)
    unchanged(target.learned_knowledge,before)


def test_legitimate_policy_training_restores_against_same_initialized_reference():
    source,_=bridge_generator();target,_=bridge_generator()
    assert source.learned_knowledge.config['initial_reference_sha256']==target.learned_knowledge.config['initial_reference_sha256']
    initial=snapshots(target.learned_knowledge)
    for _ in range(2):source.dpo_step([pair()],lr=.01,beta=.5)
    payload=deepcopy(source.learned_knowledge.checkpoint())
    target.learned_knowledge.restore(payload)
    unchanged(target.learned_knowledge,snapshots(source.learned_knowledge))
    assert any(not torch.equal(value,target.learned_knowledge.state_dict()[key]) for key,value in initial.items()
        if key.startswith('policy.'))
    for key,value in initial.items():
        if key.startswith('reference.') or '._reference.' in key:
            assert torch.equal(value,target.learned_knowledge.state_dict()[key])


def test_live_reference_drift_and_forged_checkpoint_identity_rejected():
    source,_=bridge_generator();target,_=bridge_generator()
    payload=deepcopy(source.learned_knowledge.checkpoint())
    key=next(key for key,value in payload['state'].items() if isinstance(value,torch.Tensor)
             and '._reference.output.bias' in key)
    payload['state'][key].add_(1.)
    payload['config']['initial_reference_sha256']='f'*64
    before=snapshots(target.learned_knowledge)
    with pytest.raises(ValueError):target.learned_knowledge.restore(payload)
    unchanged(target.learned_knowledge,before)
    with torch.no_grad():next(target.learned_knowledge.reference.parameters()).add_(.1)
    with pytest.raises(ValueError,match='reference identity differs'):target.learned_knowledge.checkpoint()


def test_different_initialization_seed_cannot_silently_replace_reference():
    source,_=bridge_generator()
    target=tiny_generator();target.records={}
    catalogue,schema,embeddings,scope=fixture()
    torch.manual_seed(999)
    target.configure_learned_knowledge(schema,content_digest(schema),[0],2)
    target.set_round_knowledge(pack(catalogue,schema,embeddings,scope))
    assert target.learned_knowledge.config['initial_reference_sha256']!=source.learned_knowledge.config['initial_reference_sha256']
    before=snapshots(target.learned_knowledge)
    with pytest.raises(ValueError):target.learned_knowledge.restore(source.learned_knowledge.checkpoint())
    unchanged(target.learned_knowledge,before)
