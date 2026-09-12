import json, tempfile, unittest
from pathlib import Path
import numpy as np
import pandas as pd
from prepare_quantitative_omics import prepare

class AssayTests(unittest.TestCase):
    def test_non_detection_never_zero_label(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); pd.DataFrame({'Genes':['A','B','C'],'s1':[1.,0.,float('nan')]}).to_csv(p/'x.tsv',sep='\t',index=False)
            m=prepare(p/'x.tsv',p/'out','proteome','s3://source','study')
            a=np.load(p/'out/values.npz')
            np.testing.assert_array_equal(a['observed'],[[True,False,False]])
            self.assertEqual(m['coverage']['features'],3)
    def test_negative_and_ambiguous_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            for name,value in [('A',-1.),('A;B',1.)]:
                pd.DataFrame({'Genes':[name],'s1':[value]}).to_csv(p/'x.tsv',sep='\t',index=False)
                with self.assertRaises(ValueError):prepare(p/'x.tsv',p/'out','proteome','s3://source','study')
    def test_count_zero_observed_full_library_scale(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);pd.DataFrame({'Geneid':['A','B'],'Chr':['1','1'],'Start':[1,2],'End':[1,2],
                'Strand':['+','+'],'Length':[1,1],'s1':[0,10]}).to_csv(p/'x.tsv',sep='\t',index=False)
            prepare(p/'x.tsv',p/'out','ribosome','s3://source','study');a=np.load(p/'out/values.npz')
            np.testing.assert_array_equal(a['observed'],[[True,True]])
            np.testing.assert_allclose(a['values'],[[0,np.log1p(1e4)]],rtol=1e-6)

if __name__=='__main__':unittest.main()
