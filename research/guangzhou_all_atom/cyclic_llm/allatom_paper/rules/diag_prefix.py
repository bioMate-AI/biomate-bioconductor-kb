"""Model-free diagnosis of masked-completion failures: for every pilot-3 seed prompt (same prefix protocol), is the prompt illegal for the tracker, infeasible at the start, or does the mask have a feasible continuation?
usage: diag_prefix.py OUT.json [--frac 0.85] [--n 2000]   Env: CHEMFM_TOK, CPM_CSV, MONO_JSON."""
import os, sys, json, random, collections, argparse
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..")); sys.path.insert(0, os.path.join(HERE, "..", "..", "generation_pilot")); sys.path.insert(0, os.path.join(HERE, "..", ".."))
import gen_pilot
from rules import vocab as V, spec
from rules.constraint import ChemFMConstraint
from rules.tracker import Tracker

ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--frac", type=float, default=0.85); ap.add_argument("--n", type=int, default=2000); a = ap.parse_args()
ctx = gen_pilot.context(); voc = V.load(os.environ["CHEMFM_TOK"]); con = ChemFMConstraint(voc, max_len=500); rng = random.Random(0); cnt = collections.Counter(); ex = collections.defaultdict(list)
for i in range(a.n):
    s = rng.choice(ctx["S"]); ids = voc.encode(s); body = ids[1:]
    P = max(2, min(len(body) - 1, int(round(a.frac * len(body))))); P = max(2, (P // 8) * 8) if P >= 8 else P
    prompt = [ids[0]] + body[:P]
    try: st = con.init_state(prompt)
    except ValueError: cnt["prompt_illegal_for_tracker"] += 1; ex["illegal"].append(s[:80]); continue
    if st.mass > 1400: cnt["prefix_mass_over_1400"] += 1; continue
    if st.nme_lower_bound() > 6: cnt["prefix_nme_over_6"] += 1; continue
    rem = 500 - st.n
    if not st.feasible(1400.0, 6, rem): cnt["prefix_infeasible_other"] += 1; continue
    m = con.mask(st)
    if not m.any(): cnt["mask_empty_at_start"] += 1; ex["empty"].append(s[:80]); continue
    cnt["ok"] += 1
    # mass headroom: how much room is left under 1400 (a proxy for how hard the completion is)
    cnt["headroom_lt_150"] += int((1400 - st.mass) < 150)
tot = sum(v for k, v in cnt.items() if k not in ("headroom_lt_150",)); res = dict(frac=a.frac, n=a.n, counts=dict(cnt), total=tot, examples={k: v[:5] for k, v in ex.items()})
json.dump(res, open(a.out, "w"), indent=1); print(json.dumps(res, indent=1))
