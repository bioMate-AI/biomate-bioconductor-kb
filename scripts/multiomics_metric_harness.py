#!/usr/bin/env python3
"""
Multi-omics integration benchmark — metric harness.

ONE scorer, run IDENTICALLY per method, so the head-to-head is apples-to-apples.
Consumes the standardized outputs the BioMate multi-omics workflows already emit:

  * clusters output  (SNF, iClusterPlus, intNMF): CSV with columns  sample,cluster
  * factors output   (MOFA2, JIVE, mixOmics):     CSV long  sample,factor,value
                                                   or wide  sample,Factor1,Factor2,...

Ground-truth labels come either from a labels CSV (sample,<label>) or, for the CLL
cohort, directly from the mutations matrix row (e.g. IGHV) via --label-row.

Metrics (stdlib only — no numpy/sklearn, so it runs in run_code or bare python3):
  * clusters vs categorical label : ARI, NMI
  * factors  vs binary label      : best-factor point-biserial d + AUC (which factor,
                                    signed), AND k-means(k) on factors -> ARI, NMI
The point is not any single number — it's that every method is scored the same way.

Usage:
  # SNF (clusters) vs IGHV from the CLL mutations matrix
  python3 multiomics_metric_harness.py --method SNF \
      --clusters snf_clusters.csv \
      --labels mutations.csv --label-row IGHV

  # MOFA2 (factors) vs IGHV, k-means k=2..3
  python3 multiomics_metric_harness.py --method MOFA2 \
      --factors mofa_extracted_factors.csv \
      --labels mutations.csv --label-row IGHV --kmeans 2 3
"""
import argparse, csv, sys
from collections import Counter, defaultdict
from math import comb, log


# ----------------------------- IO -----------------------------
def _strip(s): return s.strip().strip('"').strip("'")


def read_clusters(path):
    """sample,cluster -> {sample: cluster(int-or-str)}"""
    out = {}
    with open(path) as fh:
        r = csv.DictReader(fh)
        cols = [c.lower() for c in (r.fieldnames or [])]
        scol = r.fieldnames[cols.index("sample")] if "sample" in cols else r.fieldnames[0]
        ccol = r.fieldnames[cols.index("cluster")] if "cluster" in cols else r.fieldnames[1]
        for row in r:
            out[_strip(row[scol])] = _strip(row[ccol])
    return out


def read_factors(path):
    """long (sample,factor,value) or wide (sample,Factor1,...) -> {sample: [floats]}, factor_names"""
    with open(path) as fh:
        rows = list(csv.reader(fh))
    hdr = [_strip(h) for h in rows[0]]
    low = [h.lower() for h in hdr]
    fac = defaultdict(dict)
    if "value" in low and "factor" in low and "sample" in low:  # long form
        si, fi, vi = low.index("sample"), low.index("factor"), low.index("value")
        for row in rows[1:]:
            if len(row) <= max(si, fi, vi):
                continue
            v = _strip(row[vi])
            if v in ("", "NA", "NaN"):
                continue
            try:
                fac[_strip(row[si])][_strip(row[fi])] = float(v)
            except ValueError:
                pass
    else:  # wide form: col0 = sample, rest = factors
        fcols = hdr[1:]
        for row in rows[1:]:
            s = _strip(row[0])
            for j, fn in enumerate(fcols, 1):
                if j < len(row):
                    v = _strip(row[j])
                    try:
                        fac[s][fn] = float(v)
                    except ValueError:
                        pass
    names = sorted({f for d in fac.values() for f in d})
    mat = {s: [fac[s].get(f, 0.0) for f in names] for s in fac}
    return mat, names


