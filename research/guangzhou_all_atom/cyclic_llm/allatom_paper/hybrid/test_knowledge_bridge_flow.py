"""Synthetic pack/project/attend contract; execute on AWS only."""
from copy import deepcopy
import torch
from hybrid.knowledge_memory import content_digest
from hybrid.knowledge_projection import KnowledgeProjector
from hybrid.knowledge_attention import PolicyReferenceEvidenceAttention
from hybrid.test_knowledge_memory import fixture, pack


def test_trainable_projection_attention_with_independent_frozen_reference():
    torch.manual_seed(31)
    catalogue,schema,embeddings,scope=fixture()
    memory=pack(catalogue,schema,embeddings,scope)
    projector=KnowledgeProjector(schema,schema_digest=content_digest(schema),output_width=8)
    reference_projector=deepcopy(projector).requires_grad_(False).eval()
    attention=PolicyReferenceEvidenceAttention(8,2)
    hidden=torch.randn(1,4,8)
    reference_state=deepcopy(reference_projector.state_dict())
    optimizer=torch.optim.AdamW(list(projector.parameters())+list(attention.trainable_parameters()),lr=.01)
    for _ in range(2):
        optimizer.zero_grad(set_to_none=True)
        projected,eligible=projector([memory])
        prediction=attention(hidden,projected,eligible)
        prediction.square().mean().backward()
        optimizer.step()
    assert any(p.grad is not None and torch.count_nonzero(p.grad)>0 for p in projector.parameters())
    with torch.no_grad():
        projected,eligible=projector([memory])
        policy=attention(hidden,projected,eligible)
        ref_memory,ref_mask=reference_projector([memory])
        with attention.reference_mode():
            reference=attention(hidden,ref_memory,ref_mask)
    assert not torch.equal(policy,hidden)
    assert torch.equal(reference,hidden)
    for key,value in reference_state.items():
        actual=reference_projector.state_dict()[key]
        assert torch.equal(value,actual) if isinstance(value,torch.Tensor) else value==actual
    assert all(p.grad is None for p in reference_projector.parameters())
