/**
 * Chinese-LLM region policy (docs/20261112_CN_LLM_REGION_POLICY.md).
 *
 * A "China user" is a user with ANY of these signals (an OR, not a precedence order):
 *   (a) the app's UI / settings language is Chinese (context.uiLanguage, or the biomate_ui_lang
 *       cookie the client sets from the Settings language);
 *   (b) the browser's PRIMARY Accept-Language tag is zh* (zh, zh-CN, zh-TW, zh-HK…);
 *   (c) the client IP geolocates to CN_REGION_COUNTRIES (mainland China, Hong Kong, Macau,
 *       Taiwan), or an upstream CDN country header names one of them.
 *
 * Every LLM call made for a China user runs on a Chinese model (CHINESE_MODEL_VENDORS). If no
 * credential for a Chinese model is configured, the call FAILS CLOSED with
 * ChineseModelUnavailableError — never a silent fallback to Claude / Gemini / GPT.
 *
 * The policy restricts ONE direction only: users outside the region keep every model (open and
 * proprietary, Chinese included), their own keys and the existing defaults.
 *
 * Enforcement is per request through `llmPolicyStorage` (AsyncLocalStorage): set by
 * `llmRegionMiddleware` for every request and re-set by the chat stream with the user's own keys.
 * The shared LLM chokepoints read it: callGeminiFlash, llmGenerate, `policyMessagesClient` (for
 * Anthropic-SDK clients) and GalaxyAssistant (its Gemini client and intent model).
 */
import { AsyncLocalStorage } from 'node:async_hooks';
import { isIPv4, isIPv6 } from 'node:net';
import ipRanges from './data/cn-region-ip-ranges.json';
import { normalizeUiLanguage } from './response-language';
import { openaiCompatCompletion, openaiCompatMessagesClient } from './local-llm';

/** IP / CDN-header countries that make a China user. Equal to COUNTRIES in
 *  scripts/gen_cn_region_ip_ranges.py (which builds data/cn-region-ip-ranges.json). */
export const CN_REGION_COUNTRIES = ['CN', 'HK', 'MO', 'TW'] as const;

export type LlmRegion = 'cn' | 'intl';
export type RegionReason = 'ui_language' | 'accept_language' | 'ip' | 'geo_header';

// ── IP lookup ───────────────────────────────────────────────────────────────────────────────

const V4 = ipRanges.ipv4 as Array<[number, number]>;
let V6: Array<[bigint, bigint]> | null = null;
const v6Ranges = () => (V6 ??= (ipRanges.ipv6 as Array<[string, string]>).map(([a, b]) => [BigInt(`0x${a}`), BigInt(`0x${b}`)]));

function ipv4ToInt(ip: string): number {
  return ip.split('.').reduce((n, part) => n * 256 + Number(part), 0);
}

function ipv6ToBigInt(ip: string): bigint {
  let s = ip.split('%')[0];
  // An embedded IPv4 tail (::ffff:1.2.3.4, 64:ff9b::1.2.3.4) → two hex groups.
  const v4tail = s.match(/(\d+\.\d+\.\d+\.\d+)$/);
  if (v4tail) {
    const n = ipv4ToInt(v4tail[1]);
    s = s.slice(0, -v4tail[1].length) + `${(n >>> 16).toString(16)}:${(n & 0xffff).toString(16)}`;
  }
  const [head, tail] = s.includes('::') ? s.split('::') : [s, undefined];
  const h = head ? head.split(':') : [];
  const t = tail !== undefined ? (tail ? tail.split(':') : []) : [];
  const groups = tail !== undefined ? [...h, ...Array(8 - h.length - t.length).fill('0'), ...t] : h;
  return groups.reduce((n, g) => (n << 16n) + BigInt(parseInt(g || '0', 16)), 0n);
}

