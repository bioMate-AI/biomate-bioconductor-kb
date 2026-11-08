export type PrereqStatus = "ok" | "missing" | "warning";

export interface PrereqItem {
  id: "input_data" | "required_parameters";
  label: string;
  status: PrereqStatus;
  reason?: string;
  actionHint?: string;
  /** Pre-fills the chat input when user clicks "Continue in chat →" */
  chatPrompt?: string;
}

export interface PrereqChecklist {
  items: PrereqItem[];
  canRun: boolean;
  overrideAllowed: boolean;
}

interface NormalizeOptions {
  executionBlockedReason?: string;
  allowLowConfidenceOverride?: boolean;
  /** Non-empty inline params (e.g. SMILES, sequences) that count as input data */
  hasInlineData?: boolean;
}

/**
 * Return true only for values that can genuinely satisfy a workflow input.
 * Configuration such as ``threads=4`` must not make an input-less workflow
 * look executable, while inline SMILES, sequences, matrices and selected files
 * must be treated consistently by chat, the workflow card, and execution.
 */
export function hasInlineInputData(workflow: any): boolean {
  if (!workflow || typeof workflow !== "object") return false;
  const values = {
    ...(workflow.parameters && typeof workflow.parameters === "object" ? workflow.parameters : {}),
    ...(workflow.inline_parameters && typeof workflow.inline_parameters === "object" ? workflow.inline_parameters : {}),
  } as Record<string, unknown>;
  const schema = [
    ...(Array.isArray(workflow.required_params) ? workflow.required_params : []),
    ...(Array.isArray(workflow.optional_params) ? workflow.optional_params : []),
  ];
  const fileParams = new Set(
    schema.filter((p: any) => p?.type === "file").map((p: any) => String(p.name || p.id || "").toLowerCase())
  );
  // Match complete parameter tokens. In particular, `threads` must not match
  // the `reads` suffix and accidentally be treated as sequencing input.
  const inputName = /(?:^|_)(?:smiles(?:_list)?|sequences?|fasta|fastq|reads?|matrix|counts?|metadata|samplesheet|sample_sheet|coldata|contrasts?|design|library|ligands?|receptors?|genome|annotation|input)(?:$|_)/i;
  return Object.entries(values).some(([key, value]) => {
    if (value === null || value === undefined || value === "" || (Array.isArray(value) && value.length === 0)) return false;
    return fileParams.has(key.toLowerCase()) || inputName.test(key);
  });
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
      chatPrompt: "I need to provide the input data for this workflow. Here is the file I want to use: ",
    });
  } else if (inputMappings.length > 0) {
    items.push({
      id: "input_data",
      label: "Input data",
      status: "ok",
      reason: `${inputMappings.length} dataset mapping(s) detected.`,
    });
  } else if (options.hasInlineData) {
    items.push({
      id: "input_data",
      label: "Input data",
      status: "ok",
      reason: "Inline data provided (e.g. SMILES, sequence).",
    });
  } else if (hasValidatorPayload) {
    items.push({
      id: "input_data",
      label: "Input data",
      status: "warning",
      reason: "No input data detected yet.",
      actionHint: "Upload or select your data files.",
      chatPrompt: "I need to provide the input data for this workflow. Here is the file I want to use: ",
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
