import { describe, expect, it } from "vitest";
import {
  buildNextflowComputeConfig,
  evaluateHardwareGate,
  inferExecutor,
} from "./execution-env-policy";

describe("execution-env-policy", () => {
  it("defaults Nextflow executor to awsbatch", () => {
    expect(inferExecutor({}, "nextflow")).toBe("awsbatch");
  });

  it("keeps explicit local executor", () => {
    expect(inferExecutor({ executor: "local" }, "nextflow")).toBe("local");
  });

  it("does not block AWS Batch when gpu/memory values are omitted", () => {
    const result = evaluateHardwareGate(
      { gpu_required: true, min_memory_gb: 16 },
      {},
      "nextflow"
    );
    expect(result.inferredExecutor).toBe("awsbatch");
    expect(result.hardwareReady).toBe(true);
  });

  it("blocks local executor when GPU requirement is explicitly violated", () => {
    const result = evaluateHardwareGate(
      { gpu_required: true, min_memory_gb: 16 },
      { executor: "local", gpu_count: 0 },
      "nextflow"
    );
    expect(result.hardwareReady).toBe(false);
    expect(result.gpuConstraintUnmet).toBe(true);
  });

  it("blocks local executor when memory requirement is explicitly violated", () => {
    const result = evaluateHardwareGate(
      { gpu_required: false, min_memory_gb: 32 },
      { executor: "local", memory_gb: 8 },
      "nextflow"
    );
    expect(result.hardwareReady).toBe(false);
    expect(result.memoryConstraintUnmet).toBe(true);
  });

  it("autofills Nextflow compute config from hardware hints", () => {
    const cfg = buildNextflowComputeConfig({}, { gpu_required: true, min_memory_gb: 24 });
    expect(cfg.executor).toBe("awsbatch");
    expect(cfg.gpu_count).toBe(1);
    expect(cfg.memory_gb).toBe(24);
  });

  it("matches execute API contract: contradictory local request is blocked", () => {
    const hardwareRequirements = { gpu_required: true, min_memory_gb: 16 };
    const requestedComputeConfig = { executor: "local", gpu_count: 0, memory_gb: 8 };

    const gate = evaluateHardwareGate(
      hardwareRequirements,
      requestedComputeConfig,
      "nextflow"
    );

    expect(gate.inferredExecutor).toBe("local");
    expect(gate.hardwareReady).toBe(false);
    expect(gate.hardwareReason).toContain("GPU is required");
    expect(gate.hardwareReason).toContain("below minimum recommended 16 GB");
  });

  it("matches execute API contract: default Nextflow path remains allowed", () => {
    const hardwareRequirements = { gpu_required: true, min_memory_gb: 16 };
    const requestedComputeConfig = {};

    const gate = evaluateHardwareGate(
      hardwareRequirements,
      requestedComputeConfig,
      "nextflow"
    );

    expect(gate.inferredExecutor).toBe("awsbatch");
    expect(gate.hardwareReady).toBe(true);
    expect(gate.hardwareReason).toBeNull();
  });
});
