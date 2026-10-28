"""renal_objective.py — predicted kidney retention for DESIGN CANDIDATES, for use as an OPTIONAL selector objective.

Uses the mechanistic grey-box (renal_mechmodel) fit on the whole seed corpus; the candidate enters through its net charge with the chelate (two saturable routes),
the radiometal (residualising or not), albumin binder and timepoint. Prediction = log1p(kidney %ID/g) at t_h hours; LOWER is better (the selector maximises its negative).

STATUS: UNVALIDATED. Gate A (surrogate must beat net charge alone on >= 50 held-out constructs) was not passed and cross-target generalisation is not supported (see docs/20261022_RENAL_PREDICTOR_MANUSCRIPT.md).
For a peptide candidate the prediction is driven by charge, i.e. it re-encodes the field heuristic; it must not be read as a measured or validated retention estimate.
Chemistry assumption: when the candidate has a lysine, the chelator is conjugated through it, which removes that side-chain's +1 charge (applied once). Unparsable input or an unknown (chelator, metal) charge gives NaN, never a guess."""
import os, sys, math
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import renal_mechmodel as mm
import renal_features as rf

STATUS = {"validated": False, "reason": "Gate A not passed; cross-target generalisation not supported; prediction is charge-driven"}
_PARAMS = None


def _params():
    global _PARAMS
    if _PARAMS is None:
        _PARAMS = mm.fit(mm.build_observations())
    return _PARAMS


def predict_kidney(seqs, chelator="DOTA", radiometal="177Lu", t_h=4.0, albumin_binder=False, cyclic_headtail=True, lys_conjugated=True):
    params = _params(); out = []
    for s in seqs:
        if not isinstance(s, str) or not s.isalpha():
            out.append(float("nan")); continue
        f = rf.featurize(s, chelator, cyclic_headtail, radiometal)
        if f is None:
            out.append(float("nan")); continue
        q = f.net_charge_with_chelate - (1.0 if (lys_conjugated and "K" in s.upper()) else 0.0)
        obs = {"q_pos": max(q, 0.0), "q_neg": max(-q, 0.0), "residual": 1.0 if radiometal in mm._RESIDUALIZING else 0.0,
               "alb": 1.0 if albumin_binder else 0.0, "cleave": 0.0, "log_t": math.log(t_h), "is_sm": 0.0}
        out.append(float(mm.predict(params, [obs])[0]))
    return np.array(out)


def informative(pred, min_sd=0.05):
    """Can this objective discriminate between candidates? Returns (sd of finite predictions in log1p units, bool sd >= min_sd). A flat objective changes no ranking."""
    v = np.asarray(pred, float); v = v[np.isfinite(v)]
    if len(v) < 2:
        return 0.0, False
    sd = float(v.std()); return sd, bool(sd >= min_sd)
