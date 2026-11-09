# system python (h5py): extract Rest-context residual effects + KO features + shared-set kernel -> npz
import os,numpy as np,h5py
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_pertmodel"; os.makedirs(OUT,exist_ok=True)
def read_cat(g):
    c=g["categories"][:]; k=g["codes"][:]; c=np.array([x.decode() if isinstance(x,(bytes,bytearray)) else str(x) for x in c])
    return np.where(k<0,"NA",c[np.clip(k,0,len(c)-1)])
f=h5py.File(f"{WS}/perturb_full/GWCD4i.DE_stats.h5ad","r"); Y=f["layers"]["log_fc"][:].astype(np.float32)
ko=read_cat(f["obs"]["target_contrast_gene_name"]).astype(str); cond=read_cat(f["obs"]["culture_condition"]).astype(str)
mask=f["obs"]["ontarget_significant"][:].astype(bool)&(~f["obs"]["low_target_gex"][:].astype(bool)); f.close()
gmt=[]
for nm in ("reactome.gmt","kegg.gmt","go_bp.gmt"):
    p=f"{WS}/fs_long/work/{nm}"
    if os.path.exists(p):
        for ln in open(p):
            q=ln.rstrip("\n").split("\t")
            if len(q)>=3: gmt.append(set(q[2:]))
set_of={}
for j,s in enumerate(gmt):
    for g in s: set_of.setdefault(g,[]).append(j)
RP=256; R=np.random.RandomState(1).randn(len(gmt),RP).astype(np.float32)/np.sqrt(RP)
for c in ["Rest"]:
    sel=np.where(mask&(cond==c))[0]; seen={}; rows=[]
    for r in sel:
        if ko[r] not in seen: seen[ko[r]]=1; rows.append(r)
    rows=np.array(rows); kos=ko[rows]; n=len(rows)
    Yc=Y[rows].astype(np.float32); Yc-=Yc.mean(0,keepdims=True)
    F=np.zeros((n,RP),np.float32)
    for a,g in enumerate(kos):
        js=set_of.get(g,[])
        if js: F[a]=R[js].sum(0)
    F=(F-F.mean(0))/(F.std(0)+1e-6)
    cnt={}
    for g in kos:
        for j in set_of.get(g,[]): cnt[j]=cnt.get(j,0)+1
    keep={j:i for i,j in enumerate(j for j,v in cnt.items() if v>=2)}
    Mb=np.zeros((n,max(1,len(keep))),np.float32)
    for a,g in enumerate(kos):
        for j in set_of.get(g,[]):
            kk=keep.get(j)
            if kk is not None: Mb[a,kk]=1.0
    S=(Mb@Mb.T).astype(np.float32); np.fill_diagonal(S,0.0)
    fold=np.random.RandomState(0).permutation(n)%5
    np.savez(f"{OUT}/gears_{c}.npz",Y=Yc,F=F,S=S,fold=fold.astype(np.int64))
    print(f"{c}: n={n} saved Y{Yc.shape} F{F.shape} S{S.shape}",flush=True)
print("EXTRACT_COMPLETE",flush=True)
