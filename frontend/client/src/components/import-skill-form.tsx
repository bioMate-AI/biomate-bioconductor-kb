import { useState } from 'react';
import { tOr } from '@/lib/i18n';

/** Reuses the validated private-skill upload path; never replaces existing packs. */
export function ImportSkillForm({ onImported }: { onImported?: () => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState(false);
  return <div className="space-y-2 rounded-md border p-3" data-testid="import-skill-form">
    <label className="block text-sm font-medium">
      {tOr('connectors.import_skill', 'Import a skill file (.md)')}
      <input className="mt-2 block w-full text-xs" type="file" accept=".md,text/markdown" disabled={busy} onChange={async event => {
        const file = event.target.files?.[0];
        event.target.value = '';
        if (!file) return;
        setError(''); setDone(false);
        if (!/\.md$/i.test(file.name)) { setError(tOr('connectors.skill_markdown', 'Choose a Markdown (.md) skill file.')); return; }
        setBusy(true);
        try {
          const content = await file.text();
          const response = await fetch('/api/skills/upload', { method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content, filename: file.name }) });
          const data = await response.json().catch(() => ({}));
          if (!response.ok || data.success === false) throw new Error(typeof data.error === 'string' ? data.error : tOr('connectors.skill_import_failed', 'Could not import this skill. Check its frontmatter and your access.'));
          setDone(true); onImported?.();
        } catch (cause) { setError(cause instanceof Error ? cause.message : tOr('connectors.skill_import_failed', 'Could not import this skill. Check its frontmatter and your access.')); }
        finally { setBusy(false); }
      }} />
    </label>
    {busy && <p role="status" className="text-xs">{tOr('connectors.skill_importing', 'Importing skill…')}</p>}
    {done && <p role="status" className="text-xs">{tOr('connectors.skill_imported', 'Skill imported. It is available in Skills & experts.')}</p>}
    {error && <p role="alert" className="text-xs text-destructive break-words">{error}</p>}
  </div>;
}
