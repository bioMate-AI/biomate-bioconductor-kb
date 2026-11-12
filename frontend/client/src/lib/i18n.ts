/**
 * Lightweight, dependency-free i18n for the BioMate frontend.
 *
 * Ports the detection logic from the standalone i18n side-project
 * (`i18n/src/detector.ts`) without pulling in i18next at runtime.
 *
 * Active locale is resolved ONCE at module load:
 *   1. Stored user preference (userSettingsService localStorage key
 *      `biomate-user-settings`, field `language` — values like
 *      "english"/"chinese"/"spanish"…).
 *   2. navigator.language (e.g. "zh-CN" → "zh").
 *   3. "en" (hard fallback).
 *
 * A manual language change (Settings → Language) persists the preference
 * and triggers a full page reload; the reload re-runs this module and the
 * new locale takes effect. (Acceptable for v1 — no live re-render.)
 */

import enCommon from '@/locales/en/common.json';
import zhCommon from '@/locales/zh/common.json';

export const SUPPORTED_LOCALES = ['en', 'zh', 'ja', 'es'] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

/** Only the locales we actually ship translation bundles for. */
const RESOURCES: Partial<Record<SupportedLocale, Record<string, unknown>>> = {
  en: enCommon as Record<string, unknown>,
  zh: zhCommon as Record<string, unknown>,
};

const LOCALE_STORAGE_KEY = 'biomate-user-settings';

/**
 * Map the userSettings `language` enum values
 * (english/spanish/french/german/chinese) to ISO 639-1 codes.
 * Anything unknown falls through to normaliseLocale (BCP-47 handling).
 */
const SETTINGS_LANG_MAP: Record<string, SupportedLocale> = {
  english: 'en',
  chinese: 'zh',
  spanish: 'es',
  japanese: 'ja',
  // french / german have no bundle yet → will fall back to 'en' below.
};

/** Normalise any BCP-47 tag (or bare code) to a supported locale, else 'en'. */
export function normaliseLocale(raw: string): SupportedLocale {
  if (!raw) return 'en';
  const lower = raw.toLowerCase();
  if ((SUPPORTED_LOCALES as readonly string[]).includes(lower)) {
    return lower as SupportedLocale;
  }
  const prefix = lower.split('-')[0];
  if ((SUPPORTED_LOCALES as readonly string[]).includes(prefix)) {
    return prefix as SupportedLocale;
  }
  return 'en';
}

/** Read the stored language preference (raw settings value) — browser only. */
export function readStoredLanguage(): string | null {
  try {
    const raw =
      typeof localStorage !== 'undefined'
        ? localStorage.getItem(LOCALE_STORAGE_KEY)
        : null;
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return typeof parsed.language === 'string' ? parsed.language : null;
  } catch {
    return null;
  }
}

/**
 * English-phrase keys (`t('Run Manager')`), used by components that were written against the on-prem build's
 * phrase dictionary. Consulted only when the active locale is Chinese and the dot-path bundles have no entry.
 */
const ZH_PHRASES: Record<string, string> = {
  // ── Sidebar navigation ───────────────────────────────────────────────────
  'Workspace': '工作区',
  'New Chat': '新建对话',
  'Start a fresh AI conversation': '开始新的 AI 对话',
  'Workflows': '工作流',
  'Run history, browse & import pipelines': '运行历史 · 浏览并导入流程',
  'Connectors': '连接器',
  'Databases, LLMs & platform integrations': '数据库、大模型及平台集成',
  'IND Report': 'IND 报告',
  'Generate regulatory submission documents': '生成法规申报文档',
  'Projects': '项目',
  'Recent': '最近',
  'New project': '新建项目',
  'No chats yet': '暂无对话',
  'Settings & API Keys': '设置与 API 密钥',
  'System Admin': '系统管理',
  // ── Chat input ───────────────────────────────────────────────────────────
  'Message BioMate AI...': '向 BioMate AI 发送消息…',
  'Send message': '发送',
  'Stop generating': '停止生成',
  // ── Workflow panel ───────────────────────────────────────────────────────
  'Confirm & Run': '确认并运行',
  'Running...': '运行中…',
  'Run again': '再次运行',
  'Restart': '重启',
  'Completed': '已完成',
  'Failed': '失败',
  'Parameters': '参数',
  'Outputs': '输出',
  'Findings': '分析结果',
  'Download report': '下载报告',
  // ── Common UI ────────────────────────────────────────────────────────────
  'Cancel': '取消',
  'Save': '保存',
  'Close': '关闭',
  'Delete': '删除',
  'Edit': '编辑',
  'Back': '返回',
  'Loading...': '加载中…',
  'Error': '错误',
  'Success': '成功',
  'Copy': '复制',
  'Copied!': '已复制！',
  // ── Auth ─────────────────────────────────────────────────────────────────
  'Sign in': '登录',
  'Sign out': '退出登录',
  'Email': '邮箱',
  'Password': '密码',
  'Remember me': '记住我',
  'Forgot password?': '忘记密码？',
  // ── Chat main area ───────────────────────────────────────────────────────
  'New thread': '新对话',
  'New chat': '新对话',
  'Run Manager': '运行管理器',
  'What would you like to analyze?': '您想分析什么？',
  'Select your research areas — BioMate will prioritise relevant workflows.': '选择您的研究方向 — BioMate 将优先推荐相关工作流。',
  'Input your use case here': '在此输入您的使用场景',
  'MG patient stratification → ADMET': 'MG 患者分层 → ADMET',
  'ADMET screen from SMILES': '基于 SMILES 的 ADMET 筛选',
  'RNA-seq differential expression': 'RNA-seq 差异表达分析',
  'Variant calling on WGS sample': 'WGS 样本变异检测',
  // ── Admin panel ──────────────────────────────────────────────────────────
  'System Dashboard': '系统管理面板',
  'Health': '服务状态',
  'LLM Configuration': '大模型配置',
};

