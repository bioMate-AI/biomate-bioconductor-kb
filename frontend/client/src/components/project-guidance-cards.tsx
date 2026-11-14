import { t, tOr, locale } from '@/lib/i18n';
import { useEffect, useState, type CSSProperties } from 'react';
import { Button } from './ui/button';
import { Textarea } from './ui/textarea';
import { normalizeSkillPack, type SkillPack } from './skills-selector';
import { parseOutputFormats, exampleOutputFormats, appendMissingOutputFormats, type OutputFormat, type OutputFormatKind } from '@/lib/output-requirements';

/* ── Stream 4: project Instructions page (Rules · Output formats · Skills & experts · Memory) ──
   Appearance matches the data-centric prototype (claude_code_core/dataui/ProjectSetup.jsx):
   v2 design tokens, wrapped in [data-v2-ui]. Persistence reuses existing endpoints —
   rules ↔ PATCH /api/projects/:id {researchGoal}, formats/skills ↔ instruction-settings,
   notes ↔ persisted human-only notes-list; not assistant memory. */

type MemoryItem = { id: string; text: string; source?: string };

const S: Record<string, CSSProperties> = {
  card: { border: '1px solid var(--border)', borderRadius: 'var(--r-lg)', background: 'var(--bg-elev)', padding: '18px 20px', display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0, overflowWrap: 'anywhere' },
  k2: { fontSize: 'var(--fs-sm)', fontWeight: 600, letterSpacing: '0.05em', textTransform: 'uppercase', color: 'var(--text-muted)' },
  hint: { fontSize: 'var(--fs-base)', lineHeight: 1.5, color: 'var(--text-muted)' },
  row: { display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, minWidth: 0 },
  qline: { display: 'flex', flexWrap: 'wrap', alignItems: 'flex-start', gap: 10, padding: '9px 0', borderBottom: '1px solid var(--border)', minWidth: 0 },
  rulen: { width: 22, height: 22, flexShrink: 0, borderRadius: 999, background: 'var(--surface-2)', color: 'var(--text-muted)', fontSize: 'var(--fs-xs)', fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 1 },
  input: { flex: 1, minWidth: 0, height: 32, padding: '0 10px', fontSize: 'var(--fs-base)', color: 'var(--text)', background: 'var(--bg-elev)', border: '1px solid var(--border)', borderRadius: 'var(--r-sm)' },
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
  const examples = exampleOutputFormats(locale);
  const [rules, setRules] = useState<string[]>([]);
  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState<number | null>(null);
  const [formats, setFormats] = useState<OutputFormat[]>([]);
  const [formatEditor, setFormatEditor] = useState<{ index: number | null; value: OutputFormat } | null>(null);
  const [savingSettings, setSavingSettings] = useState(false);
  const [skills, setSkills] = useState<SkillPack[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [memory, setMemory] = useState<MemoryItem[]>([]);
  const [noteBusy, setNoteBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const parseRules = (t: string) => (t || '').split('\n').map(s => s.trim()).filter(Boolean);
  const parseFormats = (raw: string): OutputFormat[] => parseOutputFormats(raw);

  useEffect(() => { setRules(parseRules(instructions)); }, [instructions]);

  useEffect(() => {
    let cancelled = false; setLoading(true); setError('');
    Promise.all([
      fetch(`/api/projects/${projectId}/instruction-settings`, { credentials: 'include' }).then(r => r.ok ? r.json() : Promise.reject(new Error(t("project_instructions.load_error")))),
      fetch('/api/skills', { credentials: 'include' }).then(r => r.ok ? r.json() : { skills: [] }),
      fetch(`/api/projects/${projectId}/notes-list`, { credentials: 'include' }).then(r => r.ok ? r.json() : { notes: [] }).catch(() => ({ notes: [] })),
    ]).then(([settings, catalogue, notesRes]: any[]) => {
      if (cancelled) return;
      setSelected(settings.settings.skillPackIds ?? []);
      setFormats(parseFormats(settings.settings.outputRequirements ?? ''));
      setSkills((catalogue.skills ?? []).map(normalizeSkillPack));
      setMemory((notesRes.notes ?? []).map((n: any) => ({ id: String(n.id), text: String(n.content ?? ''), source: undefined })).filter((m: MemoryItem) => m.text));
    }).catch((e: Error) => { if (!cancelled) setError(e.message); }).finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [projectId]);

  async function saveRules(next: string[]) {
    setError('');
    try {
      const r = await fetch(`/api/projects/${projectId}`, { method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ researchGoal: next.join('\n') || null }) });
      if (!r.ok) throw new Error(t("project_instructions.rules_error"));
      setRules(next);
      onInstructionsSaved(next.join('\n'));
      // Let the composer (and anything keyed on project state) refetch so e.g. the instructions-chip
      // count reflects an added/removed rule without a reload — same event saveSettings dispatches.
      window.dispatchEvent(new Event('biomate:projects-updated'));
      return true;
    } catch (e) { setError(e instanceof Error ? e.message : t("project_instructions.rules_error")); return false; }
  }
  async function saveSettings(ids: string[], fmts: OutputFormat[]) {
    setSavingSettings(true); setError('');
    try {
      const r = await fetch(`/api/projects/${projectId}/instruction-settings`, { method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ skillPackIds: ids, outputRequirements: JSON.stringify(fmts) }) });
      if (!r.ok) throw new Error(t("instructions_formats.save_error"));
      setSelected(ids); setFormats(fmts);
      window.dispatchEvent(new Event('biomate:projects-updated'));
      return true;
    } catch (e) { setError(e instanceof Error ? e.message : t("project_instructions.settings_error")); return false; }
    finally { setSavingSettings(false); }
  }

  async function removeNote(noteId: string) {
    setNoteBusy(true); setError('');
    try {
      const response = await fetch(`/api/projects/${projectId}/notes-list/${encodeURIComponent(noteId)}`, { method: 'DELETE', credentials: 'include' });
      if (!response.ok) throw new Error(t("project_instructions.delete_note_error"));
      setMemory(items => items.filter(item => item.id !== noteId));
    } catch (e) { setError(e instanceof Error ? e.message : t("project_instructions.delete_note_error")); }
    finally { setNoteBusy(false); }
  }

  const addRule = async () => { const v = draft.trim(); if (!v) return; if (await saveRules([...rules, v])) setDraft(''); };
  const nFmtOn = formats.filter(f => f.on).length;

  return (
    <div data-v2-ui="true" style={{ maxWidth: 960, margin: '0 auto', padding: '24px 24px 48px', display: 'flex', flexDirection: 'column', gap: 16, color: 'var(--text)', fontFamily: 'var(--font-ui)' }}>
      {/* header */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ fontSize: 'var(--fs-sm)', color: 'var(--text-muted)' }}>{projectName} / {t("project_instructions.instructions")}</div>
        <div style={{ ...S.row, gap: 12 }}>
          <h2 style={{ margin: 0, fontSize: 'var(--fs-2xl)', fontWeight: 650, letterSpacing: '-0.02em' }}>{t("project_instructions.instructions")}</h2>
          <span className="chip" style={accChip}>{t("project_instructions.summary", { rules: rules.length, formats: nFmtOn })}</span>
          <span style={{ flex: 1 }} />
          <span style={S.hint}>{t("project_instructions.applies")}</span>
        </div>
      </div>
      {error && <p role="alert" style={{ fontSize: 'var(--fs-base)', color: 'var(--err)' }}>{error}</p>}

      {/* RULES */}
      <section style={S.card} data-testid="instructions-rules">
        <div style={S.row}><span style={S.k2}>{t("project_instructions.rules")}</span><span style={{ flex: 1 }} /><span style={S.hint}>{t("project_instructions.rules_hint")}</span></div>
        {rules.length > 0 && (
          <p style={{ ...S.hint, margin: 0 }} data-testid="rules-seed-hint">
            {tOr('project_instructions.rules_seed_hint', 'Rules shown here may be project defaults or examples — you can edit or remove any that don’t fit your work.')}
          </p>
        )}
        <div>
          {rules.map((r, i) => (
            <div key={i} style={S.qline}>
              <span style={S.rulen}>{i + 1}</span>
              {editing === i ? (
                <input style={S.input} autoFocus defaultValue={r}
                  onBlur={e => { const v = e.target.value.trim(); saveRules(v ? rules.map((y, j) => j === i ? v : y) : rules.filter((_, j) => j !== i)); setEditing(null); }}
                  onKeyDown={e => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }} />
              ) : (
                <span style={{ flex: 1, fontSize: 'var(--fs-base)', lineHeight: 1.5, cursor: canEdit ? 'text' : 'default' }} onClick={() => canEdit && setEditing(i)}>{r}</span>
              )}
              {canEdit && <button className="linkish" title={t("project_instructions.remove")} onClick={() => saveRules(rules.filter((_, j) => j !== i))}>{t("project_instructions.remove")}</button>}
            </div>
          ))}
          {rules.length === 0 && <span style={{ ...S.hint, display: 'block', padding: '6px 0' }}>{t("project_instructions.no_rules")}</span>}
        </div>
        {canEdit && (
          <div style={{ ...S.row, gap: 8 }}>
            <input style={S.input} placeholder={t("project_instructions.add_rule")} value={draft}
              onChange={e => setDraft(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') addRule(); }} data-testid="input-add-rule" />
            <button className="btn sm" onClick={addRule}>{t("project_instructions.add")}</button>
          </div>
        )}
      </section>

      {/* OUTPUT FORMATS */}
      <section style={S.card} data-testid="instructions-formats">
        <div style={S.row}><span style={S.k2}>{t("project_instructions.formats")}</span><span style={{ flex: 1 }} /><span style={S.hint}>{t("project_instructions.formats_hint")}</span></div>
        <div>
          {formats.map((f, i) => (
            <div key={i} style={{ ...S.qline, alignItems: 'center' }}>
              <Switch on={f.on} disabled={!canEdit || savingSettings || formatEditor !== null} title={t("instructions_formats.enable", { name: f.name })} onClick={() => saveSettings(selected, formats.map((x, j) => j === i ? { ...x, on: !x.on } : x))} />
              <span className="chip">{t(`project_instructions.kind_${f.kind}`)}</span>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, flex: 1, minWidth: 0 }}>
                <span style={{ fontSize: 'var(--fs-base)', fontWeight: 600 }}>{f.name}</span>
                {f.detail && <span style={S.hint}>{f.detail}</span>}
              </div>
              {canEdit && <button className="btn sm ghost" disabled={savingSettings || formatEditor !== null} onClick={() => setFormatEditor({ index: i, value: { ...f } })}>{t("instructions_formats.edit")}</button>}
              {canEdit && <button className="linkish" title={t("project_instructions.remove")} disabled={savingSettings || formatEditor !== null} onClick={() => saveSettings(selected, formats.filter((_, j) => j !== i))}>{t("project_instructions.remove")}</button>}
            </div>
          ))}
          {formats.length === 0 && <span style={{ ...S.hint, display: 'block', padding: '6px 0' }}>{t("project_instructions.no_formats")}</span>}
        </div>
        {/* TEMPLATE EXAMPLES — output requirements are hard to define from a blank field, so show
            concrete, editable examples of each kind (design: ProjectSetup.jsx `outputs`). "Use" adds
            one (switched OFF so it never silently takes effect until the user turns it on). */}
        {/* Examples are an onboarding aid for the empty/partial state. Once every
            example kind is already configured in the list above, this block is just a
            second copy of the same items — hide it so the list isn't duplicated
            (founder request: keep the list, not a duplicated examples panel). */}
        {canEdit && appendMissingOutputFormats(formats, examples).length > formats.length && (
          <div style={{ border: '1px dashed var(--border)', borderRadius: 'var(--r-md, 8px)', background: 'var(--bg)', padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 6 }} data-testid="instructions-formats-examples">
            <span style={{ ...S.hint, fontWeight: 600 }}>{t("project_instructions.examples")}</span>
            {examples.map((ex, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
                <span className="chip">{t(`project_instructions.kind_${ex.kind}`)}</span>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 1, flex: 1, minWidth: 0 }}>
                  <span style={{ fontSize: 'var(--fs-base)', fontWeight: 600 }}>{ex.name}</span>
                  <span style={S.hint}>{ex.detail}</span>
                </div>
                <button className="btn sm ghost" title={t("project_instructions.use_hint", { name: ex.name })} disabled={savingSettings || formatEditor !== null || appendMissingOutputFormats(formats, [ex]).length === formats.length} onClick={() => saveSettings(selected, appendMissingOutputFormats(formats, [ex]))}>{t("project_instructions.use")}</button>
              </div>
            ))}
            <button className="btn sm" style={{ alignSelf: 'flex-start', marginTop: 2 }} data-testid="formats-seed-examples" disabled={savingSettings || formatEditor !== null || appendMissingOutputFormats(formats, examples).length === formats.length} onClick={() => saveSettings(selected, appendMissingOutputFormats(formats, examples))}>{t("project_instructions.seed")}</button>
          </div>
        )}
        {canEdit && <button className="btn sm" style={{ alignSelf: 'flex-start' }} disabled={savingSettings || formatEditor !== null} onClick={() => setFormatEditor({ index: null, value: { kind: 'report', name: '', detail: '', on: false } })}>{t("project_instructions.add_format")}</button>}
      </section>

      {formatEditor && <section role="dialog" aria-label={t("instructions_formats.edit_title")} style={S.card}>
        <h3 style={{ margin: 0 }}>{t("instructions_formats.edit_title")}</h3>
        <label>{t("instructions_formats.name")}<input style={{ ...S.input, display: 'block', width: '100%' }} value={formatEditor.value.name} onChange={e => setFormatEditor({ ...formatEditor, value: { ...formatEditor.value, name: e.target.value } })} /></label>
        <label>{t("instructions_formats.kind")}<select style={{ ...S.input, display: 'block', width: '100%' }} value={formatEditor.value.kind} onChange={e => setFormatEditor({ ...formatEditor, value: { ...formatEditor.value, kind: e.target.value as OutputFormatKind } })}>{['report', 'figure', 'table', 'naming'].map(kind => <option key={kind} value={kind}>{t(`project_instructions.kind_${kind}`)}</option>)}</select></label>
        <label>{t("instructions_formats.requirements")}<Textarea value={formatEditor.value.detail} onChange={e => setFormatEditor({ ...formatEditor, value: { ...formatEditor.value, detail: e.target.value } })} /></label>
        <div style={S.row}><button className="btn sm" disabled={savingSettings || !formatEditor.value.name.trim()} onClick={async () => {
          const value = { ...formatEditor.value, name: formatEditor.value.name.trim(), detail: formatEditor.value.detail.trim() };
          const next = formatEditor.index === null ? [...formats, value] : formats.map((f, i) => i === formatEditor.index ? value : f);
          if (await saveSettings(selected, next)) setFormatEditor(null);
        }}>{savingSettings ? t("instructions_formats.saving") : t("instructions_formats.save")}</button><button className="btn sm ghost" disabled={savingSettings} onClick={() => setFormatEditor(null)}>{t("instructions_formats.cancel")}</button></div>
      </section>}

      {/* SKILLS & EXPERTS */}
      <section style={S.card} data-testid="instructions-skills">
        <div style={S.row}>
          <span style={S.k2}>{t("project_instructions.skills")}</span>
          <span className="chip" style={selected.length ? accChip : undefined}>{t("project_instructions.selected", { count: selected.length })}</span>
          <span style={{ flex: 1 }} />
          <a className="linkish" href="/settings/connections?tab=skills">{t("project_instructions.manage")}</a>
        </div>
        {loading ? <span style={S.hint}>{t("project_instructions.loading_skills")}</span> : !skills.length ? <span style={S.hint}>{t("project_instructions.no_skills")}</span> : (
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {skills.map(skill => {
              const on = selected.includes(skill.id);
              return (
                <button key={skill.id} className="chip" aria-pressed={on} title={skill.description}
                  disabled={!canEdit || savingSettings}
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
          <span style={S.k2}>{t("project_instructions.memory")}</span><span className="chip">{memory.length}</span>
          <span style={{ flex: 1 }} />
        </div>
        <div>
          {memory.map((m, i) => (
            <div key={m.id} style={S.qline}>
              <span style={{ flex: 1, fontSize: 'var(--fs-base)', lineHeight: 1.5 }}>{m.text}{m.source && <span style={{ ...S.hint, marginLeft: 8 }}>· {m.source}</span>}</span>
              {canEdit && <button className="linkish" disabled={noteBusy} onClick={async () => { setNoteBusy(true); try { await saveRules(rules.includes(m.text) ? rules : [...rules, m.text]); } finally { setNoteBusy(false); } }}>{t("project_instructions.make_rule")}</button>}
              {canEdit && <button className="linkish" disabled={noteBusy} onClick={() => removeNote(m.id)}>{t("project_instructions.forget")}</button>}
            </div>
          ))}
          {memory.length === 0 && <span style={{ ...S.hint, display: 'block', padding: '6px 0' }}>{t("project_instructions.no_memory")}</span>}
        </div>
        <span style={S.hint}>{t("project_instructions.memory_note")}</span>
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
      fetch(`/api/projects/${projectId}/instruction-settings`, { credentials: 'include' }).then(async r => { if (!r.ok) throw new Error(t("project_instructions.load_error")); return r.json(); }),
      fetch('/api/skills', { credentials: 'include' }).then(async r => { if (!r.ok) throw new Error(t("project_instructions.load_skills_error")); return r.json(); }),
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
      if (!r.ok) throw new Error(t("project_instructions.save_project_error"));
      setSelected(ids); setSavedOutputs(requirements); setEditing(false);
      window.dispatchEvent(new Event('biomate:projects-updated'));
    } catch (e) { setError(e instanceof Error ? e.message : t("project_instructions.settings_error")); }
    finally { setSaving(false); }
  }
  return <>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <section className="rounded-lg border border-border p-5 space-y-3" data-testid="project-output-requirements">
      <div className="flex items-center justify-between gap-3"><h3 className="font-medium text-sm">{t("project_instructions.output_requirements")}</h3>{canEdit && <Button size="sm" variant="outline" disabled={loading || saving} onClick={() => { setOutputs(savedOutputs); setEditing(!editing); }}>{editing ? t("instructions_formats.cancel") : t("instructions_formats.edit")}</Button>}</div>
      <p className="text-xs text-muted-foreground">{t("project_instructions.output_hint")}</p>
      {editing ? <><Textarea aria-label={t("project_instructions.output_requirements")} maxLength={3000} value={outputs} onChange={e => setOutputs(e.target.value)} placeholder={t("project_instructions.output_placeholder")} /><Button size="sm" disabled={saving} onClick={() => save(selected, outputs)}>{t("project_instructions.save_requirements")}</Button></> : <p className="text-sm whitespace-pre-wrap">{savedOutputs || t("project_instructions.no_requirements")}</p>}
    </section>
    <section className="rounded-lg border border-border p-5 space-y-3" data-testid="project-skills-card">
      <div className="flex flex-wrap items-center gap-2"><h3 className="font-medium text-sm">{t("project_instructions.skills")}</h3><span className="text-xs text-muted-foreground">{t("project_instructions.selected", { count: selected.length })}</span><a className="text-xs text-primary ml-auto" href="/settings/connections?tab=skills">{t("project_instructions.manage_account")}</a></div>
      <p className="text-xs text-muted-foreground">{t("project_instructions.skills_hint")}</p>
      {loading ? <p className="text-sm text-muted-foreground">{t("project_instructions.loading_skills")}</p> : !skills.length ? <p className="text-sm text-muted-foreground">{t("project_instructions.no_skills")}</p> : <div>{skills.map(skill => <label key={skill.id} className="flex items-start gap-3 py-3 border-b border-border last:border-0 cursor-pointer"><input type="checkbox" role="switch" aria-label={skill.label} checked={selected.includes(skill.id)} disabled={!canEdit || saving} onChange={e => save(e.target.checked ? [...selected, skill.id] : selected.filter(id => id !== skill.id), savedOutputs)} /><span className="text-sm min-w-0 break-words">{skill.label}{skill.description && <span className="block text-xs text-muted-foreground mt-1 line-clamp-2" title={skill.description}>{skill.description}</span>}</span></label>)}</div>}
    </section>

  </>;
}

export function ProjectInheritanceCard({ onOpenFiles }: { onOpenFiles: () => void }) {
  return (<section className="rounded-lg border border-border p-5 space-y-3" data-testid="project-inheritance-card"><h3 className="font-medium text-sm">{t("project_instructions.inherits")}</h3><p className="text-xs text-muted-foreground">{t("project_instructions.inherits_hint")}</p><Button size="sm" variant="outline" onClick={onOpenFiles}>{t("project_instructions.see_data")}</Button></section>);
}
