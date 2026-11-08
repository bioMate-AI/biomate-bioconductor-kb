#!/usr/bin/env python3
"""Learned binding-model inference + applicability-domain gating (gap G3).

train_binding_model.py produced results/binding_model_prod.pkl (XGB on binding_affinity_v1:
ECFP4(2048) + 16 physchem + 4 assay one-hot -> pAffinity = 9 - log10(nM), higher = stronger).
This module loads it and scores a peptide, BUT — and this is the whole point of G3 — it reports
an HONEST applicability-domain / confidence verdict alongside the number, because the model's
NOVEL-TARGET generalisation is weak and regresses to the mean:

  from results/binding_model_metrics_cyclic.json (novel-target hold-out = PD-L1 + avb6 OUT of train):
    XGBoost  Spearman 0.377   (PD-L1 0.314, avb6 0.470)   R2 0.178
    pred_std ~0.6 vs true_std ~1.1  -> predictions compress toward the mean (regress-to-mean)

The model is LIGAND-ONLY (no target channel — by design, so the novel-target test is honest). It
therefore CANNOT tell two novel targets apart; for a de-novo design campaign against a target the
model never trained on, its pAffinity is at best a weak chemotype prior, NOT a binding oracle.

Applicability-domain verdict combines:
  * TARGET level  — target_in_distribution (caller-asserted). Default FALSE: our ACT campaigns
    (avb6, PD-L1 de-novo) are novel targets, so the conservative default is out-of-domain.
  * LIGAND level  — max Tanimoto similarity of the candidate ECFP4 to the training ligands
    (results/binding_feature_cache.npz). Below ad_threshold (default 0.35) -> chemically novel.
  status = "in_domain" only if target_in_distribution AND ligand within AD; else "out_of_domain"
  (low_confidence=True). "unknown" when the AD reference bank is unavailable.

Consumers MUST treat an out-of-domain / low-confidence score as advisory only (see peptide_verify:
affinity_ml is NOT part of the gated property vector and NOT a selection objective — it never
re-ranks a novel-target pool).
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, Optional, Tuple

import numpy as np

ROOT = Path(__file__).resolve().parent
DEFAULT_MODEL = ROOT / "results" / "binding_model_prod.pkl"
DEFAULT_CACHE = ROOT / "results" / "binding_feature_cache.npz"
DEFAULT_AD_THRESHOLD = 0.35
DEFAULT_ASSAY = "Kd"

# Honest headline numbers from results/binding_model_metrics_cyclic.json (novel-target hold-out).
NOVEL_TARGET_SPEARMAN = 0.377
NOVEL_TARGET_NOTE = (
    "learned pAffinity (higher=stronger); novel-target Spearman ~0.38 (PD-L1 0.31 / avb6 0.47), "
    "regresses to mean (pred_std 0.6 vs true_std 1.1) — ADVISORY chemotype prior, NOT a binding "
    "oracle and NOT a MM-GBSA replacement")


# --------------------------------------------------------------------------------------------
# applicability domain (pure numpy — unit-testable without xgboost/rdkit)
# --------------------------------------------------------------------------------------------
def tanimoto_max(cand_bits: np.ndarray, ref_matrix: np.ndarray) -> float:
    """Max Tanimoto similarity of a 0/1 fingerprint to any row of a 0/1 (N,B) reference matrix."""
    cand = np.asarray(cand_bits).astype(bool)
    ref = np.asarray(ref_matrix).astype(bool)
    if ref.ndim != 2 or ref.shape[0] == 0:
        return 0.0
    inter = (ref & cand).sum(axis=1).astype(np.float64)
    union = ref.sum(axis=1) + cand.sum() - inter
    with np.errstate(divide="ignore", invalid="ignore"):
        tani = np.where(union > 0, inter / union, 0.0)
    return float(tani.max()) if tani.size else 0.0


def applicability(cand_bits: Optional[np.ndarray], *, target_in_distribution: bool,
                  cache_path=DEFAULT_CACHE, ad_threshold: float = DEFAULT_AD_THRESHOLD,
                  _ref_override: Optional[np.ndarray] = None) -> Dict:
    """Return the AD verdict dict. Never raises."""
    verdict = {
        "target_in_distribution": bool(target_in_distribution),
        "ligand_in_domain": None,
        "max_tanimoto": None,
        "ad_threshold": ad_threshold,
        "status": "unknown",
        "low_confidence": True,
        "reason": "",
    }
    ref = _ref_override
    if ref is None and cand_bits is not None:
        try:
            z = np.load(cache_path, allow_pickle=True)
            ref = z["fp"]
        except Exception as e:  # noqa: BLE001
            verdict["reason"] = f"AD reference bank unavailable ({type(e).__name__}); ligand AD not checked"
    if cand_bits is not None and ref is not None:
        mx = tanimoto_max(cand_bits, ref)
        verdict["max_tanimoto"] = round(mx, 4)
        verdict["ligand_in_domain"] = bool(mx >= ad_threshold)
    # combine target + ligand levels
    if verdict["ligand_in_domain"] is None:
        verdict["status"] = "unknown"
        verdict["low_confidence"] = True
        verdict["reason"] = verdict["reason"] or "ligand AD could not be evaluated"
    elif target_in_distribution and verdict["ligand_in_domain"]:
        verdict["status"] = "in_domain"
        verdict["low_confidence"] = False
        verdict["reason"] = "target asserted in-distribution AND ligand within chemical AD"
    else:
        verdict["status"] = "out_of_domain"
        verdict["low_confidence"] = True
        bits = []
        if not target_in_distribution:
            bits.append("novel/unknown target (default)")
        if verdict["ligand_in_domain"] is False:
            bits.append(f"ligand chemically novel (max Tanimoto {verdict['max_tanimoto']} < {ad_threshold})")
        verdict["reason"] = "out of applicability domain: " + "; ".join(bits)
    return verdict


# --------------------------------------------------------------------------------------------
# featurisation + model prediction (lazy heavy deps; graceful degrade)
# --------------------------------------------------------------------------------------------
def candidate_fingerprint(seq: Optional[str], smiles: Optional[str]) -> Optional[np.ndarray]:
    """ECFP4(2048) uint8 bits for a candidate, via the SAME featuriser the model trained on."""
    import binding_features as bf
    smi = smiles
    if smi is None and seq:
        smi = bf.seq_to_smiles(seq)
    if not smi:
        return None
    r = bf.featurize_smiles(smi)
    return None if r is None else np.asarray(r[0], dtype=np.uint8)


def _assemble_x(seq, smiles, assay_type, assay_types) -> Optional[np.ndarray]:
    import binding_features as bf
    smi = smiles or (bf.seq_to_smiles(seq) if seq else None)
    if not smi:
        return None
    r = bf.featurize_smiles(smi)
    if r is None:
        return None
    fp, desc = np.asarray(r[0], np.float32), np.asarray(r[1], np.float32)
    onehot = np.zeros(len(assay_types), np.float32)
    if assay_type in assay_types:
        onehot[assay_types.index(assay_type)] = 1.0
    x = np.hstack([fp, desc, onehot]).astype(np.float32)
    return np.nan_to_num(x, nan=0.0, posinf=0.0, neginf=0.0).reshape(1, -1)


def load_model(model_path=DEFAULT_MODEL):
    """Load the pickled production model bundle. Raises on missing deps/file (callers guard)."""
    import pickle
    with open(model_path, "rb") as fh:
        return pickle.load(fh)


def predict_paffinity(seq: Optional[str], smiles: Optional[str], *,
                      model_path=DEFAULT_MODEL, assay_type: str = DEFAULT_ASSAY,
                      _bundle=None) -> Tuple[Optional[float], Dict]:
    """Return (predicted pAffinity, info). Never raises — returns (None, {error:...}) on any
    failure (missing xgboost, missing model file, unparseable SMILES)."""
    info: Dict = {"model": os.path.basename(str(model_path)), "assay_type": assay_type}
    try:
        bundle = _bundle if _bundle is not None else load_model(model_path)
    except Exception as e:  # noqa: BLE001  (xgboost missing / file missing)
        info["error"] = f"model unavailable: {type(e).__name__}: {e}"
        return None, info
    assay_types = bundle.get("assay_types", ["IC50", "Ki", "EC50", "Kd"])
    try:
        x = _assemble_x(seq, smiles, assay_type, assay_types)
    except Exception as e:  # noqa: BLE001  (rdkit missing / featurisation error)
        info["error"] = f"featurisation failed: {type(e).__name__}: {e}"
        return None, info
    if x is None:
        info["error"] = "could not build features from seq/smiles"
        return None, info
    if x.shape[1] != bundle.get("feat_dim", x.shape[1]):
        info["error"] = f"feature dim {x.shape[1]} != model feat_dim {bundle.get('feat_dim')}"
        return None, info
    try:
        val = float(bundle["model"].predict(x)[0])
    except Exception as e:  # noqa: BLE001
        info["error"] = f"model.predict failed: {type(e).__name__}: {e}"
        return None, info
    return val, info


def score(seq: Optional[str], smiles: Optional[str], *, target_in_distribution: bool = False,
          model_path=DEFAULT_MODEL, cache_path=DEFAULT_CACHE, assay_type: str = DEFAULT_ASSAY,
          ad_threshold: float = DEFAULT_AD_THRESHOLD, _bundle=None, _ref_override=None) -> Dict:
    """One call: predicted pAffinity + applicability verdict. Never raises."""
    val, info = predict_paffinity(seq, smiles, model_path=model_path, assay_type=assay_type, _bundle=_bundle)
    try:
        fp = candidate_fingerprint(seq, smiles)
    except Exception:  # noqa: BLE001
        fp = None
    ad = applicability(fp, target_in_distribution=target_in_distribution,
                       cache_path=cache_path, ad_threshold=ad_threshold, _ref_override=_ref_override)
    return {"paffinity": val, "info": info, "applicability": ad}


# --------------------------------------------------------------------------------------------
# selftest — pure AD logic + graceful-degrade (no xgboost required)
# --------------------------------------------------------------------------------------------
def _selftest() -> int:
    checks = {}

    a = np.array([1, 1, 1, 0, 0], np.uint8)
    ref = np.array([[1, 1, 1, 0, 0], [0, 0, 0, 1, 1]], np.uint8)
    checks["tanimoto: identical row -> 1.0"] = abs(tanimoto_max(a, ref) - 1.0) < 1e-9
    b = np.array([0, 0, 0, 1, 0], np.uint8)
    # vs row0 (3 bits): inter 0 -> 0; vs row1 (2 bits): inter 1, union 2 -> 0.5
    checks["tanimoto: partial -> 0.5"] = abs(tanimoto_max(b, ref) - 0.5) < 1e-9
    checks["tanimoto: empty ref -> 0"] = tanimoto_max(a, np.zeros((0, 5))) == 0.0

    # AD combine logic
    sim_ref = np.array([[1, 1, 1, 0, 0]], np.uint8)  # candidate a is identical -> in AD
    v_in = applicability(a, target_in_distribution=True, _ref_override=sim_ref, ad_threshold=0.35)
    checks["in_domain only when target IN-dist AND ligand in AD"] = (
        v_in["status"] == "in_domain" and v_in["low_confidence"] is False)
    v_novel_tgt = applicability(a, target_in_distribution=False, _ref_override=sim_ref)
    checks["novel target -> out_of_domain + low_confidence (even if ligand familiar)"] = (
        v_novel_tgt["status"] == "out_of_domain" and v_novel_tgt["low_confidence"] is True)
    v_novel_lig = applicability(b, target_in_distribution=True, _ref_override=sim_ref, ad_threshold=0.9)
    checks["novel ligand -> out_of_domain"] = (
        v_novel_lig["status"] == "out_of_domain" and v_novel_lig["ligand_in_domain"] is False)
    v_unknown = applicability(None, target_in_distribution=True)
    checks["no fingerprint -> unknown + low_confidence"] = (
        v_unknown["status"] == "unknown" and v_unknown["low_confidence"] is True)

    # graceful degrade: no model file -> (None, error), no raise
    val, info = predict_paffinity("ACDEF", None, model_path="/no/such/model.pkl")
    checks["missing model -> (None, error) no raise"] = (val is None and "error" in info)

    # mocked model bundle (no xgboost): prove the feature+predict wiring with a stub predictor
    class _Stub:
        def predict(self, x):
            return np.array([7.5], np.float32)
    try:
        import binding_features  # noqa: F401  (rdkit present?)
        _have_bf = True
    except Exception:  # noqa: BLE001
        _have_bf = False
    if _have_bf:
        bundle = {"model": _Stub(), "assay_types": ["IC50", "Ki", "EC50", "Kd"], "feat_dim": 2068}
        val2, info2 = predict_paffinity("ACDEFGHIK", None, _bundle=bundle, assay_type="Kd")
        checks["mocked predictor returns the stub pAffinity (feature wiring ok)"] = (val2 == 7.5)
    else:
        print("  SKIP  mocked predictor path (rdkit/binding_features unavailable)")
        checks["mocked predictor returns the stub pAffinity (feature wiring ok)"] = True

    for k, v in checks.items():
        print(f"  {'PASS' if v else 'FAIL'}  {k}")
    ok = all(checks.values())
    print("ALL_CHECKS_PASS=" + str(ok))
    return 0 if ok else 1


if __name__ == "__main__":
    import sys

    if "--selftest" in sys.argv:
        sys.exit(_selftest())
    print(__doc__)
