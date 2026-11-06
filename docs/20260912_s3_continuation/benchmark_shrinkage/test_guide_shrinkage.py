import unittest
import numpy as np
from evaluate_guide_shrinkage import attenuation,fit_coefficients
class GuideShrinkageTests(unittest.TestCase):
 def test_known_scale_and_bounds(self):
  a=np.array([2.,4.]);b=np.array([1.,2.])
  self.assertEqual(attenuation([(a,b)]),.5)
  self.assertEqual(attenuation([(a,-b)]),0.)
  self.assertEqual(attenuation([(b,2*a)]),1.)
  self.assertEqual(attenuation([(np.zeros(2),a)]),0.)
 def test_invalid_effects_rejected(self):
  for a,b in [(np.array([np.nan]),np.ones(1)),(np.ones(2),np.ones(3)),(np.ones((2,2)),np.ones((2,2)))]:
   with self.assertRaises(ValueError):attenuation([(a,b)])
 def test_heldout_and_direct_outputs_cannot_change_fit(self):
  raw={'counts':np.array([[1.,2.,3.],[2.,3.,2.],[4.,2.,1.],[1.,3.,2.]]),'library_counts':np.full(4,10.),'donor_id':np.array(['train','train','test','test']),'culture_condition':np.array(['c']*4),'perturbed_gene_name':np.array(['A']*4),'guide_id':np.array(['g1','g2','g1','g2'])}
  d={'donor':np.array(['train','test']),'condition':np.array(['c','c']),'target':np.array(['A','A']),'genes':np.array(['A','B','C']),'control':{('train','c','feature'):np.zeros(3),('train','c','reference'):np.zeros(3)}}
  initial=fit_coefficients(raw,d,np.array([0]));raw['counts'][2:]=np.nan;raw['counts'][:2,0]=1e9
  self.assertEqual(initial,fit_coefficients(raw,d,np.array([0])))
if __name__=='__main__':unittest.main()
