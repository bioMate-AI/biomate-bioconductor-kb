# Design-conformance audit + committee-review fixes — living session doc

Date 2026-11-05 → 2026-11-06. Branch `cursor/tutorial-live-recording-and-report-editing-4ea7`.
This is the living master doc for two interleaved workstreams: (A) finishing the findings
document-as-truth cutover prep + a multi-model committee review of those changes, and (B) a
design-conformance audit of the composer **instruction panel** and the **add-connector button**,
with the fixes shipped from it. Continuously updated; newest status at the bottom of each section.

All changes are committed, pushed, and deployed to dev (`https://dev-public.biomate.ai`). Gate for
every change: `cd frontend && npx tsc --noEmit -p . && npx vitest run` (green), then
`scripts/sync_to_dev.sh` (result=healthy), then a live read-only check where applicable.

---

## A. Findings cutover prep + committee review (2026-11-05)

### A.1 Per-domain descriptor parity (all 4 parser domains)
Goal: make the entity-aware `findings_document` (`documentToLegacy`) reach parity with the
deterministic parser flat, so the document can become the single verdict source (delete
`reconcileFindingsDocument`) — the "document-as-truth" cutover. Status gate = the live shadow in
`routes.ts` (`[Findings][shadow] … cutover-safe / cutover-ready / BLOCKED`).

| Domain | Parser today | Result | Commit |
|---|---|---|---|
| ADMET | deterministic flat | 16 metrics incl. all liabilities | `84577b8e1`, `466893371` |
| DESeq2 | deterministic flat | 32 real ENSG ids (TSV+CSV) | `84577b8e1` |
| enrichGO | LLM context only (no flat) | 12 GO terms w/ p.adjust/GeneRatio/Count — pure upgrade | `84577b8e1` |
| raredisease/variant | LLM context only (no flat) | exact IMPACT buckets (MODIFIER≠MODERATE) — pure upgrade | n/a (descriptor already correct) |

`84577b8e1` brought DESeq2/enrichGO descriptors to parser parity (autodelim + col-0 gene-id).
`677500172`/`0523373ea` document the per-domain evidence.

### A.2 The ADMET multi-file bug (shadow caught a REAL defect; my earlier "artifact" claim was wrong)
Added a read-only `?regen=1` hook (`5a8bf2184`) to force findings recompute from existing outputs
(no workflow run), then captured a clean live shadow on ADMET run `331245f4`: it still showed
`doc-only=[logP]`. Root cause (`466893371`): a real ADMET run emits 7 files; the structured report is
`toxicity_report.json`, but a sibling `pk_summary.json` also carries a `per_compound` array (RDKit
logP) and matched ADMET_REPORT's generic `contentIncludes:['per_compound']`; `matchDescriptor`
returned the FIRST file hitting any signal → the wrong file → the ADMET document collapsed to a
single `logP`, losing every safety liability. My earlier local repro fed only `toxicity_report.json`,
masking it.

Root fix (`466893371`):
- ADMET_REPORT `contentIncludes` → `['per_compound_admet_ai']` (the AI block is the toxicity report's
  distinctive marker; a legacy per_compound-only report still matches via FILENAME).
- `matchDescriptor` now SCORES candidates (filename+content=4 > content=3 > filename=2 > wf-name=1)
  and picks the best per descriptor, not the first hit. +3 regression tests.
- `0d208839b`: the shadow log now encodes the true gate — `parser-only=[]` with doc extras =
  **cutover-safe (superset)**, distinct from `cutover-ready` (exact) and `cutover BLOCKED`.
- Live-verified after deploy: `parser-only=[] … cutover-safe (document is a superset)`.

