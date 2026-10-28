"""Score WS3's frozen items (analyses I and M2) with the pre-registered zero-fit arms; writes score files for retro_recovery/run_s3.py.
  A1   v4 LLR(e_hi vs e_lo | target descriptor), mean over backbone rotations, tokens from the converter (learned dictionary monomer_dictionary_v5.json); unscored if unmapped/not in v4 vocab
  A1c  same with target descriptors PERMUTED across targets (fixed seed) -> tests target dependence
  A2   atom LM mean per-token log-likelihood of the SMILES (compound-level typicality control; carries no target information)
usage: python3 score_benchmark.py ATOM_CKPT ATOM_VOCAB  (cyclic_llm/v4_eval)"""
import sys, os, json, random
import numpy as np, pandas as pd, torch
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..")); sys.path.insert(0, os.path.join(HERE, "..", "allatom"))
import scorers as SC, smiles_to_monomers as S
from train_cyclic_llm_v3 import target_feature
W3 = f"{HERE}/../../multitarget/integrin_chembl/retro_recovery/data"; OUT = f"{HERE}/results"
C = pd.read_csv(f"{W3}/compounds.csv.gz").set_index("compound_id")
items = pd.concat([pd.read_csv(f"{W3}/items_I.csv.gz").assign(an="I"), pd.read_csv(f"{W3}/items_M2.csv.gz").assign(an="M2")])
pairs = items[["target_key", "compound_id"]].drop_duplicates(); comps = sorted(set(pairs.compound_id))
tj = json.load(open(f"{HERE}/benchmark_target_sequences.json")); seqs = tj["accessions"]
tvec = {k: torch.tensor(np.mean([target_feature(seqs[a]).astype("float32") for a in accs], 0)) for k, accs in tj["targets"].items()}
dic = json.load(open(f"{HERE}/monomer_dictionary_v5.json")); v4 = SC.V4Scorer(f"{HERE}/../../runs_helm/unified_cyclic_llm_v4.pt", dictionary=dic)
seg = {}
for c in comps:
    r = S.segment(C.loc[c, "iso_smiles"], dic)
    seg[c] = r if (r.get("ok") and r["complete"] and all(t in v4.stoi for t in r["tokens"]) and len(r["tokens"]) + 4 <= v4.block) else None
mapped = [c for c in comps if seg[c] is not None]; print("compounds", len(comps), "mapped for v4", len(mapped), f"({len(mapped)/len(comps):.3f})")
def llr(c, tf):
    r = seg[c]; rots = S.rotations(r["tokens"]) if r["cyclic"] else [r["tokens"]]
    return float(np.mean(v4._loglik(rots, "<e_hi>", tf) - v4._loglik(rots, "<e_lo>", tf)))
tkeys = sorted(tvec); perm = dict(zip(tkeys, random.Random(7).sample(tkeys, len(tkeys))))
rows1, rows1c = [], []
for k, g in pairs.groupby("target_key"):
    for c in g.compound_id:
        if seg[c] is None: continue
        rows1.append((k, c, llr(c, tvec[k]))); rows1c.append((k, c, llr(c, tvec[perm[k]])))
pd.DataFrame(rows1, columns=["target_key", "compound_id", "score"]).to_csv(f"{OUT}/scores_A1_v4.csv", index=False)
pd.DataFrame(rows1c, columns=["target_key", "compound_id", "score"]).to_csv(f"{OUT}/scores_A1c_v4_shuffled_target.csv", index=False)
print("A1 rows", len(rows1), "A1c rows", len(rows1c))
if len(sys.argv) > 2:
    am = SC.AtomLMScorer(sys.argv[1], sys.argv[2]); rows2 = []
    for c in comps:
        o = am.score_smiles(C.loc[c, "iso_smiles"])
        if o["score"] is not None: rows2.append((c, o["score"]))
    pd.DataFrame(rows2, columns=["compound_id", "score"]).to_csv(f"{OUT}/scores_A2_atomlm.csv", index=False); print("A2 compounds scored", len(rows2), "of", len(comps))
