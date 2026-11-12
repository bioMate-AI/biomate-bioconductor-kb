// @vitest-environment node
/**
 * The Chinese model SET (llm-region-policy.ts CN_MODEL_SET): China-region users run each role on its
 * own Chinese model, like the English hybrid — intent GLM 5.2, reply + tool loop + images DeepSeek
 * V4.1 Flash, hard reasoning DeepSeek V4 Pro, light work Qwen 3.5 Flash, and the backend chain
 * DeepSeek V4.1 Flash → GLM 5.2 → Qwen 3.5 Plus. Each role is env-overridable, but only by a Chinese
 * model; a user's Chinese pick replaces the response role only.
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  CN_MODEL_SET, CN_ROLE_ENV, OPENROUTER_URL, cnModelSet, resolveCnRoute, cnRoleForMessagesCall,
  cnRoleMessagesClient, cnChainCompletion, policySummary, classifyRegion,
} from './llm-region-policy';

const noEnv = {} as NodeJS.ProcessEnv;
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe('the default set', () => {
  it('is the approved per-role table', () => {
    expect(CN_MODEL_SET).toEqual({
      intent: 'z-ai/glm-5.2',
      response: 'deepseek/deepseek-v4.1-flash',
      reasoning: 'deepseek/deepseek-v4-pro',
      light: 'qwen/qwen3.5-flash-02-23',
      vision: 'deepseek/deepseek-v4.1-flash',
      galaxyChain: ['deepseek/deepseek-v4.1-flash', 'z-ai/glm-5.2', 'qwen/qwen3.5-plus-20260420'],
    });
  });
  it('a China user\'s route carries every role from the set', () => {
    const r = resolveCnRoute({}, { OPENROUTER_ZH_API_KEY: 'zh' } as any)!;
    expect(r.model).toBe(CN_MODEL_SET.response);
    expect(r.models).toEqual({ ...CN_MODEL_SET, galaxyChain: [...CN_MODEL_SET.galaxyChain] });
  });
});

describe('env overrides', () => {
  it('each role has its own env var', () => {
    const env = {
      [CN_ROLE_ENV.intent]: 'qwen/qwen3.5-plus-20260420', [CN_ROLE_ENV.response]: 'moonshotai/kimi-k3',
      [CN_ROLE_ENV.reasoning]: 'moonshotai/kimi-k3.1-pro', [CN_ROLE_ENV.light]: 'deepseek/deepseek-v4-flash',
      [CN_ROLE_ENV.vision]: 'qwen/qwen3-vl-235b-a22b-instruct', [CN_ROLE_ENV.galaxyChain]: ' z-ai/glm-5.2 , deepseek/deepseek-v4-pro ',
    } as any;
    expect(cnModelSet(env)).toEqual({
      intent: 'qwen/qwen3.5-plus-20260420', response: 'moonshotai/kimi-k3', reasoning: 'moonshotai/kimi-k3.1-pro',
      light: 'deepseek/deepseek-v4-flash', vision: 'qwen/qwen3-vl-235b-a22b-instruct', galaxyChain: ['z-ai/glm-5.2', 'deepseek/deepseek-v4-pro'],
    });
  });
  it('a non-Chinese override is rejected with a warning; the role keeps its default', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const set = cnModelSet({ [CN_ROLE_ENV.light]: 'anthropic/claude-haiku-4.5', [CN_ROLE_ENV.galaxyChain]: 'google/gemini-3.8-flash,z-ai/glm-5.2' } as any);
    expect(set.light).toBe(CN_MODEL_SET.light);
    expect(set.galaxyChain).toEqual(['z-ai/glm-5.2']);
    expect(warn).toHaveBeenCalled();
    // A chain of only non-Chinese models falls back to the default chain, never an empty or foreign one.
    expect(cnModelSet({ [CN_ROLE_ENV.galaxyChain]: 'openai/gpt-6' } as any).galaxyChain).toEqual([...CN_MODEL_SET.galaxyChain]);
  });
  it('OPENROUTER_ZH_DEFAULT_MODEL still sets the response role; BIOMATE_CN_RESPONSE_MODEL wins over it', () => {
    expect(cnModelSet({ OPENROUTER_ZH_DEFAULT_MODEL: 'moonshotai/kimi-k3' } as any).response).toBe('moonshotai/kimi-k3');
    expect(cnModelSet({ OPENROUTER_ZH_DEFAULT_MODEL: 'moonshotai/kimi-k3', [CN_ROLE_ENV.response]: 'z-ai/glm-5.2' } as any).response).toBe('z-ai/glm-5.2');
  });
});

describe('the user\'s pick', () => {
  it('a Chinese pick replaces the response role only', () => {
    const r = resolveCnRoute({ userOpenrouterKey: 'sk-or', selectedModel: 'moonshotai/kimi-k3' }, noEnv)!;
    expect(r.model).toBe('moonshotai/kimi-k3');
    expect(r.models).toMatchObject({ response: 'moonshotai/kimi-k3', intent: CN_MODEL_SET.intent, reasoning: CN_MODEL_SET.reasoning,
      light: CN_MODEL_SET.light, vision: CN_MODEL_SET.vision, galaxyChain: [...CN_MODEL_SET.galaxyChain] });
  });
  it('a non-Chinese pick changes nothing', () => {
    expect(resolveCnRoute({ userOpenrouterKey: 'sk-or', selectedModel: 'anthropic/claude-opus-5.5' }, noEnv)!.models.response).toBe(CN_MODEL_SET.response);
  });
});

describe('role of an Anthropic-SDK call (the English code already picks a model per role)', () => {
  it('Haiku-class → light; Pro / Opus / thinking → reasoning; images → vision; otherwise the response model', () => {
    expect(cnRoleForMessagesCall({ model: 'claude-haiku-4-5', messages: [] })).toBe('light');
    expect(cnRoleForMessagesCall({ model: 'gpt-4o-mini', messages: [] })).toBe('light');
    expect(cnRoleForMessagesCall({ model: 'claude-opus-4-6', messages: [] })).toBe('reasoning');
    expect(cnRoleForMessagesCall({ model: 'gemini-3.1-pro-preview', messages: [] })).toBe('reasoning');
    expect(cnRoleForMessagesCall({ model: 'claude-sonnet-4-5', thinking: { type: 'enabled', budget_tokens: 2000 }, messages: [] })).toBe('reasoning');
    expect(cnRoleForMessagesCall({ model: 'gpt-5.6-luna', messages: [] })).toBe('response');
    expect(cnRoleForMessagesCall({ model: 'gemini-3.8-flash', messages: [] })).toBe('response');
    expect(cnRoleForMessagesCall({ model: 'claude-haiku-4-5', messages: [{ role: 'user', content: [{ type: 'image', source: {} }] }] })).toBe('vision');
  });
  it('the role-aware client sends each call to its role\'s model', async () => {
    const sent: string[] = [];
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: any) => {
      sent.push(JSON.parse(init.body).model);
      return new Response(JSON.stringify({ id: 'x', choices: [{ finish_reason: 'stop', message: { content: 'ok' } }], usage: {} }));
    }));
    const route = resolveCnRoute({}, { OPENROUTER_ZH_API_KEY: 'zh' } as any)!;
    const client = cnRoleMessagesClient(route);
    await client.messages.create({ model: 'claude-haiku-4-5', max_tokens: 50, messages: [{ role: 'user', content: 'summarise' }] });
    await client.messages.create({ model: 'gpt-5.6-luna', max_tokens: 50, messages: [{ role: 'user', content: 'answer' }] });
    await client.messages.create({ model: 'claude-opus-4-6', max_tokens: 50, messages: [{ role: 'user', content: 'think' }] });
    expect(sent).toEqual([CN_MODEL_SET.light, CN_MODEL_SET.response, CN_MODEL_SET.reasoning]);
  });
});

describe('the backend chain', () => {
  const route = () => resolveCnRoute({}, { OPENROUTER_ZH_API_KEY: 'zh' } as any)!;
  it('falls through to the next Chinese model when one fails, and never leaves the chain', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const tried: string[] = [];
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: any) => {
      const model = JSON.parse(init.body).model;
      tried.push(model);
      if (model === 'deepseek/deepseek-v4.1-flash') return new Response('upstream down', { status: 502 });
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: '回答' } }] }));
    }));
    const r = await cnChainCompletion(route(), { messages: [{ role: 'user', content: 'p' }] });
    expect(r).toEqual({ text: '回答', model: 'z-ai/glm-5.2' });
    expect(tried).toEqual(['deepseek/deepseek-v4.1-flash', 'z-ai/glm-5.2']);
  });
  it('throws when every model in the chain fails (fail closed, no foreign fallback)', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const tried: string[] = [];
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: any) => {
      tried.push(JSON.parse(init.body).model);
      return new Response('down', { status: 503 });
    }));
    await expect(cnChainCompletion(route(), { messages: [{ role: 'user', content: 'p' }] })).rejects.toThrow();
    expect(tried).toEqual([...CN_MODEL_SET.galaxyChain]);
  });
});

describe('policy summary', () => {
  it('shows a China user the set', () => {
    const s = policySummary(classifyRegion({ uiLanguage: 'zh' }), { OPENROUTER_ZH_API_KEY: 'zh' } as any);
    expect(s.defaultModel).toBe(CN_MODEL_SET.response);
    expect(s.modelSet).toEqual({ ...CN_MODEL_SET, galaxyChain: [...CN_MODEL_SET.galaxyChain] });
    expect(policySummary(classifyRegion({ acceptLanguage: 'en-US' }), noEnv).modelSet).toBeNull();
  });
});
