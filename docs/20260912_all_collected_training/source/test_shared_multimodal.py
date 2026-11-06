import unittest
import torch
from shared_multimodal_trainer import SharedMultimodalEncoder,reconstruction,knowledge_regularizer,CanonicalAdapter
class Multi(unittest.TestCase):
 def test_all_assay_gradients_and_knowledge(self):
  torch.manual_seed(1);torch.set_num_threads(1);m=SharedMultimodalEncoder(9,16,1,4)
  b={'ids':torch.arange(9).reshape(3,3),'values':torch.randn(3,3),'valid':torch.ones(3,3,dtype=torch.bool),'modality':torch.arange(3)[:,None].expand(-1,3)}
  b['values'][2]=torch.tensor([0.,1.,0.]);loss,z,terms=reconstruction(m,b);self.assertEqual(set(terms),{0,1,2});edges=torch.tensor([[0.,1.,1.],[2.,3.,-1.]]);total=loss+.1*knowledge_regularizer(m,edges);total.backward()
  for h in m.modality_readout:self.assertGreater(h.weight.grad.abs().sum(),0)
  self.assertTrue(torch.isfinite(z).all())
 def test_absent_nan_is_not_observation(self):
  torch.manual_seed(1);m=SharedMultimodalEncoder(4,16,1,4).eval();ids=torch.tensor([[0,1,99]]);v=torch.tensor([[1.,2.,float('nan')]]);valid=torch.tensor([[True,True,False]]);mod=torch.tensor([[0,1,99]])
  a,z=m(ids,v,valid,torch.zeros_like(valid),mod);self.assertTrue(torch.isfinite(z).all())
 def test_h1_uses_shared_multimodal_latent(self):
  torch.manual_seed(1);m=SharedMultimodalEncoder(3,16,1,4);adapter=CanonicalAdapter(m,{'cell_dim':16,'perturbation_dim':2,'machinery_dim':8,'n_transcripts':3,'protein_to_transcript':[0,1],'peptide_dim':4,'hla_dim':2})
  b={'ids':torch.tensor([[0,1,2]]),'values':torch.rand(1,3),'valid':torch.ones(1,3,dtype=torch.bool),'modality':torch.tensor([[0,1,2]])};labels={'h1_transcription_delta':{'value':torch.rand(1,3),'observed':torch.ones(1,3,dtype=torch.bool)}}
  loss,_,_=adapter.measured_batch(b,torch.rand(1,2),labels,{'h1_transcription_delta':1.});loss.backward();self.assertGreater(m.genes.weight.grad.abs().sum(),0)
if __name__=='__main__':unittest.main()
