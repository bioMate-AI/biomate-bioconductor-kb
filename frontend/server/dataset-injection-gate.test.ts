/**
 * Tests for the context-aware dataset-injection gate.
 *
 * Per-signal unit tests prove each extractor is correct in isolation.
 * Composition tests prove the gate makes the right call when signals
 * combine. The composition tests are written from the user-story
 * angle in docs/20260613_DATASET_INJECTION_GATE_DESIGN.md — each
 * "counter-example" the doc cites is exercised here.
 */
import { describe, expect, it } from "vitest";
import {
  shouldInjectDatasets,
  messageReferencesData,
  runStateRelevant,
  lastAssistantTurnReferencedData,
  isShortFollowupAfterDataThread,
  historyShowsAnyDataDiscussion,
  intentSuggestsData,
  pureAbstractKnowledgeIntent,
  type ChatTurn,
  type DatasetRef,
} from "./dataset-injection-gate";

const D: DatasetRef[] = [
  { id: "f796f3f2-efd5-45c8-abfa-af346006206f", name: "gse22055_expression.csv", type: "csv" },
  { id: "5cf7a795-565d-487e-bdb6-47a9859ff02d", name: "clinical_gse22055.csv", type: "csv" },
];

describe("messageReferencesData", () => {
  it("matches generic data phrases (the dataset / my counts / file I uploaded)", () => {
    expect(messageReferencesData("show me the dataset", D)).toBe(true);
    expect(messageReferencesData("plot my counts matrix", D)).toBe(true);
    expect(messageReferencesData("use the file I uploaded", D)).toBe(true);
    expect(messageReferencesData("look at the attached csv", D)).toBe(true);
  });

  it("matches an attached dataset name by substring (word-bounded)", () => {
    expect(messageReferencesData("rerun on gse22055_expression.csv", D)).toBe(true);
    expect(messageReferencesData("clinical_gse22055.csv has 92 rows", D)).toBe(true);
  });

  it("matches a Galaxy dataset id (UUID form) in the message", () => {
    expect(messageReferencesData("use f796f3f2-efd5-45c8-abfa-af346006206f", D)).toBe(true);
  });

  it("does NOT match abstract terms with no data reference", () => {
    expect(messageReferencesData("what is BH FDR correction", D)).toBe(false);
    expect(messageReferencesData("compare limma to DESeq2", D)).toBe(false);
    expect(messageReferencesData("how long will this take", D)).toBe(false);
    expect(messageReferencesData("hello", D)).toBe(false);
  });

  it("avoids false positives on short irrelevant tokens", () => {
    // "dataset" not preceded by "the/my/uploaded/attached" must NOT match,
    // unless filename / id matches independently.
    expect(messageReferencesData("dataset", D)).toBe(false);
    expect(messageReferencesData("file size limits", D)).toBe(false);
  });
});

describe("runStateRelevant", () => {
  const NOW = 1_700_000_000_000;
  it("true when a run is active", () => {
    expect(runStateRelevant({ active: true }, NOW)).toBe(true);
  });
  it("true when a run completed within the recent window", () => {
    expect(runStateRelevant({ lastTerminalAt: NOW - 30_000 }, NOW)).toBe(true);
  });
  it("false when last terminal was > 60s ago", () => {
    expect(runStateRelevant({ lastTerminalAt: NOW - 120_000 }, NOW)).toBe(false);
  });
  it("false when no run state given", () => {
    expect(runStateRelevant(undefined, NOW)).toBe(false);
    expect(runStateRelevant({}, NOW)).toBe(false);
  });
});

describe("lastAssistantTurnReferencedData", () => {
  it("true when last assistant text mentions a dataset filename", () => {
    const hist: ChatTurn[] = [
      { role: "user", content: "any thoughts?" },
      { role: "assistant", content: "I'd run DEG on gse22055_expression.csv first." },
    ];
    expect(lastAssistantTurnReferencedData(hist, D)).toBe(true);
  });
  it("true when last assistant text emitted <session_datasets>", () => {
    const hist: ChatTurn[] = [
      { role: "assistant", content: "<session_datasets>...</session_datasets>" },
    ];
    expect(lastAssistantTurnReferencedData(hist, D)).toBe(true);
  });
  it("false when last assistant text is abstract", () => {
    const hist: ChatTurn[] = [
      { role: "assistant", content: "BH FDR corrects p-values across multiple tests." },
    ];
    expect(lastAssistantTurnReferencedData(hist, D)).toBe(false);
  });
  it("false on empty history", () => {
    expect(lastAssistantTurnReferencedData(undefined, D)).toBe(false);
    expect(lastAssistantTurnReferencedData([], D)).toBe(false);
  });
});

