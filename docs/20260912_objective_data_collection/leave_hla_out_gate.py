#!/usr/bin/env python3
"""leave_hla_out_gate.py — the DECISION-GATE harness that tests whether the widened H4
(presentation) thesis GENERALIZES ACROSS HLA BACKGROUNDS. This gate sizes any future CRO spend.

BACKGROUND (see OBJECTIVES.md §8.2 kill-gate):
  H4 thesis = presentation is controlled by antigen-processing MACHINERY STATE, not by
  source-protein abundance. Already validated on ONE line/HLA background (HAP1, PXD056426):
  B2M-KO -> 2% presentation while the matched proteome stays ~100%; the B1 baseline
  ("presentation proportional to source abundance") is INVERTED (Spearman rho = -0.51),
  and machinery essentials lose ~87pp of presentation BEYOND what abundance explains.
  The open question this harness answers: does that machinery->presentation relationship
  TRANSFER to HLA backgrounds it was not learned on? That is the generalization gate.

WHAT THIS HARNESS COMPUTES, PER DEPOSIT (each deposit == one HLA background):
  (B1) baseline  : Spearman(presentation_frac_of_WT, proteome_frac_of_WT) across KO conditions.
                   B1 "works" if presentation tracks source abundance (positive rho).
  (H4) metric    : presentation_loss_beyond_abundance = proteome_frac - immunopeptidome_frac,
                   per KO. The mean over MACHINERY ESSENTIALS is the discriminative effect
                   ("beyond-abundance" loss). H4 "wins" locally when essentials lose large
                   POSITIVE beyond-abundance (protein still there, peptide gone) AND B1 rho
                   is not the explanation (rho <= 0 or beyond-abundance >> 0).

ACROSS DEPOSITS (the actual generalization gate):
  (LOO) leave-HLA-out CV : hold out each HLA background; fit machinery-KO -> presentation-loss
                   on the OTHER backgrounds; predict the held-out background; score transfer
                   (Spearman of predicted vs observed loss ranking on the held-out HLA bg).
  (NULL) permutation null : shuffle the KO<->presentation-loss labels within each training
                   background; re-run LOO; the real transfer must beat the null band.
  (LEAK) leakage check : the predictor uses ONLY the KO gene identity's machinery role
                   (an HLA-agnostic feature), never the held-out deposit's own peptides ->
                   confirms transfer is machinery-driven, not deposit memorization. Also
                   reports per-deposit HLA overlap to flag shared-allele leakage.

HOW IT RUNS ONCE MULTI-HLA AGGREGATION LANDS:
  Reads H4_CORPUS_INVENTORY.json (produced by the aggregation agent). Each entry supplies a
  deposit id, HLA background/genotype, hla_class, and a normalized per-condition table
  (columns: condition, immunopeptidome_frac, proteome_frac). If the inventory is absent, the
  harness runs on explicitly-passed deposit directories using built-in loaders (currently
  PXD056426 FragPipe/DIA-NN 'Search.zip'). This lets the harness be PROVEN on held data now
  and scale to the full corpus with no code change.

CRO SIZING RULE (the point of the whole thing):
  PASS  (LOO transfer beats permutation null on >=3 HLA backgrounds, class-consistent) ->
        the machinery->presentation relationship generalizes on PUBLIC data -> SHRINK the CRO:
        it only needs to fill genuinely missing HLA x KO cells / add absolute-quant, not
        re-establish the thesis.
  FAIL  (transfer indistinguishable from null, or only 1 background carries it) ->
        generalization is UNPROVEN on public data -> the CRO MUST supply the missing
        HLA x KO cells (>=3 distinct HLA backgrounds x the machinery-KO panel + matched
        proteome) before H4 can be trained/claimed cross-allele. This is the expensive path.

training_eligible = FALSE. This is an evaluation/decision harness, not a training artifact.
Honest caveats live in the emitted JSON ('caveats') and in LEAVE_HLA_OUT_GATE.md.

Usage:
  # inventory-driven (once aggregation lands):
  python leave_hla_out_gate.py --inventory H4_CORPUS_INVENTORY.json --out RESULT.json
  # dry-run on a held deposit dir (Search.zip present):
  python leave_hla_out_gate.py --deposit PXD056426=/path/to/PXD056426 --hla "HAP1_A*03:01" \
         --hla-class I --out DRYRUN.json
"""
import sys, os, csv, json, io, zipfile, argparse, math, random
from collections import defaultdict

