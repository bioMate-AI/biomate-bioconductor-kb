# Research-Agent v2 sandbox — comprehensive E2E test plan

Date: 2026-05-19
Reference: `frontend/e2e/cryoem-stepwise-and-output.e2e.ts` (SuiteRecord
pattern, per-test `assert(rec, name, condition, note)`, screenshots,
`audit_<ts>.json` summary).

## Scope

The sandbox under test is `frontend/research_agent_v2/`, a single-page
React app served by `python3 -m http.server 8765`. It has no backend,
no auth, no DB — everything is driven by URL params and the
`window.SseAdapter` mock/real factory. The test plan therefore focuses
on **rendering correctness across every surface the user can see** and
**event-shape contracts** that the real-backend smoke depends on.

## Test groups (22 tests across 6 groups)

### Group A — URL & mode wiring (RA-1 to RA-3)
**RA-1** `?live=mock&scenario=drugscreen` → page loads, 0 JS errors, SSE adapter present
**RA-2** Missing `?live=` falls back to tape walker (engine plays the static `research-data.js` scenario)
**RA-3** Bad scenario → engine logs a warning but does not crash; sidebar still navigable

### Group B — SSE adapter contract (RA-4 to RA-7)
**RA-4** `SseAdapter.deriveSpeaker(kind)` returns canonical pills: `workflow.qc_*`→qc, `workflow.autoloop_*`→loop, `deepagent.*`→agent, `plan.*`→plan, `findings.*`→find, default→wf
**RA-5** `SseAdapter.renderFriendly(kind, technical)` returns templated strings for the documented kinds (phase_started, qc_gate_warning, completed, autoloop_started, etc.) — verifies templates
**RA-6** Spread pattern (`{...e('K'), technical: {…}}`) yields **non-stale** friendly_message at emit time (regression for the `Object.defineProperty(non-enumerable)` fix)
**RA-7** `connectRealBiomateStream(inv, {onStatus})` invokes `onStatus('connecting', url)` immediately and `onStatus('error', …)` when EventSource fails (no backend running on 8765)

### Group C — Plan checklist (RA-8 to RA-10)
**RA-8** All 4 scenarios — plan checklist reaches **5/5 done** with the per-scenario item titles (Ingest/ADMET/hERG/Ames/ranking · A-E · QC/STAR/Salmon/DESeq2/enrichment · prep/align/recal/call/vqsr)
**RA-9** Plan progress bar percentage increments as `__planUpdate` events flow (intermediate state has at least one item in `running` status)
**RA-10** `warn` status renders distinctly from `done` (variant scenario: BWA-MEM2 alignment shows warn during run, transitions to done at completion)

### Group D — Chat thread (RA-11 to RA-14)
**RA-11** Speaker pills present in chat — at minimum WF (workflow.*), QC (workflow.qc_*) for drugscreen + variant; AGENT (deepagent.*) for drugscreen; LOOP (workflow.autoloop_*) for drugscreen
**RA-12** Friendly messages are templated, not generic fallbacks — `Step 2/5: STAR alignment…` instead of `Step step…`; `QC flagged hERG_fail_rate = 0.18 (threshold 0.10).` instead of `QC flagged metric.`
**RA-13** Collapse marker — when more than `collapseThreshold` consecutive same-speaker events fire, chat shows `WF — N earlier updates · click to show` collapse marker
**RA-14** `Workflow finished. 5/5 steps succeeded.` appears at completion (regression for the friendly_message fix where this line used to render as bare `Workflow finished.`)

### Group E — Cards (RA-15 to RA-18)
**RA-15** Drugscreen: PilotPromptCard renders early — title "Worth a pilot first?", sampled / total / runtime split, action buttons present
**RA-16** Drugscreen: PilotPromotionCard renders after first QC failure — `result: fail`, the per-gate QC list (hERG/Ames/DILI), and the suggestion changes block with `logp_max` and `mw_max_da`
**RA-17** Drugscreen: ComparisonCard renders — table with Run A vs Run B metric rows (hERG/Ames/Candidate/Runtime), autoloop-tagged param diff (`5.5 → 4.5`, `600 → 480`), recommendation card with **`p 0.008`** confidence chip
**RA-18** Each scenario produces a FindingsChatCard with the scenario-specific title (`47 BBB-penetrant candidates`, `3.1 Å reconstruction`, `1,847 DEGs · 23 enriched pathways`, `3.84M PASS variants · ts/tv 2.04`)

### Group F — Live-mode diagnostics (RA-19 to RA-22)
**RA-19** `?live=real` with no `?inv=` → `SSE: error` pill renders next to thread title; tooltip detail says missing inv
**RA-20** `?live=real&inv=bogus` → pill transitions through `connecting` → `error` (since no backend on the sandbox port); detail shows `readyState`
**RA-21** Mock-mode `?live=mock` — no SSE pill is rendered (pill is real-mode-only)
**RA-22** Headless audit summary — all 4 scenarios produce **zero JS errors** across full run; consolidated audit.json shows 22/22 pass

## Output

- Screenshots per test under `frontend/e2e/screenshots/research_agent_v2/`
  (named `RA-<NN>__<short>.png`).
- Audit JSON `audit_<ts>.json` next to screenshots with the same shape
  as the cryo suites (suiteId, runs[], per-run assertions).
- Each test wall-time-bounded ≤ 30s (sandbox is local-static, fast).

## Running

```
# Start sandbox server (if not already running)
cd frontend/research_agent_v2 && python3 -m http.server 8765 &

# Run the suite
cd frontend && npx playwright test e2e/research_agent_v2_sandbox.e2e.ts
```

The suite is independent of `BIOMATE_URL` — it always points at the
sandbox on port 8765. It can run on a workstation with no BioMate
backend or AWS credentials.