describe("isShortFollowupAfterDataThread", () => {
  const dataThread: ChatTurn[] = [
    { role: "user", content: "what about clinical_gse22055.csv?" },
    { role: "assistant", content: "I see clinical_gse22055.csv has 92 samples." },
  ];
  it("true when message is short AND last assistant referenced data", () => {
    expect(isShortFollowupAfterDataThread("yes", dataThread, D)).toBe(true);
    expect(isShortFollowupAfterDataThread("do that", dataThread, D)).toBe(true);
    expect(isShortFollowupAfterDataThread("really?", dataThread, D)).toBe(true);
  });
  it("false when message is short but no data thread", () => {
    const abstractThread: ChatTurn[] = [
      { role: "assistant", content: "FDR controls expected proportion of false positives." },
    ];
    expect(isShortFollowupAfterDataThread("yes", abstractThread, D)).toBe(false);
  });
  it("false when message is long even if data thread", () => {
    const long = "I would like to know exactly how you decided which contrast to apply and why";
    expect(isShortFollowupAfterDataThread(long, dataThread, D)).toBe(false);
  });
});

describe("historyShowsAnyDataDiscussion", () => {
  it("true when any of last 3 turns mention data", () => {
    const hist: ChatTurn[] = [
      // "my counts" matches the data-phrase regex.
      { role: "user", content: "I have my counts ready" },
      { role: "assistant", content: "ok" },
      { role: "user", content: "thanks" },
    ];
    expect(historyShowsAnyDataDiscussion(hist, D)).toBe(true);
  });
  it("false when last 3 turns are abstract knowledge", () => {
    const hist: ChatTurn[] = [
      { role: "user", content: "what is FDR" },
      { role: "assistant", content: "false discovery rate" },
      { role: "user", content: "and BH?" },
    ];
    expect(historyShowsAnyDataDiscussion(hist, D)).toBe(false);
  });
});

describe("intent helpers", () => {
  it("intentSuggestsData covers transformation-intent labels", () => {
    expect(intentSuggestsData("workflow_generation")).toBe(true);
    expect(intentSuggestsData("data_interpretation")).toBe(true);
    expect(intentSuggestsData("parameter_optimization")).toBe(true);
    expect(intentSuggestsData("methods_writing")).toBe(true);
    expect(intentSuggestsData("research_question")).toBe(false);
  });
  it("pureAbstractKnowledgeIntent covers research/comparison/regulatory", () => {
    expect(pureAbstractKnowledgeIntent("research_question")).toBe(true);
    expect(pureAbstractKnowledgeIntent("comparative_methodology")).toBe(true);
    expect(pureAbstractKnowledgeIntent("regulatory_compliance")).toBe(true);
    expect(pureAbstractKnowledgeIntent("data_interpretation")).toBe(false);
  });
  it("intents fall back to false on null/undefined/empty", () => {
    expect(intentSuggestsData(undefined)).toBe(false);
    expect(pureAbstractKnowledgeIntent(null)).toBe(false);
    expect(intentSuggestsData("")).toBe(false);
  });
});

/* ─────────────  Composition / user-story coverage  ──────────────── */

describe("shouldInjectDatasets — counter-examples from the design doc", () => {
  it("'What is BH FDR correction?' → SKIP when no run / no history", () => {
    const r = shouldInjectDatasets({
      message: "What is BH FDR correction?",
      intentType: "research_question",
      datasets: D,
    });
    expect(r.inject).toBe(false);
    expect(r.reason).toBe("pure_abstract_intent_no_signals");
  });

  it("'What is BH FDR correction?' → INJECT when user just ran DEG (runStateRelevant fires)", () => {
    const r = shouldInjectDatasets({
      message: "What is BH FDR correction?",
      intentType: "research_question",
      datasets: D,
      runState: { lastStatus: "completed", lastTerminalAt: Date.now() - 5_000 },
    });
    expect(r.inject).toBe(true);
    expect(r.reason).toBe("run_state_relevant");
  });

  it("'How long will this take?' → INJECT (run-active) — answer depends on dataset size", () => {
    const r = shouldInjectDatasets({
      message: "How long will this take?",
      intentType: "troubleshooting",
      datasets: D,
      runState: { active: true },
    });
    expect(r.inject).toBe(true);
    expect(r.reason).toBe("run_state_relevant");
  });

  it("'Show me a paper on limma' → SKIP correctly (no data thread, abstract intent)", () => {
    const r = shouldInjectDatasets({
      message: "Show me a paper on limma",
      intentType: "research_question",
      datasets: D,
    });
    expect(r.inject).toBe(false);
  });

  it("'Run DESeq2' with NO datasets attached → SKIP (nothing to inject)", () => {
    const r = shouldInjectDatasets({
      message: "Run DESeq2",
      intentType: "workflow_generation",
      datasets: [],
    });
    expect(r.inject).toBe(false);
    expect(r.reason).toBe("no_datasets_attached");
  });

  it("'Run DESeq2' with datasets attached → INJECT", () => {
    const r = shouldInjectDatasets({
      message: "Run DESeq2",
      intentType: "workflow_generation",
      datasets: D,
    });
    expect(r.inject).toBe(true);
  });

  it("'yes' as a short follow-up after a data-thread → INJECT", () => {
    const r = shouldInjectDatasets({
      message: "yes",
      intentType: "research_question",
      datasets: D,
      history: [
        { role: "user", content: "what about clinical_gse22055.csv?" },
        { role: "assistant", content: "I see clinical_gse22055.csv has 92 samples — proceed?" },
      ],
    });
    expect(r.inject).toBe(true);
    expect(r.reason).toBe("short_followup_after_data_thread");
  });

  it("'yes' as a short reply after pure abstract Q → SKIP", () => {
    const r = shouldInjectDatasets({
      message: "yes",
      intentType: "research_question",
      datasets: D,
      history: [
        { role: "user", content: "is BH the same as Benjamini-Hochberg?" },
        { role: "assistant", content: "Yes, it's the same procedure." },
      ],
    });
    expect(r.inject).toBe(false);
  });

  it("workflow_generation intent + recent data mention in history → INJECT", () => {
    const r = shouldInjectDatasets({
      message: "let's set up the next step",
      intentType: "workflow_generation",
      datasets: D,
      history: [
        { role: "user", content: "I have my counts matrix and metadata" },
        { role: "assistant", content: "Got it." },
      ],
    });
    expect(r.inject).toBe(true);
    // Either data_intent_with_history_discussion or default_on
    expect(["data_intent_with_history_discussion", "default_on_no_negative_signals"]).toContain(r.reason);
  });

  it("default-on when intent is unknown / not in either set", () => {
    const r = shouldInjectDatasets({
      message: "let's go",
      intentType: "unknown_intent_label",
      datasets: D,
    });
    expect(r.inject).toBe(true);
    expect(r.reason).toBe("default_on_no_negative_signals");
  });

  it("message naming a dataset filename overrides pure-abstract intent", () => {
    const r = shouldInjectDatasets({
      message: "is gse22055_expression.csv normalized?",
      intentType: "research_question",
      datasets: D,
    });
    expect(r.inject).toBe(true);
    expect(r.reason).toBe("message_references_data");
  });
});

