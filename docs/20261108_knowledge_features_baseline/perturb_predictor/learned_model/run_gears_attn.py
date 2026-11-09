"""GEARS-style learned-attention perturbation model (runs in envpin2: real torch+CUDA).
The faithful nonlinear generalization of the neighbor-mean: instead of FIXED shared-set weighting, it
LEARNS which training KOs to attend to. If learned attention beats the neighbor-mean (+0.078 Rest),
the nonlinear lever is real; if not, the neighbor-mean is the frontier for this data.

Inputs (pre-extracted by system-python/h5py into gears_<ctx>.npz): Y[n,G] residual effects,
F[n,d] KO knowledge features (RP of gene-set membership), S[n,n] shared-set kernel (neighbor-mean
baseline), fold[n] 5-fold ids. Proper leave-KO-out: for each test fold, train on the other 4.

Run:  ~/ihlm/envpin2/bin/python run_gears_attn.py Rest
"""
import sys, json, time, numpy as np, torch, torch.nn as nn
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_pertmodel"
ctx=sys.argv[1] if len(sys.argv)>1 else "Rest"
d=np.load(f"{OUT}/gears_{ctx}.npz"); Y=d["Y"].astype(np.float32); F=d["F"].astype(np.float32)
S=d["S"]; fold=d["fold"]; n,G=Y.shape; dev="cuda"
dtop=50
def pear(a,b):
    a=a-a.mean(); b=b-b.mean(); den=np.sqrt((a*a).sum()*(b*b).sum()); return float((a*b).sum()/den) if den>1e-12 else 0.0
def topr(P):
    return np.array([pear(P[i,o],Y[i,o]) for i in range(n) for o in [np.argsort(-np.abs(Y[i]))[:dtop]]])
# neighbor-mean baseline (shared-set weighted), LOO over all
pk=np.zeros_like(Y)
for g in range(n):
    nb=np.where(S[g]>0)[0]
    if len(nb)>0: w=S[g,nb]; pk[g]=(Y[nb]*w[:,None]).sum(0)/w.sum()
nbr_r=float(topr(pk).mean())
print(f"{ctx}: n={n} G={G} | neighbor-mean top{dtop}-r = {nbr_r:+.4f}",flush=True)

class AttnPred(nn.Module):
    def __init__(s,d,e=128):
        super().__init__(); s.mlp=nn.Sequential(nn.Linear(d,256),nn.GELU(),nn.Linear(256,e))
        s.logtau=nn.Parameter(torch.tensor(0.0))
    def emb(s,F): return s.mlp(F)
    def predict(s,q_emb,k_emb,V,self_mask=None):
        logits=q_emb@k_emb.T/torch.exp(s.logtau).clamp(0.05,20)
        if self_mask is not None: logits=logits.masked_fill(self_mask,-1e9)
        A=torch.softmax(logits,dim=1); return A@V

Yt=torch.tensor(Y,device=dev); Ft=torch.tensor(F,device=dev)
preds=np.zeros_like(Y)
for k in range(5):
    te=np.where(fold==k)[0]; tr=np.where(fold!=k)[0]
    tr_t=torch.tensor(tr,device=dev); te_t=torch.tensor(te,device=dev)
    # inner val split of train for early stop
    rng=np.random.RandomState(k); perm=rng.permutation(len(tr)); vi=tr[perm[:len(tr)//6]]; ti=tr[perm[len(tr)//6:]]
    ti_t=torch.tensor(ti,device=dev); vi_t=torch.tensor(vi,device=dev)
    m=AttnPred(F.shape[1]).to(dev); opt=torch.optim.Adam(m.parameters(),lr=1e-3,weight_decay=1e-5)
    best=(1e9,None); bad=0
    selfmask=torch.eye(len(ti),dtype=torch.bool,device=dev)
    for ep in range(400):
        m.train(); opt.zero_grad()
        emb=m.emb(Ft)
        # train: each inner-train KO attends to other inner-train KOs (self-masked) -> reconstruct its Y
        pred=m.predict(emb[ti_t],emb[ti_t],Yt[ti_t],self_mask=selfmask)
        loss=((pred-Yt[ti_t])**2).mean()
        loss.backward(); opt.step()
        if ep%20==0:
            m.eval()
            with torch.no_grad():
                emb=m.emb(Ft)
                vpred=m.predict(emb[vi_t],emb[ti_t],Yt[ti_t])  # val attends to inner-train
                vl=((vpred-Yt[vi_t])**2).mean().item()
            if vl<best[0]-1e-5: best=(vl,{kk:v.detach().clone() for kk,v in m.state_dict().items()}); bad=0
            else: bad+=1
            if bad>=4: break
    if best[1] is not None: m.load_state_dict(best[1])
    m.eval()
    with torch.no_grad():
        emb=m.emb(Ft)
        preds[te]=m.predict(emb[te_t],emb[tr_t],Yt[tr_t]).cpu().numpy()   # test attends to ALL train
    print(f"  fold {k}: done (val_mse={best[0]:.4f})",flush=True)
attn_r=float(topr(preds).mean())
dl=topr(preds)-topr(pk); t=float(dl.mean()/(dl.std(ddof=1)/np.sqrt(len(dl)))) if dl.std()>0 else 0.0
res=dict(ctx=ctx,n=int(n),neighbor_mean=nbr_r,learned_attention=attn_r,attn_minus_neighbor_mean=float(dl.mean()),t=t,frac_pos=float((dl>0).mean()))
json.dump(res,open(f"{OUT}/gears_attn_{ctx}.json","w"),indent=2)
print(f"\n=== {ctx}: learned-attention {attn_r:+.4f}  vs  neighbor-mean {nbr_r:+.4f}  (Δ={dl.mean():+.4f} t={t:+.1f} frac>0={float((dl>0).mean()):.2f}) ===",flush=True)
print("VERDICT:", "ATTENTION BEATS NEIGHBOR-MEAN" if attn_r>nbr_r and t>2 else "neighbor-mean holds (attention does not beat it)",flush=True)
print("GEARS_ATTN_COMPLETE",flush=True)
