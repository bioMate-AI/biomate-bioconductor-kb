/**
 * UI labels the server's prose must refer to EXACTLY as the user sees them. Read
 * from the client's own locale bundles so a reply can never name a button that
 * does not exist (2026-11-11: replies said "点击Run按钮" while the zh button reads
 * "确认并运行").
 */
import en from '../client/src/locales/en/common.json';
import zh from '../client/src/locales/zh/common.json';

type Lang = 'en' | 'zh' | undefined | null;

/** The panel's primary pre-run button ("Confirm & Run" / "确认并运行"). */
export function runButtonLabel(lang: Lang): string {
  const b = lang === 'zh' ? zh : en;
  return (b as any)?.workflow?.actions?.confirm_and_run || (lang === 'zh' ? '确认并运行' : 'Confirm & Run');
}
