export interface HardwareRequirements {
  gpu_required?: boolean;
  min_memory_gb?: number | null;
}

export interface HardwareGateResult {
  inferredExecutor: string;
  hardwareReady: boolean;
  gpuConstraintUnmet: boolean;
  memoryConstraintUnmet: boolean;
  hardwareReason: string | null;
}

export function inferExecutor(
  requestedComputeConfig: Record<string, any> | undefined,
  workflowType: string | undefined
): string {
  return String(
    requestedComputeConfig?.executor ||
      (workflowType === "nextflow" ? "awsbatch" : "local")
  ).toLowerCase();
}

export function evaluateHardwareGate(
  hardwareRequirements: HardwareRequirements | null | undefined,
  requestedComputeConfig: Record<string, any> | undefined,
  workflowType: string | undefined
): HardwareGateResult {
  const inferredExecutor = inferExecutor(requestedComputeConfig, workflowType);
  const isAwsBatchExecutor = inferredExecutor === "awsbatch";

  const gpuConstraintUnmet =
    !isAwsBatchExecutor &&
    hardwareRequirements?.gpu_required === true &&
    requestedComputeConfig?.gpu_count !== undefined &&
    Number(requestedComputeConfig.gpu_count) <= 0;

  const memoryConstraintUnmet =
    !isAwsBatchExecutor &&
    typeof hardwareRequirements?.min_memory_gb === "number" &&
    requestedComputeConfig?.memory_gb !== undefined &&
    Number(requestedComputeConfig.memory_gb) < Number(hardwareRequirements.min_memory_gb);

  const hardwareReady = !(gpuConstraintUnmet || memoryConstraintUnmet);
  const hardwareReason = !hardwareReady
    ? [
        gpuConstraintUnmet
          ? "GPU is required by workflow tool runtime hints but requested compute_config.gpu_count is 0."
          : null,
        memoryConstraintUnmet
          ? `Requested compute_config.memory_gb is below minimum recommended ${hardwareRequirements?.min_memory_gb} GB.`
          : null,
      ]
        .filter(Boolean)
        .join(" ")
    : null;

  return {
    inferredExecutor,
    hardwareReady,
    gpuConstraintUnmet,
    memoryConstraintUnmet,
    hardwareReason,
  };
}

export function buildNextflowComputeConfig(
  requestedComputeConfig: Record<string, any> | undefined,
  hardwareRequirements: HardwareRequirements | null | undefined
): Record<string, any> {
  const nextflowComputeConfig = {
    ...(requestedComputeConfig || {}),
  };

  if (!nextflowComputeConfig.executor) {
    // Default to awsbatch — BioMate platform standard; override with NEXTFLOW_DEFAULT_EXECUTOR=local for local dev
    nextflowComputeConfig.executor = process.env.NEXTFLOW_DEFAULT_EXECUTOR || "awsbatch";
  }

  if (
    hardwareRequirements?.gpu_required === true &&
    (nextflowComputeConfig.gpu_count === undefined ||
      Number(nextflowComputeConfig.gpu_count) <= 0)
  ) {
    nextflowComputeConfig.gpu_count = 1;
  }

  if (
    typeof hardwareRequirements?.min_memory_gb === "number" &&
    (nextflowComputeConfig.memory_gb === undefined ||
      Number(nextflowComputeConfig.memory_gb) <= 0)
  ) {
    nextflowComputeConfig.memory_gb = Number(hardwareRequirements.min_memory_gb);
  }

  return nextflowComputeConfig;
}
