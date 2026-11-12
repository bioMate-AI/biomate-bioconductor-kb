/**
 * AddSkillForm — the "describe your own skill or expert" creation flow (design parity:
 * data_centroid_design_v2/dataui/Connectors.jsx ADD_CONNECTOR 'Skill or expert' —
 * "Something your team repeats … You describe it in your own words. It cannot change a parameter —
 * to change what runs, write it in a project's instructions.").
 *
 * The user names it, says what it does, and says what the expert should do each time; we generate a
 * valid Markdown-with-frontmatter skill file and POST it to /api/skills/upload — the same endpoint
 * the backend validates with `validate_skill_upload` (skill_manager.py). Private skills require
 * personal Galaxy access; the server returns 409 otherwise, which we surface honestly and never
 * bypass.
 */
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { useToast } from '@/hooks/use-toast';
import { Sparkles, Loader2 } from 'lucide-react';

/** kebab-case slug matching the backend rule `[a-z0-9]+(?:-[a-z0-9]+)*`, max 64 chars. Returns ''
 *  when the input yields nothing usable (caller treats that as "name required"). */
export function skillSlug(title: string): string {
  const s = title
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64)
    .replace(/-+$/, '');
  return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(s) ? s : '';
}

/** Stable fallback id when a title has no Latin letters/digits (e.g. Chinese), so a non-Latin name
 *  is still usable instead of blocking the user. Always matches the backend name regex. */
export function fallbackSlug(title: string): string {
  let h = 0;
  for (let i = 0; i < title.length; i++) h = (Math.imul(h, 31) + title.charCodeAt(i)) | 0;
  return `expert-${(h >>> 0).toString(36)}`;
}

/** The id the backend will store: a kebab-case slug, or a stable fallback for a non-Latin name. */
export function resolveSkillSlug(title: string): string {
  const t = title.trim();
  if (!t) return '';
  return skillSlug(t) || fallbackSlug(t);
}

// Strip control characters (keep tab/newline) — PyYAML's reader rejects DEL/other non-printables and
// fails the whole upload with an opaque "invalid YAML"; the user never typed anything that needs them.
const stripControl = (s: string): string => s.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '');
const splitCsv = (s: string): string[] => s.split(',').map((x) => stripControl(x).trim()).filter(Boolean);

/** Build a valid skill file. Every scalar/list is JSON-encoded — including `name` — so a colon,
 *  quote, or a YAML 1.1 magic token the user typed (yes/on/no/off/null/2024) can never break the
 *  frontmatter or be re-typed to a bool/int/None (which fails the backend's isinstance(name,str)
 *  check). YAML flow syntax is a superset of JSON. */
export function buildSkillMarkdown(opts: {
  slug: string; title: string; description: string; body: string; triggers: string[]; domains: string[];
}): string {
  const frontmatter = [
    '---',
    `name: ${JSON.stringify(opts.slug)}`,
    `title: ${JSON.stringify(stripControl(opts.title) || opts.slug)}`,
    `description: ${JSON.stringify(stripControl(opts.description))}`,
    `domains: ${JSON.stringify(opts.domains)}`,
    ...(opts.triggers.length ? [`triggers: ${JSON.stringify(opts.triggers)}`] : []),
    '---',
    '',
  ].join('\n');
  return frontmatter + stripControl(opts.body).trim() + '\n';
}

