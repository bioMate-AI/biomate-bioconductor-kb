import { describe, it, expect } from "vitest";
import { localIntentPrompt } from "./local-intent-prompt";

// NOTE: this pins the PROMPT CONTRACT (that the on-prem routing prompt carries the
// rules we rely on and emits a well-formed schema). It is NOT a runtime validation of
// the on-prem model's classification — that requires the on-prem LLM. It guards against
// the rule being silently dropped and against the schema example going malformed.
describe("localIntentPrompt", () => {
  // The chain matcher only considers message tokens >3 chars, matched against the
  // chain name's underscore/space/hyphen-split parts — so use full tokens ("rnaseq",
  // "analysis") that actually appear in 'bulk_rnaseq_de_analysis'.
  const prompt = localIntentPrompt("", [], ["bulk_rnaseq_de_analysis", "admet_screen"], "run the rnaseq differential expression analysis pipeline");

  it("builds a non-empty prompt and surfaces matching chain hints", () => {
    expect(prompt.length).toBeGreaterThan(200);
    expect(prompt).toContain("bulk_rnaseq_de_analysis");
  });

  it("carries the draft / 'don't launch yet' rule (parity with the cloud prompt)", () => {
    expect(prompt).toMatch(/don't launch\/run yet|prepare\/draft\/stage the plan/i);
    expect(prompt).toMatch(/still workflow_generation/i);
    expect(prompt).toMatch(/Do not downgrade these to general_question or experiment_design/i);
  });

  it("emits a parseable JSON output-schema example", () => {
    // The schema example is the first {...} block after 'Output schema:'.
    const m = prompt.match(/Output schema:\s*(\{.*?\})\s*\n/s);
    expect(m, "schema example present").toBeTruthy();
    expect(() => JSON.parse(m![1])).not.toThrow();
    const parsed = JSON.parse(m![1]);
    expect(parsed).toHaveProperty("intents");
    expect(parsed).toHaveProperty("is_sequential");
  });
});
