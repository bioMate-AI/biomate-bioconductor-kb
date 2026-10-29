import {it,expect} from 'vitest';
import {groundedResearchReply,researchEvidenceContext} from './grounded-research-reply';
const research={success:true,answer:'Grounded finding [1].',citations:[{title:'Real paper',year:2025,pmid:'123'}]};
it('rejects a new inferred reference and uses the original answer and real bibliography',()=>{
  const result=groundedResearchReply('Changed claim [1, 9].\n\n## References\n\n[9] Inferred consensus',research);
  expect(result.usedBackendAnswer).toBe(true);
  expect(result.message).toContain('Grounded finding [1].');
  expect(result.message).not.toContain('Inferred');
  expect(result.message).not.toContain('[9]');
});
it('always builds reference metadata from the actual returned sources, not model inventions',()=>{
  const result=groundedResearchReply('Paraphrase [1].\n\n## References\n\n[1] Invented title PMID:999',research);
  expect(result.usedBackendAnswer).toBe(true);
  expect(result.message).toContain('Real paper (2025) PMID: 123');
  expect(result.message).not.toContain('999');
});
it('fails closed for missing references or invalid canonical citation markers',()=>{
  expect(groundedResearchReply('Fake [1]',{success:true,answer:'x',citations:[]}).message).toContain('could not be verified');
  expect(groundedResearchReply('Fake [1]',{...research,answer:'Bad [2]'}).message).toContain('could not be verified');
});
it('handles grouped and range markers without accepting an out-of-range endpoint',()=>{
  expect(groundedResearchReply('Claim [1–3]',research).usedBackendAnswer).toBe(true);
});
it('retains the ninth reference, abstracts and the full answer instead of cutting their mapping',()=>{
  const answer='x'.repeat(5000)+' last finding [9].';
  const citations=Array.from({length:9},(_,i)=>({title:`Paper ${i+1}`,pmid:String(100+i),abstract:`Actual abstract ${i+1}`}));
  const context=researchEvidenceContext({answer,citations});
  expect(context).toContain(answer);
  expect(context).toContain('[9] Paper 9');
  expect(context).toContain('Actual abstract 9');
  expect(context).toContain('preclinical');
});
it('rejects inferred bibliography entries even if the number happens to be in range',()=>{
  const result=groundedResearchReply('Invented interpretation [1].\n\n## References\n\n[1] (Inferred from consensus)',research);
  expect(result.usedBackendAnswer).toBe(true);
  expect(result.message).toContain('Grounded finding [1].');
});
