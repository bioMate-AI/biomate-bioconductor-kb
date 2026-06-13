/**
 * schemaGroundedExtractor.ts — Stage 3 orchestrator.
 *
 * Wires together:
 *   3a. paramRules.runRulePass — rule pass (zero LLM, deterministic)
 *   3b. callLLMResolver         — LLM pass over what rules missed
 *   3c. validateAgainstSchema   — enum / required / unknown checks
 *
 * Returns a structured result the chat layer can either:
 *   - hand straight to the workflow form (high confidence path), or
 *   - turn into a ParamClarificationCard chat message (low confidence /
 *     enum violation / missing-required path).
 *
 * The LLM call is INJECTED so the extractor is unit-testable without
 * spinning up the Galaxy backend or hitting Claude live.
 */

import {
  runRulePass,
  validateAgainstSchema,
  type ValidationReport,
} from "./paramRules.js";
import {
  renderSchemaForPrompt,
  type WorkflowSchema,
} from "./paramSchema.js";

export type LlmCallFn = (prompt: string) => Promise<string>;

export type ExtractorInput = {
  schema: WorkflowSchema;
  userQuery: string;
  /** Optional pre-extracted params from upstream (e.g. legacy intent stage). */
  rawParams?: Record<string, unknown>;
  /** Keys the user manually edited; the extractor will not overwrite them. */
  userOverriddenKeys?: Set<string>;
  /** Inject the LLM call. In prod: wrap llmGenerate(). In tests: stub. */
  llmCall: LlmCallFn;
  /** Skip LLM resolver entirely (debug / cost-control flag). */
  skipLlm?: boolean;
};

export type ParamClarification =
  | {
      kind: "missing_required";
      paramName: string;
      hint?: string;
      examples?: string[];
    }
  | {
      kind: "enum_violation";
      paramName: string;
      userValue: string;
      allowed: string[];
    };

export type ExtractorResult = {
  params: Record<string, string | string[]>;
  /** Confidence in [0,1] — used to decide whether to ask the user. */
  confidence: number;
  /** "from your message" provenance per canonical key. */
  provenance: Array<{ key: string; source: string; rule: string }>;
  clarifications: ParamClarification[];
  validation: ValidationReport;
  /** Diagnostic: which stages fired. */
  stagesFired: {
    rules: boolean;
    llm: boolean;
    validation: boolean;
  };
};

const SYSTEM_PROMPT_HEAD = `You extract scientific parameters for a workflow from a user request.

You will be given:
  1. A workflow name
  2. A list of canonical parameter keys, with their allowed values where applicable
  3. The user request

Rules:
- Use ONLY the canonical key names listed. Do NOT invent keys.
- Omit any parameter the user did not mention or imply.
- If a parameter is "alias of X", store the value under X, not the alias.
- For enum-typed parameters: prefer the literal allowed value. Normalize obvious
  formatting differences (e.g. "T cells" → "T_cell" when T_cell is allowed).
  If the user clearly mentions a value that is NOT in the allowed list, still
  emit it under the canonical key (the system will flag the mismatch and ask
  the user to choose) — do NOT silently drop user-stated values.
- If the user gives a comma-separated list for a list-typed parameter, return
  a comma-separated string.
- Return ONLY a JSON object — no prose, no markdown.
`;

