"""Synthetic restore-validation contracts; remote CPU QA only."""
import pytest
import torch
from hybrid.verify_restore import assert_equal, validate_state


def state():
    return dict(adapter={'a':torch.tensor([1.])},
                optimizer={'state':{0:{'step':torch.tensor(1.),'exp_avg':torch.tensor([0.])}}},
                steps=1,extra_state={},rng_cpu=torch.tensor([1],dtype=torch.uint8),
                rng_cuda=[],knowledge_config=None,sampling_config={})


def test_finite_updated_checkpoint():
    assert validate_state(state()) == [1.]


def test_empty_update_or_nonfinite_fails():
    s=state();s['steps']=0
    with pytest.raises(ValueError,match='no completed'):
        validate_state(s)
    s=state();s['adapter']['a'][0]=float('nan')
    with pytest.raises(ValueError,match='nonfinite'):
        validate_state(s)


def test_optimizer_step_mismatch_fails():
    s=state();s['steps']=2
    with pytest.raises(ValueError,match='disagrees'):
        validate_state(s)


def test_restore_checks_values_keys_and_dtype():
    assert_equal(state(),state())
    s=state();s['adapter']['a']=s['adapter']['a'].double()
    with pytest.raises(ValueError,match='tensor mismatch'):
        assert_equal(state(),s)
    s=state();s['extra_state']['lost']=True
    with pytest.raises(ValueError,match='keys mismatch'):
        assert_equal(state(),s)
