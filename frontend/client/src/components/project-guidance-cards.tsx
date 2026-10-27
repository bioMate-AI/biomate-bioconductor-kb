import { useEffect, useState, type CSSProperties } from 'react';
import { Button } from './ui/button';
import { Textarea } from './ui/textarea';
import { normalizeSkillPack, type SkillPack } from './skills-selector';

/* ── Stream 4: project Instructions page (Rules · Output formats · Skills & experts · Memory) ──
   Appearance matches the data-centric prototype (claude_code_core/dataui/ProjectSetup.jsx):
   v2 design tokens, wrapped in [data-v2-ui]. Persistence reuses existing endpoints —
   rules ↔ PATCH /api/projects/:id {researchGoal}, formats/skills ↔ instruction-settings,
   memory ↔ local stub seeded from notes-list. */

type OutputFormat = { kind: 'report' | 'figure' | 'table' | 'naming'; name: string; detail: string; on: boolean };
type MemoryItem = { id: string; text: string; source?: string };

const S: Record<string, CSSProperties> = {
  card: { border: '1px solid var(--border)', borderRadius: 'var(--r-lg)', background: 'var(--bg-elev)', padding: '18px 20px', display: 'flex', flexDirection: 'column', gap: 8 },
  k2: { fontSize: 12, fontWeight: 600, letterSpacing: '0.05em', textTransform: 'uppercase', color: 'var(--text-muted)' },
  hint: { fontSize: 12.5, lineHeight: 1.5, color: 'var(--text-muted)' },
  row: { display: 'flex', alignItems: 'center', gap: 8 },
  qline: { display: 'flex', alignItems: 'flex-start', gap: 10, padding: '9px 0', borderBottom: '1px solid var(--border)' },
  rulen: { width: 22, height: 22, flexShrink: 0, borderRadius: 999, background: 'var(--surface-2)', color: 'var(--text-muted)', fontSize: 11, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 1 },
  input: { flex: 1, minWidth: 0, height: 32, padding: '0 10px', fontSize: 13, color: 'var(--text)', background: 'var(--bg-elev)', border: '1px solid var(--border)', borderRadius: 'var(--r-sm)' },
};

function Switch({ on, onClick, disabled, title }: { on: boolean; onClick: () => void; disabled?: boolean; title?: string }) {
  return (
    <button type="button" role="switch" aria-checked={on} title={title} disabled={disabled} onClick={onClick}
      style={{ width: 34, height: 20, flexShrink: 0, borderRadius: 999, border: 'none', padding: 2, cursor: disabled ? 'not-allowed' : 'pointer', background: on ? 'var(--accent)' : 'var(--surface-3)', transition: 'background .15s', opacity: disabled ? 0.5 : 1 }}>
      <span style={{ display: 'block', width: 16, height: 16, borderRadius: 999, background: '#fff', boxShadow: '0 1px 2px rgba(15,23,42,0.2)', transform: on ? 'translateX(14px)' : 'translateX(0)', transition: 'transform .15s' }} />
    </button>
  );
}

const accChip: CSSProperties = { background: 'var(--accent-soft)', color: 'var(--accent-ink)' };

