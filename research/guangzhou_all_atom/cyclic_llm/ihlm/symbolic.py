"""IH-LM fast symbolic memory (closed-form; written immediately when graded results arrive). Own code (RDKit used for chemistry; no third-party modelling code).
Contents: M2 lab/assay offsets (hierarchical random effect, anchor-estimated, ridge-shrunk); M3 stereo-aware analog index (chirality-aware Morgan-count Tanimoto);
M4 edit detection + conjugate-shrinkage edit effects + edit proposals; M1 evidence weight n0/(n0+n).
Units: labels are higher-better in the units of the revealed labels; offsets and edit effects are in those units."""
import copy, hashlib, json
import numpy as np
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import rdFingerprintGenerator
RDLogger.DisableLog("rdApp.*")

EDIT_PRIORS = {"nme_add": (0.25, 20.0), "nme_remove": (-0.25, 20.0), "dflip_D": (0.0, 20.0), "dflip_L": (0.0, 20.0), "dflip": (0.0, 20.0), "other": (0.0, 20.0)}  # (prior mean, pseudo-count); docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md B4
_GEN = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
_GEN_BLIND = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=False)
NME = Chem.MolFromSmarts("[CX3](=O)[NX3;!H1]([CH3])")
NH_AMIDE = Chem.MolFromSmarts("[CX3](=O)[NX3;H1]")


def mol(s): return Chem.MolFromSmiles(s) if isinstance(s, str) else None
def iso(s): m = mol(s); return Chem.MolToSmiles(m, isomericSmiles=True) if m is not None else None
def flat(m): return Chem.MolToSmiles(m, isomericSmiles=False)
def fp_of(s, chiral=True):
    m = mol(s); return (_GEN if chiral else _GEN_BLIND).GetCountFingerprint(m) if m is not None else None
def tanimoto(a, b): return DataStructs.TanimotoSimilarity(a, b)
def n_nme(m): return len(m.GetSubstructMatches(NME))
def _cip(m): return {i: c for i, c in Chem.FindMolChiralCenters(m, includeUnassigned=True, useLegacyImplementation=False)}


def edit_type(query_smiles, analog_smiles):
    """edit that turns ANALOG into QUERY: identical | nme_add | nme_remove | dflip_D (analog L-like S centre -> query R) | dflip_L (R -> S) | dflip (direction unclear) | other | None. D-flip prior is 0 (no consistent direction, B4)."""
    q, a = mol(query_smiles), mol(analog_smiles)
    if q is None or a is None: return None
    if Chem.MolToSmiles(q) == Chem.MolToSmiles(a): return "identical"
    fq, fa = flat(q), flat(a)
    if fq == fa:
        # same constitution: map A's atoms onto Q's (A with stereo removed, SAME atom order as A), count stereocentres whose CIP label differs; min over symmetric matches
        af = Chem.Mol(a); Chem.RemoveStereochemistry(af); cq, ca = _cip(q), _cip(a); best = None; kind = "dflip"
        for m in q.GetSubstructMatches(af, uniquify=False, maxMatches=500, useChirality=False):
            diffs = [(i, lab) for i, lab in ca.items() if cq.get(m[i]) != lab]
            if best is None or len(diffs) < best:
                best = len(diffs)
                if best == 1:
                    i, lab = diffs[0]; qlab = cq.get(m[i]); kind = "dflip_D" if (lab == "S" and qlab == "R") else ("dflip_L" if (lab == "R" and qlab == "S") else "dflip")
            if best == 1: break
        return kind if best == 1 else "other"
    dn = n_nme(q) - n_nme(a)
    if abs(dn) == 1:
        big, small, kind = (q, a, "nme_add") if dn == 1 else (a, q, "nme_remove"); target = Chem.MolToSmiles(small)
        for match in big.GetSubstructMatches(NME):
            rw = Chem.RWMol(big); rw.RemoveAtom(match[3])
            try: Chem.SanitizeMol(rw)
            except Exception: continue
            if Chem.MolToSmiles(rw) == target: return kind
        return "other"
    return "other"


