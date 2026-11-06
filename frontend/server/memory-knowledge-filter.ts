/**
 * The trust boundary for project knowledge reaching the model.
 *
 * `user_notes` are promised "not read by the assistant" (the project Notes UI,
 * see chapter I.4) and `notes_synthesis` is a saved-answer note, not a standing
 * instruction. Only `research_goal` and `project_instruction` are model-read,
 * and those flow through the explicit <project_context> path. Any OTHER path
 * that injects knowledge into the prompt (e.g. the LTM memory-hint path) MUST
 * run rows through this filter first, or a private note could leak into a hint.
 */
export const KNOWLEDGE_HIDDEN_FROM_MODEL = new Set(["user_notes", "notes_synthesis"]);

export function filterModelVisibleKnowledge<T extends { knowledgeType?: string | null; type?: string | null }>(
  knowledge: T[],
): T[] {
  if (!Array.isArray(knowledge)) return [];
  return knowledge.filter(
    (k) => !KNOWLEDGE_HIDDEN_FROM_MODEL.has(String(k?.knowledgeType ?? k?.type ?? "")),
  );
}
