# system python3: read stim h5ad, CP10k+log1p, align HVG, corpus-scale -> xs.npy (h5ad cell order)
import numpy as np, h5py, os
from scipy.sparse import csr_matrix
WS="/home/yzhang/immune_fm_spark"; AUD=f"{WS}/eval_repair_20261107"; OUT=f"{WS}/ws_bench"
def _s(a): return np.array([x.decode() if isinstance(x,(bytes,bytearray)) else str(x) for x in a])
def read_col(o):
    if isinstance(o,h5py.Group):
        ks=set(o.keys())
        if "categories" in ks and "codes" in ks:
            cats=_s(o["categories"][:]); codes=o["codes"][:]; return np.where(codes<0,"NA",cats[np.clip(codes,0,len(cats)-1)])
        if "values" in ks: return _s(o["values"][:])
    return _s(o[:])
def align(names,X,hvg):
    idx={str(g).upper():i for i,g in enumerate(names)}; cols=[idx.get(str(g).upper(),-1) for g in hvg]
    out=np.zeros((X.shape[0],len(hvg)),np.float32); have=[j for j,c in enumerate(cols) if c>=0]
    sub=X[:,[cols[j] for j in have]]; out[:,have]=np.asarray(sub.todense() if hasattr(sub,"todense") else sub,np.float32); return out
sc=np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz"); hvg=list(sc["hvg_names"].astype(str))
f=h5py.File(f"{WS}/step0/GSE261278_D534.paired.h5ad","r")
var=read_col(f["var"]["_index"]); ncol=len(var)
X=csr_matrix((f["X"]["data"][:],f["X"]["indices"][:],f["X"]["indptr"][:]),shape=(len(f["X"]["indptr"][:])-1,ncol))
f.close()
lib=np.asarray(X.sum(1)).ravel(); lib[lib==0]=1; norm=X.multiply(1e4/lib[:,None]).tocsr(); norm.data=np.log1p(norm.data)
x=align(var,norm,hvg); xs=((x-sc["mean"])/sc["scale"]).astype(np.float32)
np.save(f"{OUT}/xs_stim.npy", xs); print("xs saved", xs.shape)
