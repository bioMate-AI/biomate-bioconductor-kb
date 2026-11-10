# system py: prep zero-shot cross-dataset test. Align D534 (A) + GSE239626 (B) to FM's 2000 HVG.
# For FM: corpus-scaled (fixed scaler). For raw/PCA: CP10k+log1p HVG (PCA/scaler fit on A, applied to B).
import numpy as np, anndata as ad, scipy.sparse as sp
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_zs"; import os; os.makedirs(OUT,exist_ok=True)
sc=np.load(f"{WS}/eval_repair_20261107/input_artifacts/stream_hvg_scaler.npz"); hvg=list(sc["hvg_names"].astype(str))
def prep(fn):
    A=ad.read_h5ad(f"{WS}/step0/{fn}.h5ad")
    X=A.X.tocsr().astype(np.float64); lib=np.asarray(X.sum(1)).ravel(); lib[lib==0]=1
    nm=X.multiply(1e4/lib[:,None]).tocsr(); nm.data=np.log1p(nm.data)
    names=list(A.var_names); idx={str(g).upper():i for i,g in enumerate(names)}
    cols=[idx.get(str(g).upper(),-1) for g in hvg]; have=[j for j,c in enumerate(cols) if c>=0]
    H=np.zeros((X.shape[0],len(hvg)),np.float32); H[:,have]=np.asarray(nm[:,[cols[j] for j in have]].todense(),np.float32)
    ct=A.obs["cell_type"].astype(str).to_numpy()
    return H, ct, len(have)
HA,ctA,ngA=prep("GSE261278_D534.paired")   # A: labeled source (18 named types)
HB,ctB,ngB=prep("GSE239626.paired")        # B: target (ADTc0-9 clusters)
np.save(f"{OUT}/HA_log.npy",HA); np.save(f"{OUT}/HB_log.npy",HB)
# corpus-scaled versions for FM input
np.save(f"{OUT}/HA_fm.npy",((HA-sc["mean"])/sc["scale"]).astype(np.float32))
np.save(f"{OUT}/HB_fm.npy",((HB-sc["mean"])/sc["scale"]).astype(np.float32))
np.save(f"{OUT}/ctA.npy",ctA.astype(object),allow_pickle=True); np.save(f"{OUT}/ctB.npy",ctB.astype(object),allow_pickle=True)
print(f"A n={len(HA)} genes {ngA}/2000 types {len(set(ctA))} | B n={len(HB)} genes {ngB}/2000 clusters {len(set(ctB))}",flush=True)
print("ZS_EXTRACT_COMPLETE",flush=True)