export function ProjectInstructionsPage({ projectId, projectName, canEdit, instructions, onInstructionsSaved }: {
  projectId: string; projectName: string; canEdit: boolean; instructions: string; onInstructionsSaved: (text: string) => void;
}) {
  const [rules, setRules] = useState<string[]>([]);
  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState<number | null>(null);
  const [formats, setFormats] = useState<OutputFormat[]>([]);
  const [skills, setSkills] = useState<SkillPack[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [memory, setMemory] = useState<MemoryItem[]>([]);
  const [memoryOn, setMemoryOn] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const parseRules = (t: string) => (t || '').split('\n').map(s => s.trim()).filter(Boolean);
  const parseFormats = (raw: string): OutputFormat[] => {
    if (!raw) return [];
    try { const j = JSON.parse(raw); if (Array.isArray(j)) return j.filter(f => f && f.name).map(f => ({ kind: f.kind || 'report', name: String(f.name), detail: String(f.detail || ''), on: f.on !== false })); } catch { /* legacy free text */ }
    return [{ kind: 'report', name: 'Output requirements', detail: raw, on: true }];
  };

  useEffect(() => { setRules(parseRules(instructions)); }, [instructions]);

  useEffect(() => {
    let cancelled = false; setLoading(true); setError('');
    Promise.all([
      fetch(`/api/projects/${projectId}/instruction-settings`, { credentials: 'include' }).then(r => r.ok ? r.json() : Promise.reject(new Error('Could not load project settings.'))),
      fetch('/api/skills', { credentials: 'include' }).then(r => r.ok ? r.json() : { skills: [] }),
      fetch(`/api/projects/${projectId}/notes-list`, { credentials: 'include' }).then(r => r.ok ? r.json() : { notes: [] }).catch(() => ({ notes: [] })),
    ]).then(([settings, catalogue, notesRes]: any[]) => {
      if (cancelled) return;
      setSelected(settings.settings.skillPackIds ?? []);
      setFormats(parseFormats(settings.settings.outputRequirements ?? ''));
      setSkills((catalogue.skills ?? []).map(normalizeSkillPack));
      setMemory((notesRes.notes ?? []).map((n: any) => ({ id: String(n.id), text: String(n.content ?? ''), source: n.createdAt ? 'from a chat' : undefined })).filter((m: MemoryItem) => m.text));
    }).catch((e: Error) => { if (!cancelled) setError(e.message); }).finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [projectId]);

  async function saveRules(next: string[]) {
    setRules(next);
    try {
      const r = await fetch(`/api/projects/${projectId}`, { method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ researchGoal: next.join('\n') || null }) });
      if (!r.ok) throw new Error('Could not save rules.');
      onInstructionsSaved(next.join('\n'));
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not save rules.'); }
  }
  async function saveSettings(ids: string[], fmts: OutputFormat[]) {
    setSelected(ids); setFormats(fmts);
    try {
      const r = await fetch(`/api/projects/${projectId}/instruction-settings`, { method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ skillPackIds: ids, outputRequirements: JSON.stringify(fmts) }) });
      if (!r.ok) throw new Error('Could not save settings.');
      window.dispatchEvent(new Event('biomate:projects-updated'));
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not save settings.'); }
  }

  const addRule = () => { const v = draft.trim(); if (!v) return; saveRules([...rules, v]); setDraft(''); };
  const nFmtOn = formats.filter(f => f.on).length;

  return (
    <div data-v2-ui="true" style={{ maxWidth: 960, margin: '0 auto', padding: '24px 24px 48px', display: 'flex', flexDirection: 'column', gap: 16, color: 'var(--text)', fontFamily: 'var(--font-ui)' }}>
      {/* header */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{projectName} / Instructions</div>
        <div style={{ ...S.row, gap: 12 }}>
          <h2 style={{ margin: 0, fontSize: 24, fontWeight: 650, letterSpacing: '-0.02em' }}>Instructions</h2>
          <span className="chip" style={accChip}>{rules.length} rule{rules.length === 1 ? '' : 's'} · {nFmtOn} format{nFmtOn === 1 ? '' : 's'} on</span>
          <span style={{ flex: 1 }} />
          <span style={S.hint}>Applies to every chat and run in this project.</span>
        </div>
      </div>
      {error && <p role="alert" style={{ fontSize: 13, color: 'var(--err)' }}>{error}</p>}

      {/* RULES */}
      <section style={S.card} data-testid="instructions-rules">
        <div style={S.row}><span style={S.k2}>Rules</span><span style={{ flex: 1 }} /><span style={S.hint}>The agent reads these at the start of every session.</span></div>
        <div>
          {rules.map((r, i) => (
            <div key={i} style={S.qline}>
              <span style={S.rulen}>{i + 1}</span>
              {editing === i ? (
                <input style={S.input} autoFocus defaultValue={r}
                  onBlur={e => { const v = e.target.value.trim(); saveRules(v ? rules.map((y, j) => j === i ? v : y) : rules.filter((_, j) => j !== i)); setEditing(null); }}
                  onKeyDown={e => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }} />
              ) : (
                <span style={{ flex: 1, fontSize: 13.5, lineHeight: 1.5, cursor: canEdit ? 'text' : 'default' }} onClick={() => canEdit && setEditing(i)}>{r}</span>
              )}
              {canEdit && <button className="linkish" title="Remove" onClick={() => saveRules(rules.filter((_, j) => j !== i))}>Remove</button>}
            </div>
          ))}
          {rules.length === 0 && <span style={{ ...S.hint, display: 'block', padding: '6px 0' }}>No rules yet. Anything you add applies to every session.</span>}
        </div>
        {canEdit && (
          <div style={{ ...S.row, gap: 8 }}>
            <input style={S.input} placeholder={'Add a rule, e.g. “Use GRCh38 unless a session says otherwise”'} value={draft}
              onChange={e => setDraft(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') addRule(); }} data-testid="input-add-rule" />
            <button className="btn sm" onClick={addRule}>Add</button>
          </div>
        )}
      </section>

      {/* OUTPUT FORMATS */}
      <section style={S.card} data-testid="instructions-formats">
        <div style={S.row}><span style={S.k2}>Output formats</span><span style={{ flex: 1 }} /><span style={S.hint}>Reports, figures and tables are written to the ones that are on.</span></div>
        <div>
          {formats.map((f, i) => (
            <div key={i} style={{ ...S.qline, alignItems: 'center' }}>
              <Switch on={f.on} disabled={!canEdit} onClick={() => saveSettings(selected, formats.map((x, j) => j === i ? { ...x, on: !x.on } : x))} />
              <span className="chip">{f.kind}</span>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, flex: 1, minWidth: 0 }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>{f.name}</span>
                {f.detail && <span style={S.hint}>{f.detail}</span>}
              </div>
              <button className="btn sm ghost" onClick={() => setError(`Preview builds from your last run · ${f.name}`)}>Preview</button>
              {canEdit && <button className="linkish" title="Remove" onClick={() => saveSettings(selected, formats.filter((_, j) => j !== i))}>Remove</button>}
            </div>
          ))}
          {formats.length === 0 && <span style={{ ...S.hint, display: 'block', padding: '6px 0' }}>No formats yet.</span>}
        </div>
        {canEdit && <button className="btn sm" style={{ alignSelf: 'flex-start' }} onClick={() => saveSettings(selected, [...formats, { kind: 'report', name: 'New format', detail: 'Describe the template', on: true }])}>+ Add a format</button>}
      </section>

      {/* SKILLS & EXPERTS */}
      <section style={S.card} data-testid="instructions-skills">
        <div style={S.row}>
          <span style={S.k2}>Skills &amp; experts</span>
          <span className="chip" style={selected.length ? accChip : undefined}>{selected.length ? `${selected.length} on` : 'none on'}</span>
          <span style={{ flex: 1 }} />
          <a className="linkish" href="/settings/connections?tab=skills">manage in Connectors →</a>
        </div>
        {loading ? <span style={S.hint}>Loading skills…</span> : !skills.length ? <span style={S.hint}>No skills available.</span> : (
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {skills.map(skill => {
              const on = selected.includes(skill.id);
              return (
                <button key={skill.id} className="chip" aria-pressed={on} title={skill.description}
                  disabled={!canEdit}
                  style={{ cursor: canEdit ? 'pointer' : 'default', border: on ? '1px solid transparent' : '1px dashed var(--border-strong)', ...(on ? accChip : {}) }}
                  onClick={() => canEdit && saveSettings(on ? selected.filter(id => id !== skill.id) : [...selected, skill.id], formats)}>
                  {skill.label}
                </button>
              );
            })}
          </div>
        )}
      </section>

      {/* MEMORY */}
      <section style={S.card} data-testid="instructions-memory">
        <div style={S.row}>
          <span style={S.k2}>Memory</span><span className="chip">{memory.length}</span>
          <span style={{ flex: 1 }} />
          <span style={{ ...S.hint, marginRight: 4 }}>Facts BioMate keeps between chats in this project.</span>
          <Switch on={memoryOn} disabled={!canEdit} title="Remember from chats" onClick={() => setMemoryOn(v => !v)} />
        </div>
        <div style={{ opacity: memoryOn ? 1 : 0.5 }}>
          {memory.map((m, i) => (
            <div key={m.id} style={S.qline}>
              <span style={{ flex: 1, fontSize: 13.5, lineHeight: 1.5 }}>{m.text}{m.source && <span style={{ ...S.hint, marginLeft: 8 }}>· {m.source}</span>}</span>
              {canEdit && <button className="linkish" onClick={() => { saveRules([...rules, m.text]); setMemory(x => x.filter((_, j) => j !== i)); }}>Make a rule</button>}
              {canEdit && <button className="linkish" onClick={() => setMemory(x => x.filter((_, j) => j !== i))}>Forget</button>}
            </div>
          ))}
          {memory.length === 0 && <span style={{ ...S.hint, display: 'block', padding: '6px 0' }}>Nothing remembered yet. BioMate saves a line when you correct it or state a preference; you can forget any of them.</span>}
        </div>
        <span style={S.hint}>Memory is context the agent may use. A rule is a requirement it must follow — promote a memory when it should be one.</span>
      </section>
    </div>
  );
}

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
