# Skills + cold-start UI restore (2026-11-14)

## User complaints

1. Skills set showing **long descriptions** again (“why the ui fallback again”)
2. Top / default skill not preselected when the set opens
3. Cold-start examples that attach files show **no file preview** (unlike normal uploads)

## Root cause — “fallback again”

Not a separate runtime “fallback renderer.” The compact Skills & experts UI
(foldable groups + 2-line clamp + locked `biomate-universe`) and the short
`generator-adaptation` frontmatter **were landed** (`9bff602b6e` /
`e93a461c16` / `ef6356502c`) but later **ours-style sync merges kept ancestry
tips while dropping the tree content**:

| Merge | Effect |
|-------|--------|
| `8c0663692f` `merge(sync): record deployed tip e93a461c … (keep PR398 voice settings tree)` | Parent² had clamp + short desc; merge result kept PR398 flat list + long desc |
| Later dig/sync merges (e.g. `429c3dbc52`) | Same pattern: clamp present on one parent, absent in result |
| `007df6898e` on `fix/skills-restore-on-live` | Re-dropped clamp again when bringing live tip `8c946897dd` |

So live/local tip could **claim** the restore commit as an ancestor while the
deployed `skills-selector.tsx` was still the verbose flat list. That is the
“fallback again” the user saw.

## Fixes

| Area | Change |
|------|--------|
| Composer Skills & experts | Restore groups (Default / BioMate experts / Your skills), `WebkitLineClamp: 2`, locked default auto-selected |
| `generator-adaptation.md` | Short UI blurb again (routing detail stays in body / `operation-skills.ts`) |
| Send path | Omit default-only `skillPackIds` so server auto-detects; always merge `biomate-universe` server-side (`withDefaultSkill`) |
| Project skills card | `line-clamp-2` on descriptions (same wall-of-prose class) |
| Cold-start attach preview | Stable example-file applicator ref; preview text exts include `smi`/`pdb`/`cif`/…; chips get `data-demo` + preview testid |

## Files changed

- `frontend/client/src/components/skills-selector.tsx` (+ test)
- `frontend/client/src/components/chat-input.tsx` (+ `skill-autodetect` / `example-files` tests)
- `frontend/client/src/components/chat-interface.tsx` (example-files registration comment)
- `frontend/client/src/components/project-guidance-cards.tsx`
- `frontend/client/src/locales/en/common.json`, `zh/common.json`
- `frontend/server/galaxy-assistant.ts`, `build-skill-block.test.ts`
- `backend/lib/galaxy/ai/skills/generator-adaptation.md`
- `backend/lib/galaxy/ai/skills/evidence-based-writer.md` (restored with skills land)

## How to verify in UI

1. **Compact skills** — New Chat → composer **Skills & experts** → popover shows
   Default (locked) + foldable BioMate experts; descriptions are ≤2 lines, not a
   wall of prose (esp. Generator Adaptation).
2. **Preselect** — Opening the popover with an empty project selection shows
   Default on (`· 1 on`); `biomate-universe` cannot be toggled off.
3. **Cold-start previews** — Data analysis → pick an example with sample data
   (e.g. ADMET / DESeq2 airway) → composer shows `composer-attached-file` chips
   → click the filename → dialog shows table/text content (not metadata-only for
   csv/smi/pdb).

## Tests

```bash
cd frontend && npx vitest run \
  client/src/components/skills-selector.test.tsx \
  client/src/components/chat-input.skill-autodetect.test.tsx \
  client/src/components/chat-input.example-files.test.tsx \
  server/build-skill-block.test.ts
# 26 passed
cd frontend && npx tsc --noEmit -p .
```

## Sync note

Ancestry-only sync merges that “record deployed tip X (keep Y tree)” will drop
this UI again unless the **tree** for `skills-selector.tsx` /
`generator-adaptation.md` is preserved. Prefer content-preserving merge (or
cherry-pick this restore) over tip-recording ours merges.
