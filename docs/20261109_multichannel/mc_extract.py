# system py: extract protein channels (35-slot CLR aligned to ckpt panel + full-144 CLR) + y + grp
import numpy as np, anndata as ad, json
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_mc"; import os; os.makedirs(OUT,exist_ok=True)
A=ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
panel=json.load(open(f"{WS}/eval_repair_20261107/panel_overlap.json"))
names=list(A.uns["protein_names"]); P=np.asarray(A.obsm["protein_expression"],np.float32)
def clr(X):
    X=np.log1p(np.clip(X,0,None)); return (X-X.mean(1,keepdims=True)).astype(np.float32)
# 35-slot aligned (for FM): fill matched antibodies, others 0
slots={m:i for i,m in enumerate(panel["model_panel"])}; match=panel["GSE261278"]["matched"]
use=[(names.index(n),slots[m]) for n,m in match.items()]
Xp35=np.zeros((P.shape[0],len(slots)),np.float32); C=clr(P[:,[a for a,_ in use]])
for k,(_,b) in enumerate(use): Xp35[:,b]=C[:,k]
Xp144=clr(P)  # full protein for the raw-protein baseline
y=(A.obs["stim"].astype(str).str.lower().str.contains("flu|sars")).astype(int).to_numpy()
grp=A.obs["cell_type"].astype(str).to_numpy()
np.save(f"{OUT}/Xp35.npy",Xp35); np.save(f"{OUT}/Xp144.npy",Xp144)
np.save(f"{OUT}/y.npy",y); np.save(f"{OUT}/grp.npy",grp.astype(object),allow_pickle=True)
print(f"saved Xp35{Xp35.shape} Xp144{Xp144.shape} matched {len(use)}/{len(slots)} y+={int(y.sum())}/{len(y)}",flush=True)
print("MC_EXTRACT_COMPLETE",flush=True)
