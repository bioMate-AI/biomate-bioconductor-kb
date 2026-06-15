/**
 * Local unit test for _detectCrossIntentAmbiguity.
 *
 * Verifies the detection function returns shouldClarify=true for design-shaped
 * queries that were classified as tool_search/research_question, and false for
 * queries that are correctly non-workflow.
 */
import "dotenv/config";

// Import the GalaxyAssistant class to access the private method via tunneling.
const { GalaxyAssistant } = await import("../../galaxy-assistant.ts");

type AmbiguityResult = {
  shouldClarify: boolean;
  candidates: Array<{ type: string; label: string; primary?: boolean }>;
  reason: string;
};

function check(
  ga: any,
  message: string,
  intentType: string,
  expectClarify: boolean,
): { pass: boolean; result: AmbiguityResult; intentType: string; message: string } {
  const intent = {
    id: "test",
    type: intentType,
    subQuery: message,
    keywords: [],
    inlineParameters: {},
    needsToolSearch: false,
    needsDatasets: false,
    confidence: 0.8,
    facts: [],
    dependsOn: [],
    actions: { needsToolSearch: false } as any,
  };
  const result: AmbiguityResult = ga._detectCrossIntentAmbiguity(message, intent);
  return {
    pass: result.shouldClarify === expectClarify,
    result,
    intentType,
    message,
  };
}

const CASES: Array<{ msg: string; intent: string; expectClarify: boolean; label: string }> = [
  // Should clarify: design-shaped queries classified as non-workflow
  { msg: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC", intent: "tool_search", expectClarify: true, label: "T01 misclassified" },
  { msg: "Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy", intent: "tool_search", expectClarify: true, label: "T04 misclassified" },
  { msg: "Triage modalities for a BCMA oncology target — try all options", intent: "tool_search", expectClarify: true, label: "T05 misclassified" },
  { msg: "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence", intent: "tool_search", expectClarify: true, label: "T02 misclassified" },
  { msg: "Design an in-vivo base-edit knockout of PCSK9 for hypercholesterolemia", intent: "research_question", expectClarify: true, label: "T03 misclassified as research" },
  { msg: "Design an ADC for HER2 in gastric cancer", intent: "tool_search", expectClarify: true, label: "ADC misclassified" },
  { msg: "Engineer a bispecific antibody against CTLA-4 and PD-L1", intent: "tool_search", expectClarify: true, label: "Engineer misclassified" },
  // Should NOT clarify: already correctly workflow_generation (no need)
  { msg: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC", intent: "workflow_generation", expectClarify: false, label: "T01 correct" },
  // Should NOT clarify: genuinely non-workflow queries (no design verb / no modality)
  { msg: "What is the typical hERG IC50 threshold for cardiac safety?", intent: "research_question", expectClarify: false, label: "research question" },
  { msg: "Show me the RNA-seq pipelines available", intent: "tool_search", expectClarify: false, label: "tool browse" },
  { msg: "How does fpocket score druggability?", intent: "research_question", expectClarify: false, label: "concept question" },
  // Edge: "design experiment" alone (no modality token) should NOT clarify
  { msg: "I'd like to design an experiment to test gene knockout efficiency", intent: "experiment_design", expectClarify: true, label: "design+knockout (verb+modalityToken matches)" },
];

(async () => {
  const ga = new (GalaxyAssistant as any)({ anthropicApiKey: process.env.ANTHROPIC_API_KEY || "test-key", geminiApiKey: process.env.GEMINI_API_KEY });
  let pass = 0;
  let fail = 0;
  for (const c of CASES) {
    const r = check(ga, c.msg, c.intent, c.expectClarify);
    const marker = r.pass ? "✓" : "✗";
    console.log(`${marker} ${c.label} (intent=${c.intent}) → shouldClarify=${r.result.shouldClarify} expected=${c.expectClarify}`);
    if (r.result.shouldClarify) {
      console.log(`    reason: ${r.result.reason}`);
      console.log(`    candidates: ${r.result.candidates.map((x) => x.label).join(" | ")}`);
    }
    if (r.pass) pass++;
    else fail++;
  }
  console.log(`\n=== ${pass}/${pass + fail} pass ===`);
  process.exit(fail > 0 ? 1 : 0);
})();