Correction recorded in `docs/20261105_FINDINGS_QC_SIMPLIFICATION_DESIGN.md` (CORRECTION #2): the
earlier "deploy-boundary artifact / code-proven safe" claim was disproven; the shadow was right.

### A.3 Committee review of the above changes (Opus/Sonnet/Haiku)
Three models reviewed; each finding verified against the real code before acting (experts can be
wrong). Fixes in `b0ce4d134`:
- **Sonnet Lead 1 (data-loss, CONFIRMED):** `?regen=1` on an LLM-path run re-calls the non-deterministic
  LLM; on a one-off failure the `_unavail`/`_minimal` fallbacks persisted an empty (findings-shaped)
  note to the S3 sidecar, clobbering a good one. Now both fallback persists are guarded with
  `!forceRegen` — a diagnostic regen never DOWNGRADES a good sidecar.
- **Sonnet Lead 2 (abuse, non-blocking):** rapid regens didn't coalesce → N concurrent analyses. Now
  returns `pending` if a generation is already in flight.
- **Opus Finding 1 (strict regression, CONFIRMED):** autodelim detected the delimiter by scanning the
  WHOLE file for a tab → a comma CSV with a stray tab shattered into 1 col/line (0 findings). Now
  detect from the HEADER line by column count. +2 regression tests.
- **Haiku:** strengthened a weak test assertion (`.not.toBe` passed if `m===null`).
- Declined (verified non-issues): matchDescriptor scoring = strict improvement; ADMET marker
  narrowing safe (legacy still matches by filename); col-0 fallback cosmetic; shadow block
  side-effect-free.

### A.4 Cutover status
- ADMET: **cutover-safe** (live confirmed). enrichGO/raredisease: no gate (pure upgrade). DESeq2:
  code-proven; live shadow run-blocked (dev has only failed DESeq2 runs).
- The **destructive** step (wire `documentToLegacy` as the flat source + delete the reconciler) stays
  reserved for its own committee-reviewed session; the one non-trivial piece is preserving the
  `"— potential liability"` marker contract that `flatLiabilities`/the UI depend on.

---

## B. Design-conformance audit + fixes (2026-11-05 → 06)

Trigger: the user was worried about the composer **instruction panel** and the **add-connector
button**, and whether I had thrown away working code. Design spec is the source of truth
(`reference/claude_design/data_centroid_design_v2/`).

### B.1 Deletion accounting (what was removed this session — verified)
Scanned every code commit. The ONLY genuine removal was `dcd0fed35`: a **dead, un-openable
duplicate** `<ConnectorsDialog>` in the sidebar (its `showConnectorsDialog` state was never set true —
the dialog could never open), an unused `recentProjects` computation, and two now-unused imports. The
LIVE connector UI is intact: `/settings/connections` route (`App.tsx:708/721`) renders the embedded
`ConnectorsDialog` + `AddConnectorFlow`; the sidebar "Connectors" button navigates there. Everything
else a diff-scan flagged was NOT a deletion: `InteractiveToolsRow` was re-parameterized (still
rendered, test-guarded), "removed imports" were re-imports/reorders, and the billing lines were wrong
field names replaced by correct ones (+ a storage rate blanked to "—" because it was unverifiable).
**No working feature was removed.**

### B.2 Add-connector button vs design — CONFORMS (and exceeds)
`AddConnectorFlow` matches `Connectors.jsx`/`window.ADD_CONNECTOR`: same "Add a connector" toggle,
kind rows (title·kind·mode·question·note), the verbatim "Nothing is attached until you have seen what
was found" copy. All 6 "Set up" buttons route to real surfaces (directory scan→review→attach via
`/api/connectors/directory/scan`+`/attach`; DB form; MCP form; model settings; instruments section).
Code has 6 kinds vs the design's 4 (adds Model + Instrument — design-consistent). **One partial** (not
a regression): "A skill or expert" Set up lists expert packs + points to the composer rather than a
"describe your own skill" creation flow the design implies. [OPEN — see §C]

### B.3 Instruction panel vs design — gaps found + fixed
Audit (verified against Spec 06 "The composer"): the composer instruction text DOES reach the model,
but with real conformance gaps. Fixes shipped:

- **Output requirements — template examples + send-path fix (`b3cf79c50`).** User: the field is hard
  to define from blank → show a template example in the panel.
  - New shared `frontend/client/src/lib/output-requirements.ts`: one place to parse the store and
    render the prompt, so the editor panel and the composer can't disagree. `EXAMPLE_OUTPUT_FORMATS`
    holds design-accurate examples (report memo / figure spec / supplementary table / naming
    convention, each with a real detail string).
  - Panel (`project-guidance-cards.tsx`) now shows an "Examples — what a good output format looks
    like" block with per-example "Use" and a "Start from these examples" button; examples seed
    switched OFF so they never silently take effect; the "+ Add a format" default is now a concrete
    mini-template.
  - **Coupled correctness fix:** the composer previously sent the raw JSON store **including formats
    the user switched OFF**. Now `outputRequirementsToPrompt` sends ONLY enabled formats, as prose.
    +9 unit tests.
- **Instructions chip = count, shown only when the project has rules (`12862c831`, Spec 06 §6.1).**
  Before: the in-project chip was always shown with a dot that lit for any of
  instructions/outputs/skills. Now: compute `standingRuleCount` from the project's current
  instructions (one per non-empty line), render the chip only when > 0, show the count badge, title
  "N standing instructions from &lt;project&gt; are in context". Opening the Instructions panel is
  still a click here and from the sidebar's per-project "Instructions" link (`app-sidebar.tsx:353`),
  so a 0-rule project is not stranded. Projectless inline-editor dot unchanged (separate, non-spec
  surface).

---

## C. Open gaps (next fixes)
From the instruction-panel audit:
1. ✅ **Duplicate injection — FIXED (`da00ec406`).** Verified: the server injects the project's
   standing instructions directly (`routes.ts:6815-6818` "Research goal" / "Background instructions"),
   while the composer seeded `instructions` from the same project field and re-sent it as
   `composerInstructions` → the same text appeared twice in `<project_context>`. Fix: the composer now
   captures the seeded value (`seededInstructionsRef`) and sends `instructions` only when they are
   chat-specific (changed from the seed, or projectless); an untouched project seed is dropped from the
   payload (the server already injects it). Output requirements still ride the composer path (the
   server does NOT inject those). tsc + vitest 2206/0.
