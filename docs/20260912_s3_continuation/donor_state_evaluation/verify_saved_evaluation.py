"""Independent saved-output checks; does not import training driver."""
import json
from pathlib import Path
import numpy as np
from scipy.stats import rankdata
P=Path(__file__).resolve().parent
r=json.loads((P/'results.json').read_text())
with np.load(P/'predictions.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
with np.load(P.parent/'target_state_data/targets.npz',allow_pickle=False) as z:t={k:z[k] for k in z.files}
with np.load(P.parent/'baseline_state_data/baseline_aggregates.npz',allow_pickle=False) as z:b={k:z[k] for k in z.files}
for i,record in enumerate(r['aggregation_rows']):
    ix=(t['donor_id']==record['donor'])&(t['culture_condition']==record['condition'])&(t['perturbed_gene_name']==record['target'])
    ref=(b['donor']==record['donor'])&(b['condition']==record['condition'])&(b['pool']=='reference')
    feat=(b['donor']==record['donor'])&(b['condition']==record['condition'])&(b['pool']=='feature')
    assert ref.sum()==feat.sum()==1
    label=np.log1p(t['counts'][ix].sum(0)*10000./t['library_counts'][ix].sum())-np.log1p(b['counts'][ref][0]*10000./b['library_counts'][ref][0])
    state=np.log1p(b['counts'][feat][0]*10000./b['library_counts'][feat][0])
    np.testing.assert_allclose(label,d['Y'][i],rtol=0,atol=1e-14);np.testing.assert_allclose(state,d['state'][i],rtol=0,atol=1e-14)
    assert set(t['source_rows'][ix].tolist())==set(r['source_groups'][i])
checks=0
for fold in r['outer_folds']:
    donor=fold['test_donor'];idx=d[donor+'__test_rows'];assert (d['donor'][idx]==donor).all() and donor not in fold['train_donors']
    assert len(fold['train_donors'])==3
    train=np.where(d['donor']!=donor)[0];known=set(zip(d['target'][train],d['condition'][train]));assert all(k in known for k in zip(d['target'][idx],d['condition'][idx]))
    for method,metrics in fold['metrics'].items():
        pred=d[donor+'__'+method];truth=d['Y'][idx]
        for subset in ['all_readouts','excluding_perturbed_readout']:
            masks=np.ones_like(pred,dtype=bool) if subset=='all_readouts' else d['genes'][None,:]!=d['target'][idx,None]
            mse=[];rho=[]
            for p,y,m in zip(pred,truth,masks):
                mse.append(float(np.mean(np.square(p[m]-y[m]))))
                if m.sum()>=3 and np.ptp(p[m])>1e-8 and np.ptp(y[m])>1e-8:
                    rp=rankdata(p[m]);ry=rankdata(y[m]);rp-=rp.mean();ry-=ry.mean();rho.append(float(rp@ry/np.sqrt((rp@rp)*(ry@ry))))
            np.testing.assert_allclose(np.mean(mse),metrics[subset]['mse'],rtol=0,atol=1e-14)
            if rho:np.testing.assert_allclose(np.mean(rho),metrics[subset]['spearman'],rtol=0,atol=1e-14)
            else:assert metrics[subset]['spearman'] is None
            assert len(rho)==metrics[subset]['spearman_rows'];checks+=1
    for selection in fold['selection'].values():
        assert all(len(x['inner_donor_mse'])==3 for x in selection['grid'])
        assert selection['selected_alpha']==min(selection['grid'],key=lambda x:np.mean(x['inner_donor_mse']))['alpha']
for split in r['inner_splits']:
    fit=set(d['donor'][split['fit_rows']]);val=set(d['donor'][split['validation_rows']]);assert len(fit)==2 and len(val)==1 and not fit&val and split['outer_test_donor'] not in fit|val
result={'status':'passed','labels_and_feature_states_recomputed_from_raw_selected_counts':len(d['Y']),'saved_metric_comparisons':checks,'outer_folds':len(r['outer_folds']),'inner_donor_splits':len(r['inner_splits']),'metric_implementation':'Independent rankdata/dot-product Spearman and direct squared errors','limits':'Does not reload fitted ridge objects; original driver saves predictions and hyperparameter tables'}
(P/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
