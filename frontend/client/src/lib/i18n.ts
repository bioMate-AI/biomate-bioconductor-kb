/**
 * Minimal i18n for BioMate.
 *
 * Language detection order:
 *   1. Stored user preference in localStorage (biomate-user-settings.language)
 *   2. navigator.language (browser default)
 *   3. VITE_ONPREM=true build flag (on-prem defaults to Chinese)
 *   4. 'en' fallback
 *
 * Usage:
 *   import { t } from '@/lib/i18n'
 *   <span>{t('New Chat')}</span>
 */

const ZH: Record<string, string> = {
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

const isOnPrem = typeof import.meta !== 'undefined'
  ? (import.meta as any).env?.VITE_ONPREM === 'true'
  : false;

/** Read stored language preference from localStorage (set by user settings). */
function readStoredLocale(): string | null {
  try {
    const raw = typeof localStorage !== 'undefined'
      ? localStorage.getItem('biomate-user-settings')
      : null;
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return typeof parsed.language === 'string' ? parsed.language : null;
  } catch {
    return null;
  }
}

/** Normalise a BCP-47 tag to a 2-letter prefix ('zh-CN' → 'zh'). */
function langPrefix(tag: string): string {
  return tag.toLowerCase().split('-')[0];
}

/**
 * Detect whether the active locale is Chinese.
 * Priority: stored preference → navigator.language → VITE_ONPREM flag.
 */
function isChineseLocale(): boolean {
  const stored = readStoredLocale();
  if (stored) return langPrefix(stored) === 'zh';
  const nav = typeof navigator !== 'undefined' ? navigator.language : null;
  if (nav) return langPrefix(nav) === 'zh';
  return isOnPrem;
}

const useZh = isChineseLocale();

export function t(key: string): string {
  if (!useZh) return key;
  return ZH[key] ?? key;
}

export const onPrem = isOnPrem;