def read_labels(path, label_row=None, label_col=None):
    """
    If --label-row: matrix (feature x sample), row 0 = header of samples, col 0 = feature
      -> pull the named feature row as {sample: value}.
    Else: tidy labels CSV (sample,<label_col or 2nd col>).
    """
    with open(path) as fh:
        rows = list(csv.reader(fh))
    hdr = [_strip(h) for h in rows[0]]
    if label_row:
        samples = hdr[1:]
        for row in rows[1:]:
            if _strip(row[0]).upper() == label_row.upper():
                out = {}
                for j, s in enumerate(samples, 1):
                    if j < len(row):
                        v = _strip(row[j])
                        if v not in ("", "NA", "NaN"):
                            out[s] = v
                return out
        raise SystemExit(f"label-row '{label_row}' not found in {path}")
    # tidy form
    low = [h.lower() for h in hdr]
    scol = low.index("sample") if "sample" in low else 0
    lcol = (low.index(label_col.lower()) if label_col and label_col.lower() in low
            else (1 if len(hdr) > 1 else 0))
    out = {}
    for row in rows[1:]:
        if len(row) > max(scol, lcol):
            v = _strip(row[lcol])
            if v not in ("", "NA", "NaN"):
                out[_strip(row[scol])] = v
    return out


# --------------------------- metrics ---------------------------
def contingency(a, b):
    return Counter(zip(a, b)), Counter(a), Counter(b)


def ari(a, b):
    tab, ai, bj = contingency(a, b)
    n = len(a)
    if n < 2:
        return float("nan")
    idx = sum(comb(v, 2) for v in tab.values())
    sa = sum(comb(v, 2) for v in ai.values())
    sb = sum(comb(v, 2) for v in bj.values())
    exp = sa * sb / comb(n, 2)
    mx = (sa + sb) / 2
    return (idx - exp) / (mx - exp) if mx != exp else 0.0


def nmi(a, b):
    n = len(a)
    tab, ai, bj = contingency(a, b)
    def H(c): return -sum((v / n) * log(v / n) for v in c.values() if v)
    Ha, Hb = H(ai), H(bj)
    mi = 0.0
    for (x, y), nxy in tab.items():
        mi += (nxy / n) * log((nxy * n) / (ai[x] * bj[y]))
    denom = (Ha + Hb) / 2
    return mi / denom if denom else 0.0


def _kmeans_once(X, k, cen, iters=50):
    lab = [0] * len(X)
    for _ in range(iters):
        changed = False
        for i, x in enumerate(X):
            c = min(range(k), key=lambda c: sum((a - b) ** 2 for a, b in zip(x, cen[c])))
            if c != lab[i]:
                changed = True
            lab[i] = c
        for c in range(k):
            pts = [X[i] for i in range(len(X)) if lab[i] == c]
            if pts:
                cen[c] = [sum(p[d] for p in pts) / len(pts) for d in range(len(X[0]))]
        if not changed:
            break
    inertia = sum(sum((a - b) ** 2 for a, b in zip(X[i], cen[lab[i]])) for i in range(len(X)))
    return lab, inertia


def kmeans(X, k, iters=50, n_init=10, seed=0):
    """
    k-means with n_init random restarts, returning the best-inertia labeling.
    Single-init k-means is init-unstable (on the CLL factors, k=2 ARI vs IGHV swings
    from -0.00 to 0.76 depending on the seed) — so a single init is NOT a valid
    benchmark metric. n_init restarts + inertia selection + a fixed seed make the
    reported ARI/NMI reproducible and init-independent. Deterministic LCG (no numpy).
    """
    if len(X) < k:
        return [0] * len(X)
    rng = seed
    def rand():  # portable LCG in [0,1)
        nonlocal rng
        rng = (1103515245 * rng + 12345) & 0x7FFFFFFF
        return rng / 0x7FFFFFFF
    best_lab, best_in = None, float("inf")
    for _ in range(n_init):
        idx = sorted({int(rand() * len(X)) for _ in range(k * 3)})[:k]
        while len(idx) < k:
            idx.append(int(rand() * len(X)))
        cen = [list(X[i]) for i in idx[:k]]
        lab, inertia = _kmeans_once(X, k, cen, iters)
        if inertia < best_in:
            best_lab, best_in = lab, inertia
    return best_lab


def point_biserial_d(values, binary):
    """standardized mean difference (Cohen's d) of a continuous factor across a 0/1 label."""
    g0 = [v for v, b in zip(values, binary) if b == 0]
    g1 = [v for v, b in zip(values, binary) if b == 1]
    if len(g0) < 2 or len(g1) < 2:
        return float("nan")
    def mean(z): return sum(z) / len(z)
    def var(z):
        m = mean(z)
        return sum((x - m) ** 2 for x in z) / (len(z) - 1)
    m0, m1 = mean(g0), mean(g1)
    sp = (((len(g0) - 1) * var(g0) + (len(g1) - 1) * var(g1)) / (len(g0) + len(g1) - 2)) ** 0.5
    return (m1 - m0) / sp if sp else 0.0


