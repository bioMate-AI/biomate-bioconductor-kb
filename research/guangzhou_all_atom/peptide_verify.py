"""Track A / A1 — Peptide verify-service (single interface over the existing scorers).

Per the execution plan (docs/20260925_PEPTIDE_EXECUTION_PLAN.md, item A1): wrap the
already-built verify components into ONE callable so every generated peptide gets the full
developability property vector — NOT a reimplementation of any scorer.

    verify_peptide(seq="ACDEFG") -> PeptideProperties

Design contract
---------------
* Each PROPERTY is backed by an EXISTING component. Where a real, locally-runnable scorer
  exists it is IMPORTED and called (permeability, synthetic accessibility). Where the only
  scorer is an AWS-EC2 physics job (MM-GBSA / FEP), the field is filled ONLY from an
  already-computed result JSON if one is supplied — we do NOT launch GPU jobs from here.
* FAIL-SAFE: any scorer that raises degrades ITS field to ``None`` + records the error in
  ``.errors`` and marks provenance ``"unavailable"``. One broken scorer never crashes verify.
* Every field carries a ``provenance`` tag: ``measured`` | ``predicted`` | ``proxy`` |
  ``unavailable`` — the plan's honesty requirement (measured-vs-predicted). ``uncertainty`` is
  populated where the underlying ensemble reports it.

Honest scorer-backing map (see module docstring table at bottom / the returned README):

    property                real scorer                        provenance   runs where
    ------------------------ ---------------------------------- ------------ -------------
    permeability (logPapp)   permeability_predictor.py          predicted    LOCAL CPU
    synthetic_accessibility  RDKit SA_Score contrib (via        proxy        LOCAL CPU
                             evaluate.py-style RDKit path)
    safety                   stability_predictor.py /           proxy*       LOCAL CPU
                             score_generation.py ensemble       (see note)
    affinity_dG (ΔG)         peptide_mmgbsa_v3verify.sh (AWS)   measured**   AWS EC2/GPU
                             or launch_fep_poc.sh (FEP, AWS)                  (JSON ingest
                                                                              only here)

  * "safety" is filled from the blood-STABILITY ensemble as the closest locally-runnable
    developability endpoint. This is an HONEST PROXY, not a tox/immunogenicity oracle — there
    is no standalone local safety/tox scorer in research/guangzhou_all_atom/. Tagged ``proxy``.
  ** MM-GBSA ΔG is a physics estimate (relative free energy of binding), reported as
    ``measured`` in the physics-vs-ML sense used across the stack (non-circular oracle), NOT a
    wet-lab Kd. It is only available if a physics result JSON is passed in.
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Callable, Dict, Optional

ROOT = Path(__file__).resolve().parent

# Provenance vocabulary
MEASURED = "measured"        # physics / assay-grade (MM-GBSA, FEP, wet-lab)
PREDICTED = "predicted"      # trained ML model with a real validation number
PROXY = "proxy"              # heuristic / adjacent-endpoint stand-in (honest)
UNAVAILABLE = "unavailable"  # scorer errored or dependency/data missing


# --------------------------------------------------------------------------------------------
# dataclasses
# --------------------------------------------------------------------------------------------
@dataclass
class PropertyValue:
    """One scored property with its honesty metadata."""
    value: Optional[float] = None
    provenance: str = UNAVAILABLE
    uncertainty: Optional[float] = None
    scorer: str = ""            # which component produced it
    detail: str = ""            # units / model description / caveat
    # G3: applicability-domain metadata for learned models (e.g. affinity_ml). None for scorers
    # that have no AD concept (physics, RDKit). "in_domain" | "out_of_domain" | "unknown".
    applicability: Optional[str] = None
    low_confidence: bool = False  # True => advisory only; must NOT drive gating/selection

    def ok(self) -> bool:
        return self.value is not None


@dataclass
class PeptideProperties:
    """The full developability vector for one candidate (A1 acceptance: full vector +
    uncertainty, provenance tagged measured-vs-predicted)."""
    identifier: str = ""
    sequence: Optional[str] = None
    smiles: Optional[str] = None

    affinity_dG: PropertyValue = field(default_factory=PropertyValue)          # kcal/mol
    permeability: PropertyValue = field(default_factory=PropertyValue)         # log Papp / ΔPSA3D
    synthetic_accessibility: PropertyValue = field(default_factory=PropertyValue)  # SA score 1..10
    safety: PropertyValue = field(default_factory=PropertyValue)               # dev/stability proxy

    # G3: ADDITIONAL, advisory learned-binding channel (train_binding_model.py). Deliberately NOT
    # part of scored_fields() => excluded from is_complete() AND never a selection objective
    # (peptide_select reads scored_fields/OBJECTIVE_DIRECTIONS, which do not include it). It cannot
    # replace affinity_dG (MM-GBSA) nor silently re-rank a novel-target pool. See _score_ml_affinity.
    affinity_ml: PropertyValue = field(default_factory=PropertyValue)          # learned pAffinity

    errors: Dict[str, str] = field(default_factory=dict)   # field -> error string (fail-safe log)

    def scored_fields(self) -> Dict[str, PropertyValue]:
        """The GATED developability vector (drives is_complete + selection). affinity_ml is NOT
        here on purpose — it is an advisory channel, see extra_fields()."""
        return {
            "affinity_dG": self.affinity_dG,
            "permeability": self.permeability,
            "synthetic_accessibility": self.synthetic_accessibility,
            "safety": self.safety,
        }

    def extra_fields(self) -> Dict[str, PropertyValue]:
        """Advisory, non-gating channels (reported for audit, never used for gating/selection)."""
        return {"affinity_ml": self.affinity_ml}

    def is_complete(self) -> bool:
        """True only if every property has a value (no degraded fields)."""
        return all(pv.ok() for pv in self.scored_fields().values())

    def to_dict(self) -> dict:
        d = asdict(self)
        return d


# --------------------------------------------------------------------------------------------
# lazy import of the existing local scorer modules (do NOT reimplement — import & call)
# --------------------------------------------------------------------------------------------
def _load_module(filename: str):
    """Import a sibling scorer .py by path (they are scripts, not a package)."""
    path = ROOT / filename
    if not path.exists():
        raise FileNotFoundError(f"scorer not found next to peptide_verify.py: {filename}")
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


def _default_dataset_path(registry_name: str, fallback_rel: str) -> Path:
    """G8: resolve a training CSV through cyclic_data_registry (cache-first, no surprise download),
    falling back to the committed relative path if the registry is unavailable. Behaviour-preserving
    — the registry's local_path for these datasets is exactly the committed path. Delegates to the
    shared dataset_path.resolve so every stage script routes dataset paths through one place."""
    return _load_module("dataset_path.py").resolve(registry_name, fallback_rel)


# --------------------------------------------------------------------------------------------
# individual field scorers — each returns a PropertyValue and NEVER raises past its own body
# (the aggregator also guards, but keeping each self-contained makes them independently usable)
# --------------------------------------------------------------------------------------------
_PERM_PRED_CACHE: Dict[str, Dict[str, tuple]] = {}  # csv path -> {key -> (mean, std)}


def _load_perm_predictions(csv_path: Path) -> Dict[str, tuple]:
    """G4: load a per-candidate permeability predictions CSV (predict_permeability_pool.py output)
    into an identifier/smiles/sequence -> (mean, std) lookup. Memoised per file so a batch reads
    it once. Keys are prefixed so an id never collides with a smiles/seq."""
    key = str(csv_path)
    if key in _PERM_PRED_CACHE:
        return _PERM_PRED_CACHE[key]
    import csv as _csv
    table: Dict[str, tuple] = {}
    try:
        for r in _csv.DictReader(open(csv_path)):
            try:
                val = (float(r["logPapp_mean"]), float(r.get("logPapp_std") or "nan"))
            except (KeyError, TypeError, ValueError):
                continue
            for pfx, col in (("id:", "identifier"), ("smi:", "smiles"), ("seq:", "sequence")):
                v = (r.get(col) or "").strip()
                if v:
                    table[pfx + v] = val
    except Exception:  # noqa: BLE001 — a missing/garbled predictions CSV just disables the lookup
        table = {}
    _PERM_PRED_CACHE[key] = table
    return table


def _score_permeability(seq: Optional[str], smiles: Optional[str],
                        perm_csv: Optional[Path],
                        identifier: str = "", perm_pred_csv: Optional[Path] = None) -> PropertyValue:
    """Permeability = log Papp, from permeability_predictor.py's bootstrap-bagged ensemble
    (mean + epistemic std).

    G4: if ``perm_pred_csv`` is supplied (predict_permeability_pool.py output), the candidate's
    value is LOOKED UP (keyed identifier -> smiles -> sequence) instead of re-training the ensemble
    per candidate. Falls back to the live train-on-the-fly path when no precomputed row matches, so
    the numbers are identical either way — the CSV path just avoids N full retrains in a loop.

    predicted (ranking-grade, scaffold-R2 ~0.23 per the module's own reported metric)."""
    pv = PropertyValue(scorer="permeability_predictor.py",
                       detail="log Papp; ECFP4 + bootstrap-bagged HistGBM (mean, epistemic std)")
    # G4 fast path: precomputed per-candidate prediction lookup
    if perm_pred_csv is not None:
        table = _load_perm_predictions(Path(perm_pred_csv))
        for k in (f"id:{identifier}" if identifier else None,
                  f"smi:{smiles}" if smiles else None,
                  f"seq:{seq}" if seq else None):
            if k and k in table:
                mean, std = table[k]
                pv.value = mean
                pv.uncertainty = None if std != std else std  # NaN std -> None
                pv.provenance = PREDICTED
                pv.detail += " | precomputed pool CSV (predict_permeability_pool.py)"
                return pv
        # no match -> fall through to live training (do not fail; the CSV may be partial)
    csv_path = perm_csv or _default_dataset_path("cycpeptmpdb", "data/raw/CycPeptMPDB_Peptide_All.csv")
    if not Path(csv_path).exists():
        pv.detail += f" | training CSV missing: {csv_path}"
        return pv  # provenance stays UNAVAILABLE
    import numpy as np
    from rdkit import Chem, RDLogger
    from rdkit.Chem import rdFingerprintGenerator
    RDLogger.DisableLog("rdApp.*")
    perm = _load_module("permeability_predictor.py")

    mol = None
    if smiles:
        mol = Chem.MolFromSmiles(smiles)
    if mol is None and seq:
        mol = Chem.MolFromSequence(seq)
    if mol is None:
        pv.detail += " | could not build RDKit mol from seq/smiles"
        return pv

    fpgen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    feat = np.asarray(fpgen.GetFingerprint(mol), dtype=np.float32).reshape(1, -1)

    X, y, _ = perm.load(csv_path)          # real training path
    if len(y) == 0:
        pv.detail += " | training set empty after filtering"
        return pv
    mean, std = perm.bagged_fit_predict(X, y, feat)   # real ensemble (mean + std)
    pv.value = float(mean[0])
    pv.uncertainty = float(std[0])
    pv.provenance = PREDICTED
    return pv


def _score_synthetic_accessibility(seq: Optional[str], smiles: Optional[str]) -> PropertyValue:
    """Synthetic accessibility via RDKit's SA_Score contrib (Ertl & Schuffenhauer). This is the
    de-facto SA scorer; it is a generic small-molecule heuristic, NOT peptide-synthesis-aware,
    so it is tagged ``proxy``. Lower = easier to synthesize (1 easy .. 10 hard). RDKit-mol
    construction mirrors evaluate.py's identity path."""
    pv = PropertyValue(scorer="RDKit SA_Score (contrib) via evaluate.py RDKit path",
                       detail="Ertl-Schuffenhauer SA score 1(easy)..10(hard); generic, not peptide-specific")
    try:
        from rdkit import Chem, RDLogger
        from rdkit.Chem import RDConfig
        RDLogger.DisableLog("rdApp.*")
        sa_dir = os.path.join(RDConfig.RDContribDir, "SA_Score")
        if sa_dir not in sys.path:
            sys.path.append(sa_dir)
        import sascorer  # type: ignore
    except Exception as e:  # noqa: BLE001
        pv.detail += f" | SA_Score contrib unavailable: {type(e).__name__}: {e}"
        return pv
    from rdkit import Chem
    mol = None
    if smiles:
        mol = Chem.MolFromSmiles(smiles)
    if mol is None and seq:
        mol = Chem.MolFromSequence(seq)
    if mol is None:
        pv.detail += " | could not build RDKit mol"
        return pv
    pv.value = float(sascorer.calculateScore(mol))
    pv.provenance = PROXY
    return pv


def _score_safety(seq: Optional[str], smiles: Optional[str],
                  stab_csv: Optional[Path]) -> PropertyValue:
    """Safety field, filled from the blood-STABILITY developability ensemble
    (score_generation.py / stability_predictor.py). There is NO standalone local tox /
    immunogenicity scorer in the stack, so this is an HONEST PROXY: P(stable) as a
    developability stand-in, with the ensemble's epistemic std as uncertainty.

    Uses multi_property_selection.train_stability (returns a mean-P(stable) callable) and,
    for uncertainty, score_generation's ensemble std."""
    pv = PropertyValue(scorer="stability_predictor.py / score_generation.py ensemble",
                       detail="PROXY: P(stable) developability endpoint (AUROC~0.84 leak-free); "
                              "NOT a tox/immunogenicity oracle")
    csv_path = stab_csv or _default_dataset_path("pepmsnd_stability_folds", "data/processed/pepmsnd_stability_folds.csv")
    if not Path(csv_path).exists():
        pv.detail += f" | training CSV missing: {csv_path}"
        return pv
    import csv as _csv
    import numpy as np
    from rdkit import Chem, RDLogger
    from rdkit.Chem import rdFingerprintGenerator
    RDLogger.DisableLog("rdApp.*")
    sg = _load_module("score_generation.py")   # gives train_ensemble + predict (mean, std)

    mol = None
    if smiles:
        mol = Chem.MolFromSmiles(smiles)
    if mol is None and seq:
        mol = Chem.MolFromSequence(seq)
    if mol is None:
        pv.detail += " | could not build RDKit mol"
        return pv
    fpgen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    feat = np.asarray(fpgen.GetFingerprint(mol), dtype=np.float32).reshape(1, -1)

    # train the real stability ensemble on the leak-free folds (same rows the module uses)
    Xtr, ytr = [], []
    for r in _csv.DictReader(open(csv_path)):
        if r.get("label_conflict") == "True":
            continue
        m = Chem.MolFromSmiles(r["canonical_smiles"])
        if m is None:
            continue
        Xtr.append(np.asarray(fpgen.GetFingerprint(m), dtype=np.float32))
        ytr.append(int(r["label"]))
    if len(set(ytr)) < 2:
        pv.detail += " | training labels degenerate"
        return pv
    Xtr, ytr = np.array(Xtr), np.array(ytr)
    models = sg.train_ensemble(Xtr, ytr)          # real ensemble
    mean, std = sg.predict(models, feat)          # mean P(stable) + epistemic std
    pv.value = float(mean[0])
    pv.uncertainty = float(std[0])
    pv.provenance = PROXY
    return pv


def _score_affinity(identifier: str, seq: Optional[str],
                    physics_json: Optional[Path]) -> PropertyValue:
    """Binding ΔG from the physics oracle (MM-GBSA: peptide_mmgbsa_v3verify.sh, or FEP:
    launch_fep_poc.sh). Those are AWS-EC2/GPU jobs — this verify-service does NOT launch them
    (cost/time discipline). Instead it INGESTS an already-computed physics result JSON if one
    is supplied, keyed by ``identifier`` (the design id, e.g. ``1yf4_10``).

    Expected JSON shape = peptide_mmgbsa_v3verify.sh output:
        {"<id>": {"ok": true, "seq": "...", "dG": -34.21}, ...}

    If no JSON (or the id is absent / job failed), the field stays UNAVAILABLE — honest, not a
    fabricated number."""
    pv = PropertyValue(scorer="peptide_mmgbsa_v3verify.sh (MM-GBSA) | launch_fep_poc.sh (FEP)",
                       detail="ΔG binding (kcal/mol), physics oracle; AWS EC2/GPU job — ingested "
                              "from result JSON, not launched here")
    if not physics_json:
        pv.detail += " | no physics result JSON supplied (run the AWS MM-GBSA/FEP job first)"
        return pv
    p = Path(physics_json)
    if not p.exists():
        pv.detail += f" | physics JSON not found: {p}"
        return pv
    try:
        data = json.loads(p.read_text())
    except Exception as e:  # noqa: BLE001
        pv.detail += f" | could not parse physics JSON: {type(e).__name__}: {e}"
        return pv
    rec = data.get(identifier)
    if not isinstance(rec, dict):
        pv.detail += f" | id '{identifier}' absent from physics JSON"
        return pv
    if not rec.get("ok") or ("dG" not in rec):
        pv.detail += f" | physics job for '{identifier}' did not succeed: {rec.get('error', 'no dG')}"
        return pv
    pv.value = float(rec["dG"])
    pv.provenance = MEASURED
    return pv


def _score_ml_affinity(seq: Optional[str], smiles: Optional[str], *,
                       model_path, cache_path, target_in_distribution: bool,
                       ad_threshold: float, assay_type: str) -> PropertyValue:
    """G3 — ADDITIONAL learned binding channel (binding_ml.py / binding_model_prod.pkl).

    HONESTY CONTRACT (the reason this is a separate field, not affinity_dG):
      * The learned model is ligand-only; its NOVEL-TARGET Spearman is weak (~0.38, regresses to
        mean). It is an advisory chemotype prior, NOT a binding oracle.
      * It does NOT replace MM-GBSA (affinity_dG) and is NOT a selection objective.
      * For out-of-domain candidates (novel target by default, or chemically novel ligand) the
        value is STILL reported for audit but flagged low_confidence=True + applicability tag, so
        a downstream reader can never mistake it for an in-domain prediction.

    Degrades to UNAVAILABLE (never raises) if xgboost/the model/RDKit are missing."""
    pv = PropertyValue(scorer="binding_ml.py (XGB on binding_affinity_v1) + applicability domain",
                       detail="learned pAffinity=9-log10(Kd nM), higher=stronger; ADVISORY channel")
    try:
        bml = _load_module("binding_ml.py")
    except Exception as e:  # noqa: BLE001
        pv.detail += f" | binding_ml unavailable: {type(e).__name__}: {e}"
        return pv
    res = bml.score(seq, smiles, target_in_distribution=target_in_distribution,
                    model_path=model_path or bml.DEFAULT_MODEL,
                    cache_path=cache_path or bml.DEFAULT_CACHE,
                    ad_threshold=ad_threshold, assay_type=assay_type)
    ad = res["applicability"]
    pv.applicability = ad["status"]
    pv.low_confidence = bool(ad["low_confidence"])
    if res["paffinity"] is None:
        pv.detail += f" | prediction unavailable: {res['info'].get('error', 'unknown')}"
        return pv  # stays UNAVAILABLE (no number to report)
    pv.value = float(res["paffinity"])
    pv.provenance = PREDICTED
    pv.detail = (f"{bml.NOVEL_TARGET_NOTE} | AD={ad['status']}"
                 f" (max_tanimoto={ad.get('max_tanimoto')}, {ad.get('reason')})")
    if pv.low_confidence:
        pv.detail += " | LOW-CONFIDENCE: advisory only, does not gate/select or overrule MM-GBSA"
    return pv


# map field name -> (callable(**ctx) -> PropertyValue). The aggregator wraps each in try/except.
_SCORERS: Dict[str, Callable[..., PropertyValue]] = {
    "affinity_dG": lambda ctx: _score_affinity(ctx["identifier"], ctx["seq"], ctx["physics_json"]),
    "permeability": lambda ctx: _score_permeability(ctx["seq"], ctx["smiles"], ctx["perm_csv"],
                                                     ctx["identifier"], ctx["perm_pred_csv"]),
    "synthetic_accessibility": lambda ctx: _score_synthetic_accessibility(ctx["seq"], ctx["smiles"]),
    "safety": lambda ctx: _score_safety(ctx["seq"], ctx["smiles"], ctx["stab_csv"]),
}


# --------------------------------------------------------------------------------------------
# public entry point
# --------------------------------------------------------------------------------------------
def verify_peptide(
    seq: Optional[str] = None,
    smiles: Optional[str] = None,
    identifier: str = "",
    *,
    physics_json: Optional[os.PathLike | str] = None,
    perm_csv: Optional[os.PathLike | str] = None,
    perm_pred_csv: Optional[os.PathLike | str] = None,
    stab_csv: Optional[os.PathLike | str] = None,
    only: Optional[list[str]] = None,
    # G3: opt-in advisory learned-binding channel (default OFF => behaviour unchanged for callers).
    score_ml_affinity: bool = False,
    binding_model_path: Optional[os.PathLike | str] = None,
    binding_cache_path: Optional[os.PathLike | str] = None,
    target_in_distribution: bool = False,
    ad_threshold: float = 0.35,
    assay_type: str = "Kd",
    _scorers: Optional[Dict[str, Callable[..., PropertyValue]]] = None,
) -> PeptideProperties:
    """Score one peptide on the full developability vector.

    Parameters
    ----------
    seq : one-letter peptide sequence (e.g. "ACDEFG"). Provide seq and/or smiles.
    smiles : SMILES string (preferred when the candidate is non-canonical / macrocyclic).
    identifier : design id used to look ΔG up in ``physics_json`` (e.g. "1yf4_10").
    physics_json : path to an MM-GBSA/FEP result JSON (AWS job output) for the affinity field.
    perm_csv / stab_csv : override the training CSVs (default: the committed data/ files).
    perm_pred_csv : G4 — precomputed per-candidate permeability predictions (predict_permeability_pool.py
           output). When set, permeability is looked up (id->smiles->seq) instead of retraining the
           ensemble per candidate; falls back to live training when a candidate has no precomputed row.
    only : if given, only score these fields (rest left UNAVAILABLE). Useful for A3's cheap
           pre-filter (e.g. only permeability + SA before expensive physics).
    _scorers : test hook — inject mocked scorers.

    Returns
    -------
    PeptideProperties — every field either has a value (with provenance + uncertainty) or is
    degraded to ``None`` with the reason recorded in ``.errors`` (FAIL-SAFE: never raises for a
    single broken scorer).
    """
    if not seq and not smiles:
        raise ValueError("verify_peptide requires at least one of seq= or smiles=")

    props = PeptideProperties(identifier=identifier, sequence=seq, smiles=smiles)
    ctx = {
        "identifier": identifier,
        "seq": seq,
        "smiles": smiles,
        "physics_json": Path(physics_json) if physics_json else None,
        "perm_csv": Path(perm_csv) if perm_csv else None,
        "perm_pred_csv": Path(perm_pred_csv) if perm_pred_csv else None,
        "stab_csv": Path(stab_csv) if stab_csv else None,
    }
    scorers = _scorers or _SCORERS
    fields = only or list(scorers.keys())

    for name in fields:
        scorer = scorers.get(name)
        if scorer is None:
            props.errors[name] = f"no scorer registered for field '{name}'"
            continue
        try:
            pv = scorer(ctx)
            if not isinstance(pv, PropertyValue):
                raise TypeError(f"scorer for '{name}' returned {type(pv).__name__}, not PropertyValue")
            setattr(props, name, pv)
            # a scorer that returned UNAVAILABLE with a reason -> surface it in errors too
            if not pv.ok() and pv.detail:
                props.errors.setdefault(name, pv.detail)
        except Exception as e:  # noqa: BLE001  — FAIL-SAFE: degrade this field only
            degraded = PropertyValue(provenance=UNAVAILABLE,
                                     detail=f"scorer raised: {type(e).__name__}: {e}")
            setattr(props, name, degraded)
            props.errors[name] = f"{type(e).__name__}: {e}"

    # G3: advisory learned-binding channel — opt-in, separate from the gated vector. Fail-safe:
    # a broken model never crashes verify and never touches affinity_dG or the other fields.
    if score_ml_affinity and not _scorers:
        try:
            props.affinity_ml = _score_ml_affinity(
                seq, smiles, model_path=binding_model_path, cache_path=binding_cache_path,
                target_in_distribution=target_in_distribution, ad_threshold=ad_threshold,
                assay_type=assay_type)
            if not props.affinity_ml.ok() and props.affinity_ml.detail:
                props.errors.setdefault("affinity_ml", props.affinity_ml.detail)
        except Exception as e:  # noqa: BLE001
            props.affinity_ml = PropertyValue(provenance=UNAVAILABLE,
                                              detail=f"affinity_ml raised: {type(e).__name__}: {e}")
            props.errors["affinity_ml"] = f"{type(e).__name__}: {e}"

    return props


def verify_batch(candidates: list[dict], **kwargs) -> list[PeptideProperties]:
    """Convenience: verify a pool. Each candidate is a dict with any of seq/smiles/identifier/
    physics_json. Fail-safe is per-candidate AND per-field. Feeds A2 (MPO/EHVI selection)."""
    out = []
    for c in candidates:
        merged = {**kwargs, **c}
        try:
            out.append(verify_peptide(**merged))
        except Exception as e:  # noqa: BLE001 — a malformed candidate never sinks the batch
            p = PeptideProperties(identifier=c.get("identifier", ""),
                                  sequence=c.get("seq"), smiles=c.get("smiles"))
            p.errors["_candidate"] = f"{type(e).__name__}: {e}"
            out.append(p)
    return out


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="A1 peptide verify-service (single interface).")
    ap.add_argument("--seq", help="one-letter peptide sequence")
    ap.add_argument("--smiles", help="SMILES")
    ap.add_argument("--id", dest="identifier", default="", help="design id for physics lookup")
    ap.add_argument("--physics-json", help="MM-GBSA/FEP result JSON for the affinity field")
    ap.add_argument("--only", nargs="*", help="subset of fields to score")
    args = ap.parse_args()
    result = verify_peptide(seq=args.seq, smiles=args.smiles, identifier=args.identifier,
                            physics_json=args.physics_json, only=args.only)
    print(json.dumps(result.to_dict(), indent=2))