function inRanges<T extends number | bigint>(ranges: Array<[T, T]>, x: T): boolean {
  let lo = 0, hi = ranges.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (x < ranges[mid][0]) hi = mid - 1;
    else if (x > ranges[mid][1]) lo = mid + 1;
    else return true;
  }
  return false;
}

/** Does this client IP geolocate to CN_REGION_COUNTRIES? IPv4, IPv6 and IPv4-mapped IPv6. */
export function isCnRegionIp(ip: unknown): boolean {
  if (typeof ip !== 'string' || !ip) return false;
  const mapped = ip.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/i);
  const v4 = mapped ? mapped[1] : ip;
  if (isIPv4(v4)) return inRanges(V4, ipv4ToInt(v4));
  if (isIPv6(ip)) return inRanges(v6Ranges(), ipv6ToBigInt(ip));
  return false;
}

// ── Region ──────────────────────────────────────────────────────────────────────────────────

export interface RegionSignals {
  uiLanguage?: unknown;
  acceptLanguage?: unknown;
  ip?: unknown;
  countryHeader?: unknown;
}

export interface RegionDecision {
  region: LlmRegion;
  /** Every signal that matched (empty for intl). */
  reasons: RegionReason[];
}

function primaryLanguageIsChinese(acceptLanguage: unknown): boolean {
  const primary = String(acceptLanguage || '').split(',')[0].split(';')[0].trim().toLowerCase();
  return primary === 'zh' || primary.startsWith('zh-');
}

/** China user = ANY signal (see the module comment). */
export function classifyRegion(s: RegionSignals): RegionDecision {
  const reasons: RegionReason[] = [];
  if (normalizeUiLanguage(s.uiLanguage) === 'zh') reasons.push('ui_language');
  if (primaryLanguageIsChinese(s.acceptLanguage)) reasons.push('accept_language');
  if ((CN_REGION_COUNTRIES as readonly string[]).includes(String(s.countryHeader || '').trim().toUpperCase())) reasons.push('geo_header');
  if (isCnRegionIp(s.ip)) reasons.push('ip');
  return { region: reasons.length ? 'cn' : 'intl', reasons };
}

/** The cookie the client sets from its Settings language (lib/i18n.ts), so requests that carry no
 *  chat context (notes, evidence, findings…) still know the user's UI language. */
export const UI_LANGUAGE_COOKIE = 'biomate_ui_lang';

function cookieValue(cookieHeader: unknown, name: string): string | undefined {
  for (const part of String(cookieHeader || '').split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return decodeURIComponent(v.join('='));
  }
  return undefined;
}

/** Region signals of an Express request. `uiLanguage` (from a chat request body) wins over the cookie. */
export function regionSignalsFromRequest(req: any, uiLanguage?: unknown): RegionSignals {
  const h = req?.headers || {};
  return {
    uiLanguage: uiLanguage ?? h['x-biomate-ui-language'] ?? cookieValue(h.cookie, UI_LANGUAGE_COOKIE),
    acceptLanguage: h['accept-language'],
    ip: req?.ip,
    countryHeader: h['cf-ipcountry'] || h['x-vercel-ip-country'] || h['x-appengine-country'] || h['cloudfront-viewer-country'],
  };
}

// ── Models ──────────────────────────────────────────────────────────────────────────────────

/** OpenRouter vendor prefixes of Chinese model makers (verified against openrouter.ai/api/v1/models,
 *  2026-11-12). A model counts as Chinese only through this list. */
export const CHINESE_MODEL_VENDORS = [
  'deepseek', 'qwen', 'z-ai', 'moonshotai', 'minimax', 'baidu', 'tencent', 'bytedance',
  'bytedance-seed', 'stepfun', 'inclusionai', 'meituan', 'xiaomi', 'thudm', '01-ai',
] as const;

/** Bare (provider-native, no vendor prefix) Chinese model names, e.g. an on-prem LLM_MODEL. */
const CHINESE_BARE_MODEL = /^(qwen|qwq|deepseek|glm|chatglm|kimi|moonshot|ernie|hunyuan|doubao|abab|minimax|step-|yi-)/i;

