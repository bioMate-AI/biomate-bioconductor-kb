import { localOnly, localCompletion } from './local-llm.js';
import { requireCnRoute, cnChainCompletion } from './llm-region-policy';
/**
 * llmGenerate — the ONLY way the frontend should call an LLM.
 *
 * Routes to the backend's `/internal/llm/generate` endpoint which uses the
 * YAML-defined fallback chain in `backend/config/llm_providers.yml`:
 *   1. gemini-3.1-pro-preview (primary)
 *   2. gemini-3.8-flash-preview
 *   3. claude-sonnet-4-5
 *   4. gpt-4o
 *   5. ollama qwen3:32b
 *
 * No model strings should appear in TypeScript anywhere — changing the
 * fallback order is a YAML edit, deploy of one Python file, done.
 *
 * Replaces 9 `new Anthropic()` direct instantiations across frontend/server/
 * that bypassed the chain entirely. See
 * docs/20260607_LLM_ROUTING_CONSOLIDATION_PLAN.md.
 */

export interface LlmGenerateOptions {
  prompt: string;
  system?: string;
  /** Default 4096 — high enough to avoid truncation for typical workloads. */
  maxTokens?: number;
  /** Default 0.7. */
  temperature?: number;
  /** Hint to the provider to return JSON; honored by Gemini, ignored otherwise. */
  jsonMode?: boolean;
  /**
   * Optional per-task tag forwarded to the backend chokepoint. When the on-prem
   * SFT-gold adapter is enabled (flag default OFF) and this task is allowlisted
   * (findings / decomposition), the backend routes the call to the adapter and
   * falls back to the cloud chain on any error. Omit it for normal routing.
   */
  task?: string;
}

export interface LlmGenerateResult {
  text: string;
  /** Which provider+model actually answered (for observability/billing). */
  modelUsed: string;
  /** 0 = primary, 1 = first fallback, ... */
  fallbackDepth: number;
}

function backendUrl(): string {
  // Inside the dev EC2: GALAXY_URL=http://biomate-galaxy-dev:8080
  // Locally:           http://localhost:8081
  return process.env.GALAXY_URL || "http://localhost:8081";
}

function internalKey(): string {
  const k = process.env.BILLING_INTERNAL_KEY || "";
  if (!k) {
    // Don't throw on import — many code paths import this module without
    // ever calling it. Log loudly the first time it's actually needed.
    console.warn(
      "[llm-client] BILLING_INTERNAL_KEY is unset; backend will return 401",
    );
  }
  return k;
}

export async function llmGenerate(
  opts: LlmGenerateOptions,
): Promise<LlmGenerateResult> {
  if (typeof opts.prompt !== "string" || !opts.prompt.trim()) {
    throw new Error("llmGenerate: prompt is required (non-empty string)");
  }
  if (localOnly()) {
    const result = await localCompletion({
      messages: [...(opts.system ? [{ role: 'system', content: opts.system }] : []),
        { role: 'user', content: opts.prompt }],
      max_tokens: opts.maxTokens ?? 4096, temperature: opts.temperature ?? 0,
      ...(opts.jsonMode ? { response_format: { type: 'json_object' } } : {}),
    });
    const choice = result.choices[0];
    if (choice.finish_reason !== 'stop' || typeof choice.message.content !== 'string') {
      throw new Error('Local generation did not produce a complete text answer');
    }
    return { text: choice.message.content, modelUsed: result.model || process.env.BIOMATE_LOCAL_LLM_MODEL!, fallbackDepth: 0 };
  }
  // China-region users: the Chinese model, not the backend's Gemini/Claude/GPT chain (llm-region-policy.ts).
  // The backend chain's Chinese replacement: the set's chain, first model that answers.
  const cnRoute = requireCnRoute();
  if (cnRoute) {
    const { text, model } = await cnChainCompletion(cnRoute, {
      messages: [{ role: 'user', content: opts.prompt }], system: opts.system,
      maxTokens: opts.maxTokens ?? 4096, temperature: opts.temperature ?? 0.7, jsonMode: opts.jsonMode,
    });
    return { text, modelUsed: model, fallbackDepth: Math.max(0, cnRoute.models.galaxyChain.indexOf(model)) };
  }
  const body = {
    prompt: opts.prompt,
    ...(opts.system ? { system: opts.system } : {}),
    max_tokens: opts.maxTokens ?? 4096,
    temperature: opts.temperature ?? 0.7,
    ...(opts.jsonMode ? { json_mode: true } : {}),
    ...(opts.task ? { task: opts.task } : {}),
  };
  const url = `${backendUrl()}/internal/llm/generate`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Internal-Key": internalKey(),
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const detail = await resp.text().catch(() => "");
    throw new Error(
      `llmGenerate failed: HTTP ${resp.status} ${detail.slice(0, 200)}`,
    );
  }
  const payload = (await resp.json()) as {
    text?: string;
    model_used?: string;
    fallback_depth?: number;
  };
  if (typeof payload.text !== "string") {
    throw new Error("llmGenerate: response missing `text` field");
  }
  return {
    text: payload.text,
    modelUsed: payload.model_used ?? "unknown",
    fallbackDepth: payload.fallback_depth ?? 0,
  };
}
