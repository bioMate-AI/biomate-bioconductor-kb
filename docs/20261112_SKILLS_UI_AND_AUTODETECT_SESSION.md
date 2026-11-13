# 2026-11-12 — Skills UI + auto-detect (session biomate-review-72)

Branch: `feat/skills-architecture-20261111` · worktree: `biomate-syncprep-20261111`

## Delivered (pushed)

1. **Skills selector restructure** (`ba377712ef`) — three groups: Default
   (`biomate-universe`, locked-on) · BioMate experts · Your skills; foldable
   headers; descriptions line-clamped to 2 lines; EN/ZH i18n; 18 selector tests.
2. **Run-manager panel** (`f5ecc66e47`) — light amber (`bg-amber-50` + border)
   so it no longer blends into the blue muted chrome.
3. **Auto-detect when nothing explicit is selected** (`9d07eac4c1`) — root cause:
   locked `biomate-universe` was always injected into `skillPackIds`, so the
   server treated every send as an explicit override and skipped
   `/api/skills/detect` (and a project with `[]` applied *no* skills). Fix:
   - Client: send `skillPackIds` only when the user toggled non-default packs;
     re-attach `biomate-universe` on those explicit sends.
   - Server: `withDefaultSkill()` always merges `biomate-universe`; empty `[]`
     falls through to auto-detect instead of apply-none.
   - Tests: `chat-input.skill-autodetect.test.tsx` (2), `build-skill-block.test.ts` (4).

## Follow-up in this continuation

4. **Trim `generator-adaptation` UI description** — frontmatter `description`
   shortened to a two-line blurb; discrimination / routing stay in the skill
   body and in `operation-skills.ts` `whenToUse` (decomp path, still flag-gated
   OFF).

## Not done / gated

- **No side-branch `sync_to_dev.sh`** from this worktree — tracks deploys overwrite
  side-branch syncs (`docs/20261111_DEMO_FIXES_AND_SKILLS_SESSION.md`). Land via
  merge into the current integration/tracks line when that base is clear.
  (`origin/integration/tracks-20261111` was not fetchable at session end; local
  tracks worktree is divergent.)
- **`OPERATION_SKILLS_IN_DECOMP` stays OFF** until the formal judged decomp eval
  + off-twice noise baseline (`docs/20261111_SKILLS_ARCHITECTURE_TASK_HANDLING.md` §7).
- **Model-version-card** presentation over `reinvent4_finetune_rl` outputs — still open.
- **Evidence-Based Writer** skill + design committed; enforcement phases (citation
  semantic-fit, claim audit) not yet built.

## Verify

- `npx vitest run` on the new/related suites: skills-selector 18, skill-autodetect 2,
  build-skill-block 4 — green.
- `npx tsc --noEmit -p .` — clean.
