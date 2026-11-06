"""Peptide-level matched molecular pairs (Part A5). Pairs are formed within source, same topology (and ring size for lariats), same length;
head-to-tail peptides are compared after cyclic-rotation alignment (no reversal). usage: python3 mmp.py CycPeptMPDB.csv"""
import sys, os, re, json, collections
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens as T, annotate as A, stats as S


def items_from_helm(helm):
    toks, _ = A.parse_helm(helm); out = []
    for t in toks:
        c = T.classify(t); out.append((c["base"], bool(c["is_D"]), bool(c["is_nme"]), t, c["comp"], c["kind"]))
    return out


def _key_item(it): return (it[0], it[1], it[2], it[3])         # (base, D, nme, token)


def classify_pair(a, b):
    """a, b: items differing at one position -> (label, delta_sign, ordered (A,B)) with canonical direction, or None."""
    if a[5] != "residue" or b[5] != "residue":
        return ("cap_or_unknown_change", 1, (a, b))
    (ba, Da, Na), (bb, Db, Nb) = a[:3], b[:3]
    if ba == bb:
        if Da == Db and Na != Nb: return ("N-Me added (with minus without)", 1 if Nb else -1, (a, b))
        if Na == Nb and Da != Db: return ("D flip (D minus L)", 1 if Db else -1, (a, b))
        if Da != Db and Na != Nb:
            # canonical A=(L, N-Me), B=(D, not N-Me)
            return ("D flip + N-Me swap ((D,nonMe) minus (L,Me))", 1 if (Db and not Nb) else -1, (a, b))
        return None
    if Da != Db or Na != Nb: return ("substitution with D/N-Me change", 1, (a, b))
    core = lambda s: re.split(r"[(_]", s)[0]
    if core(ba) == core(bb): return ("side-chain decoration (same core)", 1, (a, b))
    ca, cb = a[4], b[4]
    if (ca, ba) > (cb, bb): a, b, sgn = b, a, -1
    else: sgn = 1
    return ("substitution: %s->%s" % (a[4], b[4]), sgn, (a, b))


def find_single_pairs(df, tok_col="items", group_cols=("Source", "helm_topology", "n_monomers", "ring_res")):
    """df index = peptide id; returns DataFrame of pairs (id_a, id_b, label, delta_sign, exact_a, exact_b)."""
    rows = []
    for g, sub in df.groupby(list(group_cols)):
        topo = g[1]; ids = sub.index.tolist(); L = len(sub.iloc[0][tok_col])
        keys = collections.defaultdict(list)
        for pid in ids:
            its = [_key_item(i) for i in df.at[pid, tok_col]]; full = df.at[pid, tok_col]
            rots = range(L) if topo == "head_to_tail" else [0]
            for r in rots:
                seq = its[r:] + its[:r]; fr = full[r:] + full[:r]
                for j in range(L):
                    keys[(tuple(seq[:j]), tuple(seq[j + 1:]))].append((pid, fr[j]))
        seen = set()
        for k, lst in keys.items():
            if len(lst) < 2: continue
            for x in range(len(lst)):
                for y in range(x + 1, len(lst)):
                    (pa, ia), (pb, ib) = lst[x], lst[y]
                    if pa == pb or _key_item(ia) == _key_item(ib): continue
                    up = (min(pa, pb), max(pa, pb))
                    if up in seen: continue
                    seen.add(up)
                    c = classify_pair(ia, ib)
                    if c is None: continue
                    lab, sgn, (A_, B_) = c
                    rows.append(dict(id_a=pa, id_b=pb, label=lab, sign=sgn, exact_a=A_[0] + ("|D" if A_[1] else "") + ("|Me" if A_[2] else ""), exact_b=B_[0] + ("|D" if B_[1] else "") + ("|Me" if B_[2] else ""), source=g[0], topology=topo))
    return pd.DataFrame(rows)


DIRECTED_PREFIXES = ("N-Me added", "D flip (D minus L)", "D flip + N-Me swap", "ring +1 residue")


def is_directed(label):
    """Signed effects are meaningful only where the direction is defined by the chemistry: N-Me added, D flip (D minus L), D flip + N-Me swap, ring +1,
    and cross-class substitutions (class A->B with A != B). Same-class substitutions, N-Me shifts, decorations, cap/unknown changes and combined D/N-Me
    substitutions have an arbitrary pair orientation: only |delta| (magnitude) is reported for them."""
    if label.startswith(DIRECTED_PREFIXES): return True
    if label.startswith("substitution:"):
        a, b = label.split(":")[1].strip().split("->"); return a != b
    return False


