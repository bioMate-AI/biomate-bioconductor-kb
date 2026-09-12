/**
 * The executor status is a transport-level fact.  A completed process is not
 * automatically a usable scientific result: ordinary workflows must register
 * at least one output for the result surface to be meaningful.
 *
 * A workflow can opt out only by declaring `metadata.output_contract` as the
 * exact string `stdout_only`.  Do not infer this from a workflow name, domain,
 * or an empty output declaration: those are all prone to false positives.
 */
export type OutputCompletionMode = "artifacts_required" | "stdout_only";
export type OutputCompletionState = "ready" | "artifact_unavailable" | "stdout_only";

export interface OutputCompletionAssessment {
  mode: OutputCompletionMode;
  state: OutputCompletionState;
  registeredOutputCount: number;
  meetsContract: boolean;
}

export function getOutputCompletionMode(workflowDefinition: unknown): OutputCompletionMode {
  if (!workflowDefinition || typeof workflowDefinition !== "object") {
    return "artifacts_required";
  }

  const metadata = (workflowDefinition as { metadata?: unknown }).metadata;
  if (!metadata || typeof metadata !== "object") return "artifacts_required";

  // Keep this deliberately narrow.  Camel-case is accepted for JSON authored
  // by TypeScript clients, but truthy flags such as stdout_only: true are not:
  // a workflow author must make the contract explicit and reviewable.
  const raw = (metadata as { output_contract?: unknown; outputContract?: unknown }).output_contract
    ?? (metadata as { outputContract?: unknown }).outputContract;
  return raw === "stdout_only" ? "stdout_only" : "artifacts_required";
}

export function assessOutputCompletion(
  workflowDefinition: unknown,
  registeredOutputCount: number,
): OutputCompletionAssessment {
  const mode = getOutputCompletionMode(workflowDefinition);
  const count = Number.isFinite(registeredOutputCount)
    ? Math.max(0, Math.floor(registeredOutputCount))
    : 0;

  if (mode === "stdout_only") {
    return { mode, state: "stdout_only", registeredOutputCount: count, meetsContract: true };
  }
  if (count > 0) {
    return { mode, state: "ready", registeredOutputCount: count, meetsContract: true };
  }
  return { mode, state: "artifact_unavailable", registeredOutputCount: 0, meetsContract: false };
}
