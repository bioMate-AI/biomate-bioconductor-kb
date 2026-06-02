# AfterRunReport Design Review — PM Sign-Off Pass

**Date:** 2026-06-01
**Reviewer:** PM agent (general-purpose, instructed to be blunt and opinionated)
**Subject:** `docs/20260601_AFTERRUN_PANEL_DESIGN.md`

---

## Verdict

**Ship v0 with 4 must-fix gaps closed; do NOT flip v2 default in 2 weeks as planned.**

The IA is correct, the hide-when-empty discipline is right, and the client-side markdown export is a defensible v0 choice. The A3 backend audit was actually done before design — rare and disciplined.

But the doc papers over three real product gaps:
- **Failed-run UX is hand-waved** in a single table row
- **Findings is excluded from the downloadable report** (violating goal G5 "offline-readable")
- **No "Run again with edits" CTA** in the after-run surface despite that being exactly what upstream user feedback (item #25) asked for

Deferring Software and Citations is fine in principle, but the doc undersells the cost: 44% of the nf-core catalog ends up with a 3-tab experience that looks thin in a sales demo.

The 2-week cadence to v2-default is too aggressive:
- Telemetry events don't exist yet
- There are no stated success/kill criteria
- The methods endpoint still does a 20s synchronous Claude call on first read

Tighten the spec, add explicit gating criteria, push flip to T+4 weeks minimum.

---

## Top 5 must-fix items

### 1. Failed-run path needs a real spec (not one table row)

Spec what shows when `currentRun.execution.status === 'failed'`:
- Which step failed (name + step index)
- Last 200 lines of `.command.err`
- Likely-cause param (if known from QC handler or pattern match)
- A clear "Run again with edits" CTA

Without this, v0 is **worse** than v1 for the ~10-20% of runs that fail.

### 2. Inline Findings prose into the downloaded markdown report

Currently §13.1 lists this as an "open question." It is not. A report that says "see the live endpoint" is not "offline-readable" (violates goal G5).

Fix: lift FindingsCard's fetch up into AfterRunReport so the comprehensive download has the actual findings prose. ~20 LOC. **v2-flip blocker.**

### 3. Wire "Run again with edits" CTA in Parameters tab

Resolve §13.5 the same way. The upstream user feedback that triggered this work stream (item #25 in the 05_25_todo.md) explicitly asked for faster iteration on parameters. Deferring this CTA makes v2 objectively worse than v1 for the iteration-loop power user persona.

**v2-flip blocker.**

### 4. Cache the methods endpoint server-side + better loading UX

A 20s synchronous Claude call is P0, not "v1 polish."

- Backend: add file cache at `{run_dir}/methods_report.cached.md`. Hit-rate after first visit: 100%.
- Frontend: replace silent-hide-on-error with a loading skeleton + retry button. Heuristic stub detection (`<200 chars OR contains 'No QC events recorded'`) must move to a backend contract (`{available: false}` or HTTP 204) — frontend should not be string-matching server output.

### 5. Define explicit v2-flip success + kill criteria, and gather ≥2 weeks telemetry first

Listed §11 events don't exist yet. The rollout has no rollback trigger.

Minimum gating criteria for v2 default flip:
- ≥60% of completed-run page views show the panel (panel renders)
- ≥40% of those click at least one tab
- ≥10% click "Download report"
- No regression in support-ticket volume for "where are my outputs"
- Zero P0 bugs in 5 days of v1 dogfood

**Bonus quick-win:** ship Citations in v0 for the 56% of catalog where data already exists (cryo-EM RAG + 21 qc_evidence domains). Zero backend cost — endpoint reads existing yaml. Neutralizes the "3-tab thin experience" risk for nf-core genomics workflows.

---

## Strengths

- Audit-before-design discipline (A3 audit grounded the tab choices in real backend coverage)
- Hide-empty-tabs-not-placeholder rule is correct and unambiguous
- Dual-source outputs (Galaxy `outputDatasets` + Nextflow `s3_output_files`) handled cleanly
- Per-tab data source matrix in §6 is auditable
- 5 personas in §4 are distinct, not personas-as-marketing
- Section 14 "Out of scope" explicitly excludes features that would balloon the spec — rare and good
- The feature flag isolation (`?afterrun=v2` independent of `?ui=v2`) means we can validate this surface alone, without conflating with whole-app v2 risk

---

## Critique by section

### Problem framing
Real problem. Scoped right. Solution (single tabbed surface) is proportionate. The doc's framing of "five needs spread across three places" is accurate per the v1 codebase.

### Personas
Five good ones. Missing:
- **The shared/handoff persona** — user A runs, user B opens the link to inspect. Auth + permissions are punted to §14 "out of scope" but the persona is implicit in the "share with collaborator" goal.
- **Mobile reviewer** — not a primary user but a real one. Tab bar wraps and table rows are not mobile-friendly today.

### Tabs

#### Findings
- Data source correct (reuses existing endpoint)
- Reusing `FindingsCard` directly is the right call
- `pending` state polling forever is a real bug — needs 5-min give-up + retry (called out in §8 but not in tab spec)
- **Missing:** "regenerate findings" affordance. Findings are AI-generated and sometimes garbage; user should be able to retrigger.

#### Outputs
- Dual-source handling correct
- v0 = download-only per-file rows is acceptable; v1 must add inline preview or this tab is markedly worse than v1's per-step file preview
- 5 MB inline preview cap is a guess — should be configurable per file type (PDB up to 50 MB OK with 3Dmol; CSV beyond 50 MB nobody wants to render inline)
- **Missing:** file size column. Users need to know "is this 2 MB or 2 GB before I click download"
- **Missing:** sort/filter — for runs with >50 outputs (cryosparc, nf-core), grouping by step alone isn't enough

#### Methods
- Caching is P0 not P1. 20s sync Claude call blocks every visit; v0 currently fails silently
- Hide-when-stub heuristic is fragile (frontend string-matching server text). Move to backend contract.
- **Missing:** "Regenerate methods" — same as findings

#### Parameters
- Read-only echo is fine for v0
- **Run again CTA missing** (must-fix #3)
- Long values (SMILES strings, S3 paths) wrap into 5-line cells — ugly. Need truncate-with-tooltip + click-to-copy

#### QC audit
- Time-ordered table is right
- Status colour coding correct
- **Missing:** filter by status (show only halt/fail) — common debug pattern
- **Missing:** link from gate name to the gate definition (qc_evidence.yaml entry with rationale + citations)

#### Software (deferred)
- Defer is fine
- Endpoint design in §6.6 is right
- v1 ship is unambiguous

#### Citations (deferred)
- **Disagree with deferring.** Backend data exists for 56% of catalog today (cryo-EM RAG + 21 qc_evidence domains with paper_doi fields). The endpoint is ~50 LOC. Ship in v0 — eliminates "3-tab thin experience" for the demo-critical drug-discovery domains.

### Download report
- Markdown is correct v0 choice
- Client-side generation is correct
- Inlining Findings prose is must-fix (#2)
- **Missing:** include run timing / wall time / cost estimate in metadata — natural inclusion for an offline-readable report
- DOCX-via-pandoc instruction in §7 is fine, but should be in a `## How to convert` section the user can find, not buried in design rationale

### Edge cases — what's missing
- Run from a different user (shared / teams) — auth + permission punted to §14 but there's no link to where this is tracked
- Run >24 h old where Findings/Methods cache may be stale — re-fetch policy unspecified
- Run from a deleted workflow definition (user deleted the workflow, opens an old run) — currently would 404 on findings/methods; needs graceful degradation
- Network-disconnected user trying to download report — should work (data already in React state); design doesn't say so explicitly
- Concurrent users opening the same run — no concurrency concerns flagged but methods endpoint generation is currently racy (two simultaneous requests both kick off Claude calls)
- Browser back/forward navigation — tab state should be in URL, not React state, so deep-linking to a specific tab works

### Telemetry — what we can't answer
None of the §11 events exist in code today.
- Can't answer: tab click distribution, per-tab dwell time, panel render rate vs run completion rate
- Without telemetry events shipped in v0, the v2-flip decision is data-free

### Rollout — cadence + success criteria
- 2 weeks is too aggressive. Push to 4 weeks minimum.
- §12 has no kill criteria. Needs: rollback trigger, P0 bug response SLA, what fraction of users flag the v2 as worse than v1 in feedback
- §12 has no dogfood plan. Internal users should run v2 exclusively for 5 days before pilot rollout

---

## Strong opinions on open questions

### §13.1 Findings in download report?
**YES. Must-fix #2.** Not a question. Lift the fetch.

### §13.2 Auto-expand panel width?
**No.** Respect user resize. Panel width is a v2-merge concern, not after-run-specific. Don't bundle this into AfterRunReport scope.

### §13.3 Chained / pipeline runs?
**Defer entirely** — workflow_chain is a separate feature still in flight. Add a `chain_id` prop now; design the chain summary later.

### §13.4 Methods rendered as markdown?
**Yes, v0 — not v1.** Trivial: swap `<pre>` for `<ReactMarkdown>` (already in deps). Methods text already has `# ABSTRACT / ## 1 ...` headers. Better readability for zero cost.

### §13.5 Re-run from After-run?
**YES. Must-fix #3.** Not a question. Wire it.

---

## Top 3 risks to v2 default flip

### Risk 1: Failed runs land in the panel with no useful info
Today's design hand-waves this. ~10-20% of completed runs are failures. Users hitting the new v2 panel on a failed run will see Findings ("Run failed — see error in viewer below"), an empty Outputs tab, no Methods, no QC. That is strictly worse than v1's failure pathway today (which surfaces error message + step status + log in the viewer).

**Mitigation:** must-fix #1. Specify the failed-run layout properly.

### Risk 2: Methods tab silently hides for slow first-visit
Backend's 20s sync Claude call → frontend fetch errors → tab hides. User thinks "this workflow doesn't have a methods report" when it does, it's just generating. Telemetry won't catch this because nobody clicks a hidden tab.

**Mitigation:** must-fix #4. Cache + skeleton + retry.

### Risk 3: Telemetry-free flip
Without §11 events shipped, the v2-flip decision is based on vibes / support tickets / internal dogfood. That's not enough for a default-flip affecting all users.

**Mitigation:** must-fix #5. Land events in v0, gather 2 weeks before flip.

---

## What you'd cut

- Reproducibility bundle separate button — fold into "Download all" as a checkbox/option, don't pollute the bulk-action bar with two buttons that look identical
- §11's `afterrun.panel_shown` event — redundant with existing `output.panel_opened`; reuse don't proliferate
- §6.2's grouping-by-step is correct but the v0 doesn't surface "this step had QC failures" or "this step took 92% of wall time" — leave as future, don't half-ship

## What you'd add (that isn't here)

- **Cost estimate in metadata** — users on metered plans want "this run cost $X.XX". Already tracked by the billing infrastructure; surface it in the panel header next to wall time
- **Run timing breakdown** — duration per step, identify bottleneck. Free from `nextflowStatus.processes[]`
- **Citations in v0** for the 56% of catalog with existing data (cryo-EM + qc_evidence domains)
- **Tab state in URL** (`?afterrun=v2&tab=methods`) so deep-linking + back-button-from-tab work
- **"Compare to previous run" button** — even just navigation to the prior run with the same workflow definition would help iteration; full Comparison feature is correctly deferred to §14 but a one-click previous-run nav is cheap

---

## Section verdict

| Section | Verdict |
|---|---|
| §1 Problem statement | Strong |
| §2 Goals | G3 (no Coming Soon) should be reaffirmed in §6.6/6.7 — currently those sections describe tabs that hide, which is consistent with G3 |
| §3 Non-goals | Strong |
| §4 Personas | Add shared/handoff persona |
| §5 Information architecture | Strong |
| §6 Tab specs | 5 of 7 sound; Findings needs regenerate + indefinite-poll fix; Outputs needs file size; Methods needs cache promoted to P0; Parameters needs Run-again CTA |
| §7 Download report | Strong v0 choice; must-fix #2 (Findings inlining) |
| §8 Edge cases | Failed runs, shared runs, old runs, network — 4 gaps |
| §9 States | Acceptable for v0; Methods needs spinner+retry |
| §10 Visual design | Acceptable; mobile not addressed |
| §11 Telemetry | Events don't exist yet — must ship in v0 |
| §12 Rollout | 2 weeks too fast; no kill criteria |
| §13 Open questions | Two should not be open (Findings inlining, Run-again CTA) |
| §14 Out of scope | Correct exclusions; Citations should NOT be here (move into v0) |
| §15 Appendix | Strong — should be referenced from §2 Goals for grounding |
