#!/usr/bin/env node
/*
 * Local integration test for schema-grounded extraction.
 *
 * Drives Stage 3 (rules + LLM resolver + validation) against tier-0
 * workflows. The test fixture parses each workflow's .nf file into the
 * shape the backend produces (workflow_ga.required_params/optional_params
 * with name+description+default+options), simulating what the chat-stream
 * receives.
 *
 * Run:
 *   cd frontend && node_modules/.bin/tsx \
 *       server/lib/__tests__/schemaGroundedExtractor.local.ts
 *
 * Env (loaded from frontend/.env):
 *   ANTHROPIC_API_KEY — required
 */
import "dotenv/config";
import fs from "node:fs";
import path from "node:path";

const { buildSchemaFromWorkflowGa } = await import("../paramSchema.ts");
const { extractParameters } = await import("../schemaGroundedExtractor.ts");

const NF_ROOT = "/home/yzhang/biomate/backend/nf-core-workflows";

// Helper: re-create the shape the backend ships in workflow_ga by parsing the
// .nf file. In production this happens inside backend (_get_workflow_params)
// and the frontend just receives the result.
function fakeBackendEntries(nfText: string, requiredNames: string[]): {
  required: Array<{ name: string; type: string; default?: string; options?: { value: string }[]; description: string; required: boolean }>;
  optional: Array<{ name: string; type: string; default?: string; options?: { value: string }[]; description: string; required: boolean }>;
} {
  const required: any[] = [];
  const optional: any[] = [];
  const re = /^params\.(\w+)\s*=\s*(['"])([^'"]*)\2\s*(?:\/\/\s*(.*))?$/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(nfText)) !== null) {
    const [, name, , def, rawComment] = m;
    if (name === "outdir") continue;
    const comment = (rawComment ?? "").trim();
    const entry: any = {
      name,
      type: "string",
      default: def,
      description: comment,
      required: requiredNames.includes(name),
    };
    if (comment.includes("|")) {
      entry.type = "string";
      entry.options = comment.split("|").map((v) => ({ label: v.trim(), value: v.trim() }));
    } else if (/^alias for\s+/i.test(comment)) {
      entry.description = comment;
    }
    (entry.required ? required : optional).push(entry);
  }
  return { required, optional };
}

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

const CASES = [
  {
    name: "tier0-T01-bispecific",
    workflow: "bispecific_format_triage",
    required: ["target_a", "target_b"],
    nfPath: "modules/biomate-ai-tools/bispecific_format_triage/main.nf",
    query: "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC",
    expect: { target_a: /pd-?1/i, target_b: /vegf/i, indication: /nsclc/i },
    rawParams: {},
  },
  {
    name: "tier0-T02-cart",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence",
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
    nfPath: "modules/biomate-ai-tools/glp1_modality_bakeoff/main.nf",
    query: "Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy",
    expect: { indication: /mash|nash/i },
    rawParams: {},
  },
  {
    name: "tier0-T05-modality-triage",
    workflow: "modality_triage",
    required: ["target_gene"],
    nfPath: "modules/biomate-ai-tools/modality_triage/main.nf",
    query: "Triage modalities for a BCMA oncology target — try all options",
    expect: { target_gene: /bcma/i, indication: /onco/i },
    rawParams: {},
  },
  {
    name: "synonym-graph-target-to-car_target",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Design CAR-T for BCMA myeloma",
    expect: { car_target: /bcma/i, indication: /myeloma/i },
    rawParams: { target: "BCMA", disease: "myeloma" },
  },
  {
    name: "user-mentioned-out-of-enum-surfaces",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Co-design CD19 CAR for DLBCL with delivery to B cells",
    expect: { car_target: /cd19/i, indication: /dlbcl/i },
    expectClarifications: [{ kind: "enum_violation", paramName: "delivery_cell" }],
    rawParams: {},
  },
  {
    name: "enum-violation-via-rawparams",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Co-design CD19 CAR for DLBCL",
    expect: { car_target: /cd19/i, indication: /dlbcl/i },
    expectClarifications: [{ kind: "enum_violation", paramName: "delivery_cell" }],
    rawParams: { car_target: "CD19", indication: "DLBCL", delivery_cell: "B_cell" },
    skipLlm: true,
  },
  {
    name: "no-signal-graceful",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Run the CAR-T workflow please",
    expect: {},
    expectClarifications: [
      { kind: "missing_required", paramName: "car_target" },
      { kind: "missing_required", paramName: "indication" },
    ],
    rawParams: {},
  },
  // True no-signal: no IDs, no schema keywords, no enum values. LLM gate
  // should fire and stages.llm should be false.
  {
    name: "gate-skips-generic-query",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "please start it now",
    expect: {},
    expectClarifications: [
      { kind: "missing_required", paramName: "car_target" },
      { kind: "missing_required", paramName: "indication" },
    ],
    rawParams: {},
    expectLlmSkipped: true,
  },
  {
    name: "alias-of-respected",
    workflow: "glp1_modality_bakeoff",
    required: ["indication"],
    nfPath: "modules/biomate-ai-tools/glp1_modality_bakeoff/main.nf",
    query: "GLP-1 modalities for obesity",
    expect: { indication: /obesity/i },
    forbidKeys: ["disease"],
    rawParams: {},
  },
  {
    name: "rule-pass-direct-hit",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "Co-design with these params",
    expect: { car_target: "CD19", indication: "DLBCL" },
    rawParams: { car_target: "CD19", indication: "DLBCL" },
    skipLlm: true,
  },
  {
    name: "rule-enum-normalize",
    workflow: "in_vivo_cart_codesign",
    required: ["car_target", "indication"],
    nfPath: "modules/biomate-ai-tools/in_vivo_cart_codesign/main.nf",
    query: "deliver to T cells",
    expect: { delivery_cell: /^T_cell$/ },
    rawParams: { car_target: "CD19", indication: "DLBCL", delivery_cell: "T cells" },
    skipLlm: true,
  },
];

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
  const nfText = fs.readFileSync(nfFull, "utf8");
  const entries = fakeBackendEntries(nfText, c.required);
  const schema = buildSchemaFromWorkflowGa({
    workflowName: c.workflow,
    requiredParams: entries.required,
    optionalParams: entries.optional,
  });
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
  let total = 0,
    allGreen = 0,
    keysPass = 0,
    keysTotal = 0;
  const failed: string[] = [];

  for (const c of CASES) {
    total++;
    let result, schema;
    try {
      ({ result, schema } = await runCase(c));
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.log(`\n=== ${c.name} ===\nERROR: ${msg}`);
      failed.push(c.name);
      continue;
    }
    const sum = summarize(result.params, c.expect);
    keysPass += sum.pass.length;
    keysTotal += Object.keys(c.expect).length;

    let clarOk = true;
    if (c.expectClarifications) {
      for (const e of c.expectClarifications) {
        if (!result.clarifications.find((x) => x.kind === e.kind && x.paramName === e.paramName))
          clarOk = false;
      }
    }
    let forbidOk = true;
    if (c.forbidKeys) {
      for (const k of c.forbidKeys)
        if (result.params[k] !== undefined) forbidOk = false;
    }
    let llmGateOk = true;
    if ((c as any).expectLlmSkipped && result.stagesFired.llm) {
      llmGateOk = false;
    }
    const ok = sum.fail.length === 0 && clarOk && forbidOk && llmGateOk;
    if (ok) allGreen++;
    else failed.push(c.name);

    console.log(
      `\n=== ${c.name} ${ok ? "✓" : "✗"} (${sum.pass.length}/${Object.keys(c.expect).length} keys, conf=${result.confidence.toFixed(2)}, src=${schema.source}, stages=${Object.entries(result.stagesFired).filter(([, v]) => v).map(([k]) => k).join("+")}) ===`,
    );
    console.log("  out: ", result.params);
    if (sum.fail.length > 0) console.log("  fail:", sum.fail);
    if (!clarOk) console.log("  ✗ expected clarifications:", c.expectClarifications);
    if (!forbidOk && c.forbidKeys)
      console.log("  ✗ forbidden keys present:", c.forbidKeys.filter((k) => result.params[k] !== undefined));
    if (!llmGateOk) console.log("  ✗ LLM gate failed — expected stages.llm=false");
  }
  console.log(`\n=== TOTAL: ${allGreen}/${total} all-green | ${keysPass}/${keysTotal} keys correct ===`);
  if (failed.length > 0) {
    console.log("\nFAILED:", failed.join(", "));
    process.exit(1);
  }
})();
