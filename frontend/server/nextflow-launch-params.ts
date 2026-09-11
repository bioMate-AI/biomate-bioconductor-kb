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
  return value !== undefined && value !== null && value !== "";
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

  return {
    ...structuredValues,
    ...(isRecord(definition.inline_parameters) ? definition.inline_parameters : {}),
    ...(isRecord(definition.parameters) ? definition.parameters : {}),
    // Public API overrides are intentionally last, including false/0/empty
    // values. Required-value validation occurs before this launch payload is
    // constructed, and callers must be able to explicitly override defaults.
    ...(isRecord(requestParams) ? requestParams : {}),
  };
}
