import unittest
import numpy as np
from eval_protocols import fold_standardize, adaptation_split, validate_checkpoint_parameters, within_study_fewshot
from calibrated_metrics import nir

class ProtocolTests(unittest.TestCase):
    def test_heldout_cannot_change_training_transform(self):
        tr=np.array([[1.,2.],[3.,4.],[5.,8.]])
        a,_=fold_standardize(tr,np.zeros((2,2)))
        b,_=fold_standardize(tr,np.full((2,2),1e8))
        np.testing.assert_array_equal(a,b)
        np.testing.assert_allclose(a.mean(0),0,atol=1e-6)
    def test_ties_and_extremes(self):
        self.assertEqual(nir([0], [[-1],[1]],0),0.5)
        self.assertEqual(nir([0], [[0],[1],[2]],0),1)
        self.assertEqual(nir([0], [[0],[1],[2]],2),0)
        self.assertEqual(nir([0], [[0],[0],[1]],0),0.75)
    def test_invalid_retrieval(self):
        for bank in ([[0]], [[0],[float('nan')]]):
            with self.assertRaises(ValueError): nir([0],bank,0)
    def test_split_no_overlap_and_singletons(self):
        y=np.array([0]*10+[1]*6+[2]);a,q,o=adaptation_split(y,3,7)
        self.assertFalse(set(a)&set(q)); self.assertEqual(o.tolist(),[16])
        self.assertEqual(len(a),6); self.assertEqual(len(q),10)
        np.testing.assert_array_equal(a,adaptation_split(y,3,7)[0])
    def test_missing_encoder_rejected(self):
        class P: requires_grad=True
        class M:
            def named_parameters(self): return [('encoder.weight',P())]
        with self.assertRaises(ValueError): validate_checkpoint_parameters(M(),{})
        validate_checkpoint_parameters(M(),{'encoder.weight':0})
    def test_study_specific_classifiers(self):
        # Opposite label/feature relationships: pooling would erase this signal.
        y=np.tile(np.repeat([0,1],10),2); studies=np.repeat(['a','b'],20)
        x=np.concatenate([y[:20],1-y[20:]])[:,None].astype(float)
        result=within_study_fewshot(x,y,studies,3,0)
        self.assertEqual(result['n_studies_scored'],2)
        self.assertEqual(result['mean_study_macroF1'],1.)

if __name__=='__main__': unittest.main()