2. ✅ **Silent 24k truncation — FIXED.** The projectless composer-instructions textarea now has
   `maxLength={24000}` (mirrors `MAX_COMPOSER_INSTRUCTIONS_LENGTH` in `server/chat-context.ts`) so input
   can no longer be silently trimmed server-side, plus a counter that appears within 10% of the cap.
3. ✅ **"A skill or expert" creation flow — BUILT.** The add-connector skills tab now has a
   `AddSkillForm` ("Create a skill or expert"): the user names it + says what it does + what the
   expert should do each time (optional trigger keywords/domains). We generate a valid
   Markdown-with-frontmatter skill file (pure `skillSlug` + `buildSkillMarkdown`, JSON-encoded scalars
   so a colon/quote can't break the YAML) and POST it to the existing `/api/skills/upload` endpoint
   (backend-validated by `validate_skill_upload`); the packs list refetches on success. Private skills
   need personal Galaxy access — the server's 409 is surfaced honestly (not bypassed). The design
   note ("cannot change a parameter — write it in a project's instructions") is shown. +8 helper
   tests. All 3 instruction/connector-panel gaps are now closed.

## D. Verification status (as of 2026-11-06)
- tsc clean; full vitest **2206 passed / 0 failed** (latest run after the chip fix).
- dev deploys healthy: `b0ce4d134`, `b3cf79c50`, `12862c83` all `result=healthy`.
- Live checks: ADMET shadow `cutover-safe`; CAR-T (LLM-path) regen returns good 7-result findings,
  no degraded persist, coalesce engaged.

## E. Audit + test of the design-conformance batch (2026-11-06)
Multi-model committee (Opus = composer/instructions; Sonnet = skill-creation + security) reviewed the
five new commits; each finding verified against real code (and the backend YAML parser) before acting.

### Live end-to-end test (dev, fixture account)
The skill-creation flow was exercised against the REAL backend: `POST /api/skills/upload` with a
generated file (incl. an adversarial title `Audit: "strict" reviewer` — colon + escaped quotes) →
`{success:true, skill_id:"user-1-e2e-audit-reviewer", scope:"user", capability:"instructions_only"}`
HTTP 200; it appeared in `GET /api/skills`; the JSON-encoded frontmatter validated (no YAML break).
Test skill then deleted via `DELETE /api/skills/user-1-e2e-audit-reviewer` (note: the delete id is the
full `user-<n>-<slug>`, not the bare slug). Full unit suite tsc-clean, 2240/0.

### Skill-creation fixes (Sonnet)
- **Finding 1 (CONFIRMED, must-fix):** `name:` was written BARE, so a YAML-1.1 magic slug
  (`yes`/`on`/`no`/`off`/`true`/`null`/`2024`/`007`) was re-typed by PyYAML to bool/int/None →
  `validate_skill_upload`'s `isinstance(name,str)` failed with a confusing 400. Reproduced with
  `yaml.safe_load`. Fixed: `name: ${JSON.stringify(slug)}` (quoted → always a string). +8 param tests.
- **Finding 4 (inclusivity):** a non-Latin name (e.g. Chinese) slugged to `''` → the form blocked the
  user. Added `fallbackSlug` (stable `expert-<base36 hash>`, always regex-valid) via `resolveSkillSlug`.
- **Finding 2:** strip control characters from title/description/body (PyYAML's reader rejects DEL etc.).
- **Finding 3 (hardening):** drop 1-char trigger keywords (a trigger like "a" auto-fires on every
  query). NOTE for backend follow-up: the skill *body* is inserted raw into the `<skill>` system block
  (`skill_manager.py` system_block) — a body containing `</skill>` is a self prompt-injection surface;
  the correct fix is backend escaping there (out of this frontend scope) — logged, not yet done.
- 422 robustness: guard `typeof data.error === 'string'` so a non-string detail can't crash render.
- Confirmed-correct (no action): JSON-encoded scalars can't inject YAML keys/newlines; `---` in the
  body is preserved (frontmatter stops at first closing fence); no path traversal (backend builds the
  path from the regex-constrained `name`, ignores client filename); slug collision → 409 surfaced; pack
  description rendered as text (no XSS); created private skill does appear in the list.

### Composer/instructions findings (Opus) — all 4 commits SAFE
- **Finding 1 (low, staleness):** `saveRules` didn't dispatch `biomate:projects-updated`, so the chip
  count could lag an in-place rule edit. Fixed: dispatch it (same as `saveSettings`).
- **Finding 2 (low, drift):** the client `COMPOSER_INSTRUCTIONS_MAX` mirrored the server cap with no
  guard. Added `lib/composer-instructions-cap.test.ts` (source-comparison mirror test, like
  `MAX_DATASET_REFS`).
- **Finding 3 (very low):** output requirements ride the composer path and have no length cap, so a
  huge output-requirements store could still be server-trimmed past 24k (the textarea maxLength only
  covers the projectless instructions field). Accepted as a known edge; logged.
- Verified correct: outputRequirementsToPrompt drops `on:false`, preserves legacy free text, can't
  throw; duplicate-injection fix loses no data (there is no in-project instructions editor); chip count
  matches the Rules page exactly; maxLength char/byte consistent with the server slice; no test-id
  collision.
