import { afterEach, describe, expect, it, vi } from 'vitest';
import { stageAnalysisPlanDraft } from './analysis-plan-draft';
import type { Message } from '@shared/schema';
const copy = { introduction:'Help me plan an analysis using my data.', questionLabel:'Previous question:', evidenceLabel:'Literature context (not validated against my data):', requestLabel:'My dataset and analysis question:' };
const answer = { id:'a', role:'assistant', content:'', metadata:{type:'research_response',research_response:{answer:'Treatment X has literature support.',citations:[]}},timestamp:new Date() } as Message;
const question = { id:'q',role:'user',content:'What evidence supports treatment X?',timestamp:new Date() } as Message;
afterEach(() => vi.unstubAllGlobals());
describe('research analysis planning draft', () => {
 it('preserves the owning question and evidence but sends nothing', () => {
  const fetcher=vi.fn();vi.stubGlobal('fetch',fetcher);
  const setDraft=vi.fn();
  expect(stageAnalysisPlanDraft([question,answer,{...question,id:'later',content:'Unrelated question'}],answer,setDraft,copy)).toBe(true);
  const draft=setDraft.mock.calls[0][0];
  expect(draft).toContain(question.content);
  expect(draft).toContain('Treatment X has literature support.');
  expect(draft).toContain('not validated against my data');
  expect(draft).not.toContain('Unrelated question');
  expect(draft.endsWith('My dataset and analysis question:\n')).toBe(true);
  expect(fetcher).not.toHaveBeenCalled();
 });
 it('does not overwrite a draft when context or the composer is unavailable', () => {
  const setter=vi.fn();
  expect(stageAnalysisPlanDraft([question,answer],answer,null,copy)).toBe(false);
  expect(stageAnalysisPlanDraft([question],answer,setter,copy)).toBe(false);
  expect(stageAnalysisPlanDraft([answer],answer,setter,copy)).toBe(false);
  expect(setter).not.toHaveBeenCalled();
 });
});
