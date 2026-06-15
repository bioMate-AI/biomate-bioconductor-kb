/**
 * Tests for the token-budget-aware chat-history selector.
 *
 * The selector resolves a tension surfaced by two real-world findings:
 *   - wjunlin@HKU's 25-turn chat (docs/20260610_REAL_USER_FULL_CHAT_LOGS.md)
 *     proved that dropping early dataset-attachment messages breaks the
 *     LLM's ability to refer back to attached files.
 *   - The user's review of that fix (docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md
 *     Q3) flagged that naively bumping the slice window risks bloating
 *     the prompt to 50K+ tokens of chat history.
 *
 * These tests pin both halves of that contract.
 */
import { describe, expect, it } from "vitest";
import { selectChatHistoryUnderBudget, DATASET_BLOCK_RE, type ChatMessage } from "./chat-history-selector";

function bytes(s: string) { return Buffer.byteLength(s, "utf8"); }
function totalBytes(msgs: ChatMessage[]) { return msgs.reduce((acc, m) => acc + bytes(m.content), 0); }

describe("selectChatHistoryUnderBudget", () => {
  it("returns [] for empty input", () => {
    expect(selectChatHistoryUnderBudget([])).toEqual([]);
  });

  it("keeps dataset-attachment messages verbatim — wjunlin UUID round-trip", () => {
    const attach1 = "[Galaxy dataset: gse22055_expression.csv (id: f796f3f2-efd5-45c8-abfa-af346006206f)]";
    const attach2 = "[Galaxy dataset: clinical_gse22055.csv (id: 5cf7a795-565d-487e-bdb6-47a9859ff02d)]";
    const msgs: ChatMessage[] = [
      { role: "user", content: attach1 },
      { role: "assistant", content: "Got the expression matrix." },
      { role: "user", content: attach2 },
      { role: "assistant", content: "Got the clinical metadata." },
    ];
    for (let i = 0; i < 25; i++) {
      msgs.push({ role: "user", content: `chat ${i}` });
      msgs.push({ role: "assistant", content: "a".repeat(8 * 1024) }); // 8 KB bloat each
    }

    const out = selectChatHistoryUnderBudget(msgs);
    const flat = out.map(m => m.content).join("\n");

    // BOTH UUIDs survive verbatim
    expect(flat).toContain("f796f3f2-efd5-45c8-abfa-af346006206f");
    expect(flat).toContain("5cf7a795-565d-487e-bdb6-47a9859ff02d");
    // Both full attachment lines survive
    expect(flat).toContain(attach1);
    expect(flat).toContain(attach2);
  });

  it("enforces the byte budget even with very bloated assistant replies", () => {
    const msgs: ChatMessage[] = [];
    for (let i = 0; i < 50; i++) {
      msgs.push({ role: "user", content: `Q${i}` });
      msgs.push({ role: "assistant", content: "X".repeat(20 * 1024) }); // 20 KB each
    }
    const out = selectChatHistoryUnderBudget(msgs, { byteBudget: 16 * 1024 });
    // Allow a small overshoot for the single oversized-dataset escape hatch
    // (not exercised here) but assert we are well below the naive 1MB+ size.
    expect(totalBytes(out)).toBeLessThanOrEqual(16 * 1024 + 4 * 1024);
  });

  it("preserves chronological order of selected messages", () => {
    const msgs: ChatMessage[] = [];
    for (let i = 0; i < 10; i++) {
      msgs.push({ role: "user", content: `msg-${i}` });
    }
    const out = selectChatHistoryUnderBudget(msgs);
    const ids = out.map(m => m.content.match(/msg-(\d+)/)?.[1]).map(n => n ? Number(n) : null);
    const filtered = ids.filter((n): n is number => n !== null);
    for (let i = 1; i < filtered.length; i++) {
      expect(filtered[i]).toBeGreaterThan(filtered[i - 1]);
    }
  });

  it("truncates long assistant replies — head + tail kept, middle elided", () => {
    const longAssistant = "BEGIN-" + "x".repeat(20_000) + "-END";
    const msgs: ChatMessage[] = [
      { role: "user", content: "go" },
      { role: "assistant", content: longAssistant },
      { role: "user", content: "next" },
    ];
    const out = selectChatHistoryUnderBudget(msgs, { perMessageMaxChars: 600 });
    const assistantOut = out.find(m => m.role === "assistant");
    expect(assistantOut).toBeDefined();
    expect(assistantOut!.content.startsWith("BEGIN-")).toBe(true);
    expect(assistantOut!.content.endsWith("-END")).toBe(true);
    expect(assistantOut!.content).toContain("truncated for context budget");
    expect(assistantOut!.content.length).toBeLessThan(1000);
  });

  it("does NOT lose a dataset attachment even when it appears in a 30-message-old turn", () => {
    const attach = "[Galaxy dataset: pinned.csv (id: deadbeef-1234-cafe-babe-0000)]";
    const msgs: ChatMessage[] = [
      { role: "user", content: attach },
    ];
    for (let i = 0; i < 40; i++) {
      msgs.push({ role: "user", content: `later turn ${i}` });
      msgs.push({ role: "assistant", content: "y".repeat(2 * 1024) });
    }
    const out = selectChatHistoryUnderBudget(msgs);
    expect(out.some(m => m.content.includes("deadbeef-1234-cafe-babe-0000"))).toBe(true);
  });

  it("DATASET_BLOCK_RE matches the three real input shapes", () => {
    expect(DATASET_BLOCK_RE.test("[Galaxy dataset: x.csv (id: 1)]")).toBe(true);
    expect(DATASET_BLOCK_RE.test("[Uploaded datasets: x.csv: dataset_id=abc]")).toBe(true);
    expect(DATASET_BLOCK_RE.test("[Uploaded dataset: x.csv]")).toBe(true);
    expect(DATASET_BLOCK_RE.test("[Attached files: x.csv]")).toBe(true);
    expect(DATASET_BLOCK_RE.test("[Attached file: x.csv]")).toBe(true);
    expect(DATASET_BLOCK_RE.test("see attached dataset")).toBe(false);
  });
});
