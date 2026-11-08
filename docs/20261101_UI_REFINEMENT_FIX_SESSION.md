# UI refinement fix session — 2026-11-01

## Why the weeks-old UI refinements weren't showing on dev (root cause)

The refinement requests (≈70 screenshots, Oct 9 + Oct 19, tracked in
`docs/20261020_UI_REFINEMENT_TRACKER.md` + `docs/20261028_UI_AUDIT_FINDINGS.md`)
were **not** lost to a branch/deploy problem. A full reconciliation of every
requested change against the actual deploy tree (`biomate-review`, branch
`cursor/tutorial-live-recording-and-report-editing-4ea7`) found:

- **29 PRESENT** (genuinely shipped), **10 PARTIAL** (one code path fixed, old
  behavior still on another), **3 DISABLED** (built then un-mounted), **5 ABSENT**
  (never coded on any branch). No fix was stranded on a sibling worktree — nothing
  to cherry-pick.
- So the missing items were **incomplete in code**, not undeployed. The three the
  user named proved the pattern: BETA (never re-added after the Oct-20 removal),
  confirmation-panel-suppression (never coded), New-Chat dedupe (never coded).

Process note: the user deploys via `scripts/sync_to_dev.sh` from this worktree.
New rule adopted this session: **commit → push → open PR → pre-sync checks → sync**
(see memory `feedback_deploy_process`). The sync's pre-flight guard refuses to
deploy with uncommitted source — which is the discipline that rule enforces.

## Fixes landed this session (all in `biomate-review`, tsc + vitest green)

| # | Item | Commit | Files |
|---|------|--------|-------|
| 1 | Restore BETA badge | 55ba0232b | app-sidebar.tsx |
| 2 | Suppress workflow panel on confirmation/disambiguation | 55ba0232b | chat-with-artifacts.tsx |
| 3 | New-Chat pile-up dedupe + auto-remove (1d) | 184577563 | chat-history.ts |
| 4 | Blue project-child rows (1b) | 184577563 | app-sidebar.tsx |
| 5 | Cancelled run → neutral "Cancelled" not red FAILED (item 2) | 33204f937 | nextflow-workflow-viewer.tsx, chat-with-artifacts.tsx |
| 6 | Guard raw step-id on prop render path (finding 3) | d165c15a9 | v2/AfterRunReport.tsx |
| 7 | Scrub residual "BioMNI" badge (item 16) | d165c15a9 | galaxy-recommendations.tsx |
| 8 | Re-mount cold-start goal input + rebalance (item 19) | fa47beba1 | cold-start-dashboard.tsx |
| 9 | De-duplicate dataset header badges (item 6 H6) | 292c8e136 | datasets/dataset-object.tsx, en/zh common.json |
| 10 | Real output file sizes, not 0 B (item 9 Gap B) | c4671db6e | nextflow-workflow-viewer.tsx, v2/AfterRunReport.tsx, steps/step-detail.tsx, step-output-preview.tsx |
| 11 | Drop session-tab count badge in dataset picker (item 8) | a300a976f | galaxy-dataset-browser.tsx |

Deploy: commits through 292c8e136 pushed to PR #295 and synced to dev.
c4671db6e + a300a976f (+ the WIP commit 1db223db8) need a follow-up push + sync.

## Remaining items — deferred with reasons (NOT rushed, to avoid regressions)

- **Rerun traced as a new chat message (item 5).** Deeply interwoven with core chat
  flow: `handleRunWorkflow` overwrites `invocationId` in place (chat-with-artifacts.tsx
  ~1119-1282); the panel binding (1022-1060), SSE pill de-dup (1092-1106), run-matches-panel
  (~2451) and the `?runAgain=` path (438-470) all key off that id. Making each rerun a
  new traced message means appending a new workflow message + rebinding the panel to the
  new run while keeping the prior run's results reachable. **Needs a focused change with a
  live run→rerun E2E** (run A → rerun → assert both runs traced, panel on the new run, A's
  outputs still openable). Do not ship without that test.
- **Dataset picker 4-tab merge (item 8 rest).** Count badge dropped (done). Collapsing
  session/project/history/url into fewer tabs is a UX refactor that risks regressing a
  working picker — scope it deliberately with the design.
- **Per-step tool VERSION + DURATION (item 9 Gap A).** Data exists server-side but no
  endpoint surfaces it per step: `software_versions.yml` (versions) and the
  `-with-trace workflow-trace.txt` duration/realtime columns (the SSE poller at
  `backend/.../api/nextflow_executor.py` ~4241-4262 reads only name/status). Backend task:
  parse those and attach `version`/`duration` to the per-step payload; then the FE already
  has the slots (step-detail.tsx ~344-354). Tool NAME is the Nextflow process name only
  (already shown as `name`) — not mapped to the "tool" slot to avoid a misleading duplicate.
- **Nav IA + API-keys (items 1a/1f/1g/1h).** Largely intentional / crash-gated: the other
  Settings tabs are `{false && …}` because they're unfinished (un-hiding ships crashes),
  IND Report is crash-hidden on purpose, and the nav IA is an intentional divergence from
  the design (memory `project_ui_visual_parity_notes`). Left as-is rather than regress;
  revisit only with a decision to actually fix+un-gate those tabs.

## Environment issues surfaced (need user action)

- **Disk 100% full** (1.1 GB free of 228 GB). Biggest reclaim: an accidental nested git
  clone at `biomate-review/biomate/` (5.5 GB, `biomate/.git` = 2.9 GB, on
  integration/next-phase). It has 2 uncommitted files to preserve first: `scripts/sync_to_dev.sh`
  (modified) and `docs/20261031_SYSUCC_PRODUCT_AND_MCP_HIPAA_HANDOFF.md` (untracked).
  Proposal pending user approval before deletion.
- A 2,141-line uncommitted drug-discovery/Benchling WIP (assay/BO/Benchling) was blocking
  the sync guard; committed as-is (1db223db8) per user request to unblock the deploy.
