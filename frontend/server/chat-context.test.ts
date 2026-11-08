import { describe, expect, it } from "vitest";
import {
  appendComposerInstructions,
  MAX_COMPOSER_INSTRUCTIONS_LENGTH,
  normalizeComposerInstructions,
} from "./chat-context";

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
