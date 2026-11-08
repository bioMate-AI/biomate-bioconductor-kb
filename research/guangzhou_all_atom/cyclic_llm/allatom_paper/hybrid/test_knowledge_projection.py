"""Synthetic projection tests; execute on authorised AWS compute only."""
import copy
from dataclasses import replace
import json
from pathlib import Path
import sys
import pytest
import torch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.knowledge_memory import content_digest,CATEGORIES
from hybrid.knowledge_projection import KnowledgeProjector
from hybrid.test_knowledge_memory import fixture,pack


def setup():
    c,s,e,t=fixture();memory=pack(c,s,e,t)
    module=KnowledgeProjector(s,schema_digest=content_digest(s),output_width=12)
    return module,memory,s


def resign(memory,**changes):
    changed=replace(memory,**changes)
    fields=('molecular','categorical','categorical_present','molecular_present','eligible','slot_type','numeric','numeric_present')
    payload={k:getattr(changed,k) for k in fields};payload['audit']=json.loads(changed.audit_json)
    return replace(changed,digest=content_digest(payload))


def test_projection_batch_shape_zero_null_padding_and_gradients():
    module,memory,s=setup();output,eligible=module([memory,memory])
    assert output.shape==(2,3,12) and eligible.dtype==torch.bool
    assert eligible.tolist()==[[True,True,False]]*2
    assert torch.count_nonzero(output[:,0])==0 and torch.count_nonzero(output[:,2])==0
    output[:,1].sum().backward()
    assert module.projection[-1].weight.grad is not None
    assert torch.isfinite(module.projection[-1].weight.grad).all()
    assert module.projection[-1].bias.grad.abs().sum()>0
    assert isinstance(memory.molecular,tuple) and not any(isinstance(v,torch.Tensor) for row in memory.molecular for v in row)


def test_null_only_is_exact_zero_even_with_nonzero_bias():
    c,s,e,t=fixture();memory=pack(c,s,e,t,enabled=False)
    module=KnowledgeProjector(s,schema_digest=content_digest(s),output_width=8)
    with torch.no_grad():module.projection[-1].bias.fill_(7.)
    output,eligible=module([memory])
    assert torch.count_nonzero(output)==0 and eligible.tolist()==[[True,False,False]]


def test_source_audit_does_not_change_predictors():
    module,memory,s=setup()
    audit=json.loads(memory.audit_json);audit['selected'][0]['source_id']='OTHER'
    changed=resign(memory,audit_json=json.dumps(audit,sort_keys=True,separators=(',',':')))
    a,_=module([memory]);b,_=module([changed])
    assert torch.equal(a,b)


def test_frozen_deepcopy_reference_independent_and_roundtrip():
    module,memory,s=setup();reference=copy.deepcopy(module).requires_grad_(False)
    before,_=reference([memory])
    with torch.no_grad():module.projection[-1].bias.add_(1.)
    after,_=reference([memory]);policy,_=module([memory])
    assert torch.equal(before,after) and not torch.equal(after,policy)
    assert not any(p.requires_grad for p in reference.parameters())
    replacement=KnowledgeProjector(s,schema_digest=content_digest(s),output_width=12)
    replacement.load_state_dict(module.state_dict())
    assert torch.equal(replacement([memory])[0],policy)


def test_changed_vocabulary_order_or_checkpoint_schema_rejected():
    module,memory,s=setup();changed=copy.deepcopy(s)
    changed['categories']['property']+=['other']
    with pytest.raises(ValueError,match='digest'):
        KnowledgeProjector(changed,schema_digest=content_digest(s),output_width=12)
    other=KnowledgeProjector(changed,schema_digest=content_digest(changed),output_width=12)
    with pytest.raises(ValueError,match='schema'):other([memory])
    state=module.state_dict();state['_extra_state']=dict(state['_extra_state'],category_order=list(reversed(CATEGORIES)))
    with pytest.raises(ValueError,match='schema/order'):module.load_state_dict(state)


def test_invalid_ids_missingness_and_nonfinite_features_rejected():
    module,memory,s=setup()
    ids=list(memory.categorical);ids[1]=(999,)+ids[1][1:]
    with pytest.raises(ValueError,match='ID out'):module([resign(memory,categorical=tuple(ids))])
    masks=list(memory.categorical_present);masks[1]=(False,)+masks[1][1:]
    with pytest.raises(ValueError,match='missingness'):module([resign(memory,categorical_present=tuple(masks))])
    # Cannot even sign a NaN payload under the immutable feature contract.
    vectors=list(memory.molecular);vectors[1]=(float('nan'),.2)
    with pytest.raises(ValueError):module([replace(memory,molecular=tuple(vectors))])


def test_mutated_digest_numeric_channel_and_capacity_rejected():
    module,memory,s=setup()
    with pytest.raises(ValueError,match='digest'):module([replace(memory,digest='bad')])
    numeric=((),(1.,),())
    with pytest.raises(ValueError,match='numeric/history'):module([resign(memory,numeric=numeric)])
    c,s,e,t=fixture();short=pack(c,s,e,t,max_slots=2)
    with pytest.raises(ValueError,match='capacities'):module([memory,short])


def test_masked_padding_cannot_carry_nonzero_payload():
    module,memory,s=setup();vectors=list(memory.molecular);vectors[2]=(1.,2.)
    with pytest.raises(ValueError,match='must be zero'):
        module([resign(memory,molecular=tuple(vectors))])


def test_same_shape_vocab_mismatch_rejects_before_any_projector_tensor_copy():
    module,memory,s=setup()
    # Two real categories have equal cardinality but opposite ID assignments.
    left=copy.deepcopy(s);left['categories']['direction']+=['up','down']
    right=copy.deepcopy(left)
    right['categories']['direction'][-2:]=['down','up']
    target=KnowledgeProjector(left,schema_digest=content_digest(left),output_width=12)
    source=KnowledgeProjector(right,schema_digest=content_digest(right),output_width=12)
    with torch.no_grad():
        for parameter in source.parameters():parameter.fill_(17.)
    before={k:v.clone() for k,v in target.state_dict().items() if isinstance(v,torch.Tensor)}
    with pytest.raises(ValueError,match='schema/order'):
        target.load_state_dict(source.state_dict(),strict=False)
    for key,value in before.items():assert torch.equal(target.state_dict()[key],value)
    # The nested loader must also refuse before copying this projector's children.
    container=torch.nn.ModuleDict({'projector':target})
    nested_source=torch.nn.ModuleDict({'projector':source})
    with pytest.raises(ValueError,match='schema/order'):
        container.load_state_dict(nested_source.state_dict())
    for key,value in before.items():assert torch.equal(target.state_dict()[key],value)


def test_missing_checkpoint_schema_is_not_bypassed_by_non_strict_load():
    module,memory,s=setup();state=module.state_dict();state.pop('_extra_state')
    with pytest.raises(ValueError,match='schema/order'):module.load_state_dict(state,strict=False)
