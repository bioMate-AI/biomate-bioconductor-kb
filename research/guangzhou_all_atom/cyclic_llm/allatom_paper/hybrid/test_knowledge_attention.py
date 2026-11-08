"""Synthetic primitive checks only; execute on approved EC2, never locally."""
import pytest
import torch

from hybrid.knowledge_attention import EvidenceCrossAttention, PolicyReferenceEvidenceAttention


def inputs():
    torch.manual_seed(17)
    hidden, memory = torch.randn(2, 4, 8), torch.randn(2, 3, 8)
    memory[:, 0] = 0  # always-admitted null slot; no item-dependent features
    return hidden, memory, torch.tensor([[True,False,True],[True,False,False]])


def activate(module):
    with torch.no_grad():
        module.output.weight.normal_(0, 0.2)
        module.output.bias.fill_(0.3)


def test_zero_output_initialization_is_exact_identity():
    hidden, memory, eligible = inputs()
    bridge = EvidenceCrossAttention(8, 2)
    assert torch.equal(bridge(hidden, memory, eligible), hidden)
    assert torch.equal(bridge(hidden, memory[:, :1], eligible[:, :1]), hidden)


def test_ineligible_slots_and_extra_padding_cannot_change_outputs():
    hidden, memory, eligible = inputs()
    bridge = EvidenceCrossAttention(8, 2); activate(bridge)
    expected = bridge(hidden, memory, eligible)
    changed = memory.clone(); changed[~eligible] = 100000.0
    assert torch.allclose(bridge(hidden, changed, eligible), expected, atol=1e-6, rtol=1e-6)
    padded = torch.cat((memory, torch.randn(2, 5, 8)), dim=1)
    mask = torch.cat((eligible, torch.zeros(2, 5, dtype=torch.bool)), dim=1)
    assert torch.allclose(bridge(hidden, padded, mask), expected, atol=1e-6, rtol=1e-6)
    null_only = bridge(hidden, memory[:, :1], eligible[:, :1])
    assert torch.allclose(expected[1], null_only[1], atol=1e-6, rtol=1e-6)
    assert not torch.equal(null_only[1], hidden[1])  # trained null-memory capacity control
    altered = memory.clone(); altered[0, 2] += 3
    assert not torch.allclose(bridge(hidden, altered, eligible)[0], expected[0])


def test_queries_do_not_mix_future_hidden_positions():
    hidden, memory, eligible = inputs()
    bridge = EvidenceCrossAttention(8, 2); activate(bridge)
    expected = bridge(hidden, memory, eligible)
    future_changed = hidden.clone(); future_changed[:, 2:] += 100
    observed = bridge(future_changed, memory, eligible)
    assert torch.equal(observed[:, :2], expected[:, :2])


def test_initial_output_gradient_then_upstream_gradients_are_finite_and_nonzero():
    hidden, memory, eligible = inputs()
    bridge = EvidenceCrossAttention(8, 2)
    loss = bridge(hidden, memory, eligible)[0].square().mean()
    loss.backward()
    assert torch.isfinite(bridge.output.weight.grad).all()
    assert torch.count_nonzero(bridge.output.weight.grad) > 0
    with torch.no_grad():
        bridge.output.weight.add_(bridge.output.weight.grad, alpha=-0.1)
    bridge.zero_grad(set_to_none=True)
    bridge(hidden, memory, eligible)[0].square().mean().backward()
    for parameter in (bridge.query.weight, bridge.key_value.weight):
        assert parameter.grad is not None and torch.isfinite(parameter.grad).all()
        assert torch.count_nonzero(parameter.grad) > 0


def test_frozen_reference_survives_policy_update_and_exception_safe_selection():
    hidden, memory, eligible = inputs()
    bridge = PolicyReferenceEvidenceAttention(8, 2)
    original = {k:v.clone() for k,v in bridge._reference.state_dict().items()}
    activate(bridge.policy)
    policy = bridge(hidden, memory, eligible)
    assert not torch.equal(policy[0], hidden[0])
    bridge.train()
    assert bridge.policy.training and not bridge._reference.training
    assert all(not p.requires_grad for p in bridge._reference.parameters())
    assert set(map(id,bridge.trainable_parameters())).isdisjoint(map(id,bridge._reference.parameters()))
    with pytest.raises(RuntimeError, match='synthetic'):
        with bridge.reference_mode():
            assert torch.equal(bridge(hidden, memory, eligible), hidden)
            assert not bridge(hidden, memory, eligible).requires_grad
            with bridge.reference_mode():
                assert torch.equal(bridge(hidden, memory, eligible), hidden)
            raise RuntimeError('synthetic failure')
    assert torch.equal(bridge(hidden, memory, eligible), policy)
    assert bridge(hidden, memory, eligible).requires_grad
    for key,value in bridge._reference.state_dict().items():
        assert torch.equal(value, original[key])


def test_reference_and_policy_are_restored_as_distinct_states():
    hidden, memory, eligible = inputs()
    bridge = PolicyReferenceEvidenceAttention(8, 2); activate(bridge.policy)
    restored = PolicyReferenceEvidenceAttention(8, 2)
    restored.load_state_dict(bridge.state_dict())
    assert torch.equal(restored(hidden, memory, eligible), bridge(hidden, memory, eligible))
    with restored.reference_mode():assert torch.equal(restored(hidden, memory, eligible), hidden)
    assert all(not p.requires_grad for p in restored._reference.parameters())


def test_shapes_masks_and_nonfinite_padding_fail_closed():
    hidden, memory, eligible = inputs()
    bridge = EvidenceCrossAttention(8, 2)
    with pytest.raises(ValueError, match='divisible'):EvidenceCrossAttention(8, 3)
    with pytest.raises(ValueError, match='positive integers'):EvidenceCrossAttention(True, 1)
    with pytest.raises(ValueError, match='Boolean'):bridge(hidden, memory, eligible.float())
    with pytest.raises(ValueError, match='Boolean'):bridge(hidden, memory, eligible[:, :1])
    with pytest.raises(ValueError, match='memory must'):bridge(hidden, memory[:, :, :5], eligible)
    with pytest.raises(ValueError, match='admitted null'):bridge(hidden, memory, torch.zeros_like(eligible))
    with pytest.raises(ValueError, match='admitted null'):bridge(hidden, memory[:, :0], eligible[:, :0])
    with pytest.raises(ValueError, match='floating dtype'):bridge(hidden, memory.double(), eligible)
    bad = memory.clone(); bad[0, 1, 0] = float('nan')
    with pytest.raises(ValueError, match='including masked padding'):bridge(hidden, bad, eligible)
