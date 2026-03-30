import { describe, expect, it } from "vitest";

const RUN_LIVE = process.env.RUN_LIVE_EXECUTE_CONTRACT === "1";
const BASE_URL = process.env.BIOMATE_URL || "http://127.0.0.1:5000";
const REQUIRE_AWS_200 = process.env.REQUIRE_AWS_EXEC_200 === "1";

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

    // The core contract here is that AWS/default path is not confidence-gate blocked.
    expect(awsAllowed.status).not.toBe(409);
    expect(awsAllowed.body.error).not.toBe("confidence_gate_blocked");

    if (REQUIRE_AWS_200) {
      expect(awsAllowed.status).toBe(200);
      expect(awsAllowed.body.executionEngine).toBe("nextflow");
      expect(awsAllowed.body.status).toBe("running");
      expect(typeof awsAllowed.body.runId).toBe("string");
      expect(typeof awsAllowed.body.nextflowRunId).toBe("string");
    }
  }, 120000);
});