export function isChineseModel(model: unknown): boolean {
  const m = String(model || '').trim().toLowerCase();
  if (!m) return false;
  const slash = m.indexOf('/');
  if (slash > 0) return (CHINESE_MODEL_VENDORS as readonly string[]).includes(m.slice(0, slash));
  return CHINESE_BARE_MODEL.test(m);
}

const VENDORS: Record<string, { en: string; zh: string }> = {
  deepseek: { en: 'DeepSeek', zh: '深度求索' },
  qwen: { en: 'Alibaba Qwen', zh: '阿里通义千问' },
  'z-ai': { en: 'Zhipu AI', zh: '智谱' },
  thudm: { en: 'Zhipu AI', zh: '智谱' },
  moonshotai: { en: 'Moonshot AI', zh: '月之暗面' },
  minimax: { en: 'MiniMax', zh: 'MiniMax' },
  baidu: { en: 'Baidu', zh: '百度' },
  tencent: { en: 'Tencent', zh: '腾讯' },
  bytedance: { en: 'ByteDance', zh: '字节跳动' },
  'bytedance-seed': { en: 'ByteDance', zh: '字节跳动' },
  stepfun: { en: 'StepFun', zh: '阶跃星辰' },
  inclusionai: { en: 'Ant Group inclusionAI', zh: '蚂蚁集团' },
  meituan: { en: 'Meituan', zh: '美团' },
  xiaomi: { en: 'Xiaomi', zh: '小米' },
  '01-ai': { en: '01.AI', zh: '零一万物' },
  anthropic: { en: 'Anthropic', zh: 'Anthropic' },
  google: { en: 'Google', zh: 'Google' },
  openai: { en: 'OpenAI', zh: 'OpenAI' },
  'x-ai': { en: 'xAI', zh: 'xAI' },
  'meta-llama': { en: 'Meta', zh: 'Meta' },
  mistralai: { en: 'Mistral AI', zh: 'Mistral AI' },
};

const BARE_VENDOR: Array<[RegExp, string]> = [
  [/^claude/i, 'anthropic'], [/^gemini/i, 'google'], [/^(gpt|o\d)/i, 'openai'], [/^(qwen|qwq)/i, 'qwen'],
  [/^deepseek/i, 'deepseek'], [/^(glm|chatglm)/i, 'z-ai'], [/^(kimi|moonshot)/i, 'moonshotai'],
  [/^ernie/i, 'baidu'], [/^hunyuan/i, 'tencent'], [/^doubao/i, 'bytedance'], [/^(abab|minimax)/i, 'minimax'],
];

const WORDS: Record<string, string> = {
  deepseek: 'DeepSeek', glm: 'GLM', qwen: 'Qwen', kimi: 'Kimi', claude: 'Claude', gemini: 'Gemini',
  gpt: 'GPT', llama: 'Llama', grok: 'Grok', minimax: 'MiniMax', ernie: 'ERNIE', hunyuan: 'Hunyuan',
  doubao: 'Doubao', mistral: 'Mistral',
};

/** "deepseek-v4.1-flash" → "DeepSeek V4.1 Flash"; "claude-sonnet-4-5" → "Claude Sonnet 4.5". */
function displayName(name: string): string {
  const tokens = name.replace(/:.*$/, '').split('-').filter(Boolean);
  const out: string[] = [];
  for (const t of tokens) {
    const low = t.toLowerCase();
    if (/^\d+$/.test(t) && out.length && /^\d+(\.\d+)*$/.test(out[out.length - 1])) {
      out[out.length - 1] += `.${t}`;
    } else if (WORDS[low]) out.push(WORDS[low]);
    else if (/^v\d/.test(low)) out.push(`V${t.slice(1)}`);
    else if (/^\d/.test(t)) out.push(t);
    else out.push(t.charAt(0).toUpperCase() + t.slice(1));
  }
  return out.join(' ');
}

