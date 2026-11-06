"""T-LADDER adapter: the IH-LM modules behind the loop runner's backend contract (docs/20261030_IHLM_LADDER_PREREG.md).
Contract (same as loop_retro/loop_models.py): state = B.init_state(); state = B.fit(state, idx, z, steps, seed); scores = B.predict(state, idx). fit never mutates its input state.
Own code only. The neural analog attention (M3) and neural edit residual (M4) are DISABLED (xfail upstream): retrieval and edit effects enter through the symbolic memory only."""
import os, sys, copy
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
IH = os.path.join(HERE, "..", "ihlm"); sys.path.insert(0, IH); sys.path.insert(0, os.path.join(HERE, "..", "v4_eval")); sys.path.insert(0, os.path.join(HERE, "..", "loop_retro"))
import model as IM
from ladder_core import causal_labels      # noqa: F401  (re-exported: adapter.causal_labels is the pre-registered name)

RUNGS = {"R0": (), "R1": ("M1",), "R2": ("M1", "M2"), "R3": ("M1", "M2", "M3"), "R4": ("M1", "M2", "M3", "M4")}
CFG = dict(backbone_cfg=dict(d=64, layers=2, heads=4, max_len=256, kind="encoder"), tokenizer_cfg=dict(max_len=256), n0=100.0, k=5, slow_every=1, alpha=0.2, eta=1.0)      # fixed in the pre-registration (section 3)


class LadderIHLM(IM.IHLM):
    """IHLM with the neural M3 analog attention / M4 neural residual switched off: the net is built WITHOUT M3/M4 and never receives an analog pack."""
    def _ensure_net(self):
        if self.net is None:
            import torch
            torch.manual_seed(self.seed); self.net = IM.Net(len(self.tok), self.backbone_cfg, tuple(m for m in self.modules if m not in ("M3", "M4")), self.n_verif)
            self.meter.n_params = sum(p.numel() for p in self.net.parameters())
    def _pack(self, queries, targets, exclude_self): return None


class LState:
    """immutable-by-convention wrapper: the model plus the set of dataset indices already written to its memory."""
    def __init__(self, model, written): self.model, self.written = model, written


class IHLMBackend:
    name = "ihlm"
    def __init__(self, rung, smiles, srcs, K, seed=0, cfg=None):
        self.rung, self.modules, self.smiles, self.srcs = rung, RUNGS[rung], list(smiles), list(srcs); self.cfg = dict(CFG, **(cfg or {})); self.seed = int(seed)
        self.K = None if K is None else {s: float(v) for s, v in zip(self.smiles, K)}
    def init_state(self):
        knowledge = (lambda sm: [self.K.get(s) for s in sm]) if (self.K is not None and "M1" in self.modules) else None
        m = LadderIHLM(modules=self.modules, knowledge=knowledge, seed=self.seed, **self.cfg); m.tok.fit(self.smiles)       # open vocabulary fixed from the (label-free) SMILES so the net never meets an unseen id
        return LState(m, frozenset())
    def fit(self, state, idx, y, steps, seed):
        idx = [int(i) for i in idx]; y = np.asarray(y, float); assert len(idx) == len(y), f"IHLMBackend.fit: {len(idx)} indices but {len(y)} labels"
        new = [(i, v) for i, v in zip(idx, y) if i not in state.written]
        if not new: return LState(state.model.clone(), state.written)
        rows = [dict(smiles=self.smiles[i], target_seq=None, label=float(v), source=self.srcs[i]) for i, v in new]
        m = state.model.update(rows, mode="finetune_ranking", seed=int(seed), steps=int(steps))
        return LState(m, state.written | frozenset(i for i, _ in new))
    def predict(self, state, idx):
        idx = [int(i) for i in idx]; sc = state.model.score([self.smiles[i] for i in idx], sources=[self.srcs[i] for i in idx])
        return np.array([0.0 if v is None else v for v in sc], float)
    def cost_info(self, state=None):
        return state.model.cost() if state is not None else None
