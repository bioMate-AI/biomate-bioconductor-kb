/**
 * Carries the per-request Chinese-LLM region policy (llm-region-policy.ts) to the Galaxy backend, so
 * Galaxy's own LLM calls for a China user also run on a Chinese model
 * (backend/lib/galaxy/ai/llm_region.py; docs/20261112_CN_LLM_REGION_POLICY.md).
 *
 * Every request Node sends to Galaxy on behalf of a user carries
 *   X-BioMate-LLM-Policy: region=cn; model=<the resolved Chinese model>   (China user)
 *   X-BioMate-LLM-Policy: region=intl                                     (everyone else)
 * The user's own OpenRouter key is never sent: Galaxy uses the deployment's Chinese-model
 * credential.
 *
 * Where it is set — the two ways Node reaches Galaxy:
 *  - fetch(): `installGalaxyFetchPolicy()` wraps the global fetch once, adding the header to any
 *    request whose origin is Galaxy's (GALAXY_URL). This covers fetchGalaxyAsUser /
 *    backendPassthrough and the ~120 direct `fetch(`${GALAXY_URL}/…`)` calls in routes.ts,
 *    galaxy-assistant.ts and the services, including ones added later.
 *  - axios: GalaxyAPIProxy's client adds it in a request interceptor (`galaxyPolicyHeaders`).
 *
 * Trust: the header can only RESTRICT a request to Chinese models (Galaxy's default with no
 * header is its ordinary chain, the same as region=intl), so a forged header can never lift the
 * restriction. Node still strips any inbound copy from browser requests
 * (`stripInboundLlmPolicyHeader`) so a raw proxy cannot relay a forged one, and its own value
 * always overrides.
 */
import { currentLlmPolicy, type LlmPolicyState } from './llm-region-policy';

export const LLM_POLICY_HEADER = 'X-BioMate-LLM-Policy';

/** The header value for a policy state; null outside any request (boot, timers with no request). */
export function llmPolicyHeaderValue(state: LlmPolicyState | undefined = currentLlmPolicy()): string | null {
  if (!state) return null;
  if (state.region !== 'cn') return 'region=intl';
  const model = state.cnRoute?.model;
  return model ? `region=cn; model=${model}` : 'region=cn';
}

/** Headers to add to a Galaxy request (empty outside any request). */
export function galaxyPolicyHeaders(state?: LlmPolicyState): Record<string, string> {
  const v = llmPolicyHeaderValue(state ?? currentLlmPolicy());
  return v ? { [LLM_POLICY_HEADER]: v } : {};
}

function galaxyOrigins(env: NodeJS.ProcessEnv = process.env): Set<string> {
  const out = new Set<string>();
  for (const raw of [env.GALAXY_URL, env.GALAXY_INTERNAL_URL, 'http://localhost:8081']) {
    if (!raw) continue;
    try { out.add(new URL(raw).origin); } catch { /* not a URL */ }
  }
  return out;
}

export function isGalaxyUrl(url: string, origins: Set<string> = galaxyOrigins()): boolean {
  try { return origins.has(new URL(url).origin); } catch { return false; }
}

const INSTALLED = Symbol.for('biomate.galaxyFetchPolicy');

/** Wrap the global fetch once so every request to Galaxy carries the policy header. */
export function installGalaxyFetchPolicy(): void {
  const g = globalThis as any;
  if (g.fetch?.[INSTALLED]) return;
  const original: typeof fetch = g.fetch.bind(globalThis);
  const wrapped = (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : (input as Request).url;
    const value = isGalaxyUrl(url) ? llmPolicyHeaderValue() : null;
    if (!value) return original(input, init);
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    headers.set(LLM_POLICY_HEADER, value);
    return original(input, { ...init, headers });
  };
  (wrapped as any)[INSTALLED] = true;
  g.fetch = wrapped;
}

/** Express middleware: drop any X-BioMate-LLM-Policy a browser sent (only Node sets it). */
export function stripInboundLlmPolicyHeader(req: any, _res: any, next: () => void): void {
  delete req.headers?.[LLM_POLICY_HEADER.toLowerCase()];
  next();
}