def auc(values, binary):
    """rank-based AUC of a score vs 0/1 label (Mann-Whitney)."""
    pos = [v for v, b in zip(values, binary) if b == 1]
    neg = [v for v, b in zip(values, binary) if b == 0]
    if not pos or not neg:
        return float("nan")
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        avg = (i + j) / 2 + 1
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    rpos = sum(ranks[i] for i in range(len(values)) if binary[i] == 1)
    a = (rpos - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg))
    return max(a, 1 - a)  # report separation magnitude (direction-agnostic)


# ---------------------------- main ----------------------------
def main():
    ap = argparse.ArgumentParser(description="Multi-omics benchmark metric harness")
    ap.add_argument("--method", required=True)
    ap.add_argument("--clusters")
    ap.add_argument("--factors")
    ap.add_argument("--labels", required=True)
    ap.add_argument("--label-row", help="feature row name in a features x samples matrix (e.g. IGHV)")
    ap.add_argument("--label-col", help="label column in a tidy labels CSV")
    ap.add_argument("--kmeans", nargs="*", type=int, default=[2, 3])
    ap.add_argument("--tsv", action="store_true", help="emit a TSV scorecard instead of pretty text")
    args = ap.parse_args()

    labels = read_labels(args.labels, args.label_row, args.label_col)
    # numeric coercion for point-biserial (binary labels)
    def as_int(v):
        try:
            return int(float(v))
        except ValueError:
            return v
    labels = {s: as_int(v) for s, v in labels.items()}
    label_vals = set(labels.values())
    is_binary = label_vals <= {0, 1}

    scorecard = []  # (method, target, metric, value, n)

    if args.clusters:
        clus = read_clusters(args.clusters)
        common = [s for s in clus if s in labels]
        a = [clus[s] for s in common]
        b = [labels[s] for s in common]
        scorecard.append((args.method, args.label_row or "label", "ARI", ari(a, b), len(common)))
        scorecard.append((args.method, args.label_row or "label", "NMI", nmi(a, b), len(common)))
        # cluster x label contingency (context)
        if not args.tsv:
            tab = Counter(zip(a, b))
            cats = sorted(set(b))
            print(f"\n  cluster x {args.label_row or 'label'} contingency:")
            for c in sorted(set(a)):
                print("   cluster %s: " % c + "  ".join(f"{cat}={tab.get((c,cat),0)}" for cat in cats))

    if args.factors:
        mat, names = read_factors(args.factors)
        common = [s for s in mat if s in labels]
        if is_binary:
            bin_lab = [labels[s] for s in common]
            best = None
            for fi, fn in enumerate(names):
                vals = [mat[s][fi] for s in common]
                d = point_biserial_d(vals, bin_lab)
                a_ = auc(vals, bin_lab)
                if best is None or (d == d and abs(d) > abs(best[1])):
                    best = (fn, d, a_)
            if best:
                scorecard.append((args.method, args.label_row or "label", f"best-factor d ({best[0]})", best[1], len(common)))
                scorecard.append((args.method, args.label_row or "label", f"best-factor AUC ({best[0]})", best[2], len(common)))
        # k-means on factors
        X = [mat[s] for s in common]
        b = [labels[s] for s in common]
        for k in args.kmeans:
            lab = kmeans(X, k)
            scorecard.append((args.method, args.label_row or "label", f"kmeans(k={k}) ARI", ari(lab, b), len(common)))
            scorecard.append((args.method, args.label_row or "label", f"kmeans(k={k}) NMI", nmi(lab, b), len(common)))

    # ------- emit -------
    if args.tsv:
        w = csv.writer(sys.stdout, delimiter="\t")
        w.writerow(["method", "target", "metric", "value", "n"])
        for m, t, met, v, n in scorecard:
            w.writerow([m, t, met, f"{v:.4f}" if v == v else "NA", n])
    else:
        print(f"\n=== {args.method} — scorecard ===")
        for m, t, met, v, n in scorecard:
            print(f"  {met:<28} {('%.4f' % v) if v == v else 'NA':>8}   (vs {t}, n={n})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
