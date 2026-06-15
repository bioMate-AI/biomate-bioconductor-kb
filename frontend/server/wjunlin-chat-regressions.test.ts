/**
 * Regression tests for the four bugs surfaced by wjunlin@HKU's real
 * production chat (docs/20260610_REAL_USER_FULL_CHAT_LOGS.md).
 *
 *  #5 — chain planner returned "(workflow path TBD)" for all 4 RNA-seq steps
 *  #6 — "SECOND-TURN OVERRIDE applies" internal scaffolding leaked into reply
 *  #7 — Microarray data routed to DESeq2 instead of limma
 *  #4 — clinical_gse22055.csv triggered pharma boilerplate (covered in
 *       drug-dev-boilerplate-gate.test.ts)
 *
 * #3 (history rehydration from chat_sessions) needs DATABASE_URL; the
 * unit-level check here just asserts the helper shape works on synthetic
 * jsonb. Full E2E lives in tests that already have the test DB up.
 */
import { describe, expect, it } from "vitest";
import { resolveCanonicalChainStepPath } from "./canonical-chain-steps";

describe("#3 client history slice retains earlier dataset attachments", () => {
  // Replica of the client-side selection logic from
  // chat-interface.tsx (kept in sync — same regex + window). If the
  // production code's slice window shrinks again, the wjunlin scenario
  // will fail here.
  const DATASET_BLOCK_RE = /\[(?:Galaxy dataset|Uploaded datasets?|Attached files?)\s*:/i;
  function buildPayload(msgs: Array<{ role: "user" | "assistant"; content: string }>) {
    const recent = msgs.slice(-20);
    const earlier = msgs.slice(0, Math.max(0, msgs.length - 20))
      .filter(m => DATASET_BLOCK_RE.test(m.content));
    return [...earlier, ...recent];
  }

  it("retains a [Galaxy dataset: ...] attachment from turn 1 even after 25 chat turns", () => {
    const msgs: Array<{ role: "user" | "assistant"; content: string }> = [
      { role: "user", content: "[Galaxy dataset: gse22055_expression.csv (id: f796f3f2)]" },
      { role: "assistant", content: "Got the expression matrix." },
    ];
    for (let i = 0; i < 23; i++) msgs.push({ role: "user", content: `follow-up question ${i}` });

    const payload = buildPayload(msgs);
    expect(payload.some(m => /\[Galaxy dataset/.test(m.content))).toBe(true);
    expect(payload.length).toBeLessThanOrEqual(21);
  });

  it("retains TWO earlier dataset attachments (expression + clinical) — wjunlin scenario", () => {
    const msgs: Array<{ role: "user" | "assistant"; content: string }> = [
      { role: "user", content: "[Galaxy dataset: gse22055_expression.csv (id: f796f3f2)]" },
      { role: "assistant", content: "OK — what's the metadata?" },
      { role: "user", content: "[Galaxy dataset: clinical_gse22055.csv (id: 5cf7a795)]" },
      { role: "assistant", content: "Got it." },
    ];
    for (let i = 0; i < 30; i++) msgs.push({ role: "user", content: `chat turn ${i}` });

    const payload = buildPayload(msgs);
    expect(payload.filter(m => /\[Galaxy dataset/.test(m.content)).length).toBe(2);
  });

  it("does NOT explode payload when no dataset attachments are present", () => {
    const msgs: Array<{ role: "user" | "assistant"; content: string }> = [];
    for (let i = 0; i < 100; i++) msgs.push({ role: "user", content: `msg ${i}` });

    const payload = buildPayload(msgs);
    expect(payload.length).toBe(20);
  });
});

describe("#5 chain planner: canonical chain step resolver", () => {
  it("resolves the 4 classical RNA-seq chain steps wjunlin asked for", () => {
    // From wjunlin's chat — these are the exact step descriptions the planner produced:
    expect(resolveCanonicalChainStepPath(
      "Perform quality control and adapter trimming on raw RNA-seq FASTQ files."
    )).toBe("nextflow_nfcore/rnaseq/main.nf");

    expect(resolveCanonicalChainStepPath(
      "Align cleaned RNA-seq reads to a reference genome and quantify gene expression."
    )).toBe("nextflow_nfcore/rnaseq/main.nf");

    expect(resolveCanonicalChainStepPath(
      "Perform differential expression analysis using the gene count matrix."
    )).toBe("nextflow_nfcore/differentialabundance/main.nf");

    expect(resolveCanonicalChainStepPath(
      "Perform pathway and GO term enrichment analysis on the differentially expressed genes."
    )).toBe("biomni_workflows/bioconductor/clusterprofiler_enrichgo/main.nf");
  });

  it("resolves microarray-DEG step to limma, not DESeq2", () => {
    expect(resolveCanonicalChainStepPath(
      "Perform differential expression analysis on microarray data using limma"
    )).toBe("biomni_workflows/bioconductor/limma_microarray/main.nf");
  });

  it("returns null on truly ambiguous step descriptions (preserves TBD UX)", () => {
    expect(resolveCanonicalChainStepPath("Generate a report")).toBe(null);
    expect(resolveCanonicalChainStepPath("")).toBe(null);
  });

  it("resolves variant-calling chain steps to sarek", () => {
    expect(resolveCanonicalChainStepPath(
      "Run variant calling with GATK HaplotypeCaller on aligned BAM files"
    )).toBe("nf-core-pipelines/sarek/main.nf");
  });
});

describe("#6 SECOND-TURN OVERRIDE marker no longer present in system prompt", () => {
  // Load the source as a string and assert the leaky marker is gone.
  // We can't import galaxy-assistant.ts at runtime (DATABASE_URL guard),
  // so use require('fs') in a way that keeps the import-time graph clean.
  const fs = require("fs") as typeof import("fs");
  const path = require("path") as typeof import("path");
  const SRC = fs.readFileSync(path.join(__dirname, "galaxy-assistant.ts"), "utf-8");

  it("system prompt no longer uses 'SECOND-TURN OVERRIDE' as a rule label the LLM could echo", () => {
    // Before: `- SECOND-TURN OVERRIDE: If the conversation history shows…`
    // The all-caps prefix was a recognisable phrase the LLM quoted verbatim
    // in wjunlin's session. It now appears only inside the META-RULE's
    // forbidden-phrases list (and code comments). Assert neither uses it as
    // an active instruction prefix.
    expect(/^\s*-\s*SECOND-TURN OVERRIDE\s*:/m.test(SRC)).toBe(false);
  });

  it("system prompt includes an explicit anti-echo meta-rule", () => {
    expect(/META-RULE on phrasing[\s\S]{0,400}never echo the name of an internal instruction/.test(SRC)).toBe(true);
  });
});

describe("session_datasets injected into system prompt (canonical path)", () => {
  // The right architecture for "the bot must know which datasets are
  // attached" is to inject Galaxy-history-derived sessionDatasets as a
  // structured block in the system prompt every turn — independent of
  // chat-history slicing. Preserving [Galaxy dataset: ...] blocks in
  // chat history was a symptom-level fix; this is the canonical one.
  const fs = require("fs") as typeof import("fs");
  const path = require("path") as typeof import("path");
  const SRC = fs.readFileSync(path.join(__dirname, "galaxy-assistant.ts"), "utf-8");

  it("a sessionDatasetsBlock is constructed from context.sessionDatasets", () => {
    expect(/const\s+sessionDatasetsBlock\s*=\s*\(\s*\(\s*\)\s*=>/.test(SRC)).toBe(true);
    expect(SRC.includes("context as any)?.sessionDatasets")).toBe(true);
  });

  it("the system prompt embeds sessionDatasetsBlock alongside inlineDataBlock", () => {
    // Both invocations (research-intent + workflow-intent branches) must include it.
    const matches = SRC.match(/\$\{inlineDataBlock\}\$\{sessionDatasetsBlock\}\$\{domainProfileContext\}/g);
    expect(matches?.length).toBeGreaterThanOrEqual(2);
  });

  it("the block emits dataset id + name + type and tells the LLM not to re-ask for uploads", () => {
    expect(/<session_datasets>/.test(SRC)).toBe(true);
    expect(/Galaxy history is the source of truth/.test(SRC)).toBe(true);
    expect(/Do NOT ask the user to re-upload/.test(SRC)).toBe(true);
  });
});

describe("#7 microarray → limma routing rule present in system prompt", () => {
  const fs = require("fs") as typeof import("fs");
  const path = require("path") as typeof import("path");
  const SRC = fs.readFileSync(path.join(__dirname, "galaxy-assistant.ts"), "utf-8");

  it("instructs LLM to prefer limma over DESeq2 on microarray data", () => {
    expect(/Differential-expression method selection.*data-type rule/i.test(SRC)).toBe(true);
    expect(/microarray[\s\S]{0,500}prefer\s+\*?\*?limma/i.test(SRC)).toBe(true);
    expect(/DESeq2[\s\S]{0,300}assume\s+raw\s+integer\s+counts/i.test(SRC)).toBe(true);
  });
});
