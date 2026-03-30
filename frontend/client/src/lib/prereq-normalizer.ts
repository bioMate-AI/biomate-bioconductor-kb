export type PrereqStatus = "ok" | "missing" | "warning" | "blocked";

export interface PrereqItem {
  id: "input_data" | "required_parameters" | "tool_runtime" | "confidence_gate";
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
  toolInstallationSuccess?: boolean;
  allowLowConfidenceOverride?: boolean;
  allowPrereqRecovery?: boolean;
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
  const hasConfidenceBlock = !!options.executionBlockedReason;
  const allowPrereqRecovery = options.allowPrereqRecovery === true;

  if (!hasValidatorPayload && !hasConfidenceBlock) {
    // When recovery mode is active, return a minimal approval even without validator data.
    // The recovery message carries forward a workflow but no prerequisitesValidation —
    // we still want overrideAllowed=true so the Run button is unblocked.
    if (allowPrereqRecovery) {
      return { items: [], canRun: true, overrideAllowed: true };
    }
    return undefined;
  }

  const items: PrereqItem[] = [];

  if (missingInputs.length > 0) {
    items.push({
      id: "input_data",
      label: "Input data",
      status: "warning",
      reason: allowPrereqRecovery
        ? `${missingInputs.length} input(s) are missing, but recovery mode can proceed with demo/sample data.`
        : `${missingInputs.length} required input(s) are missing.`,
      actionHint: allowPrereqRecovery
        ? "Proceed to run demo/sample workflow path, or upload your own datasets for production execution."
        : "Upload/select compatible datasets before running.",
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
      reason: "No explicit input mappings detected yet.",
      actionHint: "Confirm dataset assignments before execution.",
    });
  }

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
      // When recovery mode is active, downgrade from hard "missing" to "warning"
      // so the Run button is not permanently blocked — user approved demo/sample path.
      status: allowPrereqRecovery ? "warning" : "missing",
      reason: allowPrereqRecovery
        ? `${requiredMissingWithoutDefaults.length} required parameter(s) missing, but recovery mode approved (using demo/sample data).`
        : `${requiredMissingWithoutDefaults.length} required parameter(s) are missing and have no defaults.`,
      actionHint: allowPrereqRecovery
        ? "Parameters will use demo values for this run. Fill them in for production execution."
        : "Set required parameters before execution.",
    });
  } else if (requiredMissingWithDefaults.length > 0 || optionalOrSuggestedParams.length > 0) {
    const defaultCount = requiredMissingWithDefaults.length;
    const optionalCount = optionalOrSuggestedParams.length;
    items.push({
      id: "required_parameters",
      label: "Required parameters",
      status: "warning",
      reason:
        `No hard parameter blocker. ` +
        `${defaultCount > 0 ? `${defaultCount} required parameter(s) can use defaults. ` : ""}` +
        `${optionalCount > 0 ? `${optionalCount} optional/suggested parameter(s) may improve results.` : ""}`.trim(),
      actionHint: "Review parameters for quality, but execution can proceed.",
    });
  } else if (hasValidatorPayload) {
    items.push({
      id: "required_parameters",
      label: "Required parameters",
      status: "ok",
      reason: "Required parameters are satisfied (provided or defaulted).",
    });
  }

  if (options.toolInstallationSuccess === false) {
    items.push({
      id: "tool_runtime",
      label: "Tool/runtime readiness",
      status: "missing",
      reason: "Required tools are not installed or runtime is not ready.",
      actionHint: "Install missing tools or wait for environment setup.",
    });
  } else if (options.toolInstallationSuccess === true) {
    items.push({
      id: "tool_runtime",
      label: "Tool/runtime readiness",
      status: "ok",
      reason: "Tool installation and runtime checks passed.",
    });
  }

  if (hasConfidenceBlock) {
    items.push({
      id: "confidence_gate",
      label: "Scientific confidence gate",
      status: "blocked",
      reason: options.executionBlockedReason,
      actionHint: options.allowLowConfidenceOverride
        ? "Use Confirm and Run Anyway to continue with explicit override."
        : "Regenerate workflow or refine request before execution.",
    });
  }

  const hasHardBlocker = items.some((item) => item.status === "missing" || item.status === "blocked");

  return {
    items,
    canRun: !hasHardBlocker,
    // overrideAllowed lets the viewer skip hasUnfilledRequired when recovery mode is active
    overrideAllowed: !!options.allowLowConfidenceOverride || allowPrereqRecovery,
  };
}
