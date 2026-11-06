#!/usr/bin/env python3
"""Build the KN-2 candidate plan (PREREG_KN2.md) in the repository's co-folding plan format. usage: kn2_make_plan.py out.json
Groups (seed 20261027 + offset, unique valid HELM, KN-1 samplers): L0 100 (of 180) | L1_9 100 | L1_other 100 | L2 100 (RGD motif present) | L3 100 | POS 2 | NEG 4 (target-KB non-actives)."""
import sys, os, json, random
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
import kn1_frontier as K1
from knowledge_liability_flags import parse_helm
SEED = 20261027; ring = lambda h: len(h[h.index("(") + 1:h.rindex(")")].split("-"))


def _draw(level, n, seed, accept=lambda h: True, exclude=()):
    rng = random.Random(seed); out, seen, tries = [], set(exclude), 0
    while len(out) < n and tries < 400000:
        tries += 1; h = K1.sample(level, rng)
        if h not in seen and accept(h): seen.add(h); out.append(h)
    assert len(out) == n, (level, len(out)); return out


def _entry(i, group, h): return {"id": i, "group": group, "helm": h, "pep": "".join(parse_helm(h)[0])}


def build():
    kb = json.load(open(os.path.join(HERE, "..", "target_kb", "avb6.json")))
    used = {c["helm"] for c in kb["controls"]} | set(kb["examples"]["non_actives"])          # controls are their own groups; candidates must not duplicate them (the L0 space contains the Trivehexin monomer)
    spec = [("L0", "L0", lambda h: True, 0), ("L1_9", "L1", lambda h: ring(h) == 9, 1), ("L1_other", "L1", lambda h: ring(h) != 9, 2), ("L2", "L2", lambda h: True, 3), ("L3", "L3", lambda h: True, 4)]
    pep = []
    for grp, lvl, acc, off in spec:
        hs = _draw(lvl, 100, SEED + off, acc, exclude=used); used |= set(hs); pep += [_entry(f"KN2-{grp}-{i:03d}", grp, h) for i, h in enumerate(hs)]
    pos = [c for c in kb["controls"] if c["id"] in ("Trivehexin-mono", "avebehexin")]
    names = {"Trivehexin-mono": "CTRL-TRIVEHEXIN", "avebehexin": "CTRL-AVEBEHEXIN"}
    pep += [_entry(names[c["id"]], "POS", c["helm"]) for c in pos]
    pep += [_entry(f"NEG-{i + 1}", "NEG", h) for i, h in enumerate(kb["examples"]["non_actives"][:4])]
    return {"title": "KN-2 simulated metal-aware engagement assay candidates (PREREG_KN2)", "seed": SEED, "peptides": {"avb6_kn2": pep}}


if __name__ == "__main__":
    plan = build(); json.dump(plan, open(sys.argv[1], "w"), indent=1); g = {}
    for e in plan["peptides"]["avb6_kn2"]: g[e["group"]] = g.get(e["group"], 0) + 1
    print(g)