export async function extractParameters(
  input: ExtractorInput,
): Promise<ExtractorResult> {
  const { schema, userQuery, rawParams = {}, userOverriddenKeys, llmCall, skipLlm } = input;
  const stagesFired = { rules: false, llm: false, validation: false };

  // Stage 3a — rules.
  const rulePass = runRulePass({ schema, rawParams });
  stagesFired.rules = true;

  let params: Record<string, string | string[]> = { ...rulePass.canonicalParams };
  const provenance: ExtractorResult["provenance"] = rulePass.notes.map((n) => ({
    key: n.canonicalKey,
    source: n.source,
    rule: n.rule,
  }));

  // Compute remaining schema keys (not yet filled by rules).
  const filled = new Set(Object.keys(params));
  const stillMissing = schema.params
    .filter((p) => !filled.has(p.name))
    .map((p) => p.name);

  // Stage 3b — LLM resolver.
  // Only call if there are unresolved raw keys OR required params still missing
  // OR the user query has text content we haven't fully attributed.
  const needLlm =
    !skipLlm &&
    (Object.keys(rulePass.unresolvedRaw).length > 0 ||
      schema.params.some((p) => p.required && !filled.has(p.name)) ||
      userQuery.trim().length > 20);

  if (needLlm) {
    try {
      const schemaBlock = renderSchemaForPrompt(schema, userQuery);
      const prompt = buildResolverPrompt(
        schema.workflowName,
        schemaBlock,
        userQuery,
        params,
      );
      const text = await llmCall(prompt);
      stagesFired.llm = true;
      const llmExtracted = parseLooseJson(text);
      // Merge: LLM fills gaps; never overwrites rule-derived keys or
      // user-overridden keys.
      for (const [k, v] of Object.entries(llmExtracted)) {
        if (params[k] !== undefined) continue;
        if (userOverriddenKeys?.has(k)) continue;
        if (v === null || v === undefined || v === "") continue;
        const coerced = Array.isArray(v) ? v.map(String) : String(v);
        params[k] = coerced;
        provenance.push({ key: k, source: "llm", rule: "llm-resolver" });
      }
    } catch (e) {
      // LLM failure is non-fatal — rules + raw bag still flow through.
      console.warn(
        `[schemaGroundedExtractor] LLM resolver failed (${(e as Error).message}); continuing with rule-pass output`,
      );
    }
  }

  // Drop any user-overridden keys from output (caller merges them in instead).
  if (userOverriddenKeys) {
    for (const k of userOverriddenKeys) delete params[k];
  }

  // Stage 3c — validate.
  const validation = validateAgainstSchema(params, schema);
  stagesFired.validation = true;

  // Build clarifications.
  const clarifications: ParamClarification[] = [];
  for (const v of validation.enumViolations) {
    clarifications.push({
      kind: "enum_violation",
      paramName: v.key,
      userValue: v.value,
      allowed: v.allowed,
    });
    // Drop the violating value — user must choose via card.
    delete params[v.key];
  }
  for (const missing of validation.missingRequired) {
    const spec = schema.params.find((p) => p.name === missing);
    clarifications.push({
      kind: "missing_required",
      paramName: missing,
      hint: spec?.description,
      examples: spec?.enum,
    });
  }

  // Confidence heuristic: 1.0 baseline; -0.3 per enum violation;
  // -0.4 per missing required; -0.1 per unknown-key drop.
  let confidence = 1.0;
  confidence -= 0.3 * validation.enumViolations.length;
  confidence -= 0.4 * validation.missingRequired.length;
  confidence -= 0.1 * validation.unknownKeys.length;
  confidence = Math.max(0, Math.min(1, confidence));

  return {
    params,
    confidence,
    provenance,
    clarifications,
    validation,
    stagesFired,
  };
}

function buildResolverPrompt(
  workflowName: string,
  schemaBlock: string,
  userQuery: string,
  paramsSoFar: Record<string, string | string[]>,
): string {
  const alreadyFilled = Object.keys(paramsSoFar).length
    ? `\nAlready extracted by rules (do not re-emit these; resolve the REST only):\n${Object.entries(
        paramsSoFar,
      )
        .map(([k, v]) => `  - ${k}: ${Array.isArray(v) ? v.join(",") : v}`)
        .join("\n")}\n`
    : "";
  return `${SYSTEM_PROMPT_HEAD}
Workflow: "${workflowName}"

Canonical parameters for this workflow:
${schemaBlock}
${alreadyFilled}
User request: "${userQuery}"

JSON:`;
}

/**
 * Parse JSON with light forgiveness:
 *   - strip ``` fences
 *   - find the first {...} block
 *   - return {} on failure (never throw — LLM failure is non-fatal)
 */
function parseLooseJson(text: string): Record<string, unknown> {
  if (!text) return {};
  const stripped = text.replace(/```(?:json)?\s*/gi, "").replace(/```/g, "");
  const m = stripped.match(/\{[\s\S]*\}/);
  if (!m) return {};
  try {
    const parsed = JSON.parse(m[0]);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

/**
 * Wrap llmGenerate() (or a direct Anthropic call) into the LlmCallFn shape.
 * Caller may also pass a stub for tests.
 */
export function buildLlmGenerateAdapter(
  llmGenerate: (opts: {
    prompt: string;
    maxTokens?: number;
    temperature?: number;
    jsonMode?: boolean;
  }) => Promise<{ text: string }>,
): LlmCallFn {
  return async (prompt: string) => {
    const { text } = await llmGenerate({
      prompt,
      maxTokens: 800,
      temperature: 0.1,
      jsonMode: true,
    });
    return text;
  };
}
