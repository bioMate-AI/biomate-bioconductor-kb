#!/usr/bin/env python3
"""KN-1 (PREREG_KN1.md): knowledge-novelty frontier for aVb6 cyclic peptides. usage: kn1_frontier.py out.json [n=2000]"""
import sys, os, json, random, math, difflib
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from rule_induction import predicates
from fto_score import fto_score
CAN = list("ACDEFGHIKLMNPQRSTVWY"); NC = ["[2Nal]", "[Phe4F]", "[Phe4Cl]", "[Aib]", "[Abu]", "[dP]", "[NMeK]", "[NMeA]"]
AROM = ["F", "Y", "W", "[2Nal]", "[Phe4F]", "[Phe4Cl]"]; SMALL = ["A", "G", "S", "[Aib]", "[Abu]"]; LYS = {"K", "[NMeK]"}


def tok(rng, allow_lys=True):
    while True:
        t = rng.choice(NC) if rng.random() < 0.25 else rng.choice(CAN)
        if allow_lys or t not in LYS: return t


def helm(toks): return "cyclo(" + "-".join(toks) + ")"


def sample(level, rng):
    n = rng.randint(7, 11)
    if level == "L0":
        return helm([rng.choice(AROM), "R", "G", "D", "L", rng.choice(SMALL), rng.choice(AROM), "[dP]", "[NMeK]"])
    if level == "L1":
        s = rng.randint(0, n - 4); t = [tok(rng, allow_lys=False) for _ in range(n)]; t[s:s + 4] = ["R", "G", "D", "L"]
        free = [i for i in range(n) if not (s <= i < s + 4)]; t[rng.choice(free)] = rng.choice(["K", "[NMeK]"]); return helm(t)
    if level == "L2":
        s = rng.randint(0, n - 4); t = [tok(rng) for _ in range(n)]; t[s:s + 3] = ["R", "G", "D"]; return helm(t)
    return helm([tok(rng) for _ in range(n)])


def wilson(k, n, z=1.96):
    if n == 0: return [0, 0]
    p = k / n; d = 1 + z * z / n; c = p + z * z / (2 * n); h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)); return [round((c - h) / d, 3), round((c + h) / d, 3)]


def run(out, n=2000, seed=20261027):
    rng = random.Random(seed); res = {}
    for lvl in ("L0", "L1", "L2", "L3"):
        seen, tries = [], 0
        S = set()
        while len(S) < n and tries < n * 30:
            tries += 1; h = sample(lvl, rng)
            if h not in S: S.add(h); seen.append(h)
        mech = inside = outside = other = usable = lowid = 0; ids = []; cats = {}
        for h in seen:
            try: p = predicates(h)
            except Exception: p = {}
            m = bool(p.get("has_rgd") and p.get("has_rgdl"))
            f = fto_score(h); v = f["claim"]["verdict"]; ident = f.get("nearest_patented_identity")
            ins = v.startswith("INSIDE"); outs = v.startswith("literally OUTSIDE") or "outside" in v.lower() and not ins
            cats[v.split(" at ")[0][:40]] = cats.get(v.split(" at ")[0][:40], 0) + 1
            mech += m; inside += ins; outside += (outs and not ins); other += (not ins and not outs)
            if ident is not None: ids.append(ident); lowid += ident < 0.7
            usable += (m and not ins and (ident is not None and ident < 0.7))
        N = len(seen); pairs = [difflib.SequenceMatcher(None, a.split("-"), b.split("-")).ratio() for a, b in (rng.sample(seen, 2) for _ in range(500))] if N > 2 else [1.0]
        res[lvl] = dict(n_unique=N, mechanism_features=dict(k=mech, rate=round(mech / N, 3), ci95=wilson(mech, N)), inside_genus=dict(k=inside, rate=round(inside / N, 3), ci95=wilson(inside, N)),
                        outside_genus=dict(k=outside, rate=round(outside / N, 3)), other_verdict=dict(k=other, rate=round(other / N, 3)), identity_lt_0_7=dict(k=lowid, rate=round(lowid / N, 3), ci95=wilson(lowid, N)),
                        usable_novel=dict(k=usable, rate=round(usable / N, 3), ci95=wilson(usable, N)), mean_pairwise_similarity=round(sum(pairs) / len(pairs), 3), verdict_categories=cats)
        print(lvl, json.dumps({k: res[lvl][k] for k in ("n_unique", "mechanism_features", "inside_genus", "usable_novel")}), flush=True)
    l = res; ok = l["L1"]["usable_novel"]["ci95"][0] > max(l["L0"]["usable_novel"]["ci95"][1], l["L3"]["usable_novel"]["ci95"][1]) and l["L1"]["usable_novel"]["ci95"][0] > l["L2"]["usable_novel"]["ci95"][1]
    res["CLAIM_L1_frontier_supported"] = bool(ok); json.dump(res, open(out, "w"), indent=1); print("CLAIM L1 frontier supported:", ok)


if __name__ == "__main__":
    run(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 2000)
