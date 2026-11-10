# system py: zero-shot cross-dataset transfer. Train D534-type classifier in each space on A, apply to
# B (GSE239626), score correspondence of transferred labels to B's own ADTc clusters (NMI/ARI).
# FM's shared space should transfer where A-fit PCA cannot.
import numpy as np,json,warnings; warnings.filterwarnings("ignore")
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import normalized_mutual_info_score as NMI, adjusted_rand_score as ARI
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_zs"
HA=np.load(f"{OUT}/HA_log.npy"); HB=np.load(f"{OUT}/HB_log.npy")
fmA=np.load(f"{OUT}/fmA.npy"); fmB=np.load(f"{OUT}/fmB.npy")
ctA=np.load(f"{OUT}/ctA.npy",allow_pickle=True).astype(str); ctB=np.load(f"{OUT}/ctB.npy",allow_pickle=True).astype(str)
clsA=sorted(set(ctA)); yA=np.array([clsA.index(c) for c in ctA])
def transfer(Xa,Xb):
    s=StandardScaler().fit(Xa); a=s.transform(Xa); b=s.transform(Xb)
    clf=LogisticRegression(C=1.0,max_iter=2000,tol=1e-3,solver="saga",n_jobs=-1,class_weight="balanced").fit(a,yA)
    return clf.predict(b)
# PCA fit on A, project B into A's space
pca=PCA(50,random_state=0).fit(StandardScaler().fit_transform(HA))
def pca_proj(X,Xa_mean,Xa_std): return pca.transform((X-Xa_mean)/Xa_std)
mu,sd=HA.mean(0),HA.std(0)+1e-6
REPS={"raw":(HA,HB),"pca":(pca.transform((HA-mu)/sd),pca.transform((HB-mu)/sd)),"fm":(fmA,fmB)}
res={}
for r,(Xa,Xb) in REPS.items():
    predB=transfer(Xa,Xb)
    res[r]=dict(nmi=float(NMI(ctB,predB)),ari=float(ARI(ctB,predB)),n_pred_types=int(len(set(predB))))
    print(f"{r}: transfer->B  NMI={res[r]['nmi']:.4f}  ARI={res[r]['ari']:.4f}  ({res[r]['n_pred_types']} types used)",flush=True)
json.dump(res,open(f"{OUT}/zs_results.json","w"),indent=2)
best=max(res,key=lambda r:res[r]["nmi"])
print(f"\nZERO-SHOT CROSS-DATASET winner (NMI): {best}",flush=True)
print(f"FM beats raw+PCA? {res['fm']['nmi']>max(res['raw']['nmi'],res['pca']['nmi'])}",flush=True)
print("ZS_SCORE_COMPLETE",flush=True)