def log(m): sys.stderr.write(f"[loho-gate] {m}\n"); sys.stderr.flush()

AA = set("ACDEFGHIKLMNPQRSTVWY")

# Antigen-processing machinery roles. "essential" = KO is expected to collapse presentation
# BEYOND abundance (the discriminative losers). This label is HLA-AGNOSTIC (gene identity only),
# which is exactly why using it as the transfer feature is NOT leakage of the held-out deposit.
MACHINERY_ESSENTIAL = {  # class-I core processing/loading essentials
    "B2M", "TAP1", "TAP2", "TAPBP", "ERAP1", "ERP57", "PDIA3", "CALR", "CANX",
    # class-II (for HLA-II deposits)
    "CIITA", "HLA-DM", "HLADM", "CD74", "CTSS", "CTSL",
}
MACHINERY_MODULATOR = {"IRF2", "SPPL3", "GIIA", "NLRC5", "IRF1"}  # regulators/secondary

# GRADED, HLA-AGNOSTIC machinery-severity prior: expected magnitude of presentation loss on
# KO, from the KNOWN role of the gene in the antigen-processing pathway (biology, not this
# corpus's numbers). Used ONLY as the cross-HLA transfer feature so the predictor can RANK
# within essentials (a flat essential/modulator flag ties every essential and makes the
# transfer Spearman uninformative). This is a prior, not a fit to any held-out deposit ->
# not leakage. Genes not listed fall back to their essential/modulator class score.
MACHINERY_SEVERITY = {
    # class-I: hard essentials (KO ~ ablates presentation) -> highest
    "B2M": 1.00, "TAP2": 0.90, "TAP1": 0.85, "TAPBP": 0.80, "ERP57": 0.70, "PDIA3": 0.70,
    "ERAP1": 0.55, "CANX": 0.30, "CALR": 0.25,
    # regulators / secondary (partial, indirect loss)
    "IRF2": 0.60, "NLRC5": 0.55, "IRF1": 0.50, "SPPL3": 0.35, "GIIA": 0.30,
    # class-II essentials
    "CIITA": 1.00, "HLA-DM": 0.85, "HLADM": 0.85, "CD74": 0.80, "CTSS": 0.55, "CTSL": 0.45,
}

def is_essential(ko):
    return ko.upper() in {g.upper() for g in MACHINERY_ESSENTIAL}

