"""DPO checkpoint audit: (1) weight deltas vs v4; (2) sample p_hi/null-target from each checkpoint, measure memorisation (exact monomer-tuple match to CycPeptMPDB) and the MEASURED permeability of the matched peptides
(a real label, not an oracle); (3) change in display binding LLR ranking (Spearman) between v4 and each DPO checkpoint on 1,000 PADI4 test rows.
usage: python3 audit_dpo.py OUT.json (cyclic_llm/)"""
import sys, os, json, random, csv
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import unified_cyclic_llm as U
from loop_model import LoopModel
from train_cyclic_llm_v3 import TFEAT_DIM
from scipy.stats import spearmanr
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
cks = {"v4": "unified_cyclic_llm_v4.pt", "v4_dpo": "unified_cyclic_llm_v4_dpo.pt", "v4_dpo_rc": "unified_cyclic_llm_v4_dpo_rc.pt"}
models = {k: LoopModel.from_checkpoint(f"{R}/runs_helm/{v}") for k, v in cks.items()}
out = {"weight_delta_vs_v4": {}}
sd0 = models["v4"].model.state_dict()
for k in ("v4_dpo", "v4_dpo_rc"):
    sd = models[k].model.state_dict(); num = sum(float((sd[n] - sd0[n]).norm() ** 2) for n in sd0) ** .5; den = sum(float(sd0[n].norm() ** 2) for n in sd0) ** .5
    out["weight_delta_vs_v4"][k] = {"rel_l2": round(num / den, 5), "identical": bool(num == 0)}
# measured-permeability lookup (exact monomer tuple -> mean measured Permeability)
perm = {}
for r in csv.DictReader(open(f"{R}/data/raw/CycPeptMPDB_Peptide_All.csv", encoding="utf-8-sig", errors="replace")):
    m = U.parse_monomers(r["Sequence"]);
    try: y = float(r["Permeability"])
    except Exception: continue
    if m and 3 <= len(m) <= 16 and y > -9.99: perm.setdefault(tuple(m), []).append(y)
perm = {k: float(np.mean(v)) for k, v in perm.items()}
glob = float(np.mean(list(perm.values())))
def sample(lm, n=400, seed=0):
    torch.manual_seed(seed); stoi = lm.stoi; itos = {i: t for t, i in stoi.items()}; zero = torch.zeros(TFEAT_DIM); res = []
    for _ in range(n):
        ids = [stoi["<e_na>"], stoi["<p_hi>"], stoi[U.BOS]]
        for _ in range(17):
            with torch.no_grad(): lg = lm.model(torch.tensor([ids[-lm.block:]]), zero[None])[0, -1]
            nx = int(torch.multinomial(torch.softmax(lg, -1), 1))
            if nx == stoi[U.EOS]: break
            ids.append(nx)
        res.append(tuple(itos[i] for i in ids[3:]))
    return res
out["samples"] = {}
for k, lm in models.items():
    g = sample(lm); valid = [s for s in g if 3 <= len(s) <= 16 and all(t in lm.stoi and not t.startswith("<") for t in s)]
    mem = [s for s in valid if s in perm]
    out["samples"][k] = {"n": len(g), "valid": len(valid), "unique_valid": len(set(valid)), "memorised_frac_of_valid": round(len(mem) / max(len(valid), 1), 3),
                         "n_memorised": len(mem), "mean_measured_perm_of_memorised": round(float(np.mean([perm[s] for s in mem])), 3) if mem else None,
                         "mean_measured_perm_all_training_peptides": round(glob, 3)}
    print(k, out["samples"][k], flush=True)
# binding-LLR rank change on PADI4 test rows (display)
D = f"{R}/data"
disp, tf = U.load_display(f"{D}/display/display_ngs_multitarget.csv.gz", f"{D}/display/target_proteins.json", 16)
random.Random(0).shuffle(disp)
rs = [r for r in disp if r["target"] == "PADI4"]; nte = min(3000, max(200, int(len(rs) * 0.2)))
bind = [r for r in rs if r["is_binder"]]; non = [r for r in rs if not r["is_binder"]]
te = (bind[:nte // 2] + non[:nte - len(bind[:nte // 2])])[:1000]
import types
tseq = json.load(open(f"{D}/display/target_proteins.json"))["PADI4"]["seq"]
sc = {k: np.array(lm.score_tokens([r["monomers"] for r in te], tseq)) for k, lm in models.items()}
out["padi4_llr_rank_corr_with_v4"] = {k: round(float(spearmanr(sc["v4"], sc[k])[0]), 4) for k in ("v4_dpo", "v4_dpo_rc")}
from sklearn.metrics import roc_auc_score
y = np.array([int(r["is_binder"]) for r in te])
out["padi4_auc_first1000_test"] = {k: round(float(roc_auc_score(y, sc[k])), 3) for k in sc}
json.dump(out, open(sys.argv[1], "w"), indent=1); print(json.dumps(out, indent=1))
