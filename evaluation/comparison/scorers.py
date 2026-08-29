#!/usr/bin/env python3
"""
Phase-1 truth-set scorers for the cross-system comparison (CPU + DB-search tier).

Each scorer is a PURE FUNCTION over a system's produced `output` plus a
`truth_ref` (the task reference / gold set). No network, no API calls, no file
downloads, no spend — standard libs + numpy/scipy/pandas/sklearn only.

Contract
--------
    score_<TID>(output, truth_ref) -> {"rung": "R0".."R5", "score": float, "detail": str}

Where the rung ladder mirrors run_phase1.LADDER:
    R0  produced nothing usable / refused / wrong domain
    R1  named the right design but no numeric result
    R2  runnable artifact (not scored numerically here)
    R3  EXECUTED but wrong, OR executed and no real truth-set is wired
    R4  CORRECT within tolerance of the task truth metric
    R5  governed/reproducible (out of scope for a pure metric scorer; not emitted)

Honesty rule
------------
A scorer that ran but has NO real reference available returns R3 with detail
"executed; truth-set not wired" — never a fabricated R4.

`output` is the loosely-typed thing a system produced (dict-of-values, list of
records, etc.). Every scorer is defensive: a missing / empty / non-numeric
output degrades to R0/R1, never a crash.
"""
from __future__ import annotations

import math
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

try:  # scipy is allowed and available; guard so import never hard-fails a scorer file load
    from scipy.stats import spearmanr, pearsonr
    _HAVE_SCIPY = True
except Exception:  # pragma: no cover
    _HAVE_SCIPY = False


# --------------------------------------------------------------------------- utils
def _result(rung: str, score: float, detail: str) -> Dict[str, Any]:
    return {"rung": rung, "score": float(score), "detail": detail}


def _empty(output: Any) -> bool:
    if output is None:
        return True
    if isinstance(output, (list, tuple, dict, set, str)) and len(output) == 0:
        return True
    return False


def _spearman(x: Sequence[float], y: Sequence[float]) -> float:
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    if x.size < 3 or y.size < 3 or x.size != y.size:
        return float("nan")
    if _HAVE_SCIPY:
        rho, _ = spearmanr(x, y)
        return float(rho)
    # fallback: pearson on ranks
    xr = np.argsort(np.argsort(x)).astype(float)
    yr = np.argsort(np.argsort(y)).astype(float)
    return _pearson(xr, yr)


def _pearson(x: Sequence[float], y: Sequence[float]) -> float:
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    if x.size < 3 or y.size < 3 or x.size != y.size:
        return float("nan")
    if np.std(x) == 0 or np.std(y) == 0:
        return float("nan")
    if _HAVE_SCIPY:
        r, _ = pearsonr(x, y)
        return float(r)
    return float(np.corrcoef(x, y)[0, 1])


def _align(pred_map: Dict[str, float], ref_map: Dict[str, float]) -> Tuple[List[float], List[float], List[str]]:
    keys = [k for k in ref_map if k in pred_map]
    p, r = [], []
    for k in keys:
        try:
            pv, rv = float(pred_map[k]), float(ref_map[k])
        except (TypeError, ValueError):
            continue
        if math.isnan(pv) or math.isnan(rv):
            continue
        p.append(pv)
        r.append(rv)
    return p, r, keys


def _jaccard(a: set, b: set) -> float:
    if not a and not b:
        return 0.0
    return len(a & b) / len(a | b)


