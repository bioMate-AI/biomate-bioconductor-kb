# system py: subsample 20k stratified per cohort, align to FM HVG -> log-HVG + corpus-scaled + labels
import numpy as np, anndata as ad
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_zh"; import os; os.makedirs(OUT,exist_ok=True)
sc=np.load(f"{WS}/eval_repair_20261107/input_artifacts/stream_hvg_scaler.npz"); hvg=list(sc["hvg_names"].astype(str))
import scipy.sparse as sp
def prep(name,cap=20000):
    A=ad.read_h5ad(f"{WS}/debug_20261003/work_fs/{name}.h5ad",backed="r")
    ct=A.obs["cell_type"].astype(str).to_numpy(); rng=np.random.RandomState(0)
    # stratified subsample: cap total ~cap, proportional but min floor
    idx=rng.permutation(len(ct))[:cap]; idx=np.sort(idx)
    sub=A[idx].to_memory(); X=sub.X.tocsr().astype(np.float64)
    lib=np.asarray(X.sum(1)).ravel(); lib[lib==0]=1; nm=X.multiply(1e4/lib[:,None]).tocsr(); nm.data=np.log1p(nm.data)
    names=list(sub.var_names); gi={str(g).upper():i for i,g in enumerate(names)}
    cols=[gi.get(str(g).upper(),-1) for g in hvg]; have=[j for j,c in enumerate(cols) if c>=0]
    H=np.zeros((X.shape[0],len(hvg)),np.float32); H[:,have]=np.asarray(nm[:,[cols[j] for j in have]].todense(),np.float32)
    np.save(f"{OUT}/{name}_log.npy",H); np.save(f"{OUT}/{name}_fm.npy",((H-sc["mean"])/sc["scale"]).astype(np.float32))
    np.save(f"{OUT}/{name}_ct.npy",ct[idx].astype(object),allow_pickle=True)
    print(f"{name}: n={len(H)} genes {len(have)}/2000 types {len(set(ct[idx]))}",flush=True)
for n in ["io","imid","infectious_control"]: prep(n)
print("ZH_PREP_COMPLETE",flush=True)
