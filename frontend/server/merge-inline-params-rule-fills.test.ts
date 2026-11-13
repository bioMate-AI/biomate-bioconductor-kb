import { describe, expect, it } from "vitest";
import { mergeInlineParamsPreferringRuleFills } from "./galaxy-assistant";

describe("mergeInlineParamsPreferringRuleFills", () => {
  it("keeps project-rule FDR/FC above schema-grounded LLM defaults", () => {
    const merged = mergeInlineParamsPreferringRuleFills({
      backendFilled: {
        differential_max_qval: "0.01",
        differential_min_fold_change: "2",
        normalisation_method: "deseq2",
      },
      grounded: {
        // SCHEMA_GROUNDED LLM re-emits schema default / misreads |log2FC| as 1
        differential_max_qval: "0.05",
        differential_min_fold_change: "1",
        study_type: "rnaseq",
      },
      workflowGa: {
        optional_params: [
          {
            name: "differential_max_qval",
            autoFilled: true,
            rationale: "rule-based: significance threshold from query/project rules",
          },
          {
            name: "differential_min_fold_change",
            autoFilled: true,
            rationale: "rule-based: fold-change threshold from query/project rules",
          },
        ],
      },
    });
    expect(merged.differential_max_qval).toBe("0.01");
    expect(merged.differential_min_fold_change).toBe("2");
    // Non-rule grounded keys still win over bare backend schema noise.
    expect(merged.study_type).toBe("rnaseq");
    expect(merged.normalisation_method).toBe("deseq2");
  });

  it("lets grounded overwrite backend when the fill was not rule-based", () => {
    const merged = mergeInlineParamsPreferringRuleFills({
      backendFilled: { differential_max_qval: "0.05" },
      grounded: { differential_max_qval: "0.1" },
      workflowGa: {
        optional_params: [
          { name: "differential_max_qval", autoFilled: false, rationale: "schema default" },
        ],
      },
    });
    expect(merged.differential_max_qval).toBe("0.1");
  });
});
