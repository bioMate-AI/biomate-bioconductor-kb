# system py: hardened zero-shot — gold-label accuracy, bidirectional, common shared types only.
import numpy as np,json,warnings,itertools; warnings.filterwarnings("ignore")
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score
from collections import Counter
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_zh"; names=["io","imid","infectious_control"]
D={n:dict(log=np.load(f"{OUT}/{n}_log.npy"),fm=np.load(f"{OUT}/{n}_fmz.npy"),
          ct=np.load(f"{OUT}/{n}_ct.npy",allow_pickle=True).astype(str)) for n in names}
def transfer(Xa,ya,Xb,yb,mi):
    s=StandardScaler().fit(Xa); clf=LogisticRegression(C=1.0,max_iter=mi,solver="lbfgs",n_jobs=-1,class_weight="balanced").fit(s.transform(Xa),ya)
    p=clf.predict(s.transform(Xb)); return float(accuracy_score(yb,p)), float(f1_score(yb,p,average="macro"))
rows=[]
for a,b in itertools.permutations(names,2):
    ca,cb=Counter(D[a]["ct"]),Counter(D[b]["ct"])
    sh=sorted([t for t in set(D[a]["ct"])&set(D[b]["ct"]) if ca[t]>=50 and cb[t]>=50])  # common types only
    ia=np.isin(D[a]["ct"],sh); ib=np.isin(D[b]["ct"],sh); ya=D[a]["ct"][ia]; yb=D[b]["ct"][ib]
    reps={}
    for r in ["raw","pca","fm"]:
        if r=="raw": Xa,Xb=D[a]["log"][ia],D[b]["log"][ib]; mi=300
        elif r=="fm": Xa,Xb=D[a]["fm"][ia],D[b]["fm"][ib]; mi=1000
        else:
            mu,sd=D[a]["log"][ia].mean(0),D[a]["log"][ia].std(0)+1e-6
            pc=PCA(50,random_state=0).fit((D[a]["log"][ia]-mu)/sd)
            Xa=pc.transform((D[a]["log"][ia]-mu)/sd); Xb=pc.transform((D[b]["log"][ib]-mu)/sd); mi=1000
        acc,f1=transfer(Xa,ya,Xb,yb,mi); reps[r]=dict(acc=acc,f1=f1)
    rows.append(dict(src=a,tgt=b,n_shared=len(sh),n_test=int(ib.sum()),**{f"{r}_{k}":reps[r][k] for r in reps for k in ("acc","f1")}))
    print(f"{a[:4]}->{b[:4]} shared={len(sh):2d} ntest={int(ib.sum()):5d} | acc raw={reps['raw']['acc']:.3f} pca={reps['pca']['acc']:.3f} fm={reps['fm']['acc']:.3f} | f1 raw={reps['raw']['f1']:.3f} pca={reps['pca']['f1']:.3f} fm={reps['fm']['f1']:.3f}",flush=True)
json.dump(rows,open(f"{OUT}/zh_results.json","w"),indent=2)
def mn(k): return float(np.mean([r[k] for r in rows]))
print(f"\n=== MEAN over 6 directed transfers (common shared types) ===",flush=True)
print(f"accuracy: raw {mn('raw_acc'):.4f}  pca {mn('pca_acc'):.4f}  fm {mn('fm_acc'):.4f}",flush=True)
print(f"macro-F1: raw {mn('raw_f1'):.4f}  pca {mn('pca_f1'):.4f}  fm {mn('fm_f1'):.4f}",flush=True)
print(f"FM best-accuracy in {sum(r['fm_acc']>max(r['raw_acc'],r['pca_acc']) for r in rows)}/6",flush=True)
print("ZH_SCORE_COMPLETE",flush=True)
