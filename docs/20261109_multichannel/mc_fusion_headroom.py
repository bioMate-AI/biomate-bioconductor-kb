# Does LEARNED fusion have headroom over naive concat / best single channel? If not, FM-fusion repair
# is pointless. Nonlinear MLP (early+late fusion) vs logistic-concat vs protein-alone. system py/sklearn.
import numpy as np,json,warnings; warnings.filterwarnings("ignore")
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import average_precision_score
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_mc"; AUD=f"{WS}/eval_repair_20261107"
xs=np.load(f"{WS}/ws_bench/xs_stim.npy"); Xp=np.load(f"{OUT}/Xp144.npy"); y=np.load(f"{OUT}/y.npy")
splits=np.load(f"{AUD}/normalization_20261108/split_indices.npz"); MINPOS=4
concat=np.concatenate([xs,Xp],1)
def strat(sub,frac,rng):
    pos=sub[y[sub]==1]; neg=sub[y[sub]==0]
    a=min(max(MINPOS,int(round(len(pos)*frac))),len(pos)); b=min(max(MINPOS,int(round(len(neg)*frac))),len(neg))
    return np.concatenate([rng.choice(pos,a,False),rng.choice(neg,b,False)])
def logit(X,tr,te):
    s=StandardScaler().fit(X[tr]); return LogisticRegression(C=0.01,max_iter=5000,class_weight="balanced").fit(s.transform(X[tr]),y[tr]).predict_proba(s.transform(X[te]))[:,1]
def mlp(X,tr,te):
    s=StandardScaler().fit(X[tr]); cw={0:1.0,1:float((y[tr]==0).sum()/max(1,(y[tr]==1).sum()))}
    sw=np.array([cw[v] for v in y[tr]])
    m=MLPClassifier(hidden_layer_sizes=(128,),alpha=1e-2,max_iter=300,early_stopping=True).fit(s.transform(X[tr]),y[tr])
    return m.predict_proba(s.transform(X[te]))[:,1]
ARMS={"protein_alone":(logit,Xp),"concat_logit":(logit,concat),"concat_MLP":(mlp,concat)}
rows={}
for frac in [1.0,0.25,0.06]:
    ap={a:[] for a in ARMS}
    for seed in (0,1,2):
        oof={a:np.full(len(y),np.nan) for a in ARMS}
        for fold in range(3):
            st=f"s{seed}_f{fold}"; sub=splits[st+"_labelled"]; te=splits[st+"_test"]
            bud=strat(sub,frac,np.random.RandomState(100*seed+int(frac*100)+fold))
            if y[bud].sum()<MINPOS or (1-y[bud]).sum()<MINPOS: continue
            for a,(fn,X) in ARMS.items(): oof[a][te]=fn(X,bud,te)
        for a in ARMS:
            v=oof[a]; ap[a].append(average_precision_score(y[~np.isnan(v)],v[~np.isnan(v)]))
    rows[frac]=dict(n=int(len(bud)),**{a:float(np.mean(ap[a])) for a in ARMS})
    print(json.dumps({str(frac):rows[frac]}),flush=True)
json.dump(rows,open(f"{OUT}/fusion_headroom.json","w"),indent=2)
print("\n=== fusion headroom: does learned fusion beat naive concat / protein-alone? ===",flush=True)
for frac in [1.0,0.25,0.06]:
    r=rows[frac]; hr=r["concat_MLP"]>max(r["concat_logit"],r["protein_alone"])+0.002
    print(f"~{r['n']:>5} protein_alone={r['protein_alone']:.4f} concat_logit={r['concat_logit']:.4f} concat_MLP={r['concat_MLP']:.4f}  headroom? {'YES' if hr else 'no'}",flush=True)
print("FUSION_HEADROOM_COMPLETE",flush=True)
