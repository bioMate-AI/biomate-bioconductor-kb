#!/bin/bash
# DIFFERENTIATOR experiment: does conformer-ensemble 3D-PSA "span" (the molecular-chameleon signal:
# polar-surface reorganization across conformers) improve cyclic-peptide permeability prediction over
# the 216 static 2D descriptors (which plateau ~R2 0.45)? Controlled: 2D-only vs 2D+ensemble-span on the
# SAME subsample. RDKit ETKDG-macrocycle ensembles + rdFreeSASA polar-SASA(3D-PSA) + Rgyr per conformer.
# Robust: multiprocessing, per-molecule timeout, INTERNAL time budget (stop featurizing, run ML on
# whatever completed), periodic progress. CPU. Honest caveat: survey found ensemble *variance* may carry
# <2% signal — this VALIDATES the hypothesis, doesn't assume it.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/cperm; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
NSUB=${NSUB:-900}; NCONF=${NCONF:-12}; BUDGET_S=${BUDGET_S:-10800}   # featurize <=3h then ML
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/cperm.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","detail":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "${2:-}" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 5; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 3; shutdown -h now; exit $rc' EXIT
systemd-run --unit=cperm-deadline --on-active=5h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n cperm -c conda-forge python=3.11 rdkit scikit-learn pandas numpy scipy >/dev/null 2>&1
conda activate cperm
python -c "import rdkit; from rdkit.Chem import rdFreeSASA; print('rdkit ok')"

stage fetch_data
aws s3 cp "s3://$BUCKET/cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv" ./cyc.csv --only-show-errors
[ -s ./cyc.csv ] || { echo FATAL no csv; exit 1; }

stage featurize
NSUB=$NSUB NCONF=$NCONF BUDGET_S=$BUDGET_S python - <<'PY'
import os, json, time, numpy as np, pandas as pd
from multiprocessing import Pool
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem, rdMolDescriptors, rdFreeSASA
RDLogger.DisableLog('rdApp.*')
NSUB=int(os.environ['NSUB']); NCONF=int(os.environ['NCONF']); BUDGET=float(os.environ['BUDGET_S']); t0=time.time()

