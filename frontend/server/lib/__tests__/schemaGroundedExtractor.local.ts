#!/usr/bin/env node
/*
 * Local integration test for schema-grounded extraction.
 *
 * Drives the three new modules end-to-end against real tier-0 and gap-1
 * workflows, calling Claude Haiku for the LLM resolver. Does NOT need the
 * Galaxy backend running.
 *
 * Run:
 *   cd frontend && node server/lib/__tests__/schemaGroundedExtractor.local.mjs
 *
 * Env (loaded from frontend/.env):
 *   ANTHROPIC_API_KEY — required
 */
// Run with: node_modules/.bin/tsx server/lib/__tests__/schemaGroundedExtractor.local.mjs
import "dotenv/config";
import path from "node:path";

const { buildWorkflowSchemaFromFile } = await import("../paramSchema.ts");
const { extractParameters } = await import("../schemaGroundedExtractor.ts");

// ---------- LLM stub ----------
const NF_ROOT = "/home/yzhang/biomate/backend/nf-core-workflows";

async function claude(prompt: string): Promise<string> {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": process.env.ANTHROPIC_API_KEY ?? "",
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 800,
      temperature: 0.1,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!r.ok) throw new Error(`Claude ${r.status}: ${await r.text()}`);
  const j = await r.json();
  return j.content?.[0]?.text || "";
}

