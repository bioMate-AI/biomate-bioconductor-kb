/**
 * Input gate for workflow execution requests.
 *
 * Keep this independent of Express and the workflow launcher: a rejected
 * request must be identified before any run or external invocation exists.
 */
type WorkflowInputStep = { id: string };
type InputBinding = { id?: unknown; src?: unknown; stepId?: unknown; step_id?: unknown };

function getWorkflowSteps(workflowDefinition: unknown): Record<string, unknown> | undefined {
  if (!workflowDefinition || typeof workflowDefinition !== "object") return undefined;
  const definition = workflowDefinition as { steps?: unknown; workflow_ga?: { steps?: unknown } };
  // Connector/search results commonly wrap the executable Galaxy definition in
  // workflow_ga. Prefer a populated top-level definition, then fall back to it.
  if (definition.steps && typeof definition.steps === "object" && Object.keys(definition.steps).length > 0) {
    return definition.steps as Record<string, unknown>;
  }
  if (definition.workflow_ga?.steps && typeof definition.workflow_ga.steps === "object") {
    return definition.workflow_ga.steps as Record<string, unknown>;
  }
  return undefined;
}

function requiredWorkflowInputSteps(workflowDefinition: unknown): WorkflowInputStep[] {
  const steps = getWorkflowSteps(workflowDefinition);
  if (!steps) return [];
  return Object.entries(steps).flatMap(([id, step]) => {
    const type = step && typeof step === "object" ? (step as { type?: unknown }).type : undefined;
    return type === "data_input" || type === "data_collection_input" ? [{ id }] : [];
  });
}

export function requiredWorkflowInputCount(workflowDefinition: unknown): number {
  return requiredWorkflowInputSteps(workflowDefinition).length;
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function inputBindingStepId(input: InputBinding): string | undefined {
  const stepId = input.stepId ?? input.step_id;
  if (typeof stepId === "number" && Number.isFinite(stepId)) return String(stepId);
  return nonEmptyString(stepId) ? stepId : undefined;
}

/** A well-formed input binding captured for the run record (provenance). */
export type ResolvedInputBinding = {
  stepId: string;
  datasetId: string;
  src?: string;
  name?: string;
  s3Uri?: string;
  projectFileId?: string;
};

/**
 * Extract the well-formed input bindings from an execution request's `inputs`.
 * Only entries that pass the same id/src/stepId shape check the gate enforces
 * are recorded — malformed entries are dropped (the gate rejects the run
 * separately). This is the provenance the run record stores: which exact
 * dataset was bound to each data-input step.
 */
export function extractInputBindings(inputs: unknown): ResolvedInputBinding[] {
  const inputArray = Array.isArray(inputs) ? inputs : [];
  const out: ResolvedInputBinding[] = [];
  for (const candidate of inputArray) {
    if (!candidate || typeof candidate !== "object") continue;
    const input = candidate as InputBinding & {
      name?: unknown; s3Uri?: unknown; s3_uri?: unknown; projectFileId?: unknown; project_file_id?: unknown;
    };
    const stepId = inputBindingStepId(input);
    if (!nonEmptyString(input.id) || !stepId) continue;
    const binding: ResolvedInputBinding = { stepId, datasetId: input.id };
    if (nonEmptyString(input.src)) binding.src = input.src;
    if (nonEmptyString(input.name)) binding.name = input.name;
    const s3 = input.s3Uri ?? input.s3_uri;
    if (nonEmptyString(s3)) binding.s3Uri = s3;
    const pfid = input.projectFileId ?? input.project_file_id;
    if (nonEmptyString(pfid)) binding.projectFileId = pfid;
    out.push(binding);
  }
  return out;
}

/**
 * Detect a workflow definition that is actually a generation FAILURE, so the
 * execute path never launches compute on a non-runnable workflow. Conservative:
 * only explicit failure signals (an `error`, or `success === false`) block — a
 * definition that simply omits these fields is treated as runnable.
 */
export function detectGenerationFailure(
  workflowDefinition: unknown,
): { failed: boolean; detail?: string } {
  if (!workflowDefinition || typeof workflowDefinition !== "object") {
    return { failed: true, detail: "No workflow definition was provided." };
  }
  const wf = workflowDefinition as { error?: unknown; success?: unknown; message?: unknown };
  if (wf.error) {
    return { failed: true, detail: typeof wf.error === "string" ? wf.error : "Workflow generation reported an error." };
  }
  if (wf.success === false) {
    return { failed: true, detail: typeof wf.message === "string" ? wf.message : "Workflow generation did not succeed." };
  }
  return { failed: false };
}

/**
 * Return the input ids that the caller declared UNRESOLVED (chat could not bind
 * them to a real, authorized dataset). Used to block a launch that would
 * otherwise run against a reference we know does not resolve — never
 * substituting another dataset.
 */
export function findUnresolvedInputs(inputs: unknown, unresolvedIds: unknown): string[] {
  const unresolved = new Set(
    (Array.isArray(unresolvedIds) ? unresolvedIds : []).filter(
      (x): x is string => typeof x === "string" && x.trim().length > 0,
    ),
  );
  if (!unresolved.size) return [];
  const inputArray = Array.isArray(inputs) ? inputs : [];
  const hits = new Set<string>();
  for (const candidate of inputArray) {
    if (candidate && typeof candidate === "object") {
      const id = (candidate as { id?: unknown }).id;
      if (typeof id === "string" && unresolved.has(id)) hits.add(id);
    }
  }
  return [...hits];
}

export type WorkflowInputGateResult = {
  inputStepsCount: number;
  missingInputStepIds: string[];
  invalidInputCount: number;
  inputsRequired: boolean;
  inputsInvalid: boolean;
  inputsUnsupportedForNextflow: boolean;
};

export function validateWorkflowInputs(
  workflowDefinition: unknown,
  inputs: unknown,
  executionEngine?: "galaxy" | "nextflow" | "cryosparc",
): WorkflowInputGateResult {
  const requiredSteps = requiredWorkflowInputSteps(workflowDefinition);
  const requiredStepIds = new Set(requiredSteps.map((step) => step.id));
  const inputArray = Array.isArray(inputs) ? inputs : [];
  const boundStepIds = new Set<string>();
  let invalidInputCount = 0;

  for (const candidate of inputArray) {
    if (!candidate || typeof candidate !== "object") {
      invalidInputCount += 1;
      continue;
    }
    const input = candidate as InputBinding;
    const stepId = inputBindingStepId(input);
    if (!nonEmptyString(input.id) || !nonEmptyString(input.src) || !stepId || !requiredStepIds.has(stepId)) {
      invalidInputCount += 1;
      continue;
    }
    boundStepIds.add(stepId);
  }

  const missingInputStepIds = requiredSteps
    .map((step) => step.id)
    .filter((stepId) => !boundStepIds.has(stepId));
  const inputsInvalid = requiredSteps.length > 0 && invalidInputCount > 0;
  const inputsRequired = requiredSteps.length > 0 && missingInputStepIds.length > 0;

  return {
    inputStepsCount: requiredSteps.length,
    missingInputStepIds,
    invalidInputCount,
    // Deliberately accept only the documented `inputs` array. `inputData` is
    // presentation state, not an execution input contract.
    inputsRequired,
    inputsInvalid,
    // Nextflow direct execution currently has no step-id → parameter binding.
    // The execution engine defaults to Nextflow, so this must use the same
    // resolved engine as the launcher rather than only explicit workflow tags.
    inputsUnsupportedForNextflow:
      requiredSteps.length > 0 && inputArray.length > 0 && !inputsInvalid && !inputsRequired && executionEngine === "nextflow",
  };
}
