/**
 * Client side of the Chinese-LLM region policy (server/llm-region-policy.ts,
 * docs/20261112_CN_LLM_REGION_POLICY.md). The server decides the region (UI language, browser
 * language, IP) and enforces it on every request; the Settings picker only mirrors it so a China
 * user is never offered a model the server would refuse.
 */
import { useEffect, useState } from 'react';
import { locale } from '@/lib/i18n';

/** Equal to CHINESE_MODEL_VENDORS in server/llm-region-policy.ts (llm-region.test.ts checks). */
export const CHINESE_MODEL_VENDORS = [
  'deepseek', 'qwen', 'z-ai', 'moonshotai', 'minimax', 'baidu', 'tencent', 'bytedance',
  'bytedance-seed', 'stepfun', 'inclusionai', 'meituan', 'xiaomi', 'thudm', '01-ai',
] as const;

export function isChineseModel(slug: string): boolean {
  const m = slug.trim().toLowerCase();
  const slash = m.indexOf('/');
  return slash > 0 && (CHINESE_MODEL_VENDORS as readonly string[]).includes(m.slice(0, slash));
}

export interface LlmPolicy {
  region: 'cn' | 'intl';
  reasons: string[];
  allowedVendors: string[] | 'all';
  /** The Chinese default for China users; null elsewhere (the picker keeps its own default). */
  defaultModel: string | null;
  anthropicKeyAllowed: boolean;
  chineseModelAvailable: boolean;
}

/** Quick-pick model groups. Flagship slugs verified against OpenRouter's live /models catalog. */
export const OPEN_MODELS = [
  'z-ai/glm-5.3-prime',
  'deepseek/deepseek-v4-pro',
  'qwen/qwen3-235b-a22b-2507',
  'moonshotai/kimi-k3',
  'meta-llama/llama-4-maverick',
] as const;
export const PROPRIETARY_MODELS = [
  'anthropic/claude-opus-5.5',
  'anthropic/claude-sonnet-5.5',
  'openai/gpt-6.1-sol-pro',
  'google/gemini-3.1-pro-preview',
  'x-ai/grok-4.7',
  'mistralai/mistral-large-4-0',
] as const;
/** China users: Chinese models only (the default first). */
export const CHINESE_MODELS = [
  'deepseek/deepseek-v4.1-flash',
  'z-ai/glm-5.3-prime',
  'deepseek/deepseek-v4-pro',
  'qwen/qwen3-235b-a22b-2507',
  'moonshotai/kimi-k3',
] as const;

/** The default pick for users outside the region (unchanged by the policy). */
export const INTL_DEFAULT_MODEL = 'z-ai/glm-5.3-prime';

export type ModelGroup = { key: 'chinese' | 'open' | 'proprietary'; slugs: readonly string[] };

/** The picker's groups for a region: China users see Chinese models only; everyone else sees all. */
export function modelGroups(region: LlmPolicy['region'] | undefined): ModelGroup[] {
  if (region === 'cn') return [{ key: 'chinese', slugs: CHINESE_MODELS }];
  return [{ key: 'open', slugs: OPEN_MODELS }, { key: 'proprietary', slugs: PROPRIETARY_MODELS }];
}

/** The pick to show: a China user's stored pick only if it is Chinese, else the Chinese default. */
export function effectivePick(policy: LlmPolicy | null, stored: string | null | undefined): string {
  if (policy?.region === 'cn') {
    return stored && isChineseModel(stored) ? stored : (policy.defaultModel || CHINESE_MODELS[0]);
  }
  return stored || INTL_DEFAULT_MODEL;
}

/** A pick the user may not save in their region (China user + non-Chinese slug). */
export function pickRejected(policy: LlmPolicy | null, slug: string): boolean {
  return policy?.region === 'cn' && !!slug.trim() && !isChineseModel(slug);
}

/** The caller's region policy from the server (GET /api/llm/policy). null until loaded. */
export function useLlmPolicy(enabled = true): LlmPolicy | null {
  const [policy, setPolicy] = useState<LlmPolicy | null>(null);
  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    fetch(`/api/llm/policy?uiLanguage=${encodeURIComponent(locale)}`, { credentials: 'include' })
      .then(r => (r.ok ? r.json() : null))
      .then(d => { if (alive && d) setPolicy(d as LlmPolicy); })
      .catch(() => {});
    return () => { alive = false; };
  }, [enabled]);
  return policy;
}

/** "Model: GLM 5.3 Prime (Zhipu AI)" / "模型：DeepSeek V4.1 Flash（深度求索 · 国产大模型）". */
export interface ResolvedModel {
  model: string;
  displayName: string;
  vendor: string;
  vendorZh: string;
  isChinese: boolean;
  region: 'cn' | 'intl';
}

/** The chat's model label, from the server's `model` stream event (the model that actually answers). */
export function modelLabel(m: ResolvedModel, lang: string): string {
  if (lang === 'zh') {
    const vendor = m.isChinese ? `${m.vendorZh} · 国产大模型` : m.vendorZh;
    return `模型：${m.displayName}（${vendor}）`;
  }
  return `Model: ${m.displayName} (${m.vendor}${m.isChinese ? ' · Chinese model' : ''})`;
}