export interface ModelIdentity {
  model: string;
  displayName: string;
  vendor: string;
  vendorZh: string;
  isChinese: boolean;
}

export function modelIdentity(model: string): ModelIdentity {
  const m = String(model || '').trim();
  const slash = m.indexOf('/');
  const vendorKey = slash > 0 ? m.slice(0, slash).toLowerCase() : (BARE_VENDOR.find(([re]) => re.test(m))?.[1] ?? '');
  const vendor = VENDORS[vendorKey] ?? { en: vendorKey || 'unknown vendor', zh: vendorKey || '未知厂商' };
  return { model: m, displayName: displayName(slash > 0 ? m.slice(slash + 1) : m), vendor: vendor.en, vendorZh: vendor.zh, isChinese: isChineseModel(m) };
}

/** System-prompt block that tells the model exactly which model it is, so "which LLM are you?" is
 *  answered from fact. Appended to every system prompt built for a user's chat turn. */
export function modelIdentityDirective(identity: ModelIdentity | null | undefined, region: LlmRegion = 'intl'): string {
  if (!identity?.model) return '';
  const cn = region === 'cn'
    ? ` This user is served under BioMate's China-region policy: every reply runs on a Chinese large model (国产大模型). When asked which model is used, say so plainly and name it, e.g. "我是 BioMate，当前使用的是国产大模型 ${identity.displayName}（${identity.vendorZh}）。". Background steps (understanding the request, short summaries, some analysis steps) may run on other Chinese models from the same set; if asked, say that every model used for this user is a Chinese model.`
    : identity.isChinese ? ` ${identity.displayName} is a Chinese large model (国产大模型) chosen by the user.` : '';
  return `\n\nMODEL IDENTITY: You are BioMate's assistant, and this reply is generated by the model ${identity.displayName} (${identity.model}) from ${identity.vendor}.${cn} When the user asks which model, LLM or AI you are, or who made you, answer exactly from this block. Never claim to be Claude, GPT, Gemini or any model other than ${identity.displayName}, and do not guess a version beyond what is stated here.`;
}

// ── Chinese-model route ─────────────────────────────────────────────────────────────────────

// ── The Chinese model set: one model per role, like the English hybrid ──────────────────────
//
// China-region users run every role on a Chinese model, each role on the model suited to it
// (docs/20261112_CN_LLM_REGION_POLICY.md, "Model set"). All via OpenRouter, all tool-capable
// (OpenRouter /models, 2026-11-12). Benchmarked on BioMate's evals: GLM 5.2 and the DeepSeek models;
// the Qwen picks are chosen on capability and price pending the routing / tool-call benchmarks.
export type CnRole = 'intent' | 'response' | 'reasoning' | 'light' | 'vision';

export interface CnModels {
  intent: string;      // intent / task decomposition (structured JSON)
  response: string;    // the reply + agentic tool loop — the model the user talks to
  reasoning: string;   // hard / long reasoning (the English Pro / thinking tier)
  light: string;       // tool ranking, titles, session memory, notes, compressor (the English Haiku / Flash role)
  vision: string;      // reading images (plots, figures)
  galaxyChain: string[]; // the backend chain (llmGenerate, Galaxy LLMClient): first that answers wins
}

export const CN_MODEL_SET: Readonly<CnModels> = Object.freeze({
  intent: 'z-ai/glm-5.2',
  response: 'deepseek/deepseek-v4.1-flash',
  reasoning: 'deepseek/deepseek-v4-pro',
  light: 'qwen/qwen3.5-flash-02-23',
  vision: 'deepseek/deepseek-v4.1-flash',
  galaxyChain: Object.freeze(['deepseek/deepseek-v4.1-flash', 'z-ai/glm-5.2', 'qwen/qwen3.5-plus-20260420']) as unknown as string[],
});

