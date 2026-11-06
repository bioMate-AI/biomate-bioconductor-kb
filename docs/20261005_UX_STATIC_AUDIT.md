# UX walkthrough — static audit + live-audit feasibility (2026-10-05)

Requested: audit the dev UI against the Claude design reference (CLAUDE.md "UX E2E Completeness
Standard"). What was actually feasible from this (sandboxed) environment, and the honest findings.

## Environment constraints (why the LIVE/visual audit couldn't run here)
- **Loopback blocked:** the reference design server binds (pid listening on :7779) but the sandbox
  refuses localhost TCP connections (`curl localhost:7779` and a control port both → 000), while
  external HTTPS to dev works (200). So the **pixel-diff against the `localhost:7779` reference is not
  possible from here** — it needs a browser env that can reach localhost (your machine).
- **Playwright not runnable here:** chromium build mismatch (a resolved `@playwright/test` wants build
  1200; 1223 is installed → `browserType.launch` fails), and the per-test timeout is **45 min**
  (`playwright.config` `timeout: 2_700_000`), so a hang isn't observable in a reasonable window. The
  `webServer` block is commented out (not the cause).
- Conclusion: the **live/visual UX walkthrough belongs in a browser environment** (yours, or a
  non-sandboxed runner). From here, only a **static code-vs-checklist audit** is reliable.

## Static audit — CLAUDE.md UX checklist vs. the actual components
Method: grep each checklist element against the component source, then **verify every apparent
absence** (heuristic greps miss on wording — 4 of the first "absences" were false positives).

### Workflow panel — `nextflow-workflow-viewer.tsx` (4,058 lines): COMPLETE
All checklist capabilities present: `data-status` realtime attrs (idle/pending/running/completed/
failed, 96 refs); pre-run param strip + missing-required blocked alert; Running/Run-again footers;
QC gate alert + measured-vs-threshold two-number display (38/27 refs); QC threshold user-edits
(line 1627); param override via `globalParamsOpen` panel; "View phase outputs"; step file preview
(img/table/code); auto-loop panel + was→now diff + gate table (halt/advisory/pass); Findings tab;
download (`Download`, `DownloadOutcomePrompt`, `DownloadCommandsPanel`). Apparent gaps were wording
drift, not missing features:
- Failed-state action is labeled **"Rerun"/"Start over"** (`data-testid=button-start-over-failed`),
  not the checklist's "Restart".
These are label differences between the checklist text and the current code — not missing UI.

### Chat message — `chat-message.tsx` (1,192 lines): COMPLETE
markdown/prose, code blocks, workflow card + "In panel" badge, DisambiguationCard, alert variants —
all present.

### Sidebar — `app-sidebar.tsx` (499 lines): COMPLETE except INTENTIONAL removals
Present: New Chat, Workflows, Runs/dashboard, Recent Tools, Settings, collapse/icon-rail. Two
checklist items are **intentionally absent** and must NOT be restored:
- **CRO Library** and **Billing** nav are commented out (line 306: "Billing hidden — /billing page
  crashes (BillingPage toFixed on undefined)"). Matches the standing decision (crash-hidden).
- "Starred Workflows" as a distinct dialog was refactored into the history dialog
  (`setHistoryInitialTab('runs')` / `showHistoryDialog`); the capability is reachable via "Workflows".

## Verdict
- **No structural UI gaps to fix.** The components implement the reference checklist; the only
  absences are the intentionally crash-hidden CRO/Billing nav.
- The CLAUDE.md UX checklist has **drifted** from the current code in a few labels (it lists CRO
  Library, which is intentionally hidden; "Restart" vs the code's "Rerun/Start over"; a standalone
  Starred dialog that was refactored). Doc-accuracy nits, not UI bugs. (Not edited here — CLAUDE.md
  changes should be owner-driven.)
- The remaining UX-walkthrough value is **visual polish + flow smoothness + pixel-fidelity to the
  reference**, which is exactly what this sandbox cannot assess. Recommend running it in a browser
  env: fix the Playwright browser (`npx playwright install chromium`), then the existing dev-targeting
  harness (`researcher-journey`, `sidebar-all-buttons`, `panel-and-chat-stream`,
  `demo-09/10-reference-workflow-panel`) captures the states; compare against `localhost:7779`.

## One-command live-audit harness (run in a browser env)
`scripts/run_ux_audit.sh [structural|reference|all]` wraps the whole live audit: installs the Playwright chromium, starts the reference server on :7779, sets the dev env, runs the journey + reference-comparison specs (screenshots on), and prints the report path. Run it where loopback works and a browser can launch (not the sandbox):
```
E2E_FIXTURE_PASSWORD='<fixture pw>' bash scripts/run_ux_audit.sh all
cd frontend && npm run e2e:report   # view screenshots; compare dev vs http://localhost:7779
```
