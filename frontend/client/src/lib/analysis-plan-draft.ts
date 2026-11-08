import type { Message } from '@shared/schema';

export interface AnalysisPlanCopy {
 introduction: string;
 questionLabel: string;
 evidenceLabel: string;
 requestLabel: string;
}

/** Prepare text only. No data is inferred, no workflow selected and no request sent. */
export function stageAnalysisPlanDraft(
 messages: Message[], answer: Message, setDraft: ((draft: string) => void) | null,
 copy: AnalysisPlanCopy,
): boolean {
 if (!setDraft) return false;
 const index = messages.findIndex(message => message.id === answer.id);
 if (index < 0) return false;
 const question = [...messages.slice(0, index)].reverse().find(message => message.role === 'user' && message.content?.trim());
 const evidence = (answer.metadata?.research_response?.answer || answer.content || '').trim();
 if (!question?.content?.trim() || !evidence) return false;
 setDraft(`${copy.introduction}\n\n${copy.questionLabel}\n${question.content}\n\n${copy.evidenceLabel}\n${evidence}\n\n${copy.requestLabel}\n`);
 return true;
}
