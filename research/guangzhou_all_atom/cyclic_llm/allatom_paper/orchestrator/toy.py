"""Toy peptide environment for the I-A smoke tests (a PLANTED-OPTIMUM oracle and a learnable stand-in generator).

Purpose: exercise the orchestrator, checkpoints, logging, preference updates and controls end to end with a task whose optimum
is known, before any real model is involved. A 'molecule' is an acetyl-capped linear chain of residues from {G, A, M, F} (Gly,
Ala, Sar = N-methyl-Gly, Phe) written as SMILES; the planted score depends only on residue COUNTS (so it is invariant to RDKit
canonicalisation): score = max(0, 1 - (|nF-tF| + |nM-tM| + |nA-tA|) / L). The optimum 1.0 is reachable. This is a harness
correctness test, not evidence about peptides."""
from __future__ import annotations

import hashlib
import json
import math
import os
import random
import sys
from copy import deepcopy
from typing import Dict, List, Optional, Sequence, Tuple

_HERE = os.path.dirname(os.path.abspath(__file__))
_PARENT = os.path.dirname(_HERE)
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

from contracts import PreferencePair, PromptContext  # noqa: E402
from pmo_harness import Verifier  # noqa: E402

RES = {"G": "NCC(=O)", "A": "NC(C)C(=O)", "M": "N(C)CC(=O)", "F": "NC(Cc1ccccc1)C(=O)"}
TYPES = ["G", "A", "M", "F"]
CAP = "CC(=O)"


def seq_to_smiles(seq: Sequence[str]) -> str:
    return CAP + "".join(RES[c] for c in seq) + "O"


_PATT = {}


def composition(smiles: str) -> Dict[str, int]:
    from rdkit import Chem
    if not _PATT:
        _PATT["M"] = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])")
        _PATT["A"] = Chem.MolFromSmarts("[CH3][CX4H1]([NX3])[CX3](=O)")
    m = Chem.MolFromSmiles(smiles)
    if m is None:
        return {"F": 0, "M": 0, "A": 0}
    return {"F": len(m.GetRingInfo().AtomRings()), "M": len(m.GetSubstructMatches(_PATT["M"])), "A": len(m.GetSubstructMatches(_PATT["A"]))}


def planted_verifier(target: Tuple[int, int, int] = (3, 3, 2), L: int = 10, name: str = "planted") -> Verifier:
    tF, tM, tA = target

    def fn(s: str) -> float:
        c = composition(s)
        dev = abs(c["F"] - tF) + abs(c["M"] - tM) + abs(c["A"] - tA)
        return max(0.0, 1.0 - dev / float(L))
    return Verifier(name=name, fn=fn, role="train", cost=1.0)


def planted_stop_verifier(target: Tuple[int, int, int] = (3, 3, 2), L: int = 10, name: str = "planted_stop") -> Verifier:
    """A STOP verifier correlated with the train score on honest molecules (same composition target) but a different function:
    uses only the F and M counts."""
    tF, tM, _ = target

    def fn(s: str) -> float:
        c = composition(s)
        return max(0.0, 1.0 - (abs(c["F"] - tF) + abs(c["M"] - tM)) / float(L))
    return Verifier(name=name, fn=fn, role="stop", cost=1.0, trained_on=frozenset({"stop_group"}))


def optimum_smiles(target: Tuple[int, int, int] = (3, 3, 2), L: int = 10) -> str:
    tF, tM, tA = target
    seq = ["F"] * tF + ["M"] * tM + ["A"] * tA
    seq += ["G"] * (L - len(seq))
    return seq_to_smiles(seq)


def random_sampler(L: int = 10):
    def s(rng: random.Random) -> str:
        return seq_to_smiles([rng.choice(TYPES) for _ in range(L)])
    return s


# ------------------------------------------------------------------------------------------------ generator (Generator protocol)
def _softmax(v: Sequence[float], t: float) -> List[float]:
    m = max(x / t for x in v)
    e = [math.exp(x / t - m) for x in v]
    z = sum(e)
    return [x / z for x in e]


