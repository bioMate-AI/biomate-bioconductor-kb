"""IH-LM: the in-house hybrid, loop-native cyclic LLM layers, composed around ANY base that implements the LoopModel contract
(score(smiles, target_seq)->list[float|None], update(labelled, mode, seed, **kw)->new base, fingerprint(), cost()).  Base = PeptideCLM-2 (if cleared, reviewed re-implementation)
or the 25.5 M atom LM from its checkpoint (AtomLoopModel) or the v4 LoopModel.  NO from-scratch ChEMBL pretraining.

Layers (each is switchable, so workstream 2 can run the ablation ladder; every layer has a planted-signal and a leave-labs-out control in test_ihlm.py):
  L1 knowledge prior/fusion  K(x) (kb_audit K_phys channel, any callable smiles->float) fused with the base by the conjugate/shrinkage weight w = n0/(n0+n):  score = (1-w) z(base) + w z(K)
  L2 lab/source offset       y_ij = m_i + b_s + e   (hierarchical random effect; ridge-shrunk b_s estimated from ANCHOR compounds measured in >= 2 sources; unseen lab -> b = 0)
  L3 analog retrieval        k nearest revealed analogs by chirality-aware Morgan-count Tanimoto; neighbours' offset-corrected labels (+ edit transfer) -> retrieval estimate mixed by similarity
  L4 edit-space head         edit(analog -> query) in {nme_add, nme_remove, dflip, other}; effect = conjugate shrinkage of the revealed pairs' mean towards the literature prior
                             (N-Me added +0.25 log Papp; D flip 0 = 'no consistent direction', docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md B4)
  L5 calibrated uncertainty  split-conformal interval around a calibrated label prediction, widened by distance to the nearest revealed analog; UCB acquisition
  L6 update interface        FAST symbolic memory (written immediately: revealed table, offsets, edit effects, K calibration) + SLOW neural memory (base.update every `slow_every` rounds)
Labels are higher-better in the units of the revealed labels; scores for ranking are unit-free."""
import os, sys, copy, hashlib, json, time
import numpy as np
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import rdFingerprintGenerator
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from loop_model import CostMeter

EDIT_PRIORS = {"nme_add": (0.25, 20.0), "nme_remove": (-0.25, 20.0), "dflip": (0.0, 20.0), "other": (0.0, 20.0)}   # (prior mean in label units, prior pseudo-count)
_GEN = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
_GEN_BLIND = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=False)
NME = Chem.MolFromSmarts("[CX3](=O)[NX3;!H1]([CH3])")


def _mol(s): return Chem.MolFromSmiles(s) if isinstance(s, str) else None
def _iso(s): m = _mol(s); return Chem.MolToSmiles(m, isomericSmiles=True) if m is not None else None
def _flat(m): return Chem.MolToSmiles(m, isomericSmiles=False)
def _z(v):
    v = np.asarray(v, float); sd = v.std(); return (v - v.mean()) / (sd if sd > 0 else 1.0)


def fingerprint(smiles, chiral=True):
    m = _mol(smiles); return (_GEN if chiral else _GEN_BLIND).GetCountFingerprint(m) if m is not None else None


def tanimoto_count(a, b): return DataStructs.TanimotoSimilarity(a, b)


def n_nme(m): return len(m.GetSubstructMatches(NME))


def _cip(m):
    return {i: c for i, c in Chem.FindMolChiralCenters(m, includeUnassigned=True, useLegacyImplementation=False)}