export function AddSkillForm({ onCreated }: { onCreated?: () => void }) {
  const { toast } = useToast();
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [body, setBody] = useState('');
  const [triggers, setTriggers] = useState('');
  const [domains, setDomains] = useState('');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');

  const slug = resolveSkillSlug(title);
  const canSave = !!slug && !!description.trim() && !!body.trim() && !saving;

  const save = async () => {
    setErr('');
    if (!slug) { setErr('Give it a name using letters or numbers.'); return; }
    if (!description.trim()) { setErr('Add a one-line description of what it does.'); return; }
    if (!body.trim()) { setErr('Describe what the expert should do each time.'); return; }
    setSaving(true);
    try {
      const content = buildSkillMarkdown({
        slug, title: title.trim(), description: description.trim(), body,
        // Drop 1-char triggers: a trigger like "a" auto-fires the expert on nearly every query.
        triggers: splitCsv(triggers).filter((t) => t.length >= 2), domains: splitCsv(domains),
      });
      const r = await fetch('/api/skills/upload', {
        method: 'POST', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content, filename: `${slug}.md` }),
      });
      const data = await r.json().catch(() => ({} as any));
      if (!r.ok || data?.success === false) {
        // `error` is normally a string, but a 422 (never from this form) carries a non-string detail;
        // guard so a bad shape can't crash the render.
        const msg = typeof data?.error === 'string' ? data.error : '';
        setErr(
          msg ||
          (r.status === 409
            ? 'This needs personal Galaxy access, or a skill with that name already exists.'
            : `Could not create the expert (${r.status}).`),
        );
        return;
      }
      toast({ title: 'Expert created', description: `"${title.trim()}" is now available under Skills & experts in the chat composer.` });
      setTitle(''); setDescription(''); setBody(''); setTriggers(''); setDomains('');
      onCreated?.();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Could not create the expert.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-3" data-testid="add-skill-form">
      <div>
        <h3 className="text-sm font-semibold flex items-center gap-2"><Sparkles className="w-4 h-4" /> Create a skill or expert</h3>
        <p className="text-xs text-muted-foreground mt-1">
          Something your team repeats — a section to draft, a fit to run, a figure to build, or a
          reading your specialists always apply. You describe it in your own words. It cannot change a
          parameter — to change what runs, write it in a project's instructions.
        </p>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">Name</Label>
        <Input className="h-8 text-xs" placeholder="e.g. Oncology report reviewer" value={title} onChange={(e) => setTitle(e.target.value)} data-testid="skill-title" />
        {title.trim() && (slug
          ? <p className="text-fs-xs text-muted-foreground">id: <code>{slug}</code></p>
          : <p className="text-fs-xs text-destructive">Use letters and numbers.</p>)}
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">What does it do?</Label>
        <Input className="h-8 text-xs" placeholder="One line — e.g. Reviews oncology write-ups for ICH E3 structure" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={1024} data-testid="skill-description" />
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs">What should the expert do each time?</Label>
        <Textarea className="text-xs" rows={4}
          placeholder={"In your own words, e.g.\n- Check every efficacy claim cites a table\n- Flag any dose not justified by the PK section\n- Prefer effect sizes over fold-change language"}
          value={body} onChange={(e) => setBody(e.target.value)} data-testid="skill-body" />
      </div>

      <details className="text-xs">
        <summary className="cursor-pointer text-muted-foreground select-none">Optional: trigger keywords &amp; domains</summary>
        <div className="space-y-2 mt-2">
          <div className="space-y-1"><Label className="text-xs">Trigger keywords (comma-separated)</Label><Input className="h-8 text-xs" placeholder="oncology, trial report, E3" value={triggers} onChange={(e) => setTriggers(e.target.value)} data-testid="skill-triggers" /></div>
          <div className="space-y-1"><Label className="text-xs">Domains (comma-separated)</Label><Input className="h-8 text-xs" placeholder="drug_discovery, clinical" value={domains} onChange={(e) => setDomains(e.target.value)} data-testid="skill-domains" /></div>
        </div>
      </details>

      {err && <p className="text-xs text-destructive" role="alert" data-testid="skill-error">{err}</p>}

      <Button size="sm" className="h-8 text-xs gap-1" disabled={!canSave} onClick={save} data-testid="skill-save">
        {saving ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Sparkles className="w-3.5 h-3.5" />}
        {saving ? 'Creating…' : 'Create expert'}
      </Button>
    </div>
  );
}

export default AddSkillForm;