class ToyGenerator:
    """Independent categorical policy per position (learnable); stands in for ChemFM + LoRA in the smoke test."""

    def __init__(self, L: int = 10):
        self.L = L
        self.logits = [[0.0] * len(TYPES) for _ in range(L)]
        self.seq_of: Dict[str, List[str]] = {}

    def sample(self, n: int, ctx: PromptContext, temperature: float, seed: int, constraint=None) -> List[str]:
        rng = random.Random(seed)
        out = []
        for _ in range(n):
            for _attempt in range(10):
                seq = [rng.choices(TYPES, weights=_softmax(self.logits[p], temperature))[0] for p in range(self.L)]
                smi = seq_to_smiles(seq)
                if constraint is None or constraint.check(smi):
                    break
            self.seq_of[smi] = seq
            out.append(smi)
        return out

    def logprobs(self, smiles_list: Sequence[str], ctx: PromptContext) -> List[float]:
        out = []
        for s in smiles_list:
            seq = self.seq_of.get(s)
            if seq is None:
                out.append(float("-inf"))
                continue
            lp = 0.0
            for p, c in enumerate(seq):
                lp += math.log(_softmax(self.logits[p], 1.0)[TYPES.index(c)])
            out.append(lp)
        return out

    def lora_state(self) -> bytes:
        return json.dumps(self.logits).encode()

    def load_lora(self, path: str) -> None:
        self.logits = json.loads(open(path, "rb").read().decode())

    def kl_to_reference(self, smiles_list: Sequence[str], ctx: PromptContext) -> float:
        lps = [x for x in self.logprobs(smiles_list, ctx) if x != float("-inf")]
        if not lps:
            return 0.0
        ref = -self.L * math.log(len(TYPES))
        return float(sum(lps) / len(lps) - ref)


# ------------------------------------------------------------------------------------------------ preference updater
class ToyPairUpdater:
    """PreferenceUpdater stand-in: rank-ordered pairs (top third vs bottom third of each group) and a DPO-style logistic step on
    the toy policy's logits. Reports the fraction of zero-variance groups (the failure mode of the earlier GRPO attempt)."""

    def __init__(self, generator: ToyGenerator):
        self.g = generator

    def make_pairs(self, samples, scores, margin, group_by=None):
        valid = [(s, float(sc), (group_by[i] if group_by is not None else "g0")) for i, (s, sc) in enumerate(zip(samples, scores)) if sc is not None]
        groups: Dict[str, list] = {}
        for s, sc, gid in valid:
            groups.setdefault(gid, []).append((s, sc))
        pairs, zero_var, kept, margins = [], 0, 0, []
        for gid, items in groups.items():
            sc = [x[1] for x in items]
            if len(items) < 3 or max(sc) - min(sc) < 1e-12:
                zero_var += 1
                continue
            kept += 1
            items = sorted(items, key=lambda x: -x[1])
            k = max(1, len(items) // 3)
            for (cs, cv), (rs, rv) in zip(items[:k], reversed(items[-k:])):
                if cv - rv >= max(margin, 1e-12):
                    pairs.append(PreferencePair(chosen=cs, rejected=rs, margin=cv - rv, group=gid))
                    margins.append(cv - rv)
        diag = {"frac_zero_variance_groups": (zero_var / len(groups)) if groups else 1.0, "n_pairs": float(len(pairs)),
                "mean_margin": (sum(margins) / len(margins)) if margins else 0.0, "n_groups_kept": float(kept)}
        return pairs, diag

    def step(self, pairs, lr, beta):
        before = deepcopy(self.g.logits)
        losses = []
        for p in pairs:
            sc, sr = self.g.seq_of.get(p.chosen), self.g.seq_of.get(p.rejected)
            if sc is None or sr is None:
                continue
            lpc = self.g.logprobs([p.chosen], PromptContext())[0]
            lpr = self.g.logprobs([p.rejected], PromptContext())[0]
            d = beta * (lpc - lpr)
            sig = 1.0 / (1.0 + math.exp(-d))
            losses.append(-math.log(max(sig, 1e-12)))
            w = beta * (1.0 - sig)
            for pos in range(self.g.L):
                if sc[pos] != sr[pos]:
                    self.g.logits[pos][TYPES.index(sc[pos])] += lr * w
                    self.g.logits[pos][TYPES.index(sr[pos])] -= lr * w
        flat_a = [x for row in self.g.logits for x in row]
        flat_b = [x for row in before for x in row]
        delta = math.sqrt(sum((a - b) ** 2 for a, b in zip(flat_a, flat_b)))
        norm = math.sqrt(sum(a * a for a in flat_a))
        kl = self.g.kl_to_reference([p.chosen for p in pairs], PromptContext())
        return {"loss": (sum(losses) / len(losses)) if losses else 0.0, "kl": kl, "weight_delta_rel": delta / (norm + 1e-9)}


# ------------------------------------------------------------------------------------------------ retriever (Retriever protocol)
class ScoreTopKRetriever:
    """Toy retriever: returns the k best-scored stored rows (no similarity). The real stereo-aware retriever is workstream I-B."""

    def __init__(self):
        self.rows: Dict[str, Dict[str, float]] = {}

    def build(self, rows):
        for r in rows:
            self.add(r["smiles"], r.get("scores", {}))

    def add(self, smiles, scores, doc=None, source=None):
        self.rows[smiles] = dict(scores)

    def query(self, smiles, k, exclude_docs=None):
        items = sorted(self.rows.items(), key=lambda kv: -(next(iter(kv[1].values())) if kv[1] else 0.0))
        return [(s, sc) for s, sc in items[:k]]
