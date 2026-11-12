/**
 * Folder that a chat's generated files (run_code outputs) are saved under in its project:
 * "<chat title> · <YYYY-MM-DD HH:mm>" (chat start, in the user's time zone).
 * Founder 2026-11-12: every chat wrote into one flat "分析结果" folder, so outputs of
 * different chats/runs could not be told apart and same-named files overwrote each other's
 * current version. One folder per chat fixes both (versioning is by full name).
 */
const UNSAFE = /[\/\\:*?"<>|\u0000-\u001f\u007f]+/g;
const MAX_TITLE = 30;

export function chatOutputFolderName(opts: {
  title?: string | null;
  createdAt?: Date | string | null;
  timeZone?: string | null;
  zh?: boolean;
}): string {
  const fallbackTitle = opts.zh ? '对话' : 'Chat';
  let title = String(opts.title || '').replace(UNSAFE, ' ').replace(/\s+/g, ' ').trim();
  if (!title || /^new chat$/i.test(title)) title = fallbackTitle;
  if (title.length > MAX_TITLE) title = `${title.slice(0, MAX_TITLE).trim()}…`;
  const when = opts.createdAt ? new Date(opts.createdAt) : new Date();
  return `${title} · ${formatStamp(Number.isNaN(when.getTime()) ? new Date() : when, opts.timeZone)}`;
}

/** "YYYY-MM-DD HH.mm" in the given IANA zone (UTC when unknown/invalid). A dot, not a colon:
 *  the name is also shown in download dialogs and zip entries, where ':' is not portable. */
export function formatStamp(d: Date, timeZone?: string | null): string {
  let tz = 'UTC';
  if (timeZone) {
    try { new Intl.DateTimeFormat('en-US', { timeZone }); tz = timeZone; } catch { /* invalid zone */ }
  }
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(d).map((p) => [p.type, p.value]));
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}.${parts.minute}`;
}
