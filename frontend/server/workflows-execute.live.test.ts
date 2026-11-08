import { describe, expect, it } from "vitest";

const RUN_LIVE = process.env.RUN_LIVE_EXECUTE_CONTRACT === "1";
const BASE_URL = process.env.BIOMATE_URL || "http://127.0.0.1:5000";

type JsonRecord = Record<string, any>;

async function postJson(
  path: string,
  payload: JsonRecord,
  timeoutMs = 30000
): Promise<{ status: number; body: JsonRecord }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let response: Response;
  try {
    response = await fetch(`${BASE_URL}${path}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      signal: controller.signal,
      body: JSON.stringify(payload),
    });
  } finally {
    clearTimeout(timer);
  }

  const text = await response.text();
  let body: JsonRecord;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }

  return { status: response.status, body };
}

const describeLive = RUN_LIVE ? describe : describe.skip;

describeLive("Live /api/workflows/execute confidence gate contract", () => {
  it("returns 409 for contradictory local config and allows AWS path", async () => {
    const workflowDefinitionBase = {
      workflow_type: "nextflow",
      nextflow_path: "biomni_nf/genomics/get_rna_seq_archs4/main.nf",
    };

    const workflowDefinitionForBlockedLocal = {
      ...workflowDefinitionBase,
      // Force deterministic gate behavior for the blocked-local branch.
      hardware_requirements: {
        gpu_required: true,
        min_memory_gb: 16,
      },
    };

    const localContradictory = await postJson("/api/workflows/execute", {
      workflowDefinition: workflowDefinitionForBlockedLocal,
      inputData: { datasets: [] },
      executionConfig: {
        executionEngine: "nextflow",
        monitorProgress: true,
        computeConfig: {
          executor: "local",
          gpu_count: 0,
          memory_gb: 1,
        },
      },
    }, 15000);

    expect(localContradictory.status).toBe(409);
    expect(localContradictory.body.error).toBe("confidence_gate_blocked");
    expect(localContradictory.body.hardwareReady).toBe(false);
    expect(localContradictory.body.inferredExecutor).toBe("local");

    const awsAllowed = await postJson("/api/workflows/execute", {
      // Keep AWS-path probe representative but avoid injecting synthetic
      // requirements that can overconstrain runtime environments.
      workflowDefinition: workflowDefinitionBase,
      inputData: { datasets: [] },
      executionConfig: {
        executionEngine: "nextflow",
        monitorProgress: true,
        computeConfig: {
          executor: "awsbatch",
        },
      },
    }, 60000);

    // This is an explicit live test. A non-409 response (401/500/launch error)
    // is not evidence that the AWS path is usable.
    expect(awsAllowed.status).toBe(200);
    expect(awsAllowed.body.executionEngine).toBe("nextflow");
    expect(awsAllowed.body.status).toBe("running");
    expect(typeof awsAllowed.body.runId).toBe("string");
    expect(awsAllowed.body.runId.length).toBeGreaterThan(0);
    expect(typeof awsAllowed.body.nextflowRunId).toBe("string");
    expect(awsAllowed.body.nextflowRunId.length).toBeGreaterThan(0);
    expect(typeof awsAllowed.body.galaxyInvocationId).toBe("string");
    expect(awsAllowed.body.galaxyInvocationId.length).toBeGreaterThan(0);
  }, 120000);
});

describeLive("Live /api/workflows/execute required-parameter gate contract", () => {
  // A minimal Nextflow workflow with one required param that has no default and
  // no input steps — so only the required-param gate can block it.
  const workflowWithRequiredParam = {
    name: "Required Param Probe",
    workflow_type: "nextflow",
    nextflow_path: "nextflow_nfcore/subworkflows/drug_discovery/cyp_ddi_panel/main.nf",
    required_params: [
      { name: "smiles", label: "SMILES", description: "compound SMILES", type: "string", default: null },
    ],
  };

  it("returns 400 missing_required_params (no Batch launch) when a required param is empty", async () => {
    const res = await postJson("/api/workflows/execute", {
      workflowDefinition: workflowWithRequiredParam,
      inputData: { datasets: [] },
      executionConfig: { executionEngine: "nextflow", computeConfig: { executor: "awsbatch" } },
    }, 15000);

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("missing_required_params");
    expect(Array.isArray(res.body.missing)).toBe(true);
    expect(res.body.missing.map((m: any) => m.name)).toContain("smiles");
    // No run was created.
    expect(res.body.runId).toBeUndefined();
  }, 30000);

  it("launches with IDs when a supplied SMILES satisfies the required parameter", async () => {
    const res = await postJson("/api/workflows/execute", {
      workflowDefinition: workflowWithRequiredParam,
      params: { smiles: "CC(=O)Oc1ccccc1C(=O)O" },
      inputData: { datasets: [] },
      executionConfig: { executionEngine: "nextflow", computeConfig: { executor: "awsbatch" } },
    }, 60000);

    // A gate pass alone is insufficient: this must be a successfully accepted
    // Nextflow launch with both platform and executor tracking IDs. The
    // companion non-live payload test asserts the exact `parameters.smiles`
    // sent to the executor.
    expect(res.status).toBe(200);
    expect(res.body.error).toBeUndefined();
    expect(res.body.executionEngine).toBe("nextflow");
    expect(res.body.status).toBe("running");
    expect(typeof res.body.runId).toBe("string");
    expect(res.body.runId.length).toBeGreaterThan(0);
    expect(typeof res.body.nextflowRunId).toBe("string");
    expect(res.body.nextflowRunId.length).toBeGreaterThan(0);
    expect(typeof res.body.galaxyInvocationId).toBe("string");
    expect(res.body.galaxyInvocationId.length).toBeGreaterThan(0);
  }, 90000);
});

describeLive("Live /api/workflows/execute dataset-binding safety contract", () => {
  // A Galaxy-shaped definition with a data-input step.  It deliberately has no
  // Nextflow path: production defaults unmarked executable definitions to the
  // Nextflow launcher, which must reject accepted Galaxy bindings rather than
  // silently dropping them.
  const workflowWithGalaxyInput = {
    name: "Dataset binding safety probe",
    steps: {
      "0": { type: "data_input", name: "reads" },
      "1": { type: "tool", tool_id: "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy0" },
    },
  };

  function expectNoLaunch(body: JsonRecord) {
    expect(body.runId).toBeUndefined();
    expect(body.nextflowRunId).toBeUndefined();
    expect(body.galaxyInvocationId).toBeUndefined();
  }

  it("blocks missing and malformed Galaxy dataset bindings before compute", async () => {
    const missing = await postJson("/api/workflows/execute", {
      workflowDefinition: workflowWithGalaxyInput,
      inputs: [],
    }, 15000);

    expect(missing.status).toBe(400);
    expect(missing.body).toMatchObject({
      error: "inputs_required",
      inputStepsCount: 1,
      missingInputStepIds: ["0"],
    });
    expect(typeof missing.body.message).toBe("string");
    expect(typeof missing.body.guidance).toBe("string");
    expectNoLaunch(missing.body);

    const malformed = await postJson("/api/workflows/execute", {
      workflowDefinition: workflowWithGalaxyInput,
      // A dataset id without the required Galaxy source and step id cannot be
      // passed to a launcher as a valid binding.
      inputs: [{ id: "dataset-probe" }],
    }, 15000);

    expect(malformed.status).toBe(400);
    expect(malformed.body).toMatchObject({
      error: "invalid_workflow_inputs",
      inputStepsCount: 1,
      invalidInputCount: 1,
    });
    expect(typeof malformed.body.message).toBe("string");
    expect(typeof malformed.body.guidance).toBe("string");
    expectNoLaunch(malformed.body);
  }, 45000);

  it("rejects a well-formed Galaxy binding on the default Nextflow path instead of dropping it", async () => {
    const res = await postJson("/api/workflows/execute", {
      workflowDefinition: workflowWithGalaxyInput,
      inputs: [{ id: "dataset-probe", src: "hda", step_id: "0" }],
      // Intentionally omit executionConfig: this verifies the default engine
      // follows the same no-silent-data-loss safety rule.
    }, 15000);

    expect(res.status).toBe(400);
    expect(res.body).toMatchObject({
      error: "nextflow_inputs_not_supported",
      inputStepsCount: 1,
    });
    expect(typeof res.body.message).toBe("string");
    expect(res.body.message).toContain("No compute was launched");
    expectNoLaunch(res.body);
  }, 30000);
});
