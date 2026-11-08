import unittest,tempfile
from pathlib import Path
import numpy as np
from test_baseline_state import fixture
from evaluate_downstream_state import prepare,ridge,baseline_predictions,evaluate,mask_without_target
class DownstreamTests(unittest.TestCase):
 def test_direct_labels_cannot_change_fits_or_baselines(self):
  d=prepare(*fixture());tr=np.where(d['donor']!='d4')[0];te=np.where(d['donor']=='d4')[0];p=ridge(d,tr,te,1.,'baseline_state');b=baseline_predictions(d,tr,te)
  for i in range(len(d['Y'])):d['Y'][i,d['genes']==d['target'][i]]+=1e9
  np.testing.assert_array_equal(p,ridge(d,tr,te,1.,'baseline_state'))
  for k in b:np.testing.assert_array_equal(b[k],baseline_predictions(d,tr,te)[k])
 def test_direct_labels_cannot_change_selection_or_report(self):
  d=prepare(*fixture())
  with tempfile.TemporaryDirectory() as out:a=evaluate(d,Path(out))
  for i in range(len(d['Y'])):d['Y'][i,d['genes']==d['target'][i]]+=1e9
  with tempfile.TemporaryDirectory() as out:b=evaluate(d,Path(out))
  self.assertEqual(a,b)
if __name__=='__main__':unittest.main()