# ---------------------------------------------------------------------------
# stats helpers (no scipy dependency)
# ---------------------------------------------------------------------------
def rankdata(x):
    order = sorted(range(len(x)), key=lambda i: x[i])
    ranks = [0.0] * len(x)
    i = 0
    while i < len(x):
        j = i
        while j + 1 < len(x) and x[order[j + 1]] == x[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    return ranks

def spearman(a, b):
    if len(a) < 3 or len(a) != len(b):
        return None
    ra, rb = rankdata(a), rankdata(b)
    n = len(a)
    ma = sum(ra) / n; mb = sum(rb) / n
    num = sum((ra[i] - ma) * (rb[i] - mb) for i in range(n))
    da = math.sqrt(sum((ra[i] - ma) ** 2 for i in range(n)))
    db = math.sqrt(sum((rb[i] - mb) ** 2 for i in range(n)))
    if da == 0 or db == 0:
        return None
    return num / (da * db)

# ---------------------------------------------------------------------------
# Deposit loaders. Each returns a per-condition table:
#   {condition_upper: {"immunopeptidome_frac": float or None,
#                      "proteome_frac": float or None}}   (fraction of WT)
# Add new deposit formats here; the gate logic below is format-agnostic.
# ---------------------------------------------------------------------------
def _cond_for_run(run, cmap):
    run = str(run)
    if run in cmap:
        return cmap[run]
    for raw, c in cmap.items():
        stem = raw.rsplit("_R", 1)[0]
        if stem and (stem in run or run in raw):
            return c
    return None

def load_fragpipe_searchzip(deposit_dir):
    """PXD056426-style FragPipe/DIA-NN 'Search.zip': matched immunopeptidome (Search_results_DIA.tsv)
    + proteome (search_results_proteomics.tsv) + condition map (Raw_file_list.xlsx).
    Returns (table, meta). Computes fraction-of-WT for BOTH modalities on the SAME conditions."""
    import openpyxl
    zpath = os.path.join(deposit_dir, "Search.zip")
    zf = zipfile.ZipFile(zpath)
    names = zf.namelist()

    # --- condition maps from xlsx ---
    xlsx_name = [n for n in names if n.endswith("Raw_file_list.xlsx")][0]
    with zf.open(xlsx_name) as fh:
        wb = openpyxl.load_workbook(io.BytesIO(fh.read()), read_only=True, data_only=True)
    dia_map = {}
    ws = wb["immunopep_library_search"]
    for r in ws.iter_rows(min_row=2, values_only=True):
        cond, _, raw, _ = (list(r) + [None] * 4)[:4]
        if cond and raw:
            dia_map[str(raw).strip()] = str(cond).strip().upper()
    prot_map = {}
    if "proteomics" in wb.sheetnames:
        for r in wb["proteomics"].iter_rows(min_row=2, values_only=True):
            cond, _, raw = (list(r) + [None] * 3)[:3]
            if cond and raw:
                prot_map[str(raw).strip()] = str(cond).strip().upper()

    # --- immunopeptidome: unique QC'd peptides per condition (fraction of WT) ---
    dia_name = [n for n in names if n.endswith("Search_results_DIA.tsv")][0]
    pep_by_cond = defaultdict(set); seen = {}
    with zf.open(dia_name) as fh:
        rd = csv.reader(io.TextIOWrapper(fh, "utf-8"), delimiter="\t")
        hdr = next(rd); ci = {h: i for i, h in enumerate(hdr)}
        runc = ci.get("Run", ci.get("File.Name")); seqc = ci["Stripped.Sequence"]; qc = ci.get("Q.Value")
        maxidx = max(x for x in (runc, seqc) if x is not None)
        for row in rd:
            if len(row) <= maxidx:
                continue
            if qc is not None:
                try:
                    if float(row[qc]) > 0.01:
                        continue
                except Exception:
                    pass
            pep = row[seqc].strip().upper()
            if not (8 <= len(pep) <= 25) or any(a not in AA for a in pep):
                continue
            run = row[runc]
            c = seen.get(run)
            if c is None:
                c = _cond_for_run(run, dia_map); seen[run] = c
            if c is None:
                continue
            pep_by_cond[c].add(pep)
    dia_counts = {c: len(p) for c, p in pep_by_cond.items()}
    dia_wt = dia_counts.get("WT")
    if not dia_wt:
        dia_wt = max(dia_counts.values()) if dia_counts else None

    # --- proteome: summed spectral counts per condition (fraction of WT) ---
    prot_counts = defaultdict(float)
    prot_name = [n for n in names if n.endswith("search_results_proteomics.tsv")]
    if prot_name and prot_map:
        with zf.open(prot_name[0]) as fh:
            rd = csv.reader(io.TextIOWrapper(fh, "utf-8"), delimiter="\t")
            hdr = next(rd)
            # exact 'X Spectral Count' per-run cols that map to a condition
            col2cond = {}
            for j, h in enumerate(hdr):
                if h.endswith(" Spectral Count") and not h.startswith("Combined"):
                    stem = h[: -len(" Spectral Count")].strip()
                    if stem in prot_map:
                        col2cond[j] = prot_map[stem]
            for row in rd:
                for j, c in col2cond.items():
                    if j < len(row) and row[j] not in ("", None):
                        try:
                            prot_counts[c] += float(row[j])
                        except Exception:
                            pass
    prot_wt = prot_counts.get("WT")

    conds = set(dia_counts) | set(prot_counts)
    table = {}
    for c in conds:
        table[c] = {
            "immunopeptidome_frac": (round(dia_counts[c] / dia_wt, 4)
                                     if dia_wt and c in dia_counts else None),
            "proteome_frac": (round(prot_counts[c] / prot_wt, 4)
                              if prot_wt and c in prot_counts else None),
        }
    meta = {"loader": "fragpipe_searchzip",
            "dia_wt_peptides": int(dia_wt) if dia_wt else None,
            "prot_wt_spectral": round(prot_wt, 1) if prot_wt else None,
            "n_conditions": len(table),
            "has_matched_proteome": bool(prot_wt)}
    return table, meta

LOADERS = {"fragpipe_searchzip": load_fragpipe_searchzip}

def autoload_deposit(deposit_dir):
    if os.path.exists(os.path.join(deposit_dir, "Search.zip")):
        return load_fragpipe_searchzip(deposit_dir)
    raise ValueError(f"no known loader for deposit dir {deposit_dir} "
                     f"(supported: FragPipe Search.zip). Provide a normalized table via the inventory.")

# ---------------------------------------------------------------------------
# per-deposit B1 + H4
# ---------------------------------------------------------------------------
def compute_deposit_metrics(deposit_id, hla, hla_class, table):
    kos = [c for c in table if c != "WT"]
    pres = {c: table[c]["immunopeptidome_frac"] for c in kos}
    prot = {c: table[c]["proteome_frac"] for c in kos}

    # B1: presentation vs proteome-abundance Spearman (needs matched proteome)
    paired = [(c, pres[c], prot[c]) for c in kos
              if pres[c] is not None and prot[c] is not None]
    b1_rho = spearman([p for _, p, _ in paired], [q for _, _, q in paired]) if len(paired) >= 3 else None

    # H4: presentation_loss_beyond_abundance = proteome_frac - immunopeptidome_frac
    per_ko = []
    for c in kos:
        pf, qf = pres[c], prot[c]
        beyond = (round(qf - pf, 4) if (pf is not None and qf is not None) else None)
        per_ko.append({"KO": c, "immunopeptidome_frac": pf, "proteome_frac": qf,
                       "presentation_loss_beyond_abundance": beyond,
                       "essential": is_essential(c)})
    per_ko.sort(key=lambda d: (d["immunopeptidome_frac"] is None,
                               d["immunopeptidome_frac"] if d["immunopeptidome_frac"] is not None else 9))
    ess_beyond = [d["presentation_loss_beyond_abundance"] for d in per_ko
                  if d["essential"] and d["presentation_loss_beyond_abundance"] is not None]
    mean_ess_beyond = round(sum(ess_beyond) / len(ess_beyond), 4) if ess_beyond else None

    # local H4 verdict: essentials lose presentation beyond abundance AND B1 doesn't explain it
    h4_local = None
    if mean_ess_beyond is not None:
        h4_local = bool(mean_ess_beyond > 0.15 and (b1_rho is None or b1_rho <= 0.3))

    return {
        "deposit": deposit_id, "hla_background": hla, "hla_class": hla_class,
        "n_KO_conditions": len(kos),
        "has_matched_proteome": len(paired) >= 3,
        "B1_spearman_pres_vs_proteome": (round(b1_rho, 4) if b1_rho is not None else None),
        "H4_mean_essential_loss_beyond_abundance": mean_ess_beyond,
        "H4_local_win": h4_local,
        "per_KO": per_ko,
    }

# ---------------------------------------------------------------------------
# leave-HLA-out CV + permutation null + leakage check
# ---------------------------------------------------------------------------
def _ko_feature(ko):
    """HLA-AGNOSTIC feature: graded machinery-severity prior for the KO gene (0..1). This is the
    ONLY signal the cross-HLA predictor is allowed to use -> transfer must be machinery-driven,
    not memorized. Falls back to a class score for genes without an explicit severity."""
    u = ko.upper()
    if u in MACHINERY_SEVERITY:
        return MACHINERY_SEVERITY[u]
    if is_essential(ko):
        return 0.7
    if u in {g.upper() for g in MACHINERY_MODULATOR}:
        return 0.4
    return 0.1

def _observed_loss(dep_metrics, ko):
    for d in dep_metrics["per_KO"]:
        if d["KO"] == ko:
            # observed presentation loss = 1 - immunopeptidome_frac (fraction lost vs WT)
            if d["immunopeptidome_frac"] is None:
                return None
            return 1.0 - d["immunopeptidome_frac"]
    return None

def _fit_linear(xs, ys):
    """OLS slope/intercept for loss ~ severity. Returns (a, b) s.t. pred = a*x + b."""
    n = len(xs)
    if n == 0:
        return 0.0, 0.0
    mx = sum(xs) / n; my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return 0.0, my
    a = sum((xs[i] - mx) * (ys[i] - my) for i in range(n)) / sxx
    return a, my - a * mx

def leave_hla_out_cv(deposit_metrics, permute=False, seed=0):
    """For each held-out deposit (HLA background), fit loss ~ machinery-severity on the OTHER
    deposits, predict the held-out KOs from their severity feature ONLY, and score transfer with
    Spearman(predicted_loss, observed_loss) across the held-out deposit's KOs. Because the feature
    is an HLA-agnostic biology prior and the fit never sees held-out peptides, a positive transfer
    means the machinery->presentation ordering generalizes to an unseen HLA background."""
    rng = random.Random(seed)
    folds = []
    pooled_pred, pooled_obs = [], []  # held-out predictions across ALL folds -> primary statistic
    for test in deposit_metrics:
        train = [dm for dm in deposit_metrics if dm["deposit"] != test["deposit"]]
        xs, ys = [], []  # pooled training (severity, observed_loss)
        for dm in train:
            for d in dm["per_KO"]:
                loss = _observed_loss(dm, d["KO"])
                if loss is None:
                    continue
                xs.append(_ko_feature(d["KO"])); ys.append(loss)
        if permute:
            # break the machinery->loss link: shuffle observed losses vs their severity feature
            ys = ys[:]; rng.shuffle(ys)
        a, b = _fit_linear(xs, ys)
        pred, obs = [], []
        for d in test["per_KO"]:
            o = _observed_loss(test, d["KO"])
            if o is None:
                continue
            pred.append(a * _ko_feature(d["KO"]) + b); obs.append(o)
        pooled_pred.extend(pred); pooled_obs.extend(obs)
        rho = spearman(pred, obs) if len(pred) >= 3 else None
        folds.append({"held_out_deposit": test["deposit"], "hla_background": test["hla_background"],
                      "n_KO_tested": len(pred), "transfer_spearman": (round(rho, 4) if rho is not None else None),
                      "fit_slope": round(a, 4), "n_train_deposits": len(train)})
    pooled_rho = spearman(pooled_pred, pooled_obs) if len(pooled_pred) >= 3 else None
    return folds, pooled_rho, len(pooled_pred)

def permutation_band(deposit_metrics, real_pooled_rho, n=200, seed=0):
    """Null distribution of the POOLED cross-fold transfer Spearman under label permutation, plus a
    one-sided p-value P(null >= real). Pooling all held-out (pred,obs) pairs into ONE Spearman gives
    an adequate-n, smooth null (vs the degenerate per-fold-mean whose p95 pins to +-1 at small KO
    counts). Small corpora -> wide null -> large p -> correctly hard to pass."""
    rng = random.Random(seed)
    stats = []
    for i in range(n):
        _, prho, _ = leave_hla_out_cv(deposit_metrics, permute=True, seed=rng.randint(0, 10**9))
        if prho is not None:
            stats.append(prho)
    if not stats:
        return None
    stats_sorted = sorted(stats)
    def pct(p):
        k = min(len(stats_sorted) - 1, max(0, int(round(p * (len(stats_sorted) - 1)))))
        return round(stats_sorted[k], 4)
    ge = sum(1 for s in stats if real_pooled_rho is not None and s >= real_pooled_rho)
    pval = (ge + 1) / (len(stats) + 1)  # add-one smoothed one-sided p
    return {"n_permutations": len(stats), "null_mean": round(sum(stats) / len(stats), 4),
            "null_p05": pct(0.05), "null_p50": pct(0.50), "null_p95": pct(0.95),
            "real_pooled_transfer_spearman": (round(real_pooled_rho, 4) if real_pooled_rho is not None else None),
            "perm_pvalue_one_sided": round(pval, 4)}

def hla_overlap_leakage(deposit_metrics):
    """Flag shared-allele leakage: if held-out HLA background shares alleles with training set,
    transfer could ride on allele identity rather than machinery. Reports pairwise overlap."""
    def alleles(h):
        if not h:
            return set()
        toks = [t for t in str(h).replace(",", " ").split() if "*" in t or ":" in t]
        return set(toks)
    overlaps = []
    for a in deposit_metrics:
        aa = alleles(a["hla_background"])
        for b in deposit_metrics:
            if a["deposit"] >= b["deposit"]:
                continue
            bb = alleles(b["hla_background"])
            shared = sorted(aa & bb)
            overlaps.append({"pair": [a["deposit"], b["deposit"]],
                             "shared_alleles": shared, "n_shared": len(shared)})
    any_shared = any(o["n_shared"] > 0 for o in overlaps)
    return {"any_shared_alleles": any_shared, "pairs": overlaps,
            "note": ("no parsed alleles OR all distinct -> transfer cannot ride on shared alleles"
                     if not any_shared else
                     "shared alleles present -> LOO on those pairs is optimistic; require >=1 fully-disjoint HLA fold to pass")}

# ---------------------------------------------------------------------------
# gate verdict
# ---------------------------------------------------------------------------
def gate_verdict(deposit_metrics, folds, pooled_rho, null, leakage):
    n_dep = len(deposit_metrics)
    real_transfers = [f["transfer_spearman"] for f in folds if f["transfer_spearman"] is not None]
    mean_real = round(sum(real_transfers) / len(real_transfers), 4) if real_transfers else None
    n_pos_folds = sum(1 for v in real_transfers if v >= 0.3)  # folds carrying a positive ordering
    pval = null.get("perm_pvalue_one_sided") if null else None
    n_local_h4 = sum(1 for dm in deposit_metrics if dm["H4_local_win"])

    # PRIMARY statistic = pooled cross-fold transfer Spearman (adequate-n, smooth null).
    # PASS requires: significant pooled transfer (perm p<=0.05), a meaningful pooled effect
    # (rho>=0.3), the effect carried by >=3 backgrounds (not one dominant fold), and disjoint HLA
    # alleles across folds (so transfer cannot ride on shared-allele leakage).
    if n_dep < 2:
        verdict = "INSUFFICIENT_DEPOSITS_FOR_CROSS_HLA_GATE"
        cro = ("DRY-RUN / single background only. Cannot run leave-HLA-out yet. "
               "Once >=3 HLA backgrounds land, re-run; result then sizes the CRO.")
    elif n_dep < 3:
        verdict = "TWO_BACKGROUNDS_PRELIMINARY_need_3rd"
        cro = ("Only 2 HLA backgrounds: LOO runs but the null is weak with 2 folds. "
               "Treat as preliminary; a 3rd distinct background is required before this sizes the CRO.")
    elif (pval is not None and pval <= 0.05 and pooled_rho is not None and pooled_rho >= 0.3
          and n_pos_folds >= 3 and not leakage["any_shared_alleles"]):
        verdict = "PASS_generalizes_across_HLA"
        cro = ("Machinery->presentation transfers across HLA backgrounds on PUBLIC data "
               f"(pooled transfer rho={round(pooled_rho,3)}, perm p={pval}, {n_pos_folds} backgrounds "
               "carry it, disjoint alleles). SHRINK the CRO: fill only genuinely missing HLA x KO "
               "cells + absolute quant; the thesis need not be re-established.")
    else:
        verdict = "FAIL_or_UNPROVEN_across_HLA"
        reasons = []
        if pval is not None and pval > 0.05:
            reasons.append(f"perm p={pval} (>0.05)")
        if pooled_rho is not None and pooled_rho < 0.3:
            reasons.append(f"pooled transfer rho={round(pooled_rho,3)} (<0.3)")
        if n_pos_folds < 3:
            reasons.append(f"only {n_pos_folds} backgrounds carry the ordering")
        if leakage["any_shared_alleles"]:
            reasons.append("shared alleles across folds (allele-leakage risk)")
        cro = ("Cross-HLA generalization NOT established on public data "
               f"[{'; '.join(reasons) or 'insufficient signal'}]. CRO MUST supply the missing "
               "HLA x KO cells: >=3 distinct HLA backgrounds x machinery-KO panel + matched "
               "proteome, before H4 can be trained/claimed cross-allele. (Expensive path.)")
    return {
        "verdict": verdict,
        "n_deposits": n_dep,
        "n_local_H4_wins": n_local_h4,
        "pooled_transfer_spearman": (round(pooled_rho, 4) if pooled_rho is not None else None),
        "mean_LOO_transfer_spearman": mean_real,
        "perm_pvalue_one_sided": pval,
        "n_backgrounds_carrying_transfer": n_pos_folds,
        "null_band": null,
        "shared_allele_leakage": leakage["any_shared_alleles"],
        "CRO_sizing": cro,
    }

# ---------------------------------------------------------------------------
# inventory ingestion
# ---------------------------------------------------------------------------
def deposits_from_inventory(path):
    """Expected (flexible) inventory schema, per deposit entry:
       {"deposit": "PXDxxxxxx", "hla_background": "...", "hla_class": "I"|"II",
        "conditions": [{"condition": "B2M", "immunopeptidome_frac": .., "proteome_frac": ..}, ...]}
       OR {"deposit":..,"deposit_dir": "/path"} to trigger a built-in loader."""
    inv = json.load(open(path))
    entries = inv["deposits"] if isinstance(inv, dict) and "deposits" in inv else inv
    out = []
    for e in entries:
        did = e.get("deposit") or e.get("id")
        hla = e.get("hla_background") or e.get("hla") or e.get("hla_genotype")
        hcls = e.get("hla_class") or e.get("class")
        if e.get("conditions"):
            table = {}
            for row in e["conditions"]:
                table[str(row["condition"]).strip().upper()] = {
                    "immunopeptidome_frac": row.get("immunopeptidome_frac"),
                    "proteome_frac": row.get("proteome_frac"),
                }
            out.append((did, hla, hcls, table, {"loader": "inventory_table"}))
        elif e.get("deposit_dir"):
            table, meta = autoload_deposit(e["deposit_dir"])
            out.append((did, hla, hcls, table, meta))
        else:
            log(f"skip {did}: no conditions table and no deposit_dir")
    return out

# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inventory", help="H4_CORPUS_INVENTORY.json (multi-HLA aggregation output)")
    ap.add_argument("--deposit", action="append", default=[],
                    help="ID=/path/to/deposit_dir (repeatable) for direct dry-run")
    ap.add_argument("--hla", action="append", default=[], help="HLA background per --deposit (same order)")
    ap.add_argument("--hla-class", action="append", default=[], help="I|II per --deposit (same order)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--n-perm", type=int, default=200)
    args = ap.parse_args()

    loaded = []  # (id, hla, class, table, meta)
    if args.inventory and os.path.exists(args.inventory):
        log(f"loading inventory {args.inventory}")
        loaded.extend(deposits_from_inventory(args.inventory))
    elif args.inventory:
        log(f"inventory {args.inventory} NOT FOUND -> proceeding with --deposit only (graceful).")

    for i, d in enumerate(args.deposit):
        did, path = d.split("=", 1)
        hla = args.hla[i] if i < len(args.hla) else None
        hcls = args.hla_class[i] if i < len(args.hla_class) else None
        log(f"loading deposit {did} from {path}")
        table, meta = autoload_deposit(path)
        loaded.append((did, hla, hcls, table, meta))

    if not loaded:
        log("no deposits loaded (no inventory, no --deposit). Nothing to do.")
        sys.exit(2)

    deposit_metrics = []
    deposit_meta = {}
    for did, hla, hcls, table, meta in loaded:
        dm = compute_deposit_metrics(did, hla, hcls, table)
        deposit_metrics.append(dm)
        deposit_meta[did] = meta
        log(f"{did}: B1_rho={dm['B1_spearman_pres_vs_proteome']} "
            f"H4_ess_beyond={dm['H4_mean_essential_loss_beyond_abundance']} "
            f"H4_local_win={dm['H4_local_win']}")

    cross = None
    pooled_rho = None; n_pooled = 0
    if len(deposit_metrics) >= 2:
        folds, pooled_rho, n_pooled = leave_hla_out_cv(deposit_metrics)
        null = permutation_band(deposit_metrics, pooled_rho, n=args.n_perm)
        leakage = hla_overlap_leakage(deposit_metrics)
        cross = {"leave_hla_out_folds": folds,
                 "pooled_transfer_spearman": (round(pooled_rho, 4) if pooled_rho is not None else None),
                 "n_pooled_KO_predictions": n_pooled,
                 "permutation_null": null, "leakage_check": leakage}
    else:
        folds, null, leakage = [], None, hla_overlap_leakage(deposit_metrics)

    verdict = gate_verdict(deposit_metrics, folds, pooled_rho, null, leakage)

    result = {
        "harness": "leave_hla_out_gate.py",
        "purpose": "decision-gate: does the widened H4 (machinery->presentation) thesis "
                   "generalize ACROSS HLA backgrounds; sizes CRO spend.",
        "training_eligible": False,
        "mode": ("cross_HLA_gate" if len(deposit_metrics) >= 2 else "single_background_DRY_RUN"),
        "deposit_metrics": deposit_metrics,
        "deposit_loaders": deposit_meta,
        "cross_HLA": cross,
        "GATE": verdict,
        "caveats": [
            "H4 thesis validated on ONE HLA background so far (HAP1/PXD056426). >=3 distinct "
            "HLA backgrounds with KO+matched-proteome are required for a real cross-HLA PASS.",
            "Cross-HLA transfer uses an HLA-AGNOSTIC machinery-role feature only; it is a "
            "conservative floor, not a trained H4 head. A trained head could do better OR reveal "
            "HLA-specific processing the role feature misses.",
            "Fraction-of-WT is unique-peptide count (presentation) vs summed spectral count "
            "(proteome); both are relative-abundance proxies, not absolute copies/cell. "
            "Absolute-quant + MS-detectability censoring (BMA-PGM-002 +D) still owed.",
            "Class-I and class-II presentation use different machinery; mixing classes in one LOO "
            "fold is invalid. Group by hla_class before gating when the corpus spans both.",
            "Single-background dry-run cannot run leave-HLA-out; it only proves the B1+H4 compute "
            "path and the loaders. The gate verdict there is INSUFFICIENT_DEPOSITS by design.",
        ],
    }
    json.dump(result, open(args.out, "w"), indent=2)
    print(json.dumps({"GATE": verdict, "mode": result["mode"],
                      "deposits": [{"id": dm["deposit"], "B1_rho": dm["B1_spearman_pres_vs_proteome"],
                                    "H4_ess_beyond": dm["H4_mean_essential_loss_beyond_abundance"],
                                    "H4_local_win": dm["H4_local_win"]} for dm in deposit_metrics]},
                     indent=2))
    log(f"wrote {args.out}")

if __name__ == "__main__":
    main()