def effects(pairs, y_col_a, y_col_b, source_col="source", min_pairs=10, min_sources=3):
    """pairs has columns label, sign, y_a, y_b (raw units), source. delta = sign*(y_b - y_a); sign encodes the canonical direction where defined."""
    pairs = pairs.copy(); pairs["delta"] = pairs["sign"] * (pairs["y_b"] - pairs["y_a"]); pairs["abs_delta"] = pairs["delta"].abs()
    res = []
    for lab, sub in pairs.groupby("label"):
        directed = is_directed(lab); col = "delta" if directed else "abs_delta"
        per = []
        for s, g in sub.groupby(source_col):
            if len(g) >= 3:
                v = g[col].var(ddof=1); per.append((g[col].mean(), v / len(g) if v > 0 else np.nan, len(g)))
        m = S.dl_meta([p[0] for p in per], [p[1] for p in per]) if per else S.dl_meta([], [])
        flat = sub["flat_a"].values if "flat_a" in sub else np.arange(len(sub))
        pt, lo, hi = S.cluster_boot(lambda i: sub[col].values[i].mean(), flat, B=500) if len(sub) >= 5 else (sub[col].mean(), np.nan, np.nan)
        res.append(dict(transformation=lab, directed=directed, statistic=("mean delta" if directed else "mean |delta|"), n_pairs=int(len(sub)), n_sources=int(sub[source_col].nunique()),
                        pooled=m["pooled"], meta_lo=m["lo"], meta_hi=m["hi"], I2=m["I2"], pair_mean=float(pt), boot_lo=float(lo), boot_hi=float(hi),
                        sd_delta=float(sub["delta"].std()) if directed else float(sub["abs_delta"].std()), frac_abs_gt_1=float((sub["abs_delta"] > 1.0).mean()),
                        interpretable=bool(len(sub) >= min_pairs and sub[source_col].nunique() >= min_sources)))
    return pd.DataFrame(res).sort_values("n_pairs", ascending=False)


def find_nme_shift(df, tok_col="items", group_cols=("Source", "helm_topology", "n_monomers", "ring_res")):
    """Pairs with identical (base, D) sequences after rotation alignment, equal N-Me counts, N-Me positions differing at exactly two positions (one moved)."""
    rows = []
    for g, sub in df.groupby(list(group_cols)):
        topo = g[1]; buckets = collections.defaultdict(list)
        for pid in sub.index:
            its = df.at[pid, tok_col]; bd = [(i[0], i[1]) for i in its]; me = [i[2] for i in its]; L = len(its)
            rots = range(L) if topo == "head_to_tail" else [0]
            cands = [(tuple(bd[r:] + bd[:r]), tuple(me[r:] + me[:r])) for r in rots]
            best = min(c[0] for c in cands)
            for b, m in cands:
                if b == best: buckets[(best, sum(me))].append((pid, m))
        seen = set()
        for k, lst in buckets.items():
            for x in range(len(lst)):
                for y in range(x + 1, len(lst)):
                    (pa, ma), (pb, mb) = lst[x], lst[y]
                    if pa == pb: continue
                    up = (min(pa, pb), max(pa, pb))
                    if up in seen: continue
                    if sum(1 for u, v in zip(ma, mb) if u != v) == 2:
                        seen.add(up); rows.append(dict(id_a=pa, id_b=pb, label="N-Me shift (one N-Me moved)", sign=1, exact_a="", exact_b="", source=g[0], topology=topo))
    return pd.DataFrame(rows)


def find_indel(df, tok_col="items"):
    """Head-to-tail ring-size change by one residue: longer minus one residue equals shorter up to cyclic rotation. delta sign: longer minus shorter."""
    rows = []
    h = df[df.helm_topology == "head_to_tail"]
    for src, sub in h.groupby("Source"):
        canon = {}
        for pid in sub.index:
            its = [_key_item(i) for i in sub.at[pid, tok_col]]; L = len(its)
            canon.setdefault(L, {}).setdefault(min(tuple(its[r:] + its[:r]) for r in range(L)), []).append(pid)
        for L, table in canon.items():
            if L - 1 not in canon: continue
            short = canon[L - 1]
            for key_pid in [(pid, sub.at[pid, tok_col]) for pids in table.values() for pid in pids]:
                pid, full = key_pid; its = [_key_item(i) for i in full]
                for j in range(L):
                    rest = its[:j] + its[j + 1:]; k = min(tuple(rest[r:] + rest[:r]) for r in range(L - 1))
                    if k in short:
                        removed = full[j]
                        lab = "ring +1 residue (any)"
                        for sp in short[k]:
                            rows.append(dict(id_a=sp, id_b=pid, label=lab, sign=1, exact_a="", exact_b=removed[0] + ("|D" if removed[1] else "") + ("|Me" if removed[2] else ""), added_comp=removed[4], added_nme=bool(removed[2]), source=src, topology="head_to_tail"))
    return pd.DataFrame(rows).drop_duplicates(["id_a", "id_b", "exact_b"])
