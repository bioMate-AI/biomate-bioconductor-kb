import unittest
import json
import tempfile
from pathlib import Path
from unittest.mock import patch
from sklearn.preprocessing import StandardScaler
import evaluate_baseline_state as module
import numpy as np
from evaluate_baseline_state import prepare,donor_permutation,features,ridge,seen_rows,score,mask_without_target

def fixture():
    genes=np.array(['A','B','C']);rows=[];baseline=[]
    for j,donor in enumerate(['d1','d2','d3','d4']):
      for cond in ['rest','stim']:
        for pool in ['feature','reference']:baseline.append((donor,cond,pool,[10+j,20,30]))
        for target in ['A','B']:
          for guide in ['g1','g2']:rows.append((donor,cond,target,guide,[15+j,25,30]))
    t={'counts':np.array([r[4] for r in rows]),'library_counts':np.full(len(rows),1000),'n_cells':np.ones(len(rows)),'donor_id':np.array([r[0] for r in rows]),'culture_condition':np.array([r[1] for r in rows]),'perturbed_gene_name':np.array([r[2] for r in rows]),'guide_id':np.array([r[3] for r in rows]),'source_rows':np.arange(len(rows)),'gene_symbols':genes}
    b={'counts':np.array([r[3] for r in baseline]),'library_counts':np.full(len(baseline),1000),'donor':np.array([r[0] for r in baseline]),'condition':np.array([r[1] for r in baseline]),'pool':np.array([r[2] for r in baseline]),'gene_symbols':genes}
    return t,b
class TestState(unittest.TestCase):
 def test_full_library_and_control_reference(self):
    t,b=fixture();d=prepare(t,b)
    np.testing.assert_allclose(d['Y'][0],np.log1p(np.array([15,25,30])*10)-np.log1p(np.array([10,20,30])*10))
    np.testing.assert_allclose(d['state'][0],np.log1p(np.array([10,20,30])*10))
    self.assertEqual(d['records'][0]['profiles'],2)
 def test_invalid_counts_and_duplicate_control(self):
    t,b=fixture();t['counts']=t['counts'].astype(float);t['counts'][0,0]=.5
    with self.assertRaises(ValueError):prepare(t,b)
    t,b=fixture();b['pool'][1]='feature'
    with self.assertRaises(ValueError):prepare(t,b)
 def test_gene_order_and_duplicate_rows(self):
    t,b=fixture();b['gene_symbols']=b['gene_symbols'][::-1]
    with self.assertRaises(ValueError):prepare(t,b)
    t,b=fixture();t['source_rows'][1]=0
    with self.assertRaises(ValueError):prepare(t,b)
 def test_test_labels_not_used_by_fit(self):
    d=prepare(*fixture());tr=np.where(d['donor']!='d4')[0];te=np.where(d['donor']=='d4')[0]
    original=ridge(d,tr,te,1.,'baseline_state');d['Y'][te]+=1e6
    np.testing.assert_array_equal(original,ridge(d,tr,te,1.,'baseline_state'))
 def test_training_state_unchanged_by_test_values(self):
    d=prepare(*fixture());tr=np.where(d['donor']!='d4')[0];te=np.where(d['donor']=='d4')[0]
    original,_=features(d,tr,te,True);d['state'][te]+=1e6
    changed,_=features(d,tr,te,True);np.testing.assert_array_equal(original,changed)
 def test_shuffle_grouping_and_disjointness(self):
    d=prepare(*fixture());tr=np.where(d['donor']!='d4')[0];te=np.where(d['donor']=='d4')[0]
    mapping=donor_permutation(d['donor'][tr]);self.assertEqual(set(mapping),set(mapping.values()));self.assertTrue(all(k!=v for k,v in mapping.items()))
    x,_=features(d,tr,te,True,True)
    for j,i in enumerate(tr):np.testing.assert_array_equal(x[j,-3:],d['control'][(mapping[d['donor'][i]],d['condition'][i],'feature')])
 def test_actual_scaler_fit_and_donor_guard(self):
    d=prepare(*fixture());tr=np.where(d['donor']!='d4')[0];te=np.where(d['donor']=='d4')[0]
    d['state'][te]+=1e6;expected,_=features(d,tr,te,True);seen=[]
    original=StandardScaler.fit
    def spy(instance,x,*args,**kwargs):
        seen.append(x.copy());return original(instance,x,*args,**kwargs)
    with patch.object(StandardScaler,'fit',spy):ridge(d,tr,te,1.,'baseline_state')
    self.assertEqual(len(seen),1);np.testing.assert_array_equal(seen[0],expected)
    with self.assertRaises(ValueError):ridge(d,tr,tr[:1],1.,'baseline_state')
 def test_nonempty_exclusions_serialize(self):
    d=prepare(*fixture());d['target'][0]='Z'
    with tempfile.TemporaryDirectory() as out:r=module.evaluate(d,Path(out))
    self.assertTrue(any(x['excluded_unseen_target_condition_rows'] for x in r['outer_folds']))
    json.dumps(r,allow_nan=False)
 def test_control_provenance_overlap_and_aggregation(self):
    t,b=fixture();n=len(b['counts'])
    c={'counts':b['counts'].copy(),'library_counts':b['library_counts'].copy(),'source_rows':np.arange(100,100+n),'gene_symbols':b['gene_symbols'],'guide_id':np.array(['ntc'+str(i) for i in range(n)]),'pool':b['pool'].copy(),'donor_id':b['donor'],'culture_condition':b['condition']}
    self.assertTrue(module.validate_controls(t,b,c)['aggregates_recomputed_exactly'])
    c['source_rows'][0]=0
    with self.assertRaises(ValueError):module.validate_controls(t,b,c)
    c['source_rows'][0]=100;c['guide_id'][1]=c['guide_id'][0]
    with self.assertRaises(ValueError):module.validate_controls(t,b,c)
    c['guide_id'][1]='ntc1';c['counts'][0,0]+=1
    with self.assertRaises(ValueError):module.validate_controls(t,b,c)
 def test_all_inner_folds_disjoint(self):
    d=prepare(*fixture())
    with tempfile.TemporaryDirectory() as out:r=module.evaluate(d,Path(out))
    self.assertEqual(len(r['outer_folds']),4);self.assertEqual(len(r['inner_splits']),12)
    for split in r['inner_splits']:
        fit=set(d['donor'][split['fit_rows']]);val=set(d['donor'][split['validation_rows']])
        self.assertFalse(fit&val);self.assertNotIn(split['outer_test_donor'],fit|val)
    for outer in r['outer_folds']:
        for selection in outer['selection'].values():
            self.assertEqual(len(selection['grid']),3)
            self.assertTrue(all(len(g['inner_donor_mse'])==3 for g in selection['grid']))
 def test_seen_filter_and_metric_exclusion(self):
    d=prepare(*fixture());tr=np.where(d['donor']!='d4')[0];te=np.where(d['donor']=='d4')[0];d['target'][te[0]]='Z'
    self.assertEqual(len(seen_rows(d,tr,te)),len(te)-1)
    r=score(np.zeros((1,3)),np.ones((1,3)),np.ones((1,3),bool));self.assertIsNone(r['spearman']);self.assertEqual(r['mse'],1)
    masks=mask_without_target(d,te);self.assertTrue(masks[0].all());self.assertEqual(masks[1].sum(),2)
if __name__=='__main__':unittest.main()