def edit_type(query_smiles, analog_smiles):
    """edit that turns ANALOG into QUERY -> 'identical' | 'nme_add' | 'nme_remove' | 'dflip' | 'other' (None if unparsable)."""
    q, a = _mol(query_smiles), _mol(analog_smiles)
    if q is None or a is None: return None
    fq, fa = _flat(q), _flat(a)
    if Chem.MolToSmiles(q) == Chem.MolToSmiles(a): return "identical"
    if fq == fa:   # same constitution, different stereo: count centres whose CIP label differs
        cq, ca = _cip(q), _cip(a); m = q.GetSubstructMatch(Chem.MolFromSmiles(fa))
        if m and len(m) == a.GetNumAtoms():
            ca_in_q = {m[i]: lab for i, lab in ca.items() if i < len(m)}; diff = sum(1 for i, lab in ca_in_q.items() if cq.get(i) != lab)
            return "dflip" if diff == 1 else "other"
        return "dflip" if len(set(cq.values())) else "other"
    dn = n_nme(q) - n_nme(a)
    if abs(dn) == 1:
        big, small, kind = (q, a, "nme_add") if dn == 1 else (a, q, "nme_remove"); target = Chem.MolToSmiles(small)
        for match in big.GetSubstructMatches(NME):
            rw = Chem.RWMol(big); rw.RemoveAtom(match[3])        # drop the N-methyl carbon
            try: Chem.SanitizeMol(rw)
            except Exception: continue
            if Chem.MolToSmiles(rw) == target or _flat(rw) == _flat(small) and Chem.MolToSmiles(Chem.RemoveHs(rw)) == target: return kind
        return "other"
    return "other"


