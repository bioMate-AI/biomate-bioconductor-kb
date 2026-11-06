import { describe, it, expect } from "vitest";
import { filterModelVisibleKnowledge, KNOWLEDGE_HIDDEN_FROM_MODEL } from "./memory-knowledge-filter";

describe("filterModelVisibleKnowledge — the notes trust boundary", () => {
  it("excludes user_notes and notes_synthesis; keeps research_goal + project_instruction", () => {
    const rows = [
      { knowledgeType: "user_notes", title: "a private human note" },
      { knowledgeType: "project_instruction", title: "report FDR<0.05" },
      { knowledgeType: "notes_synthesis", title: "saved answer" },
      { knowledgeType: "research_goal", title: "characterise the target" },
    ];
    const out = filterModelVisibleKnowledge(rows);
    expect(out.map((r) => r.knowledgeType)).toEqual(["project_instruction", "research_goal"]);
  });

  it("user_notes can never reach the model via the memory-hint path", () => {
    const rows = [{ knowledgeType: "user_notes", title: "SECRET", content: "do not share" }];
    expect(filterModelVisibleKnowledge(rows)).toHaveLength(0);
  });

  it("falls back to the `type` field when knowledgeType is absent", () => {
    const rows = [
      { type: "user_notes", title: "note" },
      { type: "project_instruction", title: "keep" },
    ];
    expect(filterModelVisibleKnowledge(rows).map((r) => r.type)).toEqual(["project_instruction"]);
  });

  it("is null/shape safe", () => {
    expect(filterModelVisibleKnowledge(undefined as any)).toEqual([]);
    expect(filterModelVisibleKnowledge([{} as any])).toHaveLength(1); // unknown type → visible (only the two are hidden)
  });

  it("the hidden set is exactly the two human-only stores", () => {
    expect([...KNOWLEDGE_HIDDEN_FROM_MODEL].sort()).toEqual(["notes_synthesis", "user_notes"]);
  });
});
