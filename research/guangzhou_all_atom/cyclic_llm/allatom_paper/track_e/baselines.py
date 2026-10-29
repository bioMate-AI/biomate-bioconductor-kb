"""Stage-0 baselines for the all-atom hybrid-LLM paper (Track E). Every optimiser has the signature opt(oracle, rng) -> None and is run by
pmo_harness.run_one under the SAME oracle-call budget; all share the hard-rule constraint filter (constraint failures are free but
counted, proposal cap 20 x budget). Nothing here is run on the laptop.
Methods: random_lib (floor), lib_surrogate (library enumeration + surrogate ranking), edit_ga (S-EDIT operators), selfies_ga,
gp_bo (Tanimoto-kernel GP Bayesian optimisation with UCB). The LM-based baselines (REINVENT-style RL on a causal LM, MolLEO-style
LM-as-operator) need the generator interface from Track I and are added at milestone M3, NOT here."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CL = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (os.path.join(CL, "generation_pilot"), os.path.join(CL, "ihlm"), os.path.join(CL, "ihlm_backbone"), CL, os.path.join(HERE, "..")):
    sys.path.insert(0, p)
import gen_pilot as GP  # noqa: E402  (satisfies, gen_lib, gen_edit, monomers, build_cyclic)
from pmo_harness import BudgetExhausted  # noqa: E402
from rdkit import Chem  # noqa: E402

import verifiers_e as VE  # noqa: E402


def constraint(c):
    """Hard-rule set C of pilot 3 (macrocycle ring >= 12, 2-6 N-methyl amides, MW 600-1400, TPSA <= 300, no PAINS) on a canonical SMILES."""
    m = Chem.MolFromSmiles(c)
    return bool(m is not None and GP.satisfies(m))


def build_seeds(d, groups, n=300, rng_seed=12345):
    """Seed peptides: rule-satisfying peptides from source group A (train sources); deterministic sample."""
    import random
    cand = sorted({s for s, g in zip(d["smiles"], d["Source"].map(groups)) if g == 0 and constraint(s)})
    return random.Random(rng_seed).sample(cand, min(n, len(cand)))


def _canon(s):
    return VE.canon(s)


def _call(oracle, s):
    try:
        return oracle(s)
    except BudgetExhausted:
        raise


# ------------------------------------------------------------------------------------------------ random_lib
def random_lib(cfg):
    def opt(oracle, rng):
        while True:
            for s in GP.gen_lib([], 50, rng, cfg):
                oracle(s)
    return opt


# ------------------------------------------------------------------------------------------------ lib_surrogate
def lib_surrogate(cfg_lib, pool_n=6000, init=100, batch=100, explore=0.1, seed_pool=None):
    from sklearn.ensemble import HistGradientBoostingRegressor

    def opt(oracle, rng):
        raw = GP.gen_lib([], pool_n, rng, cfg_lib)
        pool = []
        seen = set()
        for s in raw:
            c = _canon(s)
            if c and c not in seen and constraint(c):
                seen.add(c)
                pool.append(c)
        X = np.stack([VE.fp_counts(Chem.MolFromSmiles(c), 1024) for c in pool])
        ev_idx, ev_y = [], []
        order = list(range(len(pool)))
        rng.shuffle(order)
        todo = order[:init]
        done = set()
        while True:
            for i in todo:
                if i in done:
                    continue
                sc = oracle(pool[i])
                done.add(i)
                if sc is not None:
                    ev_idx.append(i)
                    ev_y.append(sc)
            rest = [i for i in range(len(pool)) if i not in done]
            if not rest:
                return
            m = HistGradientBoostingRegressor(max_iter=150, learning_rate=0.08, random_state=rng.randrange(1 << 30)).fit(X[ev_idx], ev_y)
            pred = m.predict(X[rest])
            k_exp = int(round(batch * explore))
            top = [rest[j] for j in np.argsort(-pred)[: batch - k_exp]]
            extra = rng.sample([i for i in rest if i not in set(top)], min(k_exp, max(0, len(rest) - len(top))))
            todo = top + extra
    return opt


# ------------------------------------------------------------------------------------------------ edit_ga
def edit_ga(cfg, seeds, n_init=100, n_parents=30, n_children=100, pop_cap=200, max_stall=20, k_max=6):
    """Edit-operator GA. Stall guard (fix, 2026-10-29, before any baseline number was read): if a full generation produces no NEW evaluated
    molecule (the single-edit neighbourhood of the parents is exhausted), the number of edits per child is escalated by one (up to k_max);
    after `max_stall` consecutive stalled generations the optimiser stops (BudgetExhausted-like), so a run can never spin forever on duplicates.
    Second fix (same day, still before any baseline number was read): a generation counts as 'stalled' when it yields fewer than 10% new molecules
    (n_children // 10), not only zero, because trickle yields (about one new molecule per generation) kept k=1 runs alive for over an hour."""
    def opt(oracle, rng):
        pop, known = [], set()
        for s in rng.sample(seeds, min(n_init, len(seeds))):
            sc = oracle(s)
            c = _canon(s)
            if sc is not None and c not in known:
                known.add(c)
                pop.append((sc, c))
        k, stall = cfg["k"], 0
        while True:
            pop.sort(key=lambda t: -t[0])
            pop = pop[:pop_cap]
            parents = [s for _, s in pop[:n_parents]] or seeds
            new_eval = 0
            for ch in GP.gen_edit(parents, n_children, rng, dict(k=k)):
                c = _canon(ch)
                if not c or c in known:
                    continue
                sc = oracle(ch)
                if sc is not None:
                    known.add(c)
                    pop.append((sc, c))
                    new_eval += 1
            if new_eval < max(1, n_children // 10):          # low yield (< 10% new molecules): the neighbourhood is nearly exhausted
                stall += 1
                k = min(k + 1, k_max)
                if stall >= max_stall:
                    raise BudgetExhausted("edit_ga stalled: low yield in %d consecutive generations" % max_stall)
            else:
                stall = 0
    return opt


# ------------------------------------------------------------------------------------------------ selfies_ga
def selfies_ga(cfg, seeds, n_init=100, n_parents=30, n_children=100, pop_cap=200):
    import selfies as sf

    def enc(s):
        try:
            return list(sf.split_selfies(sf.encoder(s)))
        except Exception:
            return None

    def dec(toks):
        try:
            return sf.decoder("".join(toks))
        except Exception:
            return None

    def opt(oracle, rng):
        alphabet = sorted({t for s in seeds for t in (enc(s) or [])})
        pop, known = [], set()
        for s in rng.sample(seeds, min(n_init, len(seeds))):
            sc = oracle(s)
            c = _canon(s)
            if sc is not None and c not in known:
                known.add(c)
                pop.append((sc, c))
        stall = 0
        while True:
            pop.sort(key=lambda t: -t[0])
            pop = pop[:pop_cap]
            parents = [s for _, s in pop[:n_parents]]
            made = 0
            guard = 0
            while made < n_children and guard < 50 * n_children:
                guard += 1
                a = enc(rng.choice(parents))
                if not a:
                    continue
                if rng.random() < cfg["p_cross"]:
                    b = enc(rng.choice(parents))
                    if not b:
                        continue
                    ia, ib = rng.randrange(1, len(a)), rng.randrange(1, len(b))
                    child = a[:ia] + b[ib:]
                else:
                    child = list(a)
                for _ in range(cfg["n_mut"]):
                    op = rng.random()
                    i = rng.randrange(len(child))
                    if op < 0.4:
                        child[i] = rng.choice(alphabet)
                    elif op < 0.7:
                        child.insert(i, rng.choice(alphabet))
                    elif len(child) > 8:
                        del child[i]
                sm = dec(child)
                c = _canon(sm) if sm else None
                if not c or c in known or not constraint(c):
                    continue
                sc = oracle(sm)
                made += 1
                if sc is not None:
                    known.add(c)
                    pop.append((sc, c))
            stall = stall + 1 if made == 0 else 0
            if stall >= 20:
                raise BudgetExhausted("selfies_ga stalled: no new molecules in 20 generations")
    return opt


# ------------------------------------------------------------------------------------------------ gp_bo
def gp_bo(cfg_lib, seeds, cfg_edit_k=2, pool_lib=3000, pool_edit=3000, init=50, batch=100, kappa=1.0, noise=0.1):
    from scipy.linalg import cho_factor, cho_solve

    def opt(oracle, rng):
        cand = []
        seen = set()
        for s in GP.gen_lib([], pool_lib, rng, cfg_lib) + GP.gen_edit(seeds, pool_edit, rng, dict(k=cfg_edit_k)):
            c = _canon(s)
            if c and c not in seen and constraint(c):
                seen.add(c)
                cand.append(c)
        Xc = np.stack([VE.fp_bits(Chem.MolFromSmiles(c), 2048) for c in cand]).astype(np.float32)
        idx = list(range(len(cand)))
        rng.shuffle(idx)
        done, ev_i, ev_y = set(), [], []
        todo = idx[:init]
        while True:
            for i in todo:
                if i in done:
                    continue
                sc = oracle(cand[i])
                done.add(i)
                if sc is not None:
                    ev_i.append(i)
                    ev_y.append(sc)
            rest = [i for i in idx if i not in done]
            if not rest:
                return
            Xe = Xc[ev_i]
            y = np.asarray(ev_y, np.float64)
            mu = y.mean()
            K = VE.TanimotoKRR.kern(Xe, Xe).astype(np.float64) + noise * np.eye(len(ev_i))
            cf = cho_factor(K, lower=True)
            alpha = cho_solve(cf, y - mu)
            Ks = VE.TanimotoKRR.kern(Xc[rest], Xe).astype(np.float64)
            mean = Ks @ alpha + mu
            v = cho_solve(cf, Ks.T)
            var = np.clip(1.0 - np.sum(Ks * v.T, axis=1), 1e-9, None)
            ucb = mean + kappa * np.sqrt(var)
            todo = [rest[j] for j in np.argsort(-ucb)[:batch]]
    return opt


# ------------------------------------------------------------------------------------------------ registry and grids
def registry(seeds):
    return {
        "random_lib": lambda cfg: random_lib(cfg),
        "lib_surrogate": lambda cfg: lib_surrogate(cfg),
        "edit_ga": lambda cfg: edit_ga(cfg, seeds),
        "selfies_ga": lambda cfg: selfies_ga(cfg, seeds),
        "gp_bo": lambda cfg: gp_bo(cfg, seeds),
    }


LIB_CFGS = [dict(len=ln, p_nme=a, p_d=b) for ln in ((5, 8), (6, 10)) for a in (0.4, 0.55) for b in (0.0, 0.15)]
GRIDS = {
    "random_lib": LIB_CFGS,
    "lib_surrogate": LIB_CFGS,
    "gp_bo": LIB_CFGS,
    "edit_ga": [dict(k=1), dict(k=2), dict(k=3)],
    "selfies_ga": [dict(p_cross=pc, n_mut=nm) for pc in (0.2, 0.5) for nm in (1, 2, 3)],
}