class IHLM:
    def __init__(self, base, knowledge=None, n0=100.0, k=5, slow_every=3, lam_offset=3.0, alpha=0.2, eta=1.0, edit_priors=None, layers=("K", "offset", "retrieval", "edit"), seed=0, _state=None):
        self.base, self.knowledge, self.n0, self.k, self.slow_every, self.lam, self.alpha, self.eta = base, knowledge, float(n0), int(k), int(slow_every), float(lam_offset), float(alpha), float(eta)
        self.edit_priors = dict(edit_priors or EDIT_PRIORS); self.layers = tuple(layers); self.seed = seed; self.meter = CostMeter(0)
        self.state = _state or dict(rows=[], offsets={}, edit_eff={k: v[0] for k, v in self.edit_priors.items()}, edit_n={k: 0 for k in self.edit_priors}, rounds=0, slow_rounds=0, calib=None, fast_seconds=0.0)

    # ------------------------------------------------------------------ L2 offsets
    @staticmethod
    def estimate_offsets(rows, lam=3.0, iters=50):
        """rows with keys smiles(iso canonical), source, label. Additive model y = m_i + b_s; anchors = compounds with >= 2 sources. Ridge-shrunk b_s, gauge: mean b over anchor rows = 0."""
        by = {}
        for r in rows: by.setdefault(r["smiles"], []).append(r)
        anchors = {s: v for s, v in by.items() if len({x["source"] for x in v}) >= 2}
        if not anchors: return {}
        srcs = sorted({x["source"] for v in anchors.values() for x in v}); b = {s: 0.0 for s in srcs}
        for _ in range(iters):
            m = {s: np.mean([x["label"] - b[x["source"]] for x in v]) for s, v in anchors.items()}
            for s in srcs:
                res = [x["label"] - m[sm] for sm, v in anchors.items() for x in v if x["source"] == s]; b[s] = float(np.sum(res) / (len(res) + lam))
            mu = np.mean([b[x["source"]] for v in anchors.values() for x in v]); b = {s: v - mu for s, v in b.items()}
        return b

    def _corrected(self, r): return r["label"] - (self.state["offsets"].get(r.get("source"), 0.0) if "offset" in self.layers else 0.0)

    # ------------------------------------------------------------------ scoring
    def _nbrs(self, smiles, target, exclude_self=True):
        fp = fingerprint(smiles); out = []
        if fp is None: return out
        iso = _iso(smiles)
        for r in self.state["rows"]:
            if r["target_seq"] != target or (exclude_self and r["smiles"] == iso): continue
            out.append((tanimoto_count(fp, r["fp"]), r))
        out.sort(key=lambda x: -x[0]); return out[:self.k]

    def _edit_delta(self, query, analog):
        et = edit_type(query, analog); return (et, self.state["edit_eff"].get(et, 0.0)) if et not in (None, "identical") else (et, 0.0)

    def retrieval_estimate(self, smiles, target):
        """-> (estimate in offset-corrected label units or None, max similarity). Neighbours' labels moved to the query by the edit effect (L4) when enabled."""
        nb = self._nbrs(smiles, target)
        if not nb: return None, 0.0
        vals, ws = [], []
        for sim, r in nb:
            d = self._edit_delta(smiles, r["smiles"])[1] if "edit" in self.layers else 0.0
            vals.append(self._corrected(r) + d); ws.append(max(sim, 1e-6) ** 4)
        return float(np.average(vals, weights=ws)), float(nb[0][0])

    def score(self, smiles, target_seq=None):
        """ranking score (higher better); None if neither base nor memory can score."""
        t0 = time.time(); bs = self.base.score(smiles, target_seq) if self.base is not None else [None] * len(smiles)
        n = len(self.state["rows"]); out = [None] * len(smiles); idx = [i for i, b in enumerate(bs) if b is not None]
        comp = np.zeros(len(smiles)); have = np.zeros(len(smiles), bool)
        if idx:
            z = _z([bs[i] for i in idx]); comp[idx] = z; have[idx] = True
        K = None
        if "K" in self.layers and self.knowledge is not None:
            kv = [self.knowledge(s) for s in smiles]; ok = [i for i, v in enumerate(kv) if v is not None]
            if ok:
                w = self.n0 / (self.n0 + n); zk = _z([kv[i] for i in ok]); K = np.zeros(len(smiles)); K[ok] = zk
                comp = (1 - w) * comp + w * K; have |= np.isin(np.arange(len(smiles)), ok)
        if "retrieval" in self.layers and self.state["rows"]:
            est = [self.retrieval_estimate(s, target_seq) for s in smiles]; ok = [i for i, (e, _) in enumerate(est) if e is not None]
            if ok:
                zr = _z([est[i][0] for i in ok]); smax = np.array([est[i][1] for i in ok]); r = np.zeros(len(smiles)); r[ok] = zr
                rho = np.zeros(len(smiles)); rho[ok] = smax
                comp = comp + rho * r; have |= np.isin(np.arange(len(smiles)), ok)
        for i in range(len(smiles)):
            if have[i]: out[i] = float(comp[i])
        self.state["fast_seconds"] += time.time() - t0; return out

    # ------------------------------------------------------------------ L5 calibrated prediction + acquisition
    def _fit_calibration(self):
        rows = self.state["rows"]
        if len(rows) < 12: self.state["calib"] = None; return
        h = [int(hashlib.sha256((self.seed.__str__() + r["smiles"] + str(r["source"])).encode()).hexdigest(), 16) % 2 for r in rows]
        fit = [r for r, hh in zip(rows, h) if hh == 0]; cal = [r for r, hh in zip(rows, h) if hh == 1]
        if len(fit) < 6 or len(cal) < 6: self.state["calib"] = None; return
        sc = lambda rs: [(x if x is not None else 0.0) for x in self._score_rows(rs, exclude=True)]
        sf, yf = np.array(sc(fit)), np.array([self._corrected(r) for r in fit]); c = np.cov(sf, yf)[0, 1] / (sf.var() + 1e-9) if sf.std() > 0 else 0.0
        a = float(yf.mean() - c * sf.mean()); sc_cal = np.array(sc(cal)); res = np.array([abs(self._corrected(r) - (a + c * s)) for r, s in zip(cal, sc_cal)])
        smax = np.array([self.retrieval_estimate(r["smiles"], r["target_seq"])[1] for r in cal]); nres = res / (1.0 + self.eta * (1 - smax))
        q = float(np.quantile(nres, min(1.0, np.ceil((len(nres) + 1) * (1 - self.alpha)) / len(nres))))
        self.state["calib"] = dict(a=a, c=float(c), q=q)

    def _score_rows(self, rows, exclude=True):
        out = []
        for r in rows:
            # score a revealed row WITHOUT itself in memory (leave-one-out) so calibration residuals are honest
            keep = [x for x in self.state["rows"] if x is not r]; saved = self.state["rows"]; self.state["rows"] = keep
            try: out.append(self.score([r["smiles"]], r["target_seq"])[0])
            finally: self.state["rows"] = saved
        return out

    def predict(self, smiles, target_seq=None, source=None):
        """-> list of dict(mean, lo, hi, std_proxy) in LABEL units for `source` (offset added); None entries when unscorable. Split-conformal (1-alpha) interval."""
        c = self.state["calib"]; sc = self.score(smiles, target_seq); b = self.state["offsets"].get(source, 0.0) if "offset" in self.layers else 0.0; res = []
        for s, x in zip(smiles, sc):
            if x is None or c is None: res.append(None); continue
            mean = c["a"] + c["c"] * x + b; smax = self.retrieval_estimate(s, target_seq)[1]; hw = c["q"] * (1.0 + self.eta * (1 - smax))
            res.append(dict(mean=float(mean), lo=float(mean - hw), hi=float(mean + hw), half_width=float(hw)))
        return res

    def acquire(self, smiles, target_seq=None, kappa=1.0, source=None):
        """UCB acquisition scores (mean + kappa * half_width); unscorable -> -inf."""
        p = self.predict(smiles, target_seq, source); return [(-np.inf if x is None else x["mean"] + kappa * x["half_width"]) for x in p]

    # ------------------------------------------------------------------ L6 update: fast symbolic memory + slow neural memory
    def update(self, labelled, mode="finetune_ranking", seed=0, **kw):
        """labelled: [{smiles, target_seq, label, source?}] (higher label = better). Returns a NEW IHLM. frozen: no change at all."""
        new = IHLM(self.base, self.knowledge, self.n0, self.k, self.slow_every, self.lam, self.alpha, self.eta, self.edit_priors, self.layers, self.seed, _state=copy.deepcopy(self.state))
        new.meter = copy.deepcopy(self.meter)
        if mode == "frozen": return new
        t0 = time.time(); S = new.state
        for r in labelled:
            iso = _iso(r["smiles"]); fp = fingerprint(r["smiles"])
            if iso is None or fp is None: continue
            S["rows"].append(dict(smiles=iso, fp=fp, target_seq=r["target_seq"], label=float(r["label"]), source=r.get("source")))
        S["rounds"] += 1
        if "offset" in new.layers: S["offsets"] = IHLM.estimate_offsets(S["rows"], new.lam)
        if "edit" in new.layers: new._fit_edit_effects()
        new._fit_calibration(); S["fast_seconds"] += time.time() - t0
        S["slow_rounds"] += 1
        if new.base is not None and (S["slow_rounds"] >= new.slow_every or mode == "one_shot_matched"):
            new.base = new.base.update([dict(smiles=r["smiles"], target_seq=r["target_seq"], label=new._corrected(r)) for r in S["rows"]], mode=mode, seed=seed, **kw); S["slow_rounds"] = 0
        return new

    def _fit_edit_effects(self, per_row=12):
        """conjugate shrinkage per edit type: posterior mean = (n*mean_obs + n0e*prior)/(n + n0e) over revealed same-target analog pairs (offset-corrected,
        label difference query - analog). Pairs are the `per_row` nearest analogs of each revealed compound (chirality-aware similarity), so cost is O(n^2) similarity + O(n*per_row) edit checks."""
        rows = self.state["rows"]; obs = {k: [] for k in self.edit_priors}; seen = set()
        for i, ri in enumerate(rows):
            sims = [(tanimoto_count(ri["fp"], rj["fp"]), j) for j, rj in enumerate(rows) if j != i and rj["target_seq"] == ri["target_seq"]]
            for sim, j in sorted(sims, reverse=True)[:per_row]:
                if (i, j) in seen: continue
                seen.add((i, j)); et = edit_type(ri["smiles"], rows[j]["smiles"])
                if et in obs and et != "other": obs[et].append(self._corrected(ri) - self._corrected(rows[j]))
        for k, (p, n0e) in self.edit_priors.items():
            v = obs.get(k, []); n = len(v); self.state["edit_n"][k] = n
            self.state["edit_eff"][k] = float((n * (np.mean(v) if n else 0.0) + n0e * p) / (n + n0e))

    # ------------------------------------------------------------------ interface parity
    def fingerprint_id(self):
        h = hashlib.sha256(json.dumps([(r["smiles"], r["label"], r["source"]) for r in self.state["rows"]], default=str).encode()); h.update((self.base.fingerprint() if self.base is not None else "").encode())
        return h.hexdigest()[:16]

    def cost(self, usd_per_hour=None):
        b = self.base.cost(usd_per_hour) if self.base is not None else {}
        fast = round(self.state["fast_seconds"], 3); b = dict(b); b["ihlm_fast_memory_seconds"] = fast; b["ihlm_layers"] = list(self.layers); return b
