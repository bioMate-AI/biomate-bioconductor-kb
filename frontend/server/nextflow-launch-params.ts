type ParameterDefinition = {
  name?: unknown;
  value?: unknown;
  default?: unknown;
};

type WorkflowDefinition = {
  parameters?: unknown;
  inline_parameters?: unknown;
  required_params?: unknown;
  optional_params?: unknown;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function hasValue(value: unknown): boolean {
  return value !== undefined && value !== null && (
    typeof value !== "string" || value.trim() !== ""
  );
}

function nonEmptyRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) return {};
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => hasValue(entry)));
}

/**
 * Produces the parameter map sent to Galaxy's Nextflow executor.
 *
 * The execute API supports both a workflow definition (whose structured
 * parameter rows can carry values/defaults) and a top-level `params` override
 * map.  The latter is the public API contract and must win over every workflow
 * default.  Keeping this as a pure function lets us assert the exact launch
 * payload without a live Batch submission.
 */
export function buildNextflowLaunchParameters(
  workflowDefinition: WorkflowDefinition | undefined | null,
  requestParams: unknown,
): Record<string, unknown> {
  const definition = workflowDefinition || {};
  const parameterRows = [
    ...(Array.isArray(definition.required_params) ? definition.required_params : []),
    ...(Array.isArray(definition.optional_params) ? definition.optional_params : []),
  ] as ParameterDefinition[];

  const structuredValues: Record<string, unknown> = {};
  for (const parameter of parameterRows) {
    if (!parameter || typeof parameter.name !== "string" || !parameter.name) continue;

    // A user-entered row value takes precedence over the schema default.  Do
    // not emit null/blank defaults: Nextflow should apply its own defaults when
    // no value was configured by the workflow or caller.
    const resolved = hasValue(parameter.value) ? parameter.value : parameter.default;
    if (hasValue(resolved)) structuredValues[parameter.name] = resolved;
  }

  const nonEmptyRequestParams = nonEmptyRecord(requestParams);

  const merged: Record<string, unknown> = {
    // Generic parameter maps may supply defaults, but cannot erase structured
    // values with blank/null entries. Structured rows are what the execution
    // gate validates, so preserve their values at launch.
    ...nonEmptyRecord(definition.inline_parameters),
    ...nonEmptyRecord(definition.parameters),
    ...structuredValues,
    // Public API overrides are intentionally last. Keep false and 0 (valid
    // parameter values), but never replace a validated default with blank
    // input: that would let the required-param gate pass then launch invalid
    // Nextflow arguments.
    ...nonEmptyRequestParams,
  };

  // nf-core/differentialabundance (and BioMate's DE stub) accept samplesheet OR
  // input as aliases. Panel/AI bind to `samplesheet`; some paths only set
  // `input`. Mirror whichever is present so Nextflow never sees both empty
  // while the UI showed "samplesheet → mapped" (2026-11-13 symptom 9).
  if (hasValue(merged.samplesheet) && !hasValue(merged.input)) {
    merged.input = merged.samplesheet;
  } else if (hasValue(merged.input) && !hasValue(merged.samplesheet)) {
    merged.samplesheet = merged.input;
  }

  return merged;
}
