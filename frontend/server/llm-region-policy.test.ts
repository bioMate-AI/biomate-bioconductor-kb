// @vitest-environment node
/**
 * Chinese-LLM region policy (llm-region-policy.ts, docs/20261112_CN_LLM_REGION_POLICY.md).
 * Dev 2026-11-12: a user asked "which llm are you using" and BioMate answered "I'm Claude… made by
 * Anthropic" — the model guessed (intent ran on GLM, the reply on Gemini); and Chinese-language
 * users were not reliably routed to a Chinese model (the UI language overrode the browser, the IP
 * was never consulted, a stored Anthropic key or non-Chinese pick always won).
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  CN_REGION_COUNTRIES, CHINESE_MODEL_VENDORS, classifyRegion, isCnRegionIp, isChineseModel, modelIdentity,
  modelIdentityDirective, resolveCnRoute, CN_MODEL_SET, CN_ROLE_ENV, cnModelSet, cnRoleForMessagesCall, cnChainCompletion, cnRoleMessagesClient, resolveChatLlm, requireCnRoute, llmPolicyStorage, policyStateFor,
  policyMessagesClient, policySummary, checkModelPick, ChineseModelUnavailableError, OPENROUTER_URL,
} from './llm-region-policy';
import { CHINESE_MODEL_VENDORS as CLIENT_VENDORS } from '../client/src/lib/llm-region';

const US_IP = '104.63.31.236';
const HK_IP = '47.242.215.11';      // Alibaba Cloud Hong Kong (seen on dev); an ARIN-registered block
const CN_IP = '114.114.114.114';    // 114DNS, Nanjing
const MO_IP = '202.175.3.3';        // CTM, Macau
const TW_IP = '61.219.11.1';        // HiNet, Taiwan
const JP_IP = '133.11.0.1';         // University of Tokyo
const SG_IP = '165.21.0.1';         // SingNet, Singapore

const noEnv = {} as NodeJS.ProcessEnv;

afterEach(() => { vi.unstubAllGlobals(); });

describe('region = ANY signal (OR, not precedence)', () => {
  it('Chinese UI/settings language alone', () => {
    expect(classifyRegion({ uiLanguage: 'zh', acceptLanguage: 'en-US', ip: US_IP })).toEqual({ region: 'cn', reasons: ['ui_language'] });
  });
  it('Chinese primary browser language alone — even with an English UI', () => {
    expect(classifyRegion({ uiLanguage: 'en', acceptLanguage: 'zh-CN,zh;q=0.9', ip: US_IP }).region).toBe('cn');
    for (const al of ['zh', 'zh-TW', 'zh-HK,en;q=0.5', 'ZH-cn']) expect(classifyRegion({ acceptLanguage: al }).region).toBe('cn');
    expect(classifyRegion({ acceptLanguage: 'en-US,zh-CN;q=0.8' }).region).toBe('intl'); // zh only as a fallback
  });
  it('an IP in mainland China, Hong Kong, Macau or Taiwan alone — even with English UI and browser', () => {
    for (const ip of [CN_IP, HK_IP, MO_IP, TW_IP]) {
      expect(classifyRegion({ uiLanguage: 'en', acceptLanguage: 'en-US', ip }), ip).toEqual({ region: 'cn', reasons: ['ip'] });
    }
  });
  it('a CDN country header for the same four codes', () => {
    for (const cc of CN_REGION_COUNTRIES) expect(classifyRegion({ acceptLanguage: 'en', countryHeader: cc.toLowerCase() }).region).toBe('cn');
    expect(classifyRegion({ acceptLanguage: 'en', countryHeader: 'JP' }).region).toBe('intl');
  });
  it('US, Japan and Singapore with English signals are not China users', () => {
    for (const ip of [US_IP, JP_IP, SG_IP, '8.8.8.8']) expect(classifyRegion({ uiLanguage: 'en', acceptLanguage: 'en-US', ip }).region, ip).toBe('intl');
    expect(classifyRegion({}).region).toBe('intl');
  });
  it('IPv6 and IPv4-mapped IPv6', () => {
    expect(isCnRegionIp('240e::1')).toBe(true);                 // China Telecom 240e::/20
    expect(isCnRegionIp(`::ffff:${HK_IP}`)).toBe(true);
    expect(isCnRegionIp('2001:4860:4860::8888')).toBe(false);   // Google
    expect(isCnRegionIp('not-an-ip')).toBe(false);
  });
});

describe('Chinese models', () => {
  it('by vendor allow-list (and bare on-prem names)', () => {
    for (const m of ['deepseek/deepseek-v4.1-flash', 'z-ai/glm-5.3-prime', 'qwen/qwen3-235b-a22b-2507', 'moonshotai/kimi-k3', 'qwen-max', 'glm-4'])
      expect(isChineseModel(m), m).toBe(true);
    for (const m of ['anthropic/claude-sonnet-5.5', 'openai/gpt-6.1-sol-pro', 'google/gemini-3.1-pro-preview', 'meta-llama/llama-4-maverick', 'gemini-3.8-flash', 'claude-sonnet-4-5', ''])
      expect(isChineseModel(m), m).toBe(false);
  });
  it('the client picker uses the same vendor list', () => {
    expect([...CLIENT_VENDORS]).toEqual([...CHINESE_MODEL_VENDORS]);
  });
  it('identity names the real model and vendor', () => {
    expect(modelIdentity('z-ai/glm-5.3-prime')).toMatchObject({ displayName: 'GLM 5.3 Prime', vendor: 'Zhipu AI', vendorZh: '智谱', isChinese: true });
    expect(modelIdentity('deepseek/deepseek-v4.1-flash')).toMatchObject({ displayName: 'DeepSeek V4.1 Flash', vendor: 'DeepSeek', isChinese: true });
    expect(modelIdentity('claude-sonnet-4-5')).toMatchObject({ displayName: 'Claude Sonnet 4.5', vendor: 'Anthropic', isChinese: false });
    expect(modelIdentity('gemini-3.8-flash')).toMatchObject({ displayName: 'Gemini 3.8 Flash', vendor: 'Google' });
  });
  it('the identity block forbids claiming another model; for China users it says 国产大模型', () => {
    const cn = modelIdentityDirective(modelIdentity('deepseek/deepseek-v4.1-flash'), 'cn');
    expect(cn).toContain('MODEL IDENTITY');
    expect(cn).toContain('DeepSeek V4.1 Flash');
    expect(cn).toContain('国产大模型');
    expect(cn).toMatch(/Never claim to be Claude, GPT, Gemini/);
    const intl = modelIdentityDirective(modelIdentity('gemini-3.8-flash'), 'intl');
    expect(intl).toContain('Gemini 3.8 Flash');
    expect(intl).not.toContain('China-region');
  });
});

describe('China users: Chinese model only, fail closed', () => {
  it('a non-Chinese pick is replaced by the Chinese default; a Chinese pick is honoured', () => {
    expect(resolveCnRoute({ userOpenrouterKey: 'sk-or-user', selectedModel: 'anthropic/claude-sonnet-5.5' }, noEnv))
      .toMatchObject({ url: OPENROUTER_URL, key: 'sk-or-user', model: 'deepseek/deepseek-v4.1-flash', source: 'user_openrouter' });
    expect(resolveCnRoute({ userOpenrouterKey: 'sk-or-user', selectedModel: 'moonshotai/kimi-k3' }, noEnv)!.model).toBe('moonshotai/kimi-k3');
  });
  it('credential order: own OpenRouter key → OPENROUTER_ZH_API_KEY → OPENROUTER_API_KEY → on-prem Chinese LLM', () => {
    expect(resolveCnRoute({}, { OPENROUTER_ZH_API_KEY: 'zh', OPENROUTER_API_KEY: 'sys' } as any)!.source).toBe('openrouter_zh_key');
    expect(resolveCnRoute({}, { OPENROUTER_API_KEY: 'sys' } as any)!.source).toBe('openrouter_system_key');
    expect(resolveCnRoute({}, { LLM_API_URL: 'http://dashscope/v1', LLM_MODEL: 'qwen-max' } as any))
      .toMatchObject({ url: 'http://dashscope/v1', key: 'none', model: 'qwen-max', source: 'onprem',
        models: { intent: 'qwen-max', response: 'qwen-max', reasoning: 'qwen-max', light: 'qwen-max', vision: 'qwen-max', galaxyChain: ['qwen-max'] } });
    expect(resolveCnRoute({}, { LLM_API_URL: 'http://vllm/v1', LLM_MODEL: 'llama-3' } as any)).toBeNull();
    expect(resolveCnRoute({}, noEnv)).toBeNull();
  });
  it('a non-Chinese OPENROUTER_ZH_DEFAULT_MODEL override is ignored', () => {
    const prev = process.env.OPENROUTER_ZH_DEFAULT_MODEL;
    process.env.OPENROUTER_ZH_DEFAULT_MODEL = 'anthropic/claude-opus-5.5';
    try { expect(resolveCnRoute({ userOpenrouterKey: 'k' }, noEnv)!.model).toBe('deepseek/deepseek-v4.1-flash'); }
    finally { if (prev === undefined) delete process.env.OPENROUTER_ZH_DEFAULT_MODEL; else process.env.OPENROUTER_ZH_DEFAULT_MODEL = prev; }
  });
  it('the chokepoint throws (no silent Claude/Gemini) when no Chinese model is configured', () => {
    llmPolicyStorage.run({ region: 'cn', reasons: ['ip'], cnRoute: null }, () => {
      expect(() => requireCnRoute()).toThrow(ChineseModelUnavailableError);
      expect(() => policyMessagesClient({ fallback: true })).toThrow(/国产大模型暂不可用/);
    });
    llmPolicyStorage.run({ region: 'intl', reasons: [], cnRoute: null }, () => {
      expect(requireCnRoute()).toBeNull();
      expect(policyMessagesClient({ fallback: true })).toEqual({ fallback: true });
    });
  });
});

describe('chat-stream resolution (resolveChatLlm, used by routes.ts on every request)', () => {
  const cn = classifyRegion({ acceptLanguage: 'zh-CN' });
  const us = classifyRegion({ acceptLanguage: 'en-US', ip: US_IP });
  it('China user with their own Anthropic key and a non-Chinese pick still gets a Chinese model', () => {
    const r = resolveChatLlm({ region: cn, userAnthropicKey: 'sk-ant', userOpenrouterKey: 'sk-or', selectedModel: 'anthropic/claude-opus-5.5' }, noEnv);
    expect(r.userAnthropicKey).toBeUndefined();
    expect(r.openrouterKey).toBe('sk-or');
    expect(isChineseModel(r.selectedModel)).toBe(true);
    expect(r.state.region).toBe('cn');
  });
  it('China user with only an Anthropic key: the deployment Chinese key, never Claude', () => {
    const r = resolveChatLlm({ region: cn, userAnthropicKey: 'sk-ant' }, { OPENROUTER_ZH_API_KEY: 'zh' } as any);
    expect(r.userAnthropicKey).toBeUndefined();
    expect(r.openaiBaseUrl).toBeUndefined();
    expect(r).toMatchObject({ openrouterKey: 'zh', selectedModel: 'deepseek/deepseek-v4.1-flash' });
  });
  it('China user and no Chinese credential: fail closed', () => {
    expect(() => resolveChatLlm({ region: cn, userAnthropicKey: 'sk-ant' }, noEnv)).toThrow(ChineseModelUnavailableError);
  });
  it('US user with GLM selected keeps GLM (the policy restricts only China users)', () => {
    const r = resolveChatLlm({ region: us, userOpenrouterKey: 'sk-or', selectedModel: 'z-ai/glm-5.3-prime' }, noEnv);
    expect(r).toMatchObject({ openrouterKey: 'sk-or', selectedModel: 'z-ai/glm-5.3-prime' });
    expect(r.state).toEqual({ region: 'intl', reasons: [], cnRoute: null });
  });
  it('US user keeps their Anthropic key and the deployment defaults', () => {
    expect(resolveChatLlm({ region: us, userAnthropicKey: 'sk-ant' }, noEnv)).toMatchObject({ userAnthropicKey: 'sk-ant', openrouterKey: undefined });
    expect(resolveChatLlm({ region: us }, { OPENROUTER_API_KEY: 'sys', OPENROUTER_DEFAULT_MODEL: 'z-ai/glm-5.3-prime' } as any))
      .toMatchObject({ openrouterKey: 'sys', selectedModel: 'z-ai/glm-5.3-prime' });
  });
});

describe('Chinese-model chokepoints (callGeminiFlash, llmGenerate) under a China user', () => {
  const route = { url: 'http://cn-llm.test/v1', key: 'k', model: 'deepseek/deepseek-v4.1-flash', source: 'openrouter_zh_key' as const,
    models: { ...CN_MODEL_SET, galaxyChain: [...CN_MODEL_SET.galaxyChain] } };
  const stubCompletion = () => {
    const calls: Array<{ url: string; body: any }> = [];
    vi.stubGlobal('fetch', vi.fn(async (url: string, init: any) => {
      calls.push({ url, body: JSON.parse(init.body) });
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: '国产模型回答' } }] }));
    }));
    return calls;
  };
  it('callGeminiFlash runs on the Chinese set\'s light model, never Gemini', async () => {
    const calls = stubCompletion();
    const { callGeminiFlash } = await import('./gemini-flash');
    const text = await llmPolicyStorage.run({ region: 'cn', reasons: ['ip'], cnRoute: route },
      () => callGeminiFlash({ messages: [{ role: 'user', content: 'hi' }], system: 's' }));
    expect(text).toBe('国产模型回答');
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('http://cn-llm.test/v1/chat/completions');
    expect(calls[0].body.model).toBe('qwen/qwen3.5-flash-02-23');
  });
  it('llmGenerate runs on the Chinese model, not the backend Gemini/Claude chain', async () => {
    const calls = stubCompletion();
    const { llmGenerate } = await import('./llm-client');
    const r = await llmPolicyStorage.run({ region: 'cn', reasons: ['ui_language'], cnRoute: route }, () => llmGenerate({ prompt: 'p' }));
    expect(r).toEqual({ text: '国产模型回答', modelUsed: 'deepseek/deepseek-v4.1-flash', fallbackDepth: 0 });
    expect(calls.every(c => !c.url.includes('/internal/llm/generate'))).toBe(true);
  });
});

describe('CN chain retry policy (WARN#2: a non-retryable 4xx must not walk the whole chain)', () => {
  const route = () => resolveCnRoute({}, { OPENROUTER_ZH_API_KEY: 'zh' } as any)!;
  const stubStatuses = (byModel: Record<string, number>, tried: string[]) =>
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: any) => {
      const model = JSON.parse(init.body).model;
      tried.push(model);
      const status = byModel[model] ?? 200;
      if (status !== 200) return new Response(`error body for ${model}`, { status });
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: '回答' } }] }));
    }));

  it('a 400 on the first chain model surfaces that 400 and never tries later models', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const tried: string[] = [];
    stubStatuses({ 'deepseek/deepseek-v4.1-flash': 400 }, tried);
    await expect(cnChainCompletion(route(), { messages: [{ role: 'user', content: 'p' }] }))
      .rejects.toThrow(/Inference HTTP 400/);
    expect(tried).toEqual(['deepseek/deepseek-v4.1-flash']);
  });

  it('429, 408 and 500 on the first model fall through to the next Chinese model and succeed', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    for (const status of [429, 408, 500]) {
      const tried: string[] = [];
      stubStatuses({ 'deepseek/deepseek-v4.1-flash': status }, tried);
      const r = await cnChainCompletion(route(), { messages: [{ role: 'user', content: 'p' }] });
      expect(r, String(status)).toEqual({ text: '回答', model: 'z-ai/glm-5.2' });
      expect(tried, String(status)).toEqual(['deepseek/deepseek-v4.1-flash', 'z-ai/glm-5.2']);
      vi.unstubAllGlobals();
    }
  });

  it('a network/transport error on the first model also falls through', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const tried: string[] = [];
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: any) => {
      const model = JSON.parse(init.body).model;
      tried.push(model);
      if (model === 'deepseek/deepseek-v4.1-flash') throw new TypeError('network down');
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: '回答' } }] }));
    }));
    const r = await cnChainCompletion(route(), { messages: [{ role: 'user', content: 'p' }] });
    expect(r).toEqual({ text: '回答', model: 'z-ai/glm-5.2' });
    expect(tried).toEqual(['deepseek/deepseek-v4.1-flash', 'z-ai/glm-5.2']);
  });

  it('the surfaced error reflects the FIRST non-retryable failure (not a later model)', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const tried: string[] = [];
    stubStatuses({ 'deepseek/deepseek-v4.1-flash': 403 }, tried);
    await expect(cnChainCompletion(route(), { messages: [{ role: 'user', content: 'p' }] }))
      .rejects.toThrow(/Inference HTTP 403/);
    expect(tried).toEqual(['deepseek/deepseek-v4.1-flash']);
  });
});

describe('policy summary + save check', () => {
  it('China users: Chinese vendors, Chinese default, no Anthropic key', () => {
    const s = policySummary(classifyRegion({ uiLanguage: 'zh' }), { OPENROUTER_ZH_API_KEY: 'zh' } as any);
    expect(s).toMatchObject({ region: 'cn', defaultModel: 'deepseek/deepseek-v4.1-flash', anthropicKeyAllowed: false, chineseModelAvailable: true });
    expect(s.allowedVendors).toEqual([...CHINESE_MODEL_VENDORS]);
  });
  it('others: everything allowed, no default override', () => {
    expect(policySummary(classifyRegion({ acceptLanguage: 'en-US' }), noEnv)).toMatchObject({ region: 'intl', allowedVendors: 'all', defaultModel: null, anthropicKeyAllowed: true });
  });
  it('save check rejects a non-Chinese pick only for China users', () => {
    expect(checkModelPick('cn', 'anthropic/claude-opus-5.5')).toBe('model_not_allowed_in_region');
    expect(checkModelPick('cn', 'z-ai/glm-5.3-prime')).toBeNull();
    expect(checkModelPick('intl', 'anthropic/claude-opus-5.5')).toBeNull();
    expect(checkModelPick('intl', 'z-ai/glm-5.3-prime')).toBeNull();
  });
  it('policyStateFor resolves a route only for China users', () => {
    expect(policyStateFor({ region: 'intl', reasons: [] }).cnRoute).toBeNull();
  });
});
