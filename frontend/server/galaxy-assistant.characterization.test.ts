/**
 * Phase-0 characterization oracle for the agent-flexibility refactor.
 * See docs/20261021_AGENT_FLEXIBILITY_TEST_FIRST_PLAN.md — "build the test net first,
 * prove it catches regressions, then change code behind flags, A/B against the net."
 *
 * This suite snapshots TODAY's DETERMINISTIC routing so the P1–P3 changes can be A/B'd
 * against a known baseline. It makes NO product-code change — it reads/calls existing
 * exports and pins the fabrication-root tool-gate by source assertion. When P1 drops the
 * `!hasRunnableWorkflow` term, or P3 changes the router table, THIS suite goes red first —
 * that is the net doing its job.
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { inferActionsFromType, GalaxyAssistant } from "./galaxy-assistant";

// ── A. The router action table (inferActionsFromType) ───────────────────────────
// The static type→actions table P3 demotes to a hint. Snapshot it whole + pin the
// load-bearing rows explicitly (explicit asserts survive a careless snapshot update).
const KNOWN_TYPES = [
  "workflow_generation", "data_format_conversion", "external_db_retrieval", "visualization",
  "multi_step_procedure", "tool_search", "workflow_modification", "troubleshooting",
  "parameter_optimization", "result_comparison", "research_question", "database_lookup",
  "genomics_knowledge", "clinical_genomics", "benchmark_query", "dataset_inquiry",
  "experiment_design", "data_interpretation", "protocol_guidance", "teaching_explanation",
  "methods_writing", "comparative_methodology", "regulatory_compliance", "cost_estimation",
  "general_question", "chain_proposal",
];

describe("characterization: inferActionsFromType (router action table)", () => {
  it("snapshots the full type→actions table", () => {
    const table = Object.fromEntries(KNOWN_TYPES.map((t) => [t, inferActionsFromType(t)]));
    expect(table).toMatchSnapshot();
  });

  it("pins load-bearing mappings the refactor must not silently change", () => {
    expect(inferActionsFromType("workflow_generation").needsWorkflowGeneration).toBe(true);
    expect(inferActionsFromType("tool_search").needsToolSearch).toBe(true);
    expect(inferActionsFromType("research_question").needsResearchAgent).toBe(true);
    expect(inferActionsFromType("database_lookup").needsResearchAgent).toBe(true);
    expect(inferActionsFromType("chain_proposal").needsChainProposal).toBe(true);
    // Every known type keeps LLM reasoning on.
    for (const t of KNOWN_TYPES) expect(inferActionsFromType(t).needsLLMReasoning).toBe(true);
  });

  it("an unknown type defaults to LLM reasoning only (no workflow/research/tools)", () => {
    expect(inferActionsFromType("totally_unknown_xyz")).toEqual({
      needsToolSearch: false, needsWorkflowGeneration: false, needsWorkflowModification: false,
      needsResearchAgent: false, needsBenchmarkAgent: false, needsDatasetAccess: false,
      needsLLMReasoning: true, needsChainProposal: false,
    });
  });
});

// ── B. The named _isX detectors (the regex routing patches P3 deletes) ──────────
// Pure methods (they read only `message`, never `this`) → callable off the prototype.
const detect = (name: string, msg: string): boolean =>
  (GalaxyAssistant.prototype as unknown as Record<string, (m: string) => boolean>)[name].call(null as unknown as GalaxyAssistant, msg);

const GOLDEN: Array<{ name: string; fires: string[]; notFires: string[] }> = [
  {
    name: "_isClusterProfilerQuery",
    fires: ["Run clusterProfiler enrichGO on my DEGs", "clusterProfiler GSEA with KEGG"],
    notFires: ["run DESeq2 on my counts", "open clusterProfiler"],
  },
  {
    name: "_isPocketDetectionQuery",
    fires: ["fpocket on 1IEP", "binding pocket detection druggability on this PDB"],
    notFires: ["screen these compounds for ADMET"],
  },
  {
    name: "_isPlanBCodonQuery",
    fires: ["optimize_codons_for_heterologous_expression for my gene", "codon optimization with host_codon_usage table"],
    notFires: ["codon optimization please"],
  },
  {
    name: "_isPlanAEpitopeQuery",
    fires: ["run nf-core/epitopeprediction", "epitope prediction with mhcnuggets"],
    notFires: ["epitope prediction with mhcquant"],
  },
  {
    name: "_isDirectCodeExecutionQuery",
    fires: ["use run_code to compute the mean", "do not create a workflow, just run_code this snippet"],
    // explicit run_code BUT names a pipeline keyword (deseq2) → guarded off; and a plain ADMET ask.
    notFires: ["use run_code to run DESeq2", "screen these compounds for ADMET"],
  },
];

describe("characterization: named _isX detectors", () => {
  for (const g of GOLDEN) {
    it(`${g.name} fires / does-not-fire exactly as today`, () => {
      for (const m of g.fires) expect(detect(g.name, m), `should fire: ${m}`).toBe(true);
      for (const m of g.notFires) expect(detect(g.name, m), `should NOT fire: ${m}`).toBe(false);
    });
  }
});

// ── C. The tool-gate invariant (fabrication root) — source assertion ────────────
// Pins galaxy-assistant.ts. P1 removes `!hasRunnableWorkflow`; this fails then → caught.
const SRC = readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), "galaxy-assistant.ts"), "utf8");

describe("characterization: tool-gate ties tool availability to card absence (P1 target)", () => {
  it("Claude path gate currently includes the !hasRunnableWorkflow term", () => {
    expect(SRC).toContain("const toolsEnabledThisTurn = (!useThinking && onToolEvent && !hasRunnableWorkflow);");
  });
  it("Gemini path currently strips tools when a runnable workflow exists", () => {
    expect(SRC).toContain("!hasRunnableWorkflow ? BIOMATE_TOOLS : undefined");
  });
});