def propose_edit_smiles(smiles, max_per_type=6):
    """enumerate single edits of a parent: N-Me add at secondary-amide NH, N-Me remove, D-flip at each stereocentre. -> list of (edit_type, new_smiles)."""
    m = mol(smiles); out = []
    if m is None: return out
    for match in m.GetSubstructMatches(NH_AMIDE)[:max_per_type]:
        rw = Chem.RWMol(m); n = match[2]; c = rw.AddAtom(Chem.Atom(6)); rw.AddBond(n, c, Chem.BondType.SINGLE)
        try: Chem.SanitizeMol(rw); out.append(("nme_add", Chem.MolToSmiles(rw)))
        except Exception: pass
    for match in m.GetSubstructMatches(NME)[:max_per_type]:
        rw = Chem.RWMol(m); rw.RemoveAtom(match[3])
        try: Chem.SanitizeMol(rw); out.append(("nme_remove", Chem.MolToSmiles(rw)))
        except Exception: pass
    for idx, _ in Chem.FindMolChiralCenters(m, includeUnassigned=False, useLegacyImplementation=False)[:max_per_type]:
        mm = Chem.Mol(m); a = mm.GetAtomWithIdx(idx)
        a.SetChiralTag(Chem.ChiralType.CHI_TETRAHEDRAL_CW if a.GetChiralTag() == Chem.ChiralType.CHI_TETRAHEDRAL_CCW else Chem.ChiralType.CHI_TETRAHEDRAL_CCW)
        ns = Chem.MolToSmiles(mm); out.append((edit_type(ns, smiles) if edit_type(ns, smiles) in ("dflip_D", "dflip_L") else "dflip", ns))
    seen, res = set(), []
    for t, s in out:
        if s != Chem.MolToSmiles(m) and s not in seen: seen.add(s); res.append((t, s))
    return res


