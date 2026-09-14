/**
 * Minimal i18n for on-premises deployments.
 *
 * When VITE_ONPREM=true the app shows Chinese labels on the sidebar and key UI
 * surfaces. SaaS builds (VITE_ONPREM unset) always get English.
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
  // ── Admin panel ──────────────────────────────────────────────────────────
  'System Dashboard': '系统管理面板',
  'Health': '服务状态',
  'LLM Configuration': '大模型配置',
};

const isOnPrem = typeof import.meta !== 'undefined'
  ? (import.meta as any).env?.VITE_ONPREM === 'true'
  : false;

export function t(key: string): string {
  if (!isOnPrem) return key;
  return ZH[key] ?? key;
}

export const onPrem = isOnPrem;
