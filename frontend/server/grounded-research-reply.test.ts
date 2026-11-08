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

// The research agent marks its retrieved papers as not answering the question (evidence_answers_question
// = false). An uncited draft is then kept — no "the provided literature does not contain" replacement,
// no off-topic bibliography. Cited or reference-listing drafts keep the strict behaviour above.
const offTopic={success:true,evidence_answers_question:false,answer:'The provided literature does not contain troubleshooting steps [1].',citations:[{title:'Die-attach failure in microelectronics',year:2019,pmid:'1'}]};
it('keeps an uncited draft when the research agent says the evidence does not address the question',()=>{
  const result=groundedResearchReply('Uploads over ~2 GB fail in the browser. Use **Data → Import from URL** with a direct link instead.',offTopic);
  expect(result.usedBackendAnswer).toBe(false);
  expect(result.message).toContain('Import from URL');
  expect(result.message).toContain('not drawn from retrieved sources');
  expect(result.message).not.toContain('microelectronics');
  expect(result.message).not.toContain('provided literature');
});
it('still enforces citations when the off-topic draft cites or lists references',()=>{
  expect(groundedResearchReply('Claim [1].',offTopic).message).toContain('## References');
  expect(groundedResearchReply('Claim.\n\n## References\n\n[1] Invented',offTopic).usedBackendAnswer).toBe(true);
});
it('does not change behaviour when the evidence addresses the question or the verdict is absent',()=>{
  expect(groundedResearchReply('Uncited essay.',{...research,evidence_answers_question:true}).usedBackendAnswer).toBe(true);
  expect(groundedResearchReply('Uncited essay.',research).usedBackendAnswer).toBe(true);
});
it('tells the model not to build on off-topic papers, and gives it none to copy',()=>{
  const ctx=researchEvidenceContext(offTopic);
  expect(ctx).toContain('do NOT address this question');
  expect(ctx).not.toContain('microelectronics');
  expect(ctx).not.toContain('Preserve these reference numbers');
});
it('never keeps the empty-reply placeholder as an answer',()=>{
  const result=groundedResearchReply('I processed your request using the available tools.',offTopic);
  expect(result.message).not.toMatch(/^I processed your request/);
});