# --------------------------------------------------------------------------- T01
def score_T01(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T01 — DESeq2 concordance vs SEQC/ERCC known fold-changes.

    Metric: Spearman (primary) + Pearson of predicted log2FC vs reference log2FC,
    matched by gene/spike-in id. R4 if Spearman >= 0.7.

    output   : {"logfc": {gene_id: log2fc}}  (or the mapping itself)
    truth_ref: {"logfc": {gene_id: log2fc}}  (SEQC/ERCC known truth) or None
    """
    pred = (output or {}).get("logfc", output) if isinstance(output, dict) else None
    if _empty(pred) or not isinstance(pred, dict):
        return _result("R0", 0.0, "no predicted log2FC produced")
    ref = None
    if isinstance(truth_ref, dict):
        ref = truth_ref.get("logfc", truth_ref)
    if _empty(ref) or not isinstance(ref, dict):
        return _result("R3", 0.0, "executed; truth-set not wired (no SEQC/ERCC reference)")
    p, r, keys = _align(pred, ref)
    if len(keys) < 3:
        return _result("R1", 0.0, f"executed but only {len(keys)} genes overlap reference; cannot score")
    rho = _spearman(p, r)
    rp = _pearson(p, r)
    rung = "R4" if (not math.isnan(rho) and rho >= 0.7) else "R3"
    return _result(rung, rho, f"Spearman={rho:.3f} Pearson={rp:.3f} on n={len(keys)} genes (R4 iff rho>=0.7)")


# --------------------------------------------------------------------------- T02
def score_T02(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T02 — hap.py SNV+indel F1 vs GIAB v4.2.1.

    Metric: parse a hap.py summary.csv-like dict; combined SNV+INDEL F1.
    R4 if both SNV F1 and INDEL F1 >= 0.95 (GIAB high-conf expectation).

    output   : {"SNP": {"METRIC.F1_Score": .., "METRIC.Recall":.., "METRIC.Precision":..},
                "INDEL": {...}}  — hap.py Type-indexed rows (PASS filter).
    truth_ref: {"snv_f1_min": 0.95, "indel_f1_min": 0.95} thresholds, or None to
               use defaults (GIAB is the gold set, so thresholds ARE the truth).
    """
    if _empty(output) or not isinstance(output, dict):
        return _result("R0", 0.0, "no hap.py summary produced")

    def _f1(row: Any) -> Optional[float]:
        if not isinstance(row, dict):
            return None
        for k in ("METRIC.F1_Score", "F1_Score", "f1", "F1"):
            if k in row:
                try:
                    return float(row[k])
                except (TypeError, ValueError):
                    return None
        rec = row.get("METRIC.Recall", row.get("Recall"))
        prec = row.get("METRIC.Precision", row.get("Precision"))
        try:
            rec, prec = float(rec), float(prec)
            if rec + prec == 0:
                return 0.0
            return 2 * rec * prec / (rec + prec)
        except (TypeError, ValueError):
            return None

    snv = _f1(output.get("SNP", output.get("SNV")))
    indel = _f1(output.get("INDEL", output.get("Indel")))
    if snv is None and indel is None:
        return _result("R1", 0.0, "executed but no parseable SNV/INDEL F1 in summary")
    thr = truth_ref or {}
    snv_min = float(thr.get("snv_f1_min", 0.95))
    indel_min = float(thr.get("indel_f1_min", 0.95))
    combined = np.nanmean([v for v in (snv, indel) if v is not None])
    ok = (snv is not None and snv >= snv_min) and (indel is not None and indel >= indel_min)
    rung = "R4" if ok else "R3"
    return _result(rung, float(combined),
                   f"SNV F1={snv} INDEL F1={indel} (thr SNV>={snv_min},INDEL>={indel_min}) -> {rung}")


# --------------------------------------------------------------------------- T03
def score_T03(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T03 — Jaccard overlap of called peaks vs ENCODE consensus.

    Metric: Jaccard of called-peak interval set vs ENCODE consensus set.
    Peaks compared by discretised region id (chrom, bin) or explicit ids.
    R4 if Jaccard >= 0.5 (typical ChIP replicate-consensus agreement floor).

    output   : list of peak ids/tuples, or {"peaks": [...]}
    truth_ref: list/set of consensus peak ids, or {"consensus": [...]} or None
    """
    peaks = output.get("peaks", output) if isinstance(output, dict) else output
    if _empty(peaks):
        return _result("R0", 0.0, "no peaks called")
    ref = None
    if isinstance(truth_ref, dict):
        ref = truth_ref.get("consensus", truth_ref.get("peaks"))
    else:
        ref = truth_ref
    if _empty(ref):
        return _result("R3", 0.0, "executed; truth-set not wired (no ENCODE consensus)")
    a = set(map(_hashable, peaks))
    b = set(map(_hashable, ref))
    j = _jaccard(a, b)
    thr = 0.5
    rung = "R4" if j >= thr else "R3"
    return _result(rung, j, f"Jaccard={j:.3f} on |pred|={len(a)} |ref|={len(b)} (R4 iff >= {thr})")


def _hashable(x: Any) -> Any:
    if isinstance(x, list):
        return tuple(x)
    return x


# --------------------------------------------------------------------------- T04
def score_T04(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T04 — UPS1 recall @FDR5% + yeast false-positive rate.

    Metric: of the UPS1 spike-in proteins that are truly differential, fraction
    called significant at FDR<=5% (recall); of yeast background proteins, fraction
    wrongly called (FPR). R4 if recall >= 0.5 AND FPR <= 0.05.

    output   : {"significant": [protein_ids called sig @FDR5%]}  (or list itself)
    truth_ref: {"ups1": [...true-positive ids...], "yeast": [...background ids...]}
    """
    sig = output.get("significant", output) if isinstance(output, dict) else output
    if _empty(sig):
        return _result("R0", 0.0, "no significant proteins produced")
    if not isinstance(truth_ref, dict) or _empty(truth_ref.get("ups1")):
        return _result("R3", 0.0, "executed; truth-set not wired (no UPS1/yeast reference)")
    sig_set = set(sig)
    ups1 = set(truth_ref.get("ups1", []))
    yeast = set(truth_ref.get("yeast", []))
    recall = len(sig_set & ups1) / len(ups1) if ups1 else float("nan")
    fpr = (len(sig_set & yeast) / len(yeast)) if yeast else float("nan")
    ok = (not math.isnan(recall) and recall >= 0.5) and (math.isnan(fpr) or fpr <= 0.05)
    rung = "R4" if ok else "R3"
    return _result(rung, float(recall),
                   f"UPS1 recall@FDR5%={recall:.3f} yeast FPR={fpr:.3f} (R4 iff recall>=0.5 & FPR<=0.05)")


# --------------------------------------------------------------------------- T05
def score_T05(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T05 — AMBER-style bin F1 vs CAMI gold bins.

    Metric: bin-level F1 computed from precision/completeness of predicted MAGs
    vs gold genome bins (best-match assignment on shared contigs). R4 if F1 >= 0.6.

    output   : {"bins": {bin_id: [contig_ids]}}  (predicted binning)
    truth_ref: {"gold": {genome_id: [contig_ids]}}  (CAMI gold)
    """
    pred = output.get("bins", output) if isinstance(output, dict) else output
    if _empty(pred) or not isinstance(pred, dict):
        return _result("R0", 0.0, "no bins produced")
    gold = truth_ref.get("gold") if isinstance(truth_ref, dict) else None
    if _empty(gold) or not isinstance(gold, dict):
        return _result("R3", 0.0, "executed; truth-set not wired (no CAMI gold bins)")

    gold_sets = {g: set(c) for g, c in gold.items()}
    precisions, recalls = [], []
    for _bid, contigs in pred.items():
        pset = set(contigs)
        if not pset:
            continue
        # best-matching gold genome for this predicted bin
        best_g, best_ov = None, 0
        for g, gset in gold_sets.items():
            ov = len(pset & gset)
            if ov > best_ov:
                best_ov, best_g = ov, g
        if best_g is None:
            precisions.append(0.0)
            continue
        precisions.append(best_ov / len(pset))              # purity
        recalls.append(best_ov / len(gold_sets[best_g]))    # completeness
    if not precisions:
        return _result("R1", 0.0, "executed but no contig overlap with gold")
    P = float(np.mean(precisions))
    R = float(np.mean(recalls)) if recalls else 0.0
    f1 = 0.0 if (P + R) == 0 else 2 * P * R / (P + R)
    rung = "R4" if f1 >= 0.6 else "R3"
    return _result(rung, f1, f"bin precision={P:.3f} completeness={R:.3f} F1={f1:.3f} (R4 iff F1>=0.6)")


# --------------------------------------------------------------------------- T07
def score_T07(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T07 — single-cell cluster-marker overlap + pseudobulk DE presence.

    Metric (two-part):
      (a) Jaccard of predicted cluster markers vs canonical PBMC marker panel.
      (b) presence of a pseudobulk/pseudoreplication-guarded DE result.
    R4 if marker Jaccard >= 0.3 AND a non-empty pseudobulk DE table is present.

    output   : {"markers": [gene ids], "pseudobulk_de": [rows] or truthy}
    truth_ref: {"canonical_markers": [gene ids]} or None
    """
    if not isinstance(output, dict) or _empty(output):
        return _result("R0", 0.0, "no single-cell output produced")
    markers = output.get("markers", [])
    de_present = bool(output.get("pseudobulk_de"))
    canon = None
    if isinstance(truth_ref, dict):
        canon = truth_ref.get("canonical_markers")
    if _empty(canon):
        # DE presence alone can be checked but marker truth isn't wired
        if de_present and not _empty(markers):
            return _result("R3", 0.0, "executed; truth-set not wired (no canonical marker panel)")
        return _result("R3", 0.0, "executed; truth-set not wired (no canonical marker panel)")
    j = _jaccard(set(markers), set(canon))
    ok = (j >= 0.3) and de_present
    rung = "R4" if ok else "R3"
    return _result(rung, j,
                   f"marker Jaccard={j:.3f} pseudobulk_DE_present={de_present} (R4 iff J>=0.3 & DE present)")


# --------------------------------------------------------------------------- T09
def score_T09(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T09 — ADMET screen + auto-loop.

    Metric (three-part, honesty-weighted):
      (1) endpoint-value agreement: mean-absolute-error vs reference endpoint
          values, converted to an agreement score (1 - normalised MAE).
      (2) gate-correctness: hERG / DILI risk flags match reference risk calls.
      (3) remediation applied: the C16->C4 (or any) remediation was performed.
    R4 iff gate-correctness == 1.0 AND remediation applied AND endpoint agreement
    >= 0.7 (when a reference is wired). Gate-correctness is the dominant signal.

    output   : {"endpoints": {name: value}, "herg_flag": bool, "dili_flag": bool,
                "remediation_applied": bool}
    truth_ref: {"endpoints": {name: value}, "herg_flag": bool, "dili_flag": bool}
    """
    if not isinstance(output, dict) or _empty(output):
        return _result("R0", 0.0, "no ADMET output produced")
    ep = output.get("endpoints", {})
    remediated = bool(output.get("remediation_applied"))
    if not isinstance(truth_ref, dict) or _empty(truth_ref):
        # We can still assess remediation presence, but not correctness.
        return _result("R3", 0.0, "executed; truth-set not wired (no ADMET reference values/flags)")

    # (2) gate correctness
    gate_checks, gate_ok = 0, 0
    for flag in ("herg_flag", "dili_flag"):
        if flag in truth_ref:
            gate_checks += 1
            if bool(output.get(flag)) == bool(truth_ref[flag]):
                gate_ok += 1
    gate_correct = (gate_ok / gate_checks) if gate_checks else float("nan")

    # (1) endpoint agreement
    ref_ep = truth_ref.get("endpoints", {})
    p, r, keys = _align(ep if isinstance(ep, dict) else {}, ref_ep if isinstance(ref_ep, dict) else {})
    if len(keys) >= 1:
        denom = np.maximum(np.abs(np.asarray(r)), 1e-9)
        mae_norm = float(np.mean(np.abs(np.asarray(p) - np.asarray(r)) / denom))
        agreement = max(0.0, 1.0 - mae_norm)
    else:
        agreement = float("nan")

    ep_ok = math.isnan(agreement) or agreement >= 0.7
    gate_full = (gate_checks > 0 and gate_ok == gate_checks)
    ok = gate_full and remediated and ep_ok
    rung = "R4" if ok else "R3"
    score = 0.0 if math.isnan(gate_correct) else gate_correct
    return _result(rung, score,
                   f"gate_correct={gate_correct} endpoint_agreement={agreement} "
                   f"remediation_applied={remediated} (R4 iff gate==1 & remediated & agreement>=0.7)")


# --------------------------------------------------------------------------- T11
def score_T11(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T11 — AutoDock Vina score ranking correlation vs known actives/decoys.

    Metric: Spearman of predicted Vina scores (more-negative = better) against a
    reference activity ordering, OR (preferred when labels are actives/decoys)
    a rank-based separation. We compute Spearman of -vina vs reference potency.
    R4 if |rho| >= 0.5 with the expected sign.

    output   : {"scores": {ligand_id: vina_kcal_mol}}  (lower = better binder)
    truth_ref: {"potency": {ligand_id: value}}  (higher = more active) or
               {"actives": [...], "decoys": [...]} or None
    """
    scores = output.get("scores", output) if isinstance(output, dict) else output
    if _empty(scores) or not isinstance(scores, dict):
        return _result("R0", 0.0, "no Vina scores produced")
    if not isinstance(truth_ref, dict) or _empty(truth_ref):
        return _result("R3", 0.0, "executed; truth-set not wired (no actives/decoys reference)")

    if "potency" in truth_ref and isinstance(truth_ref["potency"], dict):
        # -vina should correlate positively with potency
        keys = [k for k in truth_ref["potency"] if k in scores]
        if len(keys) < 3:
            return _result("R1", 0.0, f"only {len(keys)} ligands overlap reference; cannot rank")
        neg_vina = [-float(scores[k]) for k in keys]
        pot = [float(truth_ref["potency"][k]) for k in keys]
        rho = _spearman(neg_vina, pot)
        rung = "R4" if (not math.isnan(rho) and abs(rho) >= 0.5 and rho > 0) else "R3"
        return _result(rung, rho, f"Spearman(-vina, potency)={rho:.3f} on n={len(keys)} (R4 iff >=0.5)")

    actives = set(truth_ref.get("actives", []))
    decoys = set(truth_ref.get("decoys", []))
    if not actives or not decoys:
        return _result("R3", 0.0, "executed; truth-set not wired (no actives/decoys reference)")
    act_scores = [float(scores[k]) for k in actives if k in scores]
    dec_scores = [float(scores[k]) for k in decoys if k in scores]
    if not act_scores or not dec_scores:
        return _result("R1", 0.0, "no overlap between scored ligands and labelled sets")
    # actives should be MORE negative than decoys -> lower mean
    sep = float(np.mean(dec_scores) - np.mean(act_scores))  # >0 is correct direction
    rung = "R4" if sep > 0 else "R3"
    return _result(rung, sep,
                   f"mean(decoy)-mean(active)={sep:.3f} kcal/mol (R4 iff actives more negative)")


# --------------------------------------------------------------------------- T13
def score_T13(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T13 — BOIN phase-1 design: boundary table + correct-MTD % vs simulation.

    Metric: (a) boundary table matches the BOIN lambda_e/lambda_d escalation/
    de-escalation boundaries for target toxicity; (b) correct-MTD selection % from
    the reported simulation. R4 if correct-MTD% >= reference (default 0.5) AND the
    boundary table is present and consistent (escalate_bd < deescalate_bd).

    This is a pure-reasoning task — BOIN boundaries are deterministic given the
    target rate, so the truth is computable without external data.

    output   : {"boundary_table": {"escalate": p_e, "deescalate": p_d} or rows,
                "correct_mtd_pct": float}
    truth_ref: {"target_tox": 0.30, "correct_mtd_min": 0.5} or None (defaults used)
    """
    if not isinstance(output, dict) or _empty(output):
        return _result("R0", 0.0, "no BOIN design produced")
    bt = output.get("boundary_table")
    cmtd = output.get("correct_mtd_pct")
    thr = truth_ref or {}
    target = float(thr.get("target_tox", 0.30))
    cmtd_min = float(thr.get("correct_mtd_min", 0.5))

    # boundary consistency: escalate boundary must be below de-escalate boundary,
    # and both bracket the target toxicity.
    esc = dsc = None
    if isinstance(bt, dict):
        esc = bt.get("escalate", bt.get("lambda_e"))
        dsc = bt.get("deescalate", bt.get("lambda_d"))
    boundary_ok = False
    if esc is not None and dsc is not None:
        try:
            esc, dsc = float(esc), float(dsc)
            boundary_ok = (esc < dsc) and (esc <= target <= dsc)
        except (TypeError, ValueError):
            boundary_ok = False

    if cmtd is None:
        rung = "R3"
        return _result(rung, 0.0, f"boundary_ok={boundary_ok} but no correct_mtd_pct reported")
    try:
        cmtd = float(cmtd)
    except (TypeError, ValueError):
        return _result("R1", 0.0, "correct_mtd_pct not numeric")
    ok = boundary_ok and cmtd >= cmtd_min
    rung = "R4" if ok else "R3"
    return _result(rung, cmtd,
                   f"boundary_ok={boundary_ok} (esc={esc},desc={dsc},target={target}) "
                   f"correct_MTD%={cmtd:.3f} (R4 iff boundary_ok & >= {cmtd_min})")


# --------------------------------------------------------------------------- T15
def score_T15(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T15 — GWAS->scRNA->eQTL target chain: CTSH in top-k AND PP4 >= threshold.

    Metric: is the expected causal gene (CTSH) present in the top-k candidate list
    AND does its colocalisation PP4 meet the threshold (default 0.8)?
    R4 iff both conditions hold.

    output   : {"top_candidates": [gene ids in ranked order], "pp4": {gene: pp4}}
    truth_ref: {"expected_gene": "CTSH", "top_k": 10, "pp4_min": 0.8} or None
    """
    if not isinstance(output, dict) or _empty(output):
        return _result("R0", 0.0, "no target chain output produced")
    thr = truth_ref or {}
    gene = thr.get("expected_gene", "CTSH")
    top_k = int(thr.get("top_k", 10))
    pp4_min = float(thr.get("pp4_min", 0.8))

    cands = output.get("top_candidates", [])
    pp4_map = output.get("pp4", {})
    if _empty(cands):
        return _result("R1", 0.0, "executed but no candidate list produced")
    in_top = gene in list(cands)[:top_k]
    rank = list(cands).index(gene) + 1 if gene in cands else None
    pp4 = None
    if isinstance(pp4_map, dict):
        try:
            pp4 = float(pp4_map.get(gene)) if pp4_map.get(gene) is not None else None
        except (TypeError, ValueError):
            pp4 = None
    pp4_ok = (pp4 is not None and pp4 >= pp4_min)
    ok = in_top and pp4_ok
    rung = "R4" if ok else "R3"
    return _result(rung, float(pp4 or 0.0),
                   f"{gene} rank={rank} in_top{top_k}={in_top} PP4={pp4} "
                   f"(R4 iff in_top & PP4>={pp4_min})")


# --------------------------------------------------------------------------- T16
def score_T16(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T16 — MOFA2 vs SNF: MOFA2 IGHV AUC vs SNF ARI (both reported).

    Metric: both an MOFA2 factor->IGHV classification AUC AND an SNF cluster ARI
    (vs IGHV labels) must be reported and in valid range. R4 iff both present,
    MOFA2 AUC >= 0.75, and the head-to-head direction is reported (AUC vs ARI both
    numeric). This is a "did the comparison actually run and produce both arms"
    check plus a quality floor on the MOFA2 arm.

    output   : {"mofa2_ighv_auc": float, "snf_ighv_ari": float}
    truth_ref: {"mofa2_auc_min": 0.75} or None
    """
    if not isinstance(output, dict) or _empty(output):
        return _result("R0", 0.0, "no MOFA2/SNF output produced")
    auc = output.get("mofa2_ighv_auc")
    ari = output.get("snf_ighv_ari")

    def _num(x):
        try:
            return float(x)
        except (TypeError, ValueError):
            return None
    auc, ari = _num(auc), _num(ari)
    if auc is None and ari is None:
        return _result("R1", 0.0, "executed but neither MOFA2 AUC nor SNF ARI reported")
    if auc is None or ari is None:
        return _result("R3", 0.0,
                       f"only one arm reported (MOFA2 AUC={auc}, SNF ARI={ari}); comparison incomplete")
    thr = truth_ref or {}
    auc_min = float(thr.get("mofa2_auc_min", 0.75))
    valid = (0.0 <= auc <= 1.0) and (-1.0 <= ari <= 1.0)
    ok = valid and auc >= auc_min
    rung = "R4" if ok else "R3"
    return _result(rung, auc,
                   f"MOFA2 IGHV AUC={auc:.3f} vs SNF ARI={ari:.3f} (R4 iff both reported & AUC>={auc_min})")


# --------------------------------------------------------------------------- T17
def score_T17(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T17 — foldseek sensitivity-to-1st-FP vs SCOPe superfamily labels.

    Metric: for each query, walk the ranked hit list; count true-positive hits
    (same SCOPe superfamily) accumulated BEFORE the first false-positive (different
    superfamily / different fold). Sensitivity = TPs-before-1st-FP / total possible
    superfamily members. Report mean over queries. R4 if mean sensitivity >= 0.5.

    output   : {query_id: [ranked hit ids]}  (ranked best->worst)
    truth_ref: {"labels": {id: superfamily}, "members": {superfamily: count}} or None
    """
    hits = output.get("hits", output) if isinstance(output, dict) else output
    if _empty(hits) or not isinstance(hits, dict):
        return _result("R0", 0.0, "no foldseek hit lists produced")
    if not isinstance(truth_ref, dict) or _empty(truth_ref.get("labels")):
        return _result("R3", 0.0, "executed; truth-set not wired (no SCOPe superfamily labels)")

    labels = truth_ref["labels"]
    members = truth_ref.get("members", {})
    sens_vals = []
    for q, ranked in hits.items():
        q_sf = labels.get(q)
        if q_sf is None:
            continue
        total = members.get(q_sf)
        if total is None:
            # infer total from label table (exclude self)
            total = sum(1 for i, sf in labels.items() if sf == q_sf and i != q)
        if not total:
            continue
        tp_before_fp = 0
        for h in ranked:
            if h == q:
                continue
            h_sf = labels.get(h)
            if h_sf == q_sf:
                tp_before_fp += 1
            else:
                break  # first false positive
        sens_vals.append(tp_before_fp / total)
    if not sens_vals:
        return _result("R1", 0.0, "executed but no query overlapped the label set")
    mean_sens = float(np.mean(sens_vals))
    rung = "R4" if mean_sens >= 0.5 else "R3"
    return _result(rung, mean_sens,
                   f"mean sensitivity-to-1st-FP={mean_sens:.3f} over {len(sens_vals)} queries (R4 iff >=0.5)")


# --------------------------------------------------------------------------- T18
def score_T18(output: Any, truth_ref: Any) -> Dict[str, Any]:
    """T18 — mmseqs2/diamond homolog recall + precision vs Pfam family membership.

    Metric: treating same-Pfam-family sequences as true homologs, compute recall
    (fraction of true family members retrieved) and precision (fraction of hits that
    are true family members), pooled over queries. R4 if F1(recall,precision) >= 0.7.

    output   : {query_id: [hit ids]}  (or {"hits": {...}})
    truth_ref: {"family": {seq_id: pfam_family}} or None
    """
    hits = output.get("hits", output) if isinstance(output, dict) else output
    if _empty(hits) or not isinstance(hits, dict):
        return _result("R0", 0.0, "no homology hit lists produced")
    fam = truth_ref.get("family") if isinstance(truth_ref, dict) else None
    if _empty(fam) or not isinstance(fam, dict):
        return _result("R3", 0.0, "executed; truth-set not wired (no Pfam family membership)")

    tp = fp = fn = 0
    scored_any = False
    for q, hitlist in hits.items():
        q_fam = fam.get(q)
        if q_fam is None:
            continue
        scored_any = True
        true_members = {i for i, f in fam.items() if f == q_fam and i != q}
        retrieved = {h for h in hitlist if h != q}
        tp += len(retrieved & true_members)
        fp += len(retrieved - true_members)
        fn += len(true_members - retrieved)
    if not scored_any:
        return _result("R1", 0.0, "executed but no query overlapped the family table")
    recall = tp / (tp + fn) if (tp + fn) else float("nan")
    precision = tp / (tp + fp) if (tp + fp) else float("nan")
    if math.isnan(recall) or math.isnan(precision) or (recall + precision) == 0:
        f1 = 0.0
    else:
        f1 = 2 * recall * precision / (recall + precision)
    rung = "R4" if f1 >= 0.7 else "R3"
    return _result(rung, f1,
                   f"recall={recall:.3f} precision={precision:.3f} F1={f1:.3f} (R4 iff F1>=0.7)")


# --------------------------------------------------------------------------- registry
REGISTRY: Dict[str, Callable[[Any, Any], Dict[str, Any]]] = {
    "T01": score_T01,
    "T02": score_T02,
    "T03": score_T03,
    "T04": score_T04,
    "T05": score_T05,
    "T07": score_T07,
    "T09": score_T09,
    "T11": score_T11,
    "T13": score_T13,
    "T15": score_T15,
    "T16": score_T16,
    "T17": score_T17,
    "T18": score_T18,
}


# --------------------------------------------------------------------------- self-test
def _selftest() -> int:
    """Synthetic, in-memory inputs for every scorer. No files, no network.

    Each case asserts: (a) the returned rung is a valid ladder rung, (b) for a
    "good" synthetic output the scorer reaches R4, (c) for an empty output it
    degrades to R0, (d) for executed-but-no-reference it returns R3.
    """
    VALID_RUNGS = {"R0", "R1", "R2", "R3", "R4", "R5"}

    def _assert_valid(tid, res):
        assert isinstance(res, dict), f"{tid}: result not a dict"
        assert res["rung"] in VALID_RUNGS, f"{tid}: bad rung {res['rung']}"
        assert isinstance(res["score"], float), f"{tid}: score not float"
        assert isinstance(res["detail"], str) and res["detail"], f"{tid}: no detail"
        return res

    results = {}

    # T01 — perfectly correlated logFC -> R4; empty -> R0; no ref -> R3
    genes = [f"g{i}" for i in range(20)]
    ref_lfc = {g: float(i) - 10 for i, g in enumerate(genes)}
    pred_lfc = {g: v + np.random.default_rng(0).normal(0, 0.1) for g, v in ref_lfc.items()}
    r = _assert_valid("T01", score_T01({"logfc": pred_lfc}, {"logfc": ref_lfc}))
    assert r["rung"] == "R4", r
    assert score_T01(None, {"logfc": ref_lfc})["rung"] == "R0"
    assert score_T01({"logfc": pred_lfc}, None)["rung"] == "R3"
    results["T01"] = r

    # T02 — high F1 both types -> R4
    good = {"SNP": {"METRIC.F1_Score": 0.995}, "INDEL": {"METRIC.F1_Score": 0.98}}
    r = _assert_valid("T02", score_T02(good, None))
    assert r["rung"] == "R4", r
    assert score_T02({"SNP": {"METRIC.F1_Score": 0.5}, "INDEL": {"METRIC.F1_Score": 0.4}}, None)["rung"] == "R3"
    assert score_T02(None, None)["rung"] == "R0"
    # recall/precision fallback path
    _assert_valid("T02b", score_T02({"SNP": {"METRIC.Recall": 0.99, "METRIC.Precision": 0.99},
                                     "INDEL": {"METRIC.Recall": 0.98, "METRIC.Precision": 0.99}}, None))
    results["T02"] = r

    # T03 — high Jaccard -> R4
    consensus = [("chr1", i) for i in range(100)]
    pred_peaks = [("chr1", i) for i in range(90)]  # 90 shared, 10 missing -> J=90/100
    r = _assert_valid("T03", score_T03({"peaks": pred_peaks}, {"consensus": consensus}))
    assert r["rung"] == "R4", r
    assert score_T03([], consensus)["rung"] == "R0"
    assert score_T03(pred_peaks, None)["rung"] == "R3"
    results["T03"] = r

    # T04 — recall high, FPR low -> R4
    truth = {"ups1": [f"UPS{i}" for i in range(10)], "yeast": [f"Y{i}" for i in range(100)]}
    sig = [f"UPS{i}" for i in range(8)] + ["Y0", "Y1"]  # 8/10 recall, 2/100 FPR
    r = _assert_valid("T04", score_T04({"significant": sig}, truth))
    assert r["rung"] == "R4", r
    assert score_T04(None, truth)["rung"] == "R0"
    assert score_T04(sig, None)["rung"] == "R3"
    results["T04"] = r

    # T05 — clean bins -> R4
    gold = {"G1": [f"c{i}" for i in range(50)], "G2": [f"d{i}" for i in range(50)]}
    pred_bins = {"b1": [f"c{i}" for i in range(48)], "b2": [f"d{i}" for i in range(47)]}
    r = _assert_valid("T05", score_T05({"bins": pred_bins}, {"gold": gold}))
    assert r["rung"] == "R4", r
    assert score_T05(None, {"gold": gold})["rung"] == "R0"
    assert score_T05(pred_bins, None)["rung"] == "R3"
    results["T05"] = r

    # T07 — marker overlap + DE present -> R4
    canon = [f"MK{i}" for i in range(10)]
    out = {"markers": [f"MK{i}" for i in range(6)] + ["X", "Y"], "pseudobulk_de": [{"gene": "A"}]}
    r = _assert_valid("T07", score_T07(out, {"canonical_markers": canon}))
    assert r["rung"] == "R4", r
    assert score_T07({}, {"canonical_markers": canon})["rung"] == "R0"
    assert score_T07(out, None)["rung"] == "R3"
    results["T07"] = r

    # T09 — gates correct + remediated + endpoints agree -> R4
    ref_ep = {"logP": 2.0, "solubility": -3.0, "hERG_pIC50": 5.0}
    out09 = {"endpoints": {"logP": 2.05, "solubility": -3.1, "hERG_pIC50": 5.02},
             "herg_flag": True, "dili_flag": False, "remediation_applied": True}
    truth09 = {"endpoints": ref_ep, "herg_flag": True, "dili_flag": False}
    r = _assert_valid("T09", score_T09(out09, truth09))
    assert r["rung"] == "R4", r
    # wrong gate -> R3
    bad09 = dict(out09, herg_flag=False)
    assert score_T09(bad09, truth09)["rung"] == "R3"
    assert score_T09(None, truth09)["rung"] == "R0"
    assert score_T09(out09, None)["rung"] == "R3"
    results["T09"] = r

    # T11 — actives more negative than decoys -> R4 (actives/decoys path)
    scores11 = {**{f"a{i}": -9.0 - i * 0.1 for i in range(5)},
                **{f"d{i}": -5.0 + i * 0.1 for i in range(5)}}
    truth11 = {"actives": [f"a{i}" for i in range(5)], "decoys": [f"d{i}" for i in range(5)]}
    r = _assert_valid("T11", score_T11({"scores": scores11}, truth11))
    assert r["rung"] == "R4", r
    # potency path
    pot = {"potency": {k: -v for k, v in scores11.items()}}  # more negative vina -> higher potency
    _assert_valid("T11b", score_T11({"scores": scores11}, pot))
    assert score_T11(None, truth11)["rung"] == "R0"
    assert score_T11({"scores": scores11}, None)["rung"] == "R3"
    results["T11"] = r

    # T13 — consistent boundary + high correct-MTD -> R4 (pure reasoning)
    out13 = {"boundary_table": {"escalate": 0.24, "deescalate": 0.36}, "correct_mtd_pct": 0.62}
    r = _assert_valid("T13", score_T13(out13, {"target_tox": 0.30, "correct_mtd_min": 0.5}))
    assert r["rung"] == "R4", r
    assert score_T13(dict(out13, correct_mtd_pct=0.3), None)["rung"] == "R3"
    assert score_T13(None, None)["rung"] == "R0"
    results["T13"] = r

    # T15 — CTSH in top-k and PP4 high -> R4
    out15 = {"top_candidates": ["FOO", "CTSH", "BAR"], "pp4": {"CTSH": 0.86}}
    r = _assert_valid("T15", score_T15(out15, {"expected_gene": "CTSH", "top_k": 10, "pp4_min": 0.8}))
    assert r["rung"] == "R4", r
    assert score_T15({"top_candidates": ["FOO"], "pp4": {}}, None)["rung"] == "R3"  # CTSH absent
    assert score_T15(None, None)["rung"] == "R0"
    results["T15"] = r

    # T16 — both arms reported, MOFA2 AUC high -> R4
    out16 = {"mofa2_ighv_auc": 0.91, "snf_ighv_ari": 0.375}
    r = _assert_valid("T16", score_T16(out16, {"mofa2_auc_min": 0.75}))
    assert r["rung"] == "R4", r
    assert score_T16({"mofa2_ighv_auc": 0.91}, None)["rung"] == "R3"  # one arm only
    assert score_T16(None, None)["rung"] == "R0"
    results["T16"] = r

    # T17 — many TPs before first FP -> R4
    labels = {}
    members = {}
    for sf in ("SF1", "SF2"):
        for i in range(6):
            labels[f"{sf}_{i}"] = sf
        members[sf] = 5  # 5 other members besides the query
    hits17 = {"SF1_0": ["SF1_1", "SF1_2", "SF1_3", "SF1_4", "SF1_5", "SF2_0"]}  # 5 TP then FP
    r = _assert_valid("T17", score_T17({"hits": hits17}, {"labels": labels, "members": members}))
    assert r["rung"] == "R4", r
    assert score_T17({}, {"labels": labels})["rung"] == "R0"
    assert score_T17(hits17, None)["rung"] == "R3"
    results["T17"] = r

    # T18 — high recall+precision -> R4
    family = {}
    for pf in ("PF1", "PF2"):
        for i in range(5):
            family[f"{pf}_{i}"] = pf
    hits18 = {"PF1_0": ["PF1_1", "PF1_2", "PF1_3", "PF1_4"]}  # all 4 true members, no FP
    r = _assert_valid("T18", score_T18({"hits": hits18}, {"family": family}))
    assert r["rung"] == "R4", r
    assert score_T18({}, {"family": family})["rung"] == "R0"
    assert score_T18(hits18, None)["rung"] == "R3"
    results["T18"] = r

    # every scorer in REGISTRY was exercised
    assert set(REGISTRY) == set(results), (
        f"REGISTRY/self-test mismatch: {set(REGISTRY) ^ set(results)}")

    print("SELF-TEST PASSED — all", len(REGISTRY), "scorers return valid rungs offline.\n")
    for tid in sorted(results):
        res = results[tid]
        print(f"  {tid}: {res['rung']}  score={res['score']:.3f}  {res['detail']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_selftest())
