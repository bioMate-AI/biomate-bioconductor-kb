/**
 * Smoke test for the groundInlineParameters wrapper in galaxy-assistant.ts.
 * Verifies legacy↔schema-grounded path routing without needing the Galaxy
 * backend (the schema-grounded path is exercised by the .local.ts test;
 * here we just verify the wrapper dispatches correctly).
 *
 * Run: node_modules/.bin/tsx server/lib/__tests__/wrapper.smoke.ts
 */
import "dotenv/config";
import { groundInlineParameters } from "../../galaxy-assistant.js";

async function run() {
  let failures = 0;

  // 1. Flag off + workflow in legacy table → 'legacy-alias' path
  delete process.env.SCHEMA_GROUNDED_EXTRACTION;
  const r1 = await groundInlineParameters({
    workflowName: "in_vivo_cart_codesign",
    rawParams: { target: "CD19", disease: "DLBCL" },
    userQuery: "design CAR for DLBCL",
  });
  if (r1.path !== "legacy-alias") {
    console.log(`✗ flag-off legacy: expected legacy-alias, got ${r1.path}`);
    failures++;
  } else if (!r1.params.car_target || !r1.params.indication) {
    console.log(`✗ flag-off legacy: missing remapped keys —`, r1.params);
    failures++;
  } else {
    console.log(
      `✓ flag-off legacy path: target→car_target=${r1.params.car_target}, disease→indication=${r1.params.indication}`,
    );
  }

  // 2. Workflow=null → 'noop' path (early return)
  const r2 = await groundInlineParameters({
    workflowName: null,
    rawParams: { foo: "bar" },
    userQuery: "any query",
  });
  if (r2.path !== "noop") {
    console.log(`✗ noop: expected noop, got ${r2.path}`);
    failures++;
  } else {
    console.log("✓ workflow=null → noop path");
  }

  // 3. Flag on + workflow with .nf → schema-grounded path (won't actually call
  //    LLM in unit test — it'd need Galaxy backend; here we just verify the
  //    dispatch picks the right code path, which we infer from a failure mode
  //    of LLM unavailability returning legacy-alias fallback)
  process.env.SCHEMA_GROUNDED_EXTRACTION = "1";
  const r3 = await groundInlineParameters({
    workflowName: "in_vivo_cart_codesign",
    rawParams: { car_target: "CD19", indication: "DLBCL", delivery_cell: "T cells" },
    userQuery: "co-design CAR",
    requiredParams: ["car_target", "indication"],
    optionalParams: ["delivery_cell", "lnp_targeting", "persistence"],
  });
  // Schema-grounded should normalize "T cells" → "T_cell" via the rule pass
  // (zero LLM needed for this case).
  if (r3.path !== "schema-grounded") {
    console.log(
      `✗ flag-on: expected schema-grounded, got ${r3.path}`,
    );
    failures++;
  } else if (r3.params.delivery_cell !== "T_cell") {
    console.log(
      `✗ flag-on: enum normalization failed — got ${r3.params.delivery_cell}`,
    );
    failures++;
  } else {
    console.log(
      `✓ flag-on schema-grounded: delivery_cell normalized "T cells" → "${r3.params.delivery_cell}", confidence=${r3.details?.confidence?.toFixed(2)}`,
    );
  }

  // 4. Flag on + unknown workflow → fallback to legacy-alias (no schema)
  const r4 = await groundInlineParameters({
    workflowName: "some_workflow_with_no_nf_anywhere",
    rawParams: { foo: "bar" },
    userQuery: "test",
  });
  if (r4.path !== "legacy-alias") {
    console.log(
      `✗ flag-on unknown wf: expected legacy-alias fallback, got ${r4.path}`,
    );
    failures++;
  } else {
    console.log("✓ flag-on + unknown workflow → legacy-alias fallback");
  }

  console.log(`\n=== wrapper smoke: ${failures === 0 ? "PASS" : `${failures} FAIL`} ===`);
  process.exit(failures > 0 ? 1 : 0);
}

run().catch((e) => {
  console.error("ERROR:", e);
  process.exit(1);
});