describe("galaxy-assistant.ts wires the gate into sessionDatasetsBlock", () => {
  const fs = require("fs") as typeof import("fs");
  const path = require("path") as typeof import("path");
  const SRC = fs.readFileSync(path.join(__dirname, "galaxy-assistant.ts"), "utf-8");

  it("imports shouldInjectDatasets from ./dataset-injection-gate", () => {
    // galaxy-assistant.ts uses ES module imports, not require()
    expect(
      /import.*shouldInjectDatasets.*from.*['"]\.\/dataset-injection-gate['"]/.test(SRC) ||
      /require\(['"]\.\/dataset-injection-gate['"]\)/.test(SRC)
    ).toBe(true);
    expect(SRC.includes("shouldInjectDatasets")).toBe(true);
  });

  it("calls the gate with message + intent + datasets + history + runState", () => {
    const block = SRC.split("const sessionDatasetsBlock = ")[1]?.split("})();")[0] ?? "";
    expect(block.includes("shouldInjectDatasets({")).toBe(true);
    expect(/message,?\s*[\r\n]/.test(block)).toBe(true);
    expect(/intentType:\s*\(intent as any\)\?\.type/.test(block)).toBe(true);
    expect(/datasets:\s*sd as any/.test(block)).toBe(true);
    expect(/history:\s*\(context as any\)\?\.previousMessages/.test(block)).toBe(true);
    expect(/runState:\s*\(context as any\)\?\.runState/.test(block)).toBe(true);
  });

  it("returns '' when the gate says skip", () => {
    const block = SRC.split("const sessionDatasetsBlock = ")[1]?.split("})();")[0] ?? "";
    expect(/if\s*\(!_gate\.inject\)[\s\S]{0,200}return ''/.test(block)).toBe(true);
  });

  it("logs the audit reason on both inject and skip", () => {
    const block = SRC.split("const sessionDatasetsBlock = ")[1]?.split("})();")[0] ?? "";
    expect(block.includes("gate=skip reason=")).toBe(true);
    expect(block.includes("gate=inject reason=")).toBe(true);
  });
});

describe("shouldInjectDatasets — reason codes are stable for audit logging", () => {
  it("every reason code is one of the documented values", () => {
    const valid = new Set([
      "no_datasets_attached",
      "message_references_data",
      "run_state_relevant",
      "short_followup_after_data_thread",
      "last_assistant_referenced_data",
      "data_intent_with_history_discussion",
      "pure_abstract_intent_no_signals",
      "default_on_no_negative_signals",
    ]);
    const samples = [
      shouldInjectDatasets({ message: "hi", datasets: [] }),
      shouldInjectDatasets({ message: "the dataset", datasets: D }),
      shouldInjectDatasets({ message: "x", datasets: D, runState: { active: true } }),
      shouldInjectDatasets({ message: "yes", datasets: D, history: [{ role: "assistant", content: "use gse22055_expression.csv" }] }),
      shouldInjectDatasets({ message: "x", datasets: D, intentType: "research_question" }),
      shouldInjectDatasets({ message: "x", datasets: D, intentType: "unknown" }),
    ];
    for (const s of samples) {
      expect(valid.has(s.reason)).toBe(true);
    }
  });
});
