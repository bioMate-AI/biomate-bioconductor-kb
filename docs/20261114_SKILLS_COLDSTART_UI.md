# 2026-11-14 — Skills UI “fallback again” + cold-start attachment previews

## Root cause of “why the ui fallback again”

Not a runtime rendering fallback branch. The compact Skills & experts UI
(foldable groups + locked default + 2-line clamped descriptions) **was
landed** (`9bff602b6e` / `e93a461c16` / `ef6356502c`) and is reachable in
the commit DAG from live tip `8c946897dd`, but **sync merges kept the
ancestry tip while taking the other parent’s tree** for
`skills-selector.tsx` (and related files).

Documented drop merges:

| Merge | What happened |
|-------|----------------|
| `8c0663692f` `merge(sync): record deployed tip e93a461c … (keep PR398 voice settings tree)` | Parent `e93a461c16` had clamp; merge result kept PR398’s flat list (no `WebkitLineClamp`) |
| `429c3dbc52` `merge(dig): bring live tip …` | Same class: parent with clamp, result without |
| `007df6898e` on `fix/skills-restore-on-live` | Re-lost clamp when merging live tip onto the restore line |

Symptom: composer Skills & experts again showed **full skill frontmatter
prose** (especially `generator-adaptation`) instead of short blurbs +
line clamp — looking like a “fallback” UI even though the compact path
never ran.

## Fixes restored (this session)

1. **Compact skills selector** — `skills-selector.tsx`: Default group
   (`biomate-universe` locked + auto-preselected), BioMate experts /
   Your skills foldable groups, `WebkitLineClamp: 2` on descriptions.
2. **Top skill preselected** — `DEFAULT_SKILL_ID` exported; `useEffect`
   auto-adds `biomate-universe` when the pack is present.
3. **Short generator UI blurb** — `generator-adaptation.md` description
   trimmed; routing detail stays in the skill body /
   `operation-skills.ts`.
4. **Auto-detect contract** — composer omits `skillPackIds` when only
   the locked default is on; server `withDefaultSkill` always merges
   `biomate-universe` (`galaxy-assistant.ts` + `build-skill-block.test.ts`).
5. **Cold-start file previews** — example `File[]` injection keeps a
   stable applicator ref; preview allowlist includes cold-start formats
   (`smi`, `pdb`, `cif`, `faa`, …); chips get
   `data-testid="composer-attached-file-preview"`.
6. **Project skills card** — long descriptions `line-clamp-2` (title
   retains full text).

## Files changed

- `frontend/client/src/components/skills-selector.tsx` (+ test)
- `frontend/client/src/components/chat-input.tsx`
- `frontend/client/src/components/chat-input.skill-autodetect.test.tsx`
- `frontend/client/src/components/chat-input.example-files.test.tsx`
- `frontend/client/src/components/chat-interface.tsx`
- `frontend/client/src/components/project-guidance-cards.tsx`
- `frontend/client/src/locales/en/common.json`, `zh/common.json`
- `frontend/server/galaxy-assistant.ts`
- `frontend/server/build-skill-block.test.ts`
- `backend/lib/galaxy/ai/skills/generator-adaptation.md`
- `backend/lib/galaxy/ai/skills/evidence-based-writer.md`

## Verify in UI

1. New chat → open **Skills & experts**:
   - Default row locked/checked (`biomate-universe`).
   - Expert descriptions are **two lines max**, not a wall of prose.
   - Count shows at least **1 on** without a manual click.
2. Click a Data analysis / Design cold-start example that attaches files:
   - Composer shows `composer-attached-file` chips with sizes.
   - Click a chip name → dialog shows table/text content (CSV / SMI / PDB).
3. Send with only default skill on → request must **not** send
   `skillPackIds: ["biomate-universe"]` alone (auto-detect still runs).

## Tests

```bash
cd frontend && npx tsc --noEmit -p .
npx vitest run \
  client/src/components/skills-selector.test.tsx \
  client/src/components/chat-input.skill-autodetect.test.tsx \
  client/src/components/chat-input.example-files.test.tsx \
  server/build-skill-block.test.ts
```

## Sync note

Do **not** re-introduce ancestry-only merges that keep a skills tip SHA
while resolving `skills-selector.tsx` from the non-skills parent. Prefer
content-preserving merge / explicit restore of the files above.
See also `docs/20261113_FDR_AND_SKILLS_DIG_UPDATE.md` / sync ancestry gates.