/** The env var that overrides each role (an override must still be a Chinese model). */
export const CN_ROLE_ENV: Readonly<Record<keyof CnModels, string>> = Object.freeze({
  intent: 'BIOMATE_CN_INTENT_MODEL',
  response: 'BIOMATE_CN_RESPONSE_MODEL',
  reasoning: 'BIOMATE_CN_REASONING_MODEL',
  light: 'BIOMATE_CN_LIGHT_MODEL',
  vision: 'BIOMATE_CN_VISION_MODEL',
  galaxyChain: 'BIOMATE_CN_GALAXY_CHAIN',
});

const _warnedOverrides = new Set<string>();
function chineseOverride(name: string, value: string | undefined): string | undefined {
  const v = (value || '').trim();
  if (!v) return undefined;
  if (isChineseModel(v)) return v;
  if (!_warnedOverrides.has(`${name}=${v}`)) {
    _warnedOverrides.add(`${name}=${v}`);
    console.warn(`[llm-region-policy] ${name}=${v} is not a Chinese model — ignored; the Chinese model set keeps its default`);
  }
  return undefined;
}

/** The deployment's Chinese model set: CN_MODEL_SET with its env overrides applied. The response
 *  role also honours the older OPENROUTER_ZH_DEFAULT_MODEL / OPENROUTER_CN_DEFAULT_MODEL
 *  (zhDefaultModel) as an alias. Non-Chinese overrides are ignored with a warning. */
export function cnModelSet(env: NodeJS.ProcessEnv = process.env): CnModels {
  const alias = env.OPENROUTER_ZH_DEFAULT_MODEL || env.OPENROUTER_CN_DEFAULT_MODEL;
  const chainEnv = (env[CN_ROLE_ENV.galaxyChain] || '').split(',').map((m) => m.trim()).filter(Boolean);
  const chain = chainEnv.map((m) => chineseOverride(CN_ROLE_ENV.galaxyChain, m)).filter((m): m is string => !!m);
  return {
    intent: chineseOverride(CN_ROLE_ENV.intent, env[CN_ROLE_ENV.intent]) ?? CN_MODEL_SET.intent,
    response: chineseOverride(CN_ROLE_ENV.response, env[CN_ROLE_ENV.response])
      ?? chineseOverride('OPENROUTER_ZH_DEFAULT_MODEL', alias) ?? CN_MODEL_SET.response,
    reasoning: chineseOverride(CN_ROLE_ENV.reasoning, env[CN_ROLE_ENV.reasoning]) ?? CN_MODEL_SET.reasoning,
    light: chineseOverride(CN_ROLE_ENV.light, env[CN_ROLE_ENV.light]) ?? CN_MODEL_SET.light,
    vision: chineseOverride(CN_ROLE_ENV.vision, env[CN_ROLE_ENV.vision]) ?? CN_MODEL_SET.vision,
    galaxyChain: chain.length ? chain : [...CN_MODEL_SET.galaxyChain],
  };
}

export interface CnRoute {
  url: string;
  key: string;
  model: string;
  source: 'user_openrouter' | 'openrouter_zh_key' | 'openrouter_system_key' | 'onprem';
  /** The model for each role. `model` is the response role (the one the user talks to). */
  models: CnModels;
}

export const OPENROUTER_URL = 'https://openrouter.ai/api/v1';

/** How a China user's LLM calls reach a Chinese model, or null when no credential exists.
 *  The user's Chinese pick replaces the response role only; every other role comes from the set. */
