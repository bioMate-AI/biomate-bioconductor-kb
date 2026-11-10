import { describe, expect, it } from "vitest";
import {
  appendComposerInstructions,
  appendOutputRequirementsBlock,
  appendProjectOutputRequirements,
  MAX_COMPOSER_INSTRUCTIONS_LENGTH,
  normalizeComposerInstructions,
} from "./chat-context";
import { outputRequirementsToPrompt } from "../client/src/lib/output-requirements";

describe("composer instruction chat context boundary", () => {
  it("preserves durable project background and appends normalized one-turn guidance", () => {
    const result = appendComposerInstructions(
      "Project: Metastatic melanoma\nResearch goal: prioritize responder biomarkers",
      "  Use GRCh38 and report FDR < 0.05.  ",
    );

    expect(result).toEqual({
      projectContext: [
        "Project: Metastatic melanoma\nResearch goal: prioritize responder biomarkers",
        "Composer instructions for this chat:\nUse GRCh38 and report FDR < 0.05.",
      ].join("\n\n"),
      composerInstructions: "Use GRCh38 and report FDR < 0.05.",
    });
  });

  it("supports project-less chats without silently dropping valid guidance", () => {
    expect(appendComposerInstructions(undefined, "Prefer human studies.")).toEqual({
      projectContext: "Composer instructions for this chat:\nPrefer human studies.",
      composerInstructions: "Prefer human studies.",
    });
  });

  it("ignores empty and non-string browser input instead of coercing it into prompt text", () => {
    for (const value of [undefined, null, {}, ["do this"], 12, " \n\t "]) {
      expect(appendComposerInstructions("Project: retained", value)).toEqual({
        projectContext: "Project: retained",
        composerInstructions: undefined,
      });
    }
  });

  it("trims and caps guidance before it can reach an assistant prompt", () => {
    const tooLong = `  ${"x".repeat(MAX_COMPOSER_INSTRUCTIONS_LENGTH + 50)}  `;
    const normalized = normalizeComposerInstructions(tooLong);

    expect(normalized).toHaveLength(MAX_COMPOSER_INSTRUCTIONS_LENGTH);
    expect(normalized).toBe("x".repeat(MAX_COMPOSER_INSTRUCTIONS_LENGTH));
  });
});

describe("server-side project output requirements in chat context", () => {
  // The same store the editor panel persists (JSON array of OutputFormat).
  const store = JSON.stringify([
    { kind: "report", name: "Internal memo", detail: "Findings first (≤200 words), then methods.", on: true },
  ]);
  const prompt = outputRequirementsToPrompt(store);

  it("injects saved output requirements WITHOUT the client threading composerInstructions (MCP/programmatic path)", () => {
    // No composerInstructions at all — the server still honors the saved formats.
    const merged = appendProjectOutputRequirements(
      "Project: ADMET screen",
      prompt,
      undefined,
    );
    expect(merged).toContain("Project: ADMET screen");
    expect(merged).toContain("Output requirements (write deliverables to these):");
    expect(merged).toContain("Findings first (≤200 words)");
  });

  it("dedupes when the chat composer already threaded the identical block", () => {
    // chat-input.tsx folds outputRequirementsToPrompt(...) into composerInstructions.
    const composer = `Use GRCh38.\n\n${prompt}`;
    const merged = appendProjectOutputRequirements("Project: X", prompt, composer);
    // Server copy is suppressed — projectContext is returned unchanged so the only
    // copy the model sees is the one appendComposerInstructions adds.
    expect(merged).toBe("Project: X");
  });

  it("is idempotent against a projectContext that already carries the block", () => {
    const withReq = appendProjectOutputRequirements("Project: X", prompt, undefined)!;
    const twice = appendProjectOutputRequirements(withReq, prompt, undefined);
    expect(twice).toBe(withReq);
    // Exactly one copy of the block.
    expect(twice!.split("Output requirements (write deliverables to these):").length).toBe(2);
  });

  it("leaves context unchanged when no formats are enabled (rule-first / safe)", () => {
    // Only disabled (on:false) formats → outputRequirementsToPrompt returns ''.
    const disabledOnly = outputRequirementsToPrompt(
      JSON.stringify([{ kind: "report", name: "off", detail: "x", on: false }]),
    );
    expect(disabledOnly).toBe("");
    expect(appendProjectOutputRequirements("Project: X", disabledOnly, undefined)).toBe("Project: X");
    expect(appendProjectOutputRequirements("Project: X", "", "composer")).toBe("Project: X");
  });
});

describe("appendOutputRequirementsBlock — the deliverable-generator chokepoint composer", () => {
  const prompt = outputRequirementsToPrompt(
    JSON.stringify([{ kind: "report", name: "Internal memo", detail: "Findings first (≤200 words).", on: true }]),
  );

  it("returns the base prompt UNCHANGED when requirements are empty (behavior unchanged when unset)", () => {
    const base = "Generate a methods section.";
    expect(appendOutputRequirementsBlock(base, "", "report")).toBe(base);
    expect(appendOutputRequirementsBlock(base, undefined, "report")).toBe(base);
    expect(appendOutputRequirementsBlock(base, "   ", "findings-summary")).toBe(base);
  });

  it("frames the 'report' scope with the deliverable directive and preserves the base prompt", () => {
    const out = appendOutputRequirementsBlock("BASE PROMPT", prompt, "report");
    expect(out.startsWith("BASE PROMPT")).toBe(true);
    expect(out).toContain("PROJECT OUTPUT REQUIREMENTS (apply to this deliverable");
    expect(out).toContain("Findings first (≤200 words)");
  });

  it("frames the 'findings-summary' scope for the summary prose, not a full deliverable", () => {
    const out = appendOutputRequirementsBlock("HEAD", prompt, "findings-summary");
    expect(out).toContain('apply to the "summary" prose');
    expect(out).toContain("NEVER fabricate numbers");
    expect(out).toContain("Findings first (≤200 words)");
  });

  it("frames the 'figure' scope for figure outputs", () => {
    const out = appendOutputRequirementsBlock("HEAD", prompt, "figure");
    expect(out).toContain("apply to figures");
  });

  it("is idempotent — the block is never appended twice", () => {
    const once = appendOutputRequirementsBlock("BASE", prompt, "report");
    const twice = appendOutputRequirementsBlock(once, prompt, "report");
    expect(twice).toBe(once);
  });
});
