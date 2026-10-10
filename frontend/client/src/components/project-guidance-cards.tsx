import { useEffect, useState } from 'react';
import { Button } from './ui/button';
import { Textarea } from './ui/textarea';
import { normalizeSkillPack, type SkillPack } from './skills-selector';

export function ProjectGuidanceCards({ projectId, canEdit, onOpenFiles }: { projectId: string; canEdit: boolean; onOpenFiles: () => void }) {
  const [skills, setSkills] = useState<SkillPack[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [outputs, setOutputs] = useState('');
  const [savedOutputs, setSavedOutputs] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [editing, setEditing] = useState(false);
  useEffect(() => {
    let cancelled = false;
    setLoading(true); setError(''); setEditing(false);
    Promise.all([
      fetch(`/api/projects/${projectId}/instruction-settings`, { credentials: 'include' }).then(async r => { if (!r.ok) throw new Error('Could not load project settings.'); return r.json(); }),
      fetch('/api/skills', { credentials: 'include' }).then(async r => { if (!r.ok) throw new Error('Could not load skills.'); return r.json(); }),
    ]).then(([data, catalogue]) => {
      if (cancelled) return;
      setSelected(data.settings.skillPackIds); setOutputs(data.settings.outputRequirements); setSavedOutputs(data.settings.outputRequirements);
      setSkills((catalogue.skills ?? []).map(normalizeSkillPack));
    }).catch(e => { if (!cancelled) setError(e.message); }).finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [projectId]);
  async function save(ids: string[], requirements: string) {
    setSaving(true); setError('');
    try {
      const r = await fetch(`/api/projects/${projectId}/instruction-settings`, { method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ skillPackIds: ids, outputRequirements: requirements }) });
      if (!r.ok) throw new Error('Could not save project settings. Please retry.');
      setSelected(ids); setSavedOutputs(requirements); setEditing(false);
      window.dispatchEvent(new Event('biomate:projects-updated'));
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not save settings.'); }
    finally { setSaving(false); }
  }
  return <>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <section className="rounded-lg border border-border p-5 space-y-3" data-testid="project-output-requirements">
      <div className="flex items-center justify-between gap-3"><h3 className="font-medium text-sm">Output requirements</h3>{canEdit && <Button size="sm" variant="outline" disabled={loading || saving} onClick={() => { setOutputs(savedOutputs); setEditing(!editing); }}>{editing ? 'Cancel' : 'Edit'}</Button>}</div>
      <p className="text-xs text-muted-foreground">Report sections, figure specifications and naming conventions for work in this project.</p>
      {editing ? <><Textarea aria-label="Output requirements" maxLength={3000} value={outputs} onChange={e => setOutputs(e.target.value)} placeholder="Describe your required report sections, figures and file names…" /><Button size="sm" disabled={saving} onClick={() => save(selected, outputs)}>Save requirements</Button></> : <p className="text-sm whitespace-pre-wrap">{savedOutputs || 'No output requirements yet.'}</p>}
    </section>
    <section className="rounded-lg border border-border p-5 space-y-3" data-testid="project-skills-card">
      <div className="flex flex-wrap items-center gap-2"><h3 className="font-medium text-sm">Skills &amp; experts</h3><span className="text-xs text-muted-foreground">{selected.length} on</span><a className="text-xs text-primary ml-auto" href="/settings/connections?tab=skills">Manage account skills →</a></div>
      <p className="text-xs text-muted-foreground">Available to your account, switched on for this project. A chat can change the selection for one question.</p>
      {loading ? <p className="text-sm text-muted-foreground">Loading skills…</p> : !skills.length ? <p className="text-sm text-muted-foreground">No skills available.</p> : <div>{skills.map(skill => <label key={skill.id} className="flex items-start gap-3 py-3 border-b border-border last:border-0 cursor-pointer"><input type="checkbox" role="switch" aria-label={skill.label} checked={selected.includes(skill.id)} disabled={!canEdit || saving} onChange={e => save(e.target.checked ? [...selected, skill.id] : selected.filter(id => id !== skill.id), savedOutputs)} /><span className="text-sm min-w-0 break-words">{skill.label}{skill.description && <span className="block text-xs text-muted-foreground mt-1">{skill.description}</span>}</span></label>)}</div>}
    </section>

  </>;
}

export function ProjectInheritanceCard({ onOpenFiles }: { onOpenFiles: () => void }) {
  return (<section className="rounded-lg border border-border p-5 space-y-3" data-testid="project-inheritance-card"><h3 className="font-medium text-sm">What inherits this</h3><p className="text-xs text-muted-foreground">Chats in this project inherit standing instructions, output requirements, and selected skills. New requests use the current settings; completed runs keep their recorded context.</p><Button size="sm" variant="outline" onClick={onOpenFiles}>See the project’s data →</Button></section>);
}