export function resolveCnRoute(input: { userOpenrouterKey?: string; selectedModel?: string }, env: NodeJS.ProcessEnv = process.env): CnRoute | null {
  // The set's models are all Chinese (cnModelSet ignores non-Chinese overrides). A China user's own
  // Chinese pick replaces the RESPONSE role only — intent, reasoning, light and the backend chain
  // keep the set; vision follows the pick only when the pick is the response model the user sees.
  const set = cnModelSet(env);
  const pick = input.selectedModel && isChineseModel(input.selectedModel) ? input.selectedModel : undefined;
  const models: CnModels = { ...set, response: pick ?? set.response, galaxyChain: [...set.galaxyChain] };
  const model = models.response;
  if (input.userOpenrouterKey) return { url: OPENROUTER_URL, key: input.userOpenrouterKey, model, source: 'user_openrouter', models };
  if (env.OPENROUTER_ZH_API_KEY) return { url: OPENROUTER_URL, key: env.OPENROUTER_ZH_API_KEY, model, source: 'openrouter_zh_key', models };
  if (env.OPENROUTER_API_KEY) return { url: OPENROUTER_URL, key: env.OPENROUTER_API_KEY, model, source: 'openrouter_system_key', models };
  const onpremModel = env.LLM_MODEL || env.GALAXY_AI_LLM_MODEL || 'qwen-max';
  if (env.LLM_API_URL && isChineseModel(onpremModel)) {
    // One on-prem model serves every role.
    const one: CnModels = { intent: onpremModel, response: onpremModel, reasoning: onpremModel, light: onpremModel, vision: onpremModel, galaxyChain: [onpremModel] };
    return { url: env.LLM_API_URL, key: env.LLM_API_KEY && env.LLM_API_KEY !== 'none' ? env.LLM_API_KEY : 'none', model: onpremModel, source: 'onprem', models: one };
  }
  return null;
}

export class ChineseModelUnavailableError extends Error {
  readonly code = 'cn_model_unavailable';
  readonly status = 503;
  constructor() {
    super('Chinese model unavailable — contact the administrator. 国产大模型暂不可用，请联系管理员。');
  }
}

// ── Per-request state ───────────────────────────────────────────────────────────────────────

export interface LlmPolicyState extends RegionDecision {
  /** For a China user: the route every LLM call takes (null = none configured → fail closed). */
  cnRoute: CnRoute | null;
}

export const llmPolicyStorage = new AsyncLocalStorage<LlmPolicyState>();

export function currentLlmPolicy(): LlmPolicyState | undefined {
  return llmPolicyStorage.getStore();
}

/** The Chinese-model route for the current request; null for users outside the region. Throws
 *  ChineseModelUnavailableError for a China user when no Chinese model is configured (fail closed). */
export function requireCnRoute(): CnRoute | null {
  const p = llmPolicyStorage.getStore();
  if (!p || p.region !== 'cn') return null;
  if (!p.cnRoute) {
    console.warn(`[llm-region-policy] China user (${p.reasons.join(',')}) but no Chinese-model credential is configured — refusing the LLM call`);
    throw new ChineseModelUnavailableError();
  }
  return p.cnRoute;
}

export function policyStateFor(decision: RegionDecision, routeInput: { userOpenrouterKey?: string; selectedModel?: string } = {},
  env: NodeJS.ProcessEnv = process.env): LlmPolicyState {
  return { ...decision, cnRoute: decision.region === 'cn' ? resolveCnRoute(routeInput, env) : null };
}

/** Express middleware: classify every request and run the rest of it inside llmPolicyStorage, so any
 *  LLM chokepoint reached while serving it applies the policy (system keys; the chat stream re-runs
 *  with the user's own key). Mount after body parsing / auth. */
export function llmRegionMiddleware(req: any, _res: any, next: () => void): void {
  const state = policyStateFor(classifyRegion(regionSignalsFromRequest(req)));
  llmPolicyStorage.run(state, next);
}

export interface CnCompletionOpts {
  messages: Array<{ role: 'user' | 'assistant'; content: string }>;
  system?: string;
  maxTokens?: number;
  temperature?: number;
  jsonMode?: boolean;
}

/** The route with `role`'s model (the response role is `route.model`). */
export function cnRouteForRole(route: CnRoute, role: CnRole): CnRoute {
  return { ...route, model: route.models[role] };
}

/** Which role an Anthropic-SDK call fills, read from the model the English code asked for: the
 *  English side already picks a model per role (Haiku for light work, a Pro / Opus or thinking call
 *  for hard reasoning, the response model otherwise). A call carrying images goes to the vision
 *  model, so an image is never sent to a text-only model. */
