import unittest
from prepare_presentation_quantities import accepted

class PresentationTests(unittest.TestCase):
    def row(self,**kw):return {'Q.Value':'0.001','Global.Q.Value':'0.0001','Precursor.Quantity':'100','Stripped.Sequence':'SIINFEKL',**kw}
    def test_invalid_q_never_passes(self):
        for q in ['NaN','bad','inf','-1','0.1']:
            self.assertIsNotNone(accepted(self.row(**{'Q.Value':q})))
    def test_missing_detection_not_zero_target(self):
        for x in ['0','-1','NaN','']:
            self.assertIsNotNone(accepted(self.row(**{'Precursor.Quantity':x})))
    def test_valid_observation(self):self.assertIsNone(accepted(self.row()))

if __name__=='__main__':unittest.main()
