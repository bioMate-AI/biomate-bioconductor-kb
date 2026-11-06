"""Score the decoy-candidate pool with workstream 1's AtomLMScorer (unmodified; checkpoint s3://.../allatom/pretrain/ckpt.pt, sha256 recorded)
so typicality can be used as a matching variable (A7). Existing WS1 scores (v4_eval/results/scores_A2_atomlm.csv) are reused; only missing compounds are scored.
Consistency check: 200 already-scored compounds are re-scored and must agree (|diff| < 1e-3). Output data/typicality_atomlm.csv.gz."""
import sys, os, hashlib, time, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; SP = "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad"
sys.path.insert(0, os.path.abspath(f"{HERE}/../../../cyclic_llm/v4_eval")); import scorers as SC
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz")
need = sorted(set(P[P.label == "pos"].compound_id) | set(pd.read_csv(f"{DATA}/items_I.csv.gz").compound_id) | set(pd.read_csv(f"{DATA}/items_M2.csv.gz").compound_id))
ws1 = pd.read_csv(f"{HERE}/../../../cyclic_llm/v4_eval/results/scores_A2_atomlm.csv").set_index("compound_id").score.to_dict()
am = SC.AtomLMScorer(f"{SP}/pt/ckpt.pt", f"{SP}/pt/vocab.json")
rng = np.random.default_rng(0); chk = rng.choice(sorted(ws1), 200, replace=False); diffs = []
for c in chk:
    o = am.score_smiles(C.loc[c, "iso_smiles"])["score"]; diffs.append(abs(o - ws1[c]) if o is not None else np.nan)
print("consistency vs WS1 on 200: max |diff|", np.nanmax(diffs), "n None", int(np.isnan(diffs).sum()), flush=True)
assert np.nanmax(diffs) < 1e-3, "scorer does not reproduce WS1 scores"
out = dict(ws1); todo = [c for c in need if c not in out]; t0 = time.time(); fails = 0
for i, c in enumerate(todo):
    o = am.score_smiles(C.loc[c, "iso_smiles"])["score"]
    if o is None: fails += 1
    else: out[c] = o
    if i % 500 == 0: print(i, len(todo), round(time.time() - t0), flush=True)
df = pd.DataFrame(dict(compound_id=list(out), score=list(out.values()), source=["ws1" if c in ws1 else "ws3_same_scorer" for c in out]))
df.to_csv(f"{DATA}/typicality_atomlm.csv.gz", index=False, compression=dict(method="gzip", mtime=0))
json.dump(dict(scored=len(out), needed=len(need), covered_of_needed=round(len([c for c in need if c in out]) / len(need), 4), unscorable=fails, ckpt_sha256=hashlib.sha256(open(f"{SP}/pt/ckpt.pt", "rb").read()).hexdigest(), consistency_max_abs_diff=float(np.nanmax(diffs))), open(f"{DATA}/typicality_atomlm.json", "w"), indent=1)
print(open(f"{DATA}/typicality_atomlm.json").read())