df=pd.read_csv('cyc.csv', low_memory=False)
df=df[pd.to_numeric(df['Permeability'],errors='coerce').notna()].copy(); df['Permeability']=df['Permeability'].astype(float)
# stratified subsample by permeability quartile (representative)
df['q']=pd.qcut(df['Permeability'], 4, labels=False, duplicates='drop')
sub=df.groupby('q', group_keys=False).apply(lambda g: g.sample(min(len(g), NSUB//4), random_state=42))
sub=sub.reset_index(drop=True)
print('subsample:', len(sub))

def ensemble_feats(smi):
    try:
        m=Chem.MolFromSmiles(str(smi))
        if m is None: return None
        m=Chem.AddHs(m)
        p=AllChem.ETKDGv3(); p.useMacrocycleTorsions=True; p.randomSeed=42; p.pruneRmsThresh=0.5; p.numThreads=1
        cids=AllChem.EmbedMultipleConfs(m, numConfs=NCONF, params=p)
        if len(cids)==0: return None
        try: AllChem.MMFFOptimizeMoleculeConfs(m, numThreads=1, maxIters=200)
        except Exception: pass
        # radii for SASA
        radii=rdFreeSASA.classifyAtoms(m)
        polar=[a.GetIdx() for a in m.GetAtoms() if a.GetSymbol() in ('N','O') or
               (a.GetSymbol()=='H' and any(n.GetSymbol() in ('N','O') for n in a.GetNeighbors()))]
        psa=[]; rg=[]
        for cid in cids:
            try:
                rdFreeSASA.CalcSASA(m, radii, confIdx=cid)
                p3=sum(float(m.GetAtomWithIdx(i).GetProp('SASA')) for i in polar)
                psa.append(p3)
                conf=m.GetConformer(cid); pos=conf.GetPositions()
                c=pos.mean(0); rg.append(float(np.sqrt(((pos-c)**2).sum(1).mean())))
            except Exception: continue
        if len(psa)<2: return None
        psa=np.array(psa); rg=np.array(rg)
        return dict(psa_mean=psa.mean(),psa_min=psa.min(),psa_max=psa.max(),psa_span=psa.max()-psa.min(),psa_std=psa.std(),
                    rg_mean=rg.mean(),rg_span=rg.max()-rg.min(),rg_std=rg.std(),nconf=len(psa))
    except Exception:
        return None

smis=list(sub['SMILES']); results=[None]*len(smis); done=0
with Pool(processes=max(1, os.cpu_count()-1)) as pool:
    for i,res in enumerate(pool.imap(ensemble_feats, smis, chunksize=4)):
        results[i]=res; done+=1
        if done % 50 == 0:
            el=time.time()-t0
            open('/opt/cperm/status/status.json','w').write(json.dumps({'stage':'featurize','detail':f'{done}/{len(smis)} el={int(el)}s'}))
            os.system('aws s3 cp /opt/cperm/status/status.json '+os.environ['OUT_S3']+'/status/status.json --only-show-errors 2>/dev/null')
            if el>BUDGET: print('time budget hit, stopping featurization at',done); break

sub=sub.iloc[:len(results)].copy()
ok=[i for i,r in enumerate(results) if r is not None]
print('ensembles computed:', len(ok), '/', len(results))
ens=pd.DataFrame([results[i] for i in ok]); sub2=sub.iloc[ok].reset_index(drop=True)
ens.to_csv('ensemble_feats.csv', index=False)

# 2D features (reuse rich descriptor logic)
drop=set(['ID','Source','Year','Version','Original_Name_in_Source_Literature','Structurally_Unique_ID',
 'Same_Peptides_ID','Same_Peptides_Source','Same_Peptides_Permeability','Same_Peptides_Assay','SMILES','HELM',
 'HELM_URL','Sequence','Molecule_Shape','Permeability','PAMPA','Caco2','MDCK','RRCK','Detection_Limit_1',
 'Detection_Limit_2','R_PAMAP','R_Caco2','R_MDCK','R_RRCK','T_PAMPA','EPSA','NULL','q'])
feat2d=[c for c in sub2.columns if c not in drop]
X2=sub2[feat2d].apply(pd.to_numeric,errors='coerce').replace([np.inf,-np.inf],np.nan)
X2=X2.dropna(axis=1,how='all'); X2=X2.fillna(X2.median(numeric_only=True)).clip(-1e30,1e30)
y=sub2['Permeability'].values.astype(float)
Xe=ens.values.astype(float)
json.dump({'stage':'ml','n':len(y),'n2d':X2.shape[1],'nens':Xe.shape[1]}, open('/opt/cperm/status/status.json','w'))

from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import cross_val_predict, KFold
from sklearn.metrics import r2_score
from scipy.stats import spearmanr
# SHUFFLED KFold — the subsample is ordered by permeability quartile (stratified groupby), so unshuffled
# folds are contiguous target blocks -> model extrapolates -> spurious negative R2. Shuffle fixes it.
KF=KFold(n_splits=5, shuffle=True, random_state=42)
def cv(X):
    p=cross_val_predict(HistGradientBoostingRegressor(max_iter=400,learning_rate=0.05), X, y, cv=KF)
    return {'R2':round(float(r2_score(y,p)),3),'Spearman':round(float(spearmanr(y,p).correlation),3)}
import numpy as np
res={'n':len(y),'nconf_target':NCONF,
     '2D_only': cv(X2.values.astype(float)),
     '2D_plus_ensemble_span': cv(np.hstack([X2.values.astype(float), Xe])),
     'ensemble_only': cv(Xe),
     'note':'Controlled: same subsample, 5-fold CV. Does conformer-ensemble 3D-PSA/Rgyr span add signal '
            'over 216 static 2D descriptors? Honest: survey warns ensemble variance may carry <2% signal.'}
json.dump(res, open('/opt/cperm/status/conformer_permeability.json','w'), indent=2)
print(json.dumps(res, indent=2))
PY
aws s3 cp ensemble_feats.csv "$OUT_S3/ensemble_feats.csv" --only-show-errors || true
stage cperm_complete