export function cnRoleForMessagesCall(params: any): CnRole {
  const hasImage = Array.isArray(params?.messages) && params.messages.some((m: any) =>
    Array.isArray(m?.content) && m.content.some((b: any) => b?.type === 'image' || b?.type === 'image_url'));
  if (hasImage) return 'vision';
  const requested = String(params?.model || '').toLowerCase();
  if (/haiku|flash-lite|(^|[-/])mini\b|nano/.test(requested)) return 'light';
  if (params?.thinking || /opus|(^|[-/])pro($|[-.:])|-pro-|-pro$/.test(requested)) return 'reasoning';
  return 'response';
}

/** An Anthropic-SDK-shaped client on the China user's model SET: each create() runs on the model of
 *  the role it fills (cnRoleForMessagesCall). */
export function cnRoleMessagesClient(route: CnRoute): any {
  const clients = new Map<string, any>();
  const clientFor = (model: string) => {
    if (!clients.has(model)) clients.set(model, openaiCompatMessagesClient({ url: route.url, model, key: route.key }));
    return clients.get(model);
  };
  return { messages: { create: (params: any) => clientFor(route.models[cnRoleForMessagesCall(params)]).messages.create(params) } };
}

/** A completion on the backend chain (llmGenerate's Chinese replacement for the Gemini → Claude →
 *  GPT chain): each model in turn until one answers; never a model outside the chain. */
export async function cnChainCompletion(route: CnRoute, opts: CnCompletionOpts): Promise<{ text: string; model: string }> {
  const chain = route.models.galaxyChain.length ? route.models.galaxyChain : [route.model];
  let lastError: unknown;
  for (const model of chain) {
    try {
      return { text: await cnCompletion({ ...route, model }, opts), model };
    } catch (err) {
      lastError = err;
      console.warn(`[llm-region-policy] chain model ${model} failed (${(err as Error)?.message?.slice(0, 160)}) — trying the next Chinese model`);
    }
  }
  throw lastError instanceof Error ? lastError : new Error('Every Chinese model in the chain failed');
}

/** A plain text completion on the China user's Chinese model (the chokepoints' replacement for
 *  Gemini / the backend LLM chain). */
export async function cnCompletion(route: CnRoute, opts: CnCompletionOpts): Promise<string> {
  const result = await openaiCompatCompletion({ url: route.url, model: route.model, key: route.key }, {
    messages: [...(opts.system ? [{ role: 'system', content: opts.system }] : []), ...opts.messages],
    max_tokens: opts.maxTokens ?? 4096,
    temperature: opts.temperature ?? 0,
    ...(opts.jsonMode ? { response_format: { type: 'json_object' } } : {}),
  });
  const content = result.choices?.[0]?.message?.content;
  if (typeof content !== 'string') throw new Error(`Chinese model ${route.model} returned no text`);
  return content;
}

/** An Anthropic-SDK-shaped client that obeys the policy: for a China user, the Chinese model behind
 *  the Messages shim, each call on its role's model (fail closed when none); otherwise `fallback`. */
export function policyMessagesClient<T>(fallback: T): T {
  const route = requireCnRoute();
  if (!route) return fallback;
  return cnRoleMessagesClient(route) as unknown as T;
}

/** What GET /api/llm/policy returns and the Settings picker uses. */
export function policySummary(decision: RegionDecision, env: NodeJS.ProcessEnv = process.env) {
  return {
    region: decision.region,
    reasons: decision.reasons,
    regionCountries: [...CN_REGION_COUNTRIES],
    allowedVendors: decision.region === 'cn' ? [...CHINESE_MODEL_VENDORS] : 'all' as const,
    defaultModel: decision.region === 'cn' ? cnModelSet(env).response : null,
    modelSet: decision.region === 'cn' ? cnModelSet(env) : null,
    anthropicKeyAllowed: decision.region !== 'cn',
    chineseModelAvailable: decision.region === 'cn' ? !!resolveCnRoute({}, env) : true,
  };
}

