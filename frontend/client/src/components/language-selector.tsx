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
        onChange={(event) => {
          const value = event.target.value;
          if (value === 'english' || value === 'chinese') setLanguagePreference(value);
        }}
        className="min-w-0 flex-1 rounded border border-border bg-background px-1 py-1 text-xs"
      >
        <option value="english" lang="en">English</option>
        <option value="chinese" lang="zh-CN">简体中文</option>
        <optgroup label="Pending translation / 待翻译">
          <option value="japanese" lang="ja" disabled>日本語 — Pending / 待翻译</option>
          <option value="spanish" lang="es" disabled>Español — Pending / 待翻译</option>
          <option value="french" lang="fr" disabled>Français — Pending / 待翻译</option>
          <option value="german" lang="de" disabled>Deutsch — Pending / 待翻译</option>
        </optgroup>
      </select>
    </label>
  );
}