/** Build flag: on-prem deployments default to a Chinese UI when the browser reports no language. */
export const onPrem: boolean = typeof import.meta !== 'undefined'
  ? (import.meta as any).env?.VITE_ONPREM === 'true'
  : false;

/**
 * Resolve the active locale from the browser environment.
 * Stored preference wins over navigator language; both fall back to 'en'.
 */
export function detectLocale(): SupportedLocale {
  const stored = readStoredLanguage();
  if (stored) {
    const mapped = SETTINGS_LANG_MAP[stored.toLowerCase()] ?? normaliseLocale(stored);
    // Only honour the stored preference if we have a bundle for it;
    // otherwise fall through to navigator/en so text stays coherent.
    if (RESOURCES[mapped]) return mapped;
    return 'en';
  }
  if (typeof navigator !== 'undefined' && navigator.language) {
    const nav = normaliseLocale(navigator.language);
    return RESOURCES[nav] ? nav : 'en';
  }
  return onPrem && RESOURCES.zh ? 'zh' : 'en';
}

/** The locale resolved for this page load. Stable for the session. */
export const locale: SupportedLocale = detectLocale();

// The UI language as a cookie, so the server's Chinese-LLM region policy sees it on every request
// (signal (a) of server/llm-region-policy.ts), not only on chat requests that carry uiLanguage.
// A language change reloads the page, so setting it at load keeps it current.
try {
  if (typeof document !== 'undefined') document.cookie = `biomate_ui_lang=${locale}; path=/; max-age=31536000; samesite=lax`;
} catch { /* cookies blocked: chat requests still send uiLanguage */ }

const activeBundle = RESOURCES[locale] ?? enCommon;
const enBundle = enCommon as Record<string, unknown>;

/** Dot-path lookup into a nested resource object; returns undefined on miss. */
function lookup(bundle: Record<string, unknown>, key: string): string | undefined {
  let node: unknown = bundle;
  for (const part of key.split('.')) {
    if (node && typeof node === 'object' && part in (node as Record<string, unknown>)) {
      node = (node as Record<string, unknown>)[part];
    } else {
      return undefined;
    }
  }
  return typeof node === 'string' ? node : undefined;
}

type Vars = Record<string, string | number>;

function interpolate(text: string, vars?: Vars): string {
  if (!vars) return text;
  return text.replace(/\{\{\s*(\w+)\s*\}\}/g, (m, name: string) => (name in vars ? String(vars[name]) : m));
}

/**
 * Translate a dot-path key (e.g. "nav.dashboard", "workflow.status.running").
 * Falls back to the English value, then (Chinese only) to the English-phrase dictionary, then to the key itself. `{{name}}`
 * placeholders are filled from `vars`.
 */
export function t(key: string, vars?: Vars): string {
  const phrase = locale === 'zh' ? ZH_PHRASES[key] : undefined;
  return interpolate(lookup(activeBundle, key) ?? lookup(enBundle, key) ?? phrase ?? key, vars);
}

/** Like `t`, but for data-driven keys (e.g. a workflow domain) that may have no bundle entry. */
export function tOr(key: string, fallback: string, vars?: Vars): string {
  return interpolate(lookup(activeBundle, key) ?? lookup(enBundle, key) ?? fallback, vars);
}

/**
 * Persist a language preference (writes the userSettings localStorage key)
 * and, when it differs from the current one, reload so the new locale applies.
 * `value` is the raw settings enum (e.g. "english", "chinese").
 */
export function setLanguagePreference(value: string): void {
  try {
    const raw =
      typeof localStorage !== 'undefined'
        ? localStorage.getItem(LOCALE_STORAGE_KEY)
        : null;
    const parsed = raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
    const previous = typeof parsed.language === 'string' ? parsed.language : null;
    parsed.language = value;
    localStorage.setItem(LOCALE_STORAGE_KEY, JSON.stringify(parsed));
    if (previous !== value && typeof window !== 'undefined') {
      window.location.reload();
    }
  } catch {
    /* localStorage unavailable — ignore; nothing to persist. */
  }
}

/** Map a workflow run status to its translated label (falls back to raw). */
export function tStatus(status: string): string {
  const known = ['running', 'completed', 'failed', 'queued', 'cancelled', 'pending', 'unknown'];
  return known.includes(status) ? t(`workflow.status.${status}`) : t('workflow.status.unknown');
}