/** Save-time check of a model pick (POST /api/user/llm-api-keys): China users may only pick a
 *  Chinese model. Returns an error code or null. */
export function checkModelPick(region: LlmRegion, model: unknown): 'model_not_allowed_in_region' | null {
  if (region !== 'cn') return null;
  if (typeof model !== 'string' || !model.trim()) return null;
  return isChineseModel(model) ? null : 'model_not_allowed_in_region';
}

// ── Chat-stream resolution ──────────────────────────────────────────────────────────────────

export interface ChatLlmInput {
  region: RegionDecision;
  /** The user's own stored keys and model pick (Settings → LLM). */
  userAnthropicKey?: string;
  userOpenrouterKey?: string;
  selectedModel?: string;
}

export interface ChatLlm {
  /** Passed to GalaxyAssistant as context.userAnthropicApiKey / openrouterKey / selectedModel / openaiBaseUrl. */
  userAnthropicKey?: string;
  openrouterKey?: string;
  selectedModel?: string;
  openaiBaseUrl?: string;
  state: LlmPolicyState;
}

/** Which keys and model a chat turn uses. Re-run on EVERY request (the region can change).
 *  China user: their Chinese pick (else the Chinese default) through their OpenRouter key, else the
 *  deployment's OPENROUTER_ZH_API_KEY / OPENROUTER_API_KEY / on-prem Chinese LLM; their Anthropic key
 *  and a non-Chinese pick are dropped; no credential → ChineseModelUnavailableError (fail closed).
 *  Everyone else: unchanged — own keys and pick, else the deployment's OpenRouter key and default,
 *  else an on-prem OpenAI-compatible LLM, else the built-in models (Gemini / Claude). */
export function resolveChatLlm(input: ChatLlmInput, env: NodeJS.ProcessEnv = process.env): ChatLlm {
  const state = policyStateFor(input.region, { userOpenrouterKey: input.userOpenrouterKey, selectedModel: input.selectedModel }, env);
  if (input.region.region === 'cn') {
    const cn = state.cnRoute;
    if (!cn) throw new ChineseModelUnavailableError();
    return { openrouterKey: cn.key, selectedModel: cn.model, openaiBaseUrl: cn.url === OPENROUTER_URL ? undefined : cn.url, state };
  }
  let openrouterKey = input.userOpenrouterKey;
  let selectedModel = input.selectedModel;
  let openaiBaseUrl: string | undefined;
  if (!openrouterKey && env.OPENROUTER_API_KEY) {
    openrouterKey = env.OPENROUTER_API_KEY;
    if (!selectedModel) selectedModel = env.OPENROUTER_DEFAULT_MODEL || 'deepseek/deepseek-chat';
  }
  // On-prem OpenAI-compatible LLM (DashScope/Qianwen, vLLM…): LLM_API_URL first so LLM_API_KEY=none works.
  if (!openrouterKey && env.LLM_API_URL) {
    openrouterKey = env.LLM_API_KEY && env.LLM_API_KEY !== 'none' ? env.LLM_API_KEY : 'none';
    openaiBaseUrl = env.LLM_API_URL;
    if (!selectedModel) selectedModel = env.LLM_MODEL || env.GALAXY_AI_LLM_MODEL || 'qwen-max';
  } else if (!openrouterKey && env.LLM_API_KEY && env.LLM_API_KEY !== 'none') {
    openrouterKey = env.LLM_API_KEY;
    openaiBaseUrl = env.LLM_API_URL || undefined;
    if (!selectedModel) selectedModel = env.LLM_MODEL || env.GALAXY_AI_LLM_MODEL || 'qwen-max';
  }
  return { userAnthropicKey: input.userAnthropicKey, openrouterKey, selectedModel, openaiBaseUrl, state };
}