class FastMemory:
    def __init__(self, n0=100.0, k=5, lam_offset=3.0, edit_priors=None, layers=("K", "offset", "retrieval", "edit"), lam_resid=1.0, tau=0.04):
        self.n0, self.k, self.lam, self.lam_resid = float(n0), int(k), float(lam_offset), float(lam_resid); self.tau = float(tau); self.offset_method = {}; self.edit_priors = dict(edit_priors or EDIT_PRIORS); self.layers = tuple(layers)
        self.rows = []; self.offsets = {}; self.edit_eff = {t: v[0] for t, v in self.edit_priors.items()}; self.edit_n = {t: 0 for t in self.edit_priors}

    def clone(self): return copy.deepcopy(self)
    def evidence_weight(self, n=None):                       # M1: w = n0/(n0+n), shrinks as feedback accumulates
        n = len(self.rows) if n is None else n; return self.n0 / (self.n0 + n)

    def corrected(self, r): return r["label"] - (self.offsets.get(r.get("source"), 0.0) if "offset" in self.layers else 0.0)

    def write(self, labelled):
        for r in labelled:
            i = iso(r["smiles"]); f = fp_of(r["smiles"])
            if i is None or f is None: continue
            self.rows.append(dict(smiles=i, fp=f, target_seq=r.get("target_seq"), label=float(r["label"]), source=r.get("source"), K=r.get("K")))
        if "offset" in self.layers: self._fit_offsets()
        if "edit" in self.layers: self._fit_edit_effects()

    @staticmethod
    def estimate_offsets(rows, lam=3.0, iters=50):
        """y = m_i + b_s + e. Anchors = compounds measured in >= 2 sources. Ridge-shrunk b_s (unseen/thin source -> ~0); gauge: mean b over anchor rows = 0."""
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

    def source_counts(self):
        c = {}
        for r in self.rows: c[r.get("source")] = c.get(r.get("source"), 0) + 1
        return c

    def _fit_offsets(self):
        """two estimators, reported per source in self.offset_method: 'replicate' = compounds measured in >= 2 sources (no peptide-effect confound);
        'residual' = for sources WITHOUT replicate anchors: ridge-shrunk (lam_resid) mean residual y - (a + c*K) where (a, c) is a pooled OLS fit on the K channel when K is available
        (else y - grand mean). The residual estimator is only as good as K explains peptide effects (stated, tested with a planted world)."""
        rep = self.estimate_offsets(self.rows, self.lam); self.offsets = dict(rep); self.offset_method = {s: "replicate" for s in rep}
        srcs = sorted({r.get("source") for r in self.rows if r.get("source") is not None} - set(rep))
        if not srcs: return
        withK = [r for r in self.rows if r.get("K") is not None]
        if len(withK) >= 6 and np.std([r["K"] for r in withK]) > 0:
            Kv = np.array([r["K"] for r in withK], float); yv = np.array([r["label"] - rep.get(r.get("source"), 0.0) for r in withK], float); c = np.cov(Kv, yv)[0, 1] / Kv.var(); a = yv.mean() - c * Kv.mean(); pred = lambda r: a + c * r["K"] if r.get("K") is not None else yv.mean()
        else:
            mu = float(np.mean([r["label"] - rep.get(r.get("source"), 0.0) for r in self.rows])); pred = lambda r: mu
        res = {s: [r["label"] - pred(r) for r in self.rows if r.get("source") == s] for s in srcs}; b = {s: float(np.sum(v) / (len(v) + self.lam_resid)) for s, v in res.items()}
        mu_b = np.mean(list(b.values())) if b else 0.0                      # gauge: residual offsets sum to ~0 across sources lacking anchors
        for s in srcs: self.offsets[s] = b[s] - mu_b; self.offset_method[s] = "residual"

    def _fit_edit_effects(self, per_row=40):
        """conjugate shrinkage per edit type: posterior mean = (n*mean_obs + n0e*prior)/(n + n0e) over analog pairs of UNIQUE compounds (same target; offset-corrected label =
        mean over the compound's rows), label difference query - analog. Pairs come from each compound's `per_row` nearest distinct analogs (chirality-aware similarity)."""
        groups = {}
        for r in self.rows: groups.setdefault((r["smiles"], r["target_seq"]), []).append(r)
        U = [dict(smiles=s, target_seq=t, fp=v[0]["fp"], y=float(np.mean([self.corrected(x) for x in v]))) for (s, t), v in groups.items()]
        obs = {t: [] for t in self.edit_priors}
        for i, ri in enumerate(U):
            sims = [(tanimoto(ri["fp"], rj["fp"]), j) for j, rj in enumerate(U) if j != i and rj["target_seq"] == ri["target_seq"]]
            for _, j in sorted(sims, reverse=True)[:per_row]:
                et = edit_type(ri["smiles"], U[j]["smiles"])
                if et in obs and et != "other": obs[et].append(ri["y"] - U[j]["y"])
        for t, (p, n0e) in self.edit_priors.items():
            v = obs.get(t, []); n = len(v); self.edit_n[t] = n
            self.edit_eff[t] = float((n * (np.mean(v) if n else 0.0) + n0e * p) / (n + n0e))

    def neighbours(self, smiles, target_seq, k=None, exclude_self=True):
        f = fp_of(smiles); i = iso(smiles)
        if f is None: return []
        out = [(tanimoto(f, r["fp"]), r) for r in self.rows if r["target_seq"] == target_seq and not (exclude_self and r["smiles"] == i)]
        out.sort(key=lambda x: -x[0]); return out[:k or self.k]

    def edit_delta(self, query, analog):
        et = edit_type(query, analog); return (et, 0.0) if et in (None, "identical") else (et, self.edit_eff.get(et, 0.0))

    def retrieval(self, smiles, target_seq, use_edit=True):
        """-> (estimate in offset-corrected label units | None, max similarity, [(sim, analog row, edit, delta)])"""
        nb = self.neighbours(smiles, target_seq)
        if not nb: return None, 0.0, []
        det, vals, ws = [], [], []
        for sim, r in nb:
            et, d = self.edit_delta(smiles, r["smiles"]) if (use_edit and "edit" in self.layers) else (None, 0.0)
            det.append((sim, r, et, d)); vals.append(self.corrected(r) + d); ws.append(float(np.exp((sim - nb[0][0]) / self.tau)))     # softmax kernel on similarity; tau is a hyper-parameter (tuned on the synthetic world only)
        return float(np.average(vals, weights=ws)), float(nb[0][0]), det

    def digest(self):
        return hashlib.sha256(json.dumps([(r["smiles"], r["label"], r["source"]) for r in self.rows], default=str).encode()).hexdigest()[:16]
