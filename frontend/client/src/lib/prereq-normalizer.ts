export type PrereqStatus = "ok" | "missing" | "warning";

export interface PrereqItem {
  id: "input_data" | "required_parameters";
  label: string;
  status: PrereqStatus;
  reason?: string;
  actionHint?: string;
}

export interface PrereqChecklist {
  items: PrereqItem[];
  canRun: boolean;
  overrideAllowed: boolean;
}

interface NormalizeOptions {
  executionBlockedReason?: string;
  allowLowConfidenceOverride?: boolean;
}

export function normalizePrereqChecklist(
  prerequisitesValidation: any,
  options: NormalizeOptions = {}
): PrereqChecklist | undefined {
  const missingInputs = prerequisitesValidation?.analysis?.missingInputs ?? [];
  const missingParameters = prerequisitesValidation?.analysis?.missingParameters ?? [];
  const inputMappings = prerequisitesValidation?.analysis?.inputMappings ?? [];
  const requirementParams = prerequisitesValidation?.requirements?.parameters ?? [];
  const hasValidatorPayload = !!prerequisitesValidation;

  if (!hasValidatorPayload) {
    return undefined;
  }

  const items: PrereqItem[] = [];

  // Input data
  if (missingInputs.length > 0) {
    items.push({
      id: "input_data",
      label: "Input data",
      status: "warning",
      reason: `${missingInputs.length} required input(s) are missing.`,
      actionHint: "Upload or select your data files.",
    });
  } else if (inputMappings.length > 0) {
    items.push({
      id: "input_data",
      label: "Input data",
      status: "ok",
      reason: `${inputMappings.length} dataset mapping(s) detected.`,
    });
  } else if (hasValidatorPayload) {
    items.push({
      id: "input_data",
      label: "Input data",
      status: "warning",
      reason: "No input data detected yet.",
      actionHint: "Upload or select your data files.",
    });
  }

  // Required parameters
  const requiredParamKeys = new Set(
    requirementParams
      .filter((p: any) => p && p.optional === false)
      .map((p: any) => `${String(p.stepId)}:${String(p.paramName)}`)
  );
  const requiredWithDefaultsKeys = new Set(
    requirementParams
      .filter((p: any) => p && p.optional === false && p.defaultValue != null)
      .map((p: any) => `${String(p.stepId)}:${String(p.paramName)}`)
  );

  const requiredMissingWithoutDefaults = missingParameters.filter((p: any) => {
    const key = `${String(p?.stepId)}:${String(p?.paramName)}`;
    return requiredParamKeys.has(key) && !requiredWithDefaultsKeys.has(key);
  });
  const requiredMissingWithDefaults = missingParameters.filter((p: any) => {
    const key = `${String(p?.stepId)}:${String(p?.paramName)}`;
    return requiredWithDefaultsKeys.has(key);
  });
  const optionalOrSuggestedParams = missingParameters.filter((p: any) => {
    const key = `${String(p?.stepId)}:${String(p?.paramName)}`;
    return !requiredParamKeys.has(key) || (p?.suggestedOptions && p.suggestedOptions.length > 0);
  });

  if (requiredMissingWithoutDefaults.length > 0) {
    items.push({
      id: "required_parameters",
      label: "Required parameters",
      status: "missing",
      reason: `${requiredMissingWithoutDefaults.length} required parameter(s) are missing and have no defaults.`,
      actionHint: "Fill in the required fields above before running.",
    });
  } else if (requiredMissingWithDefaults.length > 0 || optionalOrSuggestedParams.length > 0) {
    const defaultCount = requiredMissingWithDefaults.length;
    const optionalCount = optionalOrSuggestedParams.length;
    items.push({
      id: "required_parameters",
      label: "Required parameters",
      status: "warning",
      reason:
        `${defaultCount > 0 ? `${defaultCount} required parameter(s) will use defaults. ` : ""}` +
        `${optionalCount > 0 ? `${optionalCount} optional parameter(s) may improve results.` : ""}`.trim(),
      actionHint: "Review parameters above; defaults will be used if left unchanged.",
    });
  } else if (hasValidatorPayload) {
    items.push({
      id: "required_parameters",
      label: "Required parameters",
      status: "ok",
      reason: "Required parameters are satisfied.",
    });
  }

  // Confidence gate is NOT surfaced here — the amber alert + "Confirm and Run Anyway"
  // button below the checklist already communicate domain/confidence blocks to the user.
  // Adding it here would duplicate the same reason text twice on screen.

  const hasHardBlocker = items.some((item) => item.status === "missing");

  return {
    items,
    canRun: !hasHardBlocker,
    overrideAllowed: !!options.allowLowConfidenceOverride,
  };
}
