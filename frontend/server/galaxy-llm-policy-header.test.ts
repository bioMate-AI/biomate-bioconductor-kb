/**
 * The Chinese-LLM region policy reaches Galaxy: every Node → Galaxy request made while serving a
 * user carries X-BioMate-LLM-Policy (region=cn; model=<Chinese model> for a China user, region=intl
 * otherwise), through both ways Node reaches Galaxy (fetch, and GalaxyAPIProxy's axios client).
 * A browser-sent copy of the header is never relayed, and the user's own key is never sent.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { llmPolicyStorage, type LlmPolicyState } from './llm-region-policy';
import {
  LLM_POLICY_HEADER, llmPolicyHeaderValue, installGalaxyFetchPolicy, stripInboundLlmPolicyHeader,
} from './galaxy-llm-policy-header';

const CN: LlmPolicyState = {
  region: 'cn', reasons: ['ip'],
  cnRoute: { url: 'https://openrouter.ai/api/v1', key: 'sk-user-own-key', model: 'moonshotai/kimi-k3', source: 'user_openrouter' },
};
const INTL: LlmPolicyState = { region: 'intl', reasons: [], cnRoute: null };

describe('llmPolicyHeaderValue', () => {
  it('names the resolved Chinese model for a China user, never the key', () => {
    expect(llmPolicyHeaderValue(CN)).toBe('region=cn; model=moonshotai/kimi-k3');
    expect(llmPolicyHeaderValue(CN)).not.toContain('sk-user');
    expect(llmPolicyHeaderValue({ ...CN, cnRoute: null })).toBe('region=cn');
    expect(llmPolicyHeaderValue(INTL)).toBe('region=intl');
    expect(llmPolicyHeaderValue(undefined)).toBeNull();
  });
});

describe('fetch to Galaxy carries the policy', () => {
  const seen: Array<{ url: string; header: string | null; auth: string | null }> = [];
  let realFetch: typeof fetch;
  beforeEach(() => {
    seen.length = 0;
    realFetch = globalThis.fetch;
    process.env.GALAXY_URL = 'http://galaxy.internal:8081';
    globalThis.fetch = (async (input: any, init?: RequestInit) => {
      const h = new Headers(init?.headers);
      seen.push({ url: String(input), header: h.get(LLM_POLICY_HEADER), auth: h.get('X-API-Key') });
      return new Response('{}', { status: 200 });
    }) as typeof fetch;
    installGalaxyFetchPolicy();
  });
  afterEach(() => { globalThis.fetch = realFetch; delete process.env.GALAXY_URL; });

  it('adds the header to Galaxy requests only, keeping the caller headers', async () => {
    await llmPolicyStorage.run(CN, async () => {
      await fetch('http://galaxy.internal:8081/api/ai_assistant/research_query', { method: 'POST', headers: { 'X-API-Key': 'gk' } });
      await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST' });
    });
    await llmPolicyStorage.run(INTL, () => fetch('http://galaxy.internal:8081/api/nextflow/analyze-outputs'));
    await fetch('http://galaxy.internal:8081/api/version'); // no request in scope (boot / timer)
    expect(seen).toEqual([
      { url: 'http://galaxy.internal:8081/api/ai_assistant/research_query', header: 'region=cn; model=moonshotai/kimi-k3', auth: 'gk' },
      { url: 'https://openrouter.ai/api/v1/chat/completions', header: null, auth: null },
      { url: 'http://galaxy.internal:8081/api/nextflow/analyze-outputs', header: 'region=intl', auth: null },
      { url: 'http://galaxy.internal:8081/api/version', header: null, auth: null },
    ]);
  });

  it('overrides a forged header passed through to Galaxy', async () => {
    await llmPolicyStorage.run(CN, () =>
      fetch('http://galaxy.internal:8081/api/x', { headers: { [LLM_POLICY_HEADER]: 'region=intl' } }));
    expect(seen[0].header).toBe('region=cn; model=moonshotai/kimi-k3');
  });
});

describe('inbound browser header is stripped', () => {
  it('removes X-BioMate-LLM-Policy from the incoming request', () => {
    const req: any = { headers: { 'x-biomate-llm-policy': 'region=intl', accept: '*/*' } };
    const next = vi.fn();
    stripInboundLlmPolicyHeader(req, {}, next);
    expect(req.headers).toEqual({ accept: '*/*' });
    expect(next).toHaveBeenCalled();
  });
});

describe('GalaxyAPIProxy (axios) carries the policy', () => {
  it('sets the header on its requests', async () => {
    const { GalaxyAPIProxy } = await import('./galaxy-api-proxy');
    const proxy = new GalaxyAPIProxy('http://galaxy.internal:8081', 'gk');
    const captured: any[] = [];
    proxy.client.defaults.adapter = async (config: any) => {
      captured.push(config.headers?.[LLM_POLICY_HEADER] ?? config.headers?.get?.(LLM_POLICY_HEADER));
      return { data: {}, status: 200, statusText: 'OK', headers: {}, config };
    };
    await llmPolicyStorage.run(CN, () => proxy.client.post('/api/ai_assistant/search_nextflow_workflow', {}));
    await llmPolicyStorage.run(INTL, () => proxy.client.get('/api/version'));
    expect(captured).toEqual(['region=cn; model=moonshotai/kimi-k3', 'region=intl']);
  });
});
