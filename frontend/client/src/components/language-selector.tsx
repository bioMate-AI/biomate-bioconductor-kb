import { Languages } from "lucide-react";
import { locale, setLanguagePreference } from "@/lib/i18n";

/** Both languages share this UI; changing language changes only the translation bundle. */
export function LanguageSelector() {
  return (
    <label className="flex items-center gap-2 min-w-0" style={{ padding: '5px 10px', fontSize: 12, color: 'var(--bm-text-muted)' }}>
      <Languages className="w-3.5 h-3.5 shrink-0" aria-hidden="true" />
      <span className="shrink-0">Language / 语言</span>
      <select
        aria-label="Language / 语言"
        data-testid="language-selector"
        value={locale === 'zh' ? 'chinese' : 'english'}
        onChange={(event) => setLanguagePreference(event.target.value)}
        className="min-w-0 flex-1 rounded border border-border bg-background px-1 py-1 text-xs"
      >
        <option value="english" lang="en">English</option>
        <option value="chinese" lang="zh-CN">简体中文</option>
      </select>
    </label>
  );
}
