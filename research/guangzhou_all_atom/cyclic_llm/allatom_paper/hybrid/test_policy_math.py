"""Tiny deterministic distributions verify policy math; no checkpoint quality claim."""
from contextlib import contextmanager
from types import SimpleNamespace
import sys
from pathlib import Path
import numpy as np
import pytest
import torch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.model import ChemFMGenerator
from hybrid.sampling import sample_group


class TinyPolicy(torch.nn.Module):
    def __init__(self):
        super().__init__(); self.logits=torch.nn.Parameter(torch.tensor([0.,1.,2.]));self.disabled=False
    def forward(self,input_ids,**kwargs):
        v=torch.zeros_like(self.logits) if self.disabled else self.logits
        return SimpleNamespace(logits=v.expand(*input_ids.shape,3),past_key_values=None)
    @contextmanager
    def disable_adapter(self):
        self.disabled=True
        try:yield
        finally:self.disabled=False


class Constraint:
    eos=2
    def init_state(self,prompt):return []
    def mask(self,state):return np.array([True,True,True])
    def soft_logits(self,state):return np.array([.2,0.,-.1])
    def advance(self,state,token):state.append(token);return True


def generator():
    g=ChemFMGenerator.__new__(ChemFMGenerator)
    g.model=TinyPolicy();g.device='cpu';g.masked=True;g.con=Constraint();g.temperature=2.
    g.records={'molecule':([0],[1,2])}
    return g


def test_temperature_and_soft_potential_are_identical_in_sampling_and_logprob():
    g=generator(); observed=[]
    class RNG:
        def choice(self,n,p):observed.append(p);return 2
    stats={'mask_seconds':0.,'row_steps':0}
    sample_group(g.model,'cpu',g.con,[(0,[0])],2.,True,RNG(),stats,4)
    lp=g._token_logps('molecule')[0]
    assert np.allclose(observed[0],lp.exp().numpy(),atol=1e-7)
    expected=torch.log_softmax(g.model.logits/2+torch.tensor([.2,0.,-.1]),-1)
    assert float(g._logp('molecule'))==pytest.approx(float(expected[1]+expected[2]),abs=1e-6)


def test_categorical_kl_is_nonnegative_and_not_sampled_logratio():
    g=generator()
    pol=torch.log_softmax(g.model.logits/2+torch.tensor([.2,0.,-.1]),-1)
    ref=torch.log_softmax(torch.tensor([.2,0.,-.1]),-1)
    expected=float((pol.exp()*(pol-ref)).sum())
    assert g.kl_to_reference(['molecule'],None)==pytest.approx(expected,abs=1e-6)
    assert expected>0


def test_max_tokens_bounds_nonterminating_generation():
    g=generator()
    class RNG:
        def choice(self,n,p):return 1
    stats={'mask_seconds':0.,'row_steps':0}
    row=sample_group(g.model,'cpu',g.con,[(0,[0])],1.,True,RNG(),stats,3)[0]
    assert row[0]==[1,1] and row[1] is False and row[4]=='length_cap'
    assert len(row[0])+len(row[3])==3


def test_masked_dpo_logprob_has_finite_nonzero_gradient():
    g=generator();g._logp('molecule',True).backward()
    assert torch.isfinite(g.model.logits.grad).all()
    assert torch.count_nonzero(g.model.logits.grad)>0
