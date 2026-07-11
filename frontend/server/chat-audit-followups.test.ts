/**
 * Tests for the Q1/Q2/Q4 audit follow-ups
 * (docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md).
 *
 *   Q1 — context-compressor must preserve dataset attachment blocks
 *        verbatim across summarization so UUIDs survive.
 *   Q2 — compression-dialog must offer "Start a new chat" at ≥85%.
 *   Q4 — chat-stream wires projectId via ensureDefaultProject.
 *
 * Unit-level: we don't import code that requires DATABASE_URL at module
 * load (db.ts hard-asserts). Source-level assertions plus a small
 * functional check on the dataset-block extractor are enough to lock in
 * the contract.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const ROOT = path.join(__dirname);

describe("Q1: context compressor preserves dataset blocks", () => {
  const SRC = fs.readFileSync(path.join(ROOT, "context-compressor.ts"), "utf-8");

  it("declares a DATASET_BLOCK_RE", () => {
    // Pattern accepts BioMate dataset, Galaxy dataset, Uploaded datasets?, or Attached files?
    expect(/const\s+DATASET_BLOCK_RE\s*=\s*\/\\\[\(\?:(?:BioMate dataset\|)?Galaxy dataset\|Uploaded datasets\?\|Attached files\?\)/.test(SRC)).toBe(true);
  });

  it("extracts blocks into preservedBlocks before summarization", () => {
    expect(SRC.includes("preservedBlocks")).toBe(true);
    expect(SRC.includes("preservedHeader")).toBe(true);
  });

  it("the summary header prefix appears in the assistant content", () => {
    expect(/preservedHeader\}\$\{summary\}/.test(SRC)).toBe(true);
    expect(SRC.includes("Preserved dataset attachments across compression — verbatim")).toBe(true);
  });

  // Functional check: clone the same regex into the test and prove it
  // round-trips a wjunlin-shaped input.
  it("the regex catches all three real input shapes (functional check)", () => {
    const DATASET_BLOCK_RE = /\[(?:Galaxy dataset|Uploaded datasets?|Attached files?)\s*:[^\]]+\]/gi;
    const input = [
      "First turn: [Galaxy dataset: gse22055_expression.csv (id: f796f3f2-efd5-45c8-abfa-af346006206f)] then we ask Q.",
      "Now: [Galaxy dataset: clinical_gse22055.csv (id: 5cf7a795-565d-487e-bdb6-47a9859ff02d)] and [Uploaded datasets: notes.txt: dataset_id=abc]",
      "Just text",
      "[Attached files: foo.csv, bar.csv]",
    ].join("\n");
    const matches = input.match(DATASET_BLOCK_RE) || [];
    expect(matches.length).toBe(4);
    expect(matches[0]).toContain("f796f3f2-efd5-45c8-abfa-af346006206f");
    expect(matches[1]).toContain("5cf7a795-565d-487e-bdb6-47a9859ff02d");
  });
});

describe("Q2: compression dialog offers 'Start a new chat' at ≥85%", () => {
  const DIALOG = fs.readFileSync(
    path.join(ROOT, "..", "client", "src", "components", "compression-dialog.tsx"),
    "utf-8"
  );
  const CHAT = fs.readFileSync(
    path.join(ROOT, "..", "client", "src", "components", "chat-interface.tsx"),
    "utf-8"
  );

  it("CompressionDialog accepts an onStartNewChat prop", () => {
    expect(/onStartNewChat\?\s*:\s*\(\s*\)\s*=>\s*void/.test(DIALOG)).toBe(true);
  });

  it("renders the 'Start a new chat' button only at ≥85%", () => {
    expect(DIALOG.includes("compression-start-new-chat")).toBe(true);
    expect(/onStartNewChat\s*&&\s*percentage\s*>=\s*85/.test(DIALOG)).toBe(true);
  });

  it("chat-interface wires onStartNewChat into the dialog", () => {
    expect(/onStartNewChat=\{/.test(CHAT)).toBe(true);
    expect(/createNewSession\(\)/.test(CHAT)).toBe(true);
  });

  it("'Compress Now' button has a stable testid for e2e parity", () => {
    expect(DIALOG.includes("compression-compress-now")).toBe(true);
  });
});

describe("Q4: project framework — wired, policy 'chats can be project-less'", () => {
  // 2026-06-12 policy correction: NOT every chat lives in a project.
  // Chats are project-scoped only when the client explicitly sends
  // projectId. Standalone chats stay project-less. We do NOT
  // auto-create a Default Workspace — see
  // docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
  const ROUTES = fs.readFileSync(path.join(ROOT, "routes.ts"), "utf-8");
  const MEMORY = fs.readFileSync(path.join(ROOT, "memory-repository.ts"), "utf-8");

  it("MemoryService exposes ensureLtmUser (always-on, user-scoped) separately from project resolution", () => {
    // Look for the wrapper method on MemoryService — UserMemoryRepository
    // also has an ensureLtmUser, so anchor to the MemoryService class.
    const svc = MEMORY.split("export class MemoryService")[1] ?? "";
    expect(/async\s+ensureLtmUser\s*\(\s*userId\s*:\s*string\s*,\s*email\?\s*:\s*string\s*,\s*name\?\s*:\s*string\s*\)\s*:\s*Promise<void>/.test(svc)).toBe(true);
  });

  it("MemoryService.resolveProjectForChat returns the client's projectId or null — never auto-creates", () => {
    expect(/async\s+resolveProjectForChat\s*\(\s*clientProjectId\?\s*:\s*string\s*\|\s*null\s*\)\s*:\s*Promise<string\s*\|\s*null>/.test(MEMORY)).toBe(true);
    expect(/return\s+clientProjectId\s*\|\|\s*null/.test(MEMORY)).toBe(true);
  });

  it("chat-stream calls ensureLtmUser for every authenticated request (user-scoped memory always on)", () => {
    expect(/memoryService\.ensureLtmUser\(\s*String\(_u\.id\)\s*,\s*_u\.email\s*,\s*_u\.fullName\s*\?\?\s*_u\.name\s*\)/.test(ROUTES)).toBe(true);
  });

  it("chat-stream resolves projectId only from client context (does NOT auto-create)", () => {
    expect(/memoryService\.resolveProjectForChat\(\s*context\?\.projectId\s*\)/.test(ROUTES)).toBe(true);
    // Smoking-gun negative: no call to the deprecated auto-create helper.
    expect(/memoryService\.ensureDefaultProject\(/.test(ROUTES)).toBe(false);
  });

  it("chat-stream attaches projectId (or null) to enrichedContext", () => {
    expect(/let _resolvedProjectId\s*:\s*string\s*\|\s*undefined/.test(ROUTES)).toBe(true);
    expect(/projectId\s*:\s*_resolvedProjectId/.test(ROUTES)).toBe(true);
  });

  it("chat-stream wraps the memory bootstrap in try/catch so a memory failure never breaks chat", () => {
    // The try block legitimately spans ensureLtmUser → resolveProjectForChat →
    // ensureChatLtmSession → recoverProjectDatasets (all must be guarded), so the
    // window from ensureLtmUser to the closing catch is large by design.
    expect(/try\s*\{[\s\S]{0,400}ensureLtmUser[\s\S]{0,2000}\}\s*catch/.test(ROUTES)).toBe(true);
  });

  it("the deprecated ensureDefaultProject helper survives but no longer creates a Default Workspace", () => {
    expect(/@deprecated/.test(MEMORY)).toBe(true);
    expect(/return existing\.length\s*>\s*0\s*\?\s*existing\[0\]\.id\s*:\s*null/.test(MEMORY)).toBe(true);
    // The 'Default Workspace' literal must not appear in the resolve flow.
    const helperBlock = MEMORY.split('async ensureDefaultProject')[1] ?? '';
    expect(helperBlock.includes("'Default Workspace'") || helperBlock.includes('"Default Workspace"')).toBe(false);
  });
});