// ---------- Test cases ----------
const CASES = [
  // 5 tier-0 demos — should all pass with high confidence
  {
    name: "tier0-T01-bispecific",
    workflow: "bispecific_format_triage",
    required: ["target_a", "target_b"],
    optional: ["indication", "mechanism"],
    nfPath: "modules/biomate-ai-tools/bispecific_format_triage/main.nf",
    query: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC",
    expect: { target_a: /pd-?1/i, target_b: /vegf/i, indication: /nsclc/i },
    rawParams: {},
  },
  {
    name: "tier0-T02-cart",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    optional: ["delivery_cell", "lnp_targeting", "persistence"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query:
      "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence",
    expect: {
      car_target: /cd19/i,
      indication: /dlbcl/i,
      delivery_cell: /^t.?cell$/i,
      persistence: /transient/i,
    },
    rawParams: {},
  },
  {
    name: "tier0-T03-base-edit",
    workflow: "in_vivo_base_edit_design",
    required: ["target_gene", "edit_goal"],
    optional: ["indication", "delivery", "editor_preference"],
    nfPath: "modules/biomate-ai-tools/in_vivo_base_edit_design/main.nf",
    query: "Design an in-vivo base-edit knockout of PCSK9 for hypercholesterolemia",
    expect: {
      target_gene: /pcsk9/i,
      edit_goal: /knockout|loss/i,
      indication: /hyperchol/i,
    },
    rawParams: {},
  },
  {
    name: "tier0-T04-glp1",
    workflow: "glp1_modality_bakeoff",
    required: ["indication"],
    optional: ["disease", "modalities", "delivery_pref"],
    nfPath: "modules/biomate-ai-tools/glp1_modality_bakeoff/main.nf",
    query: "Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy",
    expect: { indication: /mash|nash/i },
    rawParams: {},
  },
  {
    name: "tier0-T05-modality-triage",
    workflow: "modality_triage",
    required: ["target_gene"],
    optional: ["atlas_expression", "indication", "modalities"],
    nfPath: "modules/biomate-ai-tools/modality_triage/main.nf",
    query: "Triage modalities for a BCMA oncology target — try all options",
    expect: { target_gene: /bcma/i, indication: /onco/i },
    rawParams: {},
  },
  // Edge case: raw bag uses generic key ("target") and synonym graph must
  // route it to car_target.
  {
    name: "synonym-graph-target-to-car_target",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    optional: ["delivery_cell", "lnp_targeting", "persistence"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Design CAR-T for BCMA myeloma",
    expect: { car_target: /bcma/i, indication: /myeloma/i },
    rawParams: { target: "BCMA", disease: "myeloma" },
  },
  // Edge case: user explicitly says "B cells" — LLM should surface the value
  // and let the validator turn it into an enum-violation clarification rather
  // than silently dropping it (UX gap fix).
  {
    name: "user-mentioned-out-of-enum-surfaces",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    optional: ["delivery_cell", "lnp_targeting", "persistence"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Co-design CD19 CAR for DLBCL with delivery to B cells",
    expect: { car_target: /cd19/i, indication: /dlbcl/i },
    expectClarifications: [{ kind: "enum_violation", paramName: "delivery_cell" }],
    rawParams: {},
  },
  // Edge case: validator catches an out-of-enum value supplied upstream
  // (e.g. from a stale rawParams bag or a user override). When the LLM itself
  // sees the schema, it correctly omits invalid values — see
  // user-mentioned-but-llm-dropped case below for the harder UX gap.
  {
    name: "enum-violation-via-rawparams",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    optional: ["delivery_cell", "lnp_targeting", "persistence"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Co-design CD19 CAR for DLBCL",
    expect: { car_target: /cd19/i, indication: /dlbcl/i },
    expectClarifications: [{ kind: "enum_violation", paramName: "delivery_cell" }],
    rawParams: { car_target: "CD19", indication: "DLBCL", delivery_cell: "B_cell" },
    skipLlm: true,
  },
  // Edge case: no params signal (would set has_parameter_signal=false upstream
  // and skip extractor entirely; here we test the extractor handles "nothing
  // to extract" gracefully when forced).
  {
    name: "no-signal-graceful",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    optional: ["delivery_cell", "lnp_targeting", "persistence"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Run the CAR-T workflow please",
    expect: {},
    expectClarifications: [
      { kind: "missing_required", paramName: "car_target" },
      { kind: "missing_required", paramName: "indication" },
    ],
    rawParams: {},
  },
  // Edge case: alias_of comment in glp1 — LLM should NOT use the 'disease'
  // alias slot; it goes under indication.
  {
    name: "alias-of-respected",
    workflow: "glp1_modality_bakeoff",
    required: ["indication"],
    optional: ["disease", "modalities", "delivery_pref"],
    nfPath: "modules/biomate-ai-tools/glp1_modality_bakeoff/main.nf",
    query: "GLP-1 modalities for obesity",
    expect: { indication: /obesity/i },
    forbidKeys: ["disease"],
    rawParams: {},
  },
  // Rule pass: direct key hit (raw key matches schema canonical) — no LLM call needed.
  {
    name: "rule-pass-direct-hit",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    optional: ["delivery_cell", "lnp_targeting", "persistence"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Co-design with these params",
    expect: { car_target: "CD19", indication: "DLBCL" },
    rawParams: { car_target: "CD19", indication: "DLBCL" },
    skipLlm: true, // assert this works without LLM
  },
  // Enum normalization: "T cells" → "T_cell" via rule pass (no LLM)
  {
    name: "rule-enum-normalize",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    optional: ["delivery_cell", "lnp_targeting", "persistence"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "deliver to T cells",
    expect: { delivery_cell: /^T_cell$/ },
    rawParams: { car_target: "CD19", indication: "DLBCL", delivery_cell: "T cells" },
    skipLlm: true,
  },
];

// ---------- Runner ----------
function checkRegex(value: unknown, expected: unknown): boolean {
  if (value === undefined) return false;
  if (expected instanceof RegExp) return expected.test(String(value));
  return String(value) === String(expected);
}

function summarize(extracted: Record<string, unknown>, expected: Record<string, unknown>) {
  const pass: string[] = [];
  const fail: Array<{ key: string; expected: string; got: unknown }> = [];
  for (const [k, v] of Object.entries(expected)) {
    if (checkRegex(extracted[k], v)) pass.push(k);
    else fail.push({ key: k, expected: String(v), got: extracted[k] });
  }
  return { pass, fail };
}

async function runCase(c: (typeof CASES)[number]) {
  const nfFull = path.join(NF_ROOT, c.nfPath);
  const schema = buildWorkflowSchemaFromFile({
    workflowName: c.workflow,
    nfPath: nfFull,
    requiredParams: c.required,
    optionalParams: c.optional,
  });
  if (!schema) throw new Error(`could not load schema for ${c.workflow}`);
  const result = await extractParameters({
    schema,
    userQuery: c.query,
    rawParams: c.rawParams,
    llmCall: claude,
    skipLlm: c.skipLlm,
  });
  return { result, schema };
}

(async () => {
  let totalCases = 0;
  let totalKeysPass = 0;
  let totalKeysTotal = 0;
  let casesAllGreen = 0;
  const failed = [];

  for (const c of CASES) {
    totalCases++;
    let result, schema;
    try {
      ({ result, schema } = await runCase(c));
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.log(`\n=== ${c.name} ===\nERROR: ${msg}`);
      failed.push({ name: c.name, reason: msg });
      continue;
    }
    const summary = summarize(result.params, c.expect);
    totalKeysPass += summary.pass.length;
    totalKeysTotal += Object.keys(c.expect).length;

    // Clarification expectations
    let clarOk = true;
    if (c.expectClarifications) {
      for (const expected of c.expectClarifications) {
        const found = result.clarifications.find(
          (x) => x.kind === expected.kind && x.paramName === expected.paramName,
        );
        if (!found) clarOk = false;
      }
    }
    // Forbidden keys
    let forbidOk = true;
    if (c.forbidKeys) {
      for (const k of c.forbidKeys) {
        if (result.params[k] !== undefined) forbidOk = false;
      }
    }
    const allGreen = summary.fail.length === 0 && clarOk && forbidOk;
    if (allGreen) casesAllGreen++;
    else failed.push({ name: c.name, summary, clarOk, forbidOk });

    console.log(
      `\n=== ${c.name} ${allGreen ? "✓" : "✗"} (${summary.pass.length}/${Object.keys(c.expect).length} keys, conf=${result.confidence.toFixed(2)}, stages=${Object.entries(result.stagesFired).filter(([, v]) => v).map(([k]) => k).join("+")}) ===`,
    );
    console.log("  query:", c.query);
    console.log("  raw:  ", c.rawParams);
    console.log("  out:  ", result.params);
    if (result.clarifications.length > 0)
      console.log("  clar: ", result.clarifications);
    if (summary.fail.length > 0)
      console.log("  fail: ", summary.fail);
    if (!clarOk)
      console.log("  ✗ expected clarifications:", c.expectClarifications);
    if (!forbidOk && c.forbidKeys)
      console.log("  ✗ forbidden keys found:", c.forbidKeys.filter((k) => result.params[k] !== undefined));
    if (result.provenance.length > 0)
      console.log("  prov: ", result.provenance);
  }

  console.log(
    `\n=== TOTAL: ${casesAllGreen}/${totalCases} cases all-green | ${totalKeysPass}/${totalKeysTotal} keys correct ===`,
  );
  if (failed.length > 0) {
    console.log("\nFAILED CASES:");
    for (const f of failed) console.log(" -", f.name);
    process.exit(1);
  }
})();
