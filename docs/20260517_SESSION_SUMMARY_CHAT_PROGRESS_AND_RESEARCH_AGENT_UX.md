# Session Summary — Chat-Progress System + Research-Agent UX Foundation

**Date range:** 2026-05-12 → 2026-05-17 (one extended session)
**Branch:** `integration/next-phase`
**Audience:** Whoever picks up this work next; future-me; reviewers
**Status:** Code shipped + tested locally; design spec ready for Claude Design review; no dev sync yet

---

## 1. The session in one paragraph

Started with porting Deep Agent autofix work from a colleague's Galaxy branch.
That uncovered a broader UX gap — workflow progress was either silent or buried
in a side panel — so the work pivoted to a unified **chat-progress system**
where every workflow lifecycle event surfaces as a compact italic 🔹 chat line.
Built and tested end-to-end on real AWS Batch workflows. Found and fixed two
real bugs in the control buttons (Pause / Resume / Cancel were fake) and added
10-second auto-proceed countdowns on blocking decisions so a distracted user
never stalls a workflow. Audited what else is already built but not in the UX
(task decomposition, pilot mode, experimental comparison) and surveyed
auto-research-agent UX patterns from the CS domain (Deep Research, Sakana,
Devin, AutoGen, W&B). Wrote two complementary docs for the next phase:
engineering audit + plan, and a Claude-Design-ready 5-surface spec.

---

## 2. What's shipped on this branch (16+ commits)

Selected commits in chronological order — see `git log --oneline 165885eac..HEAD`
for the complete list (includes interleaved colleague work).

| Commit | Title |
|---|---|
| `4ec1d56b8` | Port Tier-1/Tier-2 fixers + 5 ORM models + Alembic migration `a7f3deepagent` |
| `be60cd0e7` | Fix 2 upstream bugs (model default + analysis/initial_assessment key mismatch) |
| `3ba1be2ef` | `POST /api/workflows/{id}/deep_diagnose` endpoint |
| `78c0bb8da` | Revert deep-diagnose UI panel + redesign as chat-progress |
| `ba9d1cc5f` | `DeepAnalysisAgent.progress_callback` + chat-friendly text helpers |
| `3a6a751de` | Backend chat-progress narrator + wire `workflow.submitted/completed/failed` |
| `2bd9570cf` | Frontend SSE listener + italic 🔹 chat-message render |
| `caaf2a9c0` | E2E tests — real Nextflow + Playwright UI render |
| `23ad63a3d` | Phase wire-in (`phase_started/phase_completed/phase_failed`) |
| `7668498b4` | QC gate + autoloop chat-progress wire-ins |
| `3614b43dc` | **Real cancel/pause/resume + 10s auto-proceed** on blocking decisions |
| `d2b86cfa3` | Fix 5 pre-existing TypeScript errors |
| `c3eab698a` | Engineering doc — research-agent UX requirements |
| `c919290f6` | Claude Design spec — 5-surface research-agent UX |

---

## 3. What runs end-to-end locally

### Chat-progress system

Every milestone in a Nextflow workflow lifecycle now surfaces as a compact
italic 🔹 chat line, no new UI panel:

- `workflow.submitted` → "Got it — starting your workflow now."
- `workflow.phase_started` → "Step 2/5: STAR alignment…"
- `workflow.phase_completed` → "STAR_ALIGN done."
- `workflow.phase_failed` → "MIDDLE_FAIL failed — 1 task(s) failed."
- `workflow.qc_gate_warning` → "QC flagged hERG = 0.48 (threshold 0.5)."
- `workflow.qc_gate_blocked` → "QC blocked on hERG — adjusting parameters."
- `workflow.autoloop_started` → "Trying again with logp_max=4.5, mw_max=480."
- `workflow.completed` → "Workflow finished. 5/5 steps succeeded."
- `workflow.failed` → "Workflow stopped — exit 1. Looking into why…"
- `workflow.cancelled` / `workflow.paused` / `workflow.resumed`
- `workflow.auto_proceeded` → "No response — kept current parameters and continued."

Two-channel architecture:
- **User channel** — friendly natural-language sentence → chat history via
  existing `/internal/sse-inject` + `WorkflowSSEManager`
- **Engineer channel** — `[WORKFLOW][inv=…][kind] friendly | technical=…`
  structured log line + planned `ai_fix_audit_log` DB row

### Real cancel / pause / resume

Discovered the existing Pause / Resume / Cancel buttons only updated
frontend state. The Nextflow Java subprocess kept running, kept submitting
AWS Batch tasks, kept incurring spend. Fixed by:

- Adding `POST /api/nextflow/cancel/{run_id}` and `POST /api/nextflow/pause/{run_id}`
  on the Galaxy backend — `SIGTERM` then `SIGKILL` after 5s.
- `_find_nextflow_pids_for_run()` pgrep fallback for multi-worker gunicorn
  (cancel may land on a worker that doesn't own the subprocess handle).
- Wiring the Node.js proxy handlers to actually call the new endpoints.

E2E verified: real Nextflow workflow on AWS Batch, Java PID terminated by
the pgrep fallback in 5 seconds, status flipped to `cancelled`. Pause +
Resume cycle verified: pause kills the process, resume restarts with
Nextflow's `-resume` flag, cached tasks are reused.

### 10s auto-proceed on blocking decisions

Two blocking decision points could previously stall a workflow indefinitely:

1. **QC gate inline card** — previously had a 60s auto-dismiss; reduced to 10s.
2. **Low-confidence "Execution blocked — Confirm anyway"** — previously had
   no auto-proceed; added 10s.

Both fire a `workflow.auto_proceeded` chat line on timeout so the user is
informed: "No response — kept current parameters and continued." Both have
a visible countdown ("Auto-confirming in 9s unless you act.").

### DeepAnalysisAgent

The full Deep Agent framework is operational. Verified against a real
`backend/.nextflow.log` containing an FQ_LINT exit-127 failure:
- Correct diagnosis in 7.6s at confidence 0.98
- 4 concrete remediation paths
- 5 investigation steps recorded
- Engineer-channel log lines + chat-friendly progress

---

## 4. Tests run + all green

| Test | Result |
|---|---|
| `pytest test_workflow_chat_narrator.py` (18 tests) | ✅ all pass |
| Real Nextflow E2E (1-process, AWS Batch, success path) | ✅ `workflow.completed` |
| Real Nextflow E2E (3-process, AWS Batch, success path) | ✅ 6 phase events + completed |
| Real Nextflow E2E (3-process, deliberate FAIL) | ✅ `phase_failed` + `workflow.failed` |
| Real QC gate handler emit (hERG > 0.5) | ✅ `qc_gate_blocked` chat line |
| Real QC warning handler emit (hERG = 0.48) | ✅ `qc_gate_warning` chat line |
| Real `/api/nextflow/resume/{id}` with new params | ✅ `autoloop_started` chat line |
| Real cancel on running workflow | ✅ Java PID terminated, `note: by-pgrep` |
| Real pause + resume cycle | ✅ -resume + new run_id |
| `workflow-chat-progress.e2e.ts` (Playwright) | ✅ 2 tests |
| `workflow-chat-progress-comprehensive.e2e.ts` | ✅ all 11 progress kinds render |
| `workflow-auto-proceed.e2e.ts` | ✅ 2 tests |
| Full repo TypeScript check (`tsc --noEmit`) | ✅ 0 errors |

---

## 5. Audit artifacts under `docs/screenshots/`

```
docs/screenshots/20260512_chat_progress_audit/
  01_all-kinds-fullpage.png     ← full lifecycle, 11 progress lines + bubbles
  02_render-basic.png           ← 2-line basic render
  03_compactness.png            ← 5-line compactness check
  04_render-video.webm          ← Playwright recording (78 KB)

docs/screenshots/20260515_controls_audit/
  01_auto-proceed-render.png    ← two "No response — …" lines
  02_auto-proceed-video.webm    ← Playwright recording (54 KB)
```

---

## 6. Latent capabilities surfaced (not yet wired)

This session ALSO inventoried what's already implemented in the codebase
but not exposed in the chat UX:

1. **Task decomposition + parallel execution**:
   - `TaskDecomposer`, `TaskGraph`, `AgentOrchestrator`, `_identify_parallel_groups()`, `workflow_chain.py` — backend complete.
   - `TaskList` component wired only for LangGraph generation-phase tasks; not execution.
2. **Pilot study mode**:
   - Backend honors `is_pilot` + `dataScope.fraction/strategy`.
   - `PilotExperimentPanel` component fully written but **never imported anywhere**.
3. **Experimental comparison**:
   - Full backend stack + `experiments` table + `compareExecutionRuns` route.
   - Same `PilotExperimentPanel` contains the A/B view. `parameterDifferences` field is missing in the backend response (WC-7 test gap).

---

## 7. The two next-phase docs

Both pushed to GitHub on `integration/next-phase`.

### `docs/20260515_RESEARCH_AGENT_CHAT_UX_ENGINEERING_AUDIT_AND_PLAN.md`

The engineering companion. 414 lines. Contents:
- Latent-capability inventory by file path + line numbers
- Reference-system delta table (Sakana / Deep Research / Devin / AutoGen / W&B → BioMate)
- 5-pattern proposal with per-pattern data contract
- Information architecture sketch
- Speaker taxonomy + oklch color tokens
- Pilot-mode contract + comparison data contract
- E2E coverage matrix
- Rollout order behind feature flags (B → D → E → A → C)
- 5 open questions for engineering review
- Effort estimate: ~5.5 days total behind flags

### `docs/20260516_RESEARCH_AGENT_CHAT_UX_5_SURFACES_DESIGN_SPEC.md`

The Claude-Design-ready spec. 694 lines. Follows the established BioMate
format (per-Surface Entry / Layout / Data / Behaviour / Chat variant +
"Design Notes for Claude Design" close). 5 surfaces:

- **Surface 1** — Plan checklist (sticky, above chat)
- **Surface 2** — Speaker-pilled chat lines (PLAN / WF / QC / LOOP / AGENT / FIND)
- **Surface 3** — Phase card → expand to sub-trace
- **Surface 4** — Run-vs-Run comparison card (inline chat card)
- **Surface 5** — Pilot-first toggle + promotion card

Plus shared sections: Speaker Taxonomy, Auto-Proceed Conventions table,
Information Architecture sketch, Design Notes (Tone / Typography / Color /
Motion / What NOT to do / Accessibility), API endpoints, telemetry
events, E2E coverage matrix, 7 open questions, Out of Scope, Decision
Gate.

### Why two docs

The format styles are different on purpose:
- The engineering doc is dense with file paths, ORM models, feature
  flags, and rollout sequencing — what an engineer needs.
- The design spec is dense with ASCII layouts, color/motion notes, and
  "what NOT to do" — what Claude Design (or any designer) needs.

Cross-references between them at the top.

---

## 8. Bugs found and fixed along the way

Two upstream bugs from the colleague's Galaxy `dev` branch (commit
`be60cd0e7` patches them, should be reported back):

1. `llm_client.py` default model was `gemini-3-flash-preview` — a
   colleague-local proxy default. Returns 404 from real Anthropic API.
   Changed to `claude-sonnet-4-6`.
2. `agent.py:102` referenced `round_1_result['analysis']` but the
   prompt asks the LLM to return `initial_assessment`. Mismatch caused
   a `KeyError` on every "simple error" short-circuit path. Fixed with
   backward-compatible fallback.

Five pre-existing TypeScript errors in the repo (commit `d2b86cfa3`):
- `routes.ts:4465-4470` — optional-chaining left of `>` (TS18048)
- `routes.ts:8389` — dead-code comparison post-narrowing (TS2367)
- `routes.ts:9413` — `const run` declared inside `if`, used outside (TS2304)
- `galaxy-assistant.ts:3104-3106` — referenced field not on type + variable
  from a different function scope (TS2339, TS2304)

Repo now type-checks to zero errors.

---

## 9. Pre-existing executor bug surfaced (not fixed)

When the workflow's profile mismatch makes Nextflow exit 1 before any
process starts (e.g., `-profile aws` against a script with no aws
profile), `_stream_logs` correctly fires `workflow.failed`, but a
separate downstream code path later flips status to "succeeded" with
`returncode=0` based on the "0 steps were run, so trivially complete"
heuristic. Our chat-progress wire-in does the right thing (fires
`failed` with the real exit code), but the status endpoint reports
`succeeded` — confusing for users. Out of scope for this session.

---

## 10. What's open / unaddressed

- **Dev sync** to dev EC2 — gated on your explicit go-ahead
- **AWS Batch job cleanup** — when local Nextflow is killed, tasks
  already in-flight on AWS continue to completion and incur spend. A
  full cancel would also call `aws batch terminate-job` for each
  in-flight task.
- **WorkflowRestarter adaptation** — the Galaxy `queue_invoke` path in
  the ported autofix code isn't yet replaced with BioMate's
  `nextflow_executor`. Means: the autofix3 path can DIAGNOSE but can't
  apply a fix and restart. Not blocking chat-progress; it's the
  diagnose → fix → restart loop closure for a future session.
- **The 5-surface implementation** — design spec is ready, no code
  written. Review gate before implementation.
- **Per-phase skip / skip-step buttons** in the viewer — exist as
  `button-stop-phase-*` testids but not audited in this session.

---

## 11. Reading order for whoever picks this up

1. This doc (`20260517_SESSION_SUMMARY_*`) — the orientation
2. `20260516_RESEARCH_AGENT_CHAT_UX_5_SURFACES_DESIGN_SPEC.md` — what to
   build, in visual + interaction terms
3. `20260515_RESEARCH_AGENT_CHAT_UX_ENGINEERING_AUDIT_AND_PLAN.md` —
   what's already in code, what to wire, rollout order
4. `20260512_GALAXY_DEV_CAPABILITIES_AND_DEEP_AGENT_INTEGRATION.md` —
   how Deep Agent was integrated, why the chat-progress UX came about
5. `20260514_CHAT_PROGRESS_AUDIT.md` — pre-sync audit of chat-progress
6. `20260515_CONTROLS_AND_AUTOPROCEED_AUDIT.md` — pre-sync audit of
   cancel / pause / resume + auto-proceed

---

## 12. Decision points pending

From `20260516_RESEARCH_AGENT_CHAT_UX_5_SURFACES_DESIGN_SPEC.md`
section "Open Questions for Design Review":

1. Plan editability before run?
2. Same-speaker line collapse after 3 consecutive?
3. Comparison card inline vs. side panel?
4. Pilot default auto-ON for cost ≥ $5?
5. Phase expansion modal vs. inline?
6. Speaker pill placement (before or after 🔹)?
7. Comparison auto-proceed threshold definition?

Each has a recommended answer. The implementation gate is review +
sign-off on those 7 + the Auto-Proceed Conventions table.

---

## 13. Dev sync readiness

All local tests green. Real workflows on AWS Batch verify each
wire-in. TypeScript clean. The system is ready when you decide
to run `scripts/sync_to_dev.sh`. Suggested verification on dev:

1. Run the 3-process E2E test against dev to confirm phase events fire
2. Real cancel from the dev UI to confirm subprocess termination works
   behind the dev reverse proxy
3. Verify the 10s auto-proceed countdowns are visible in dev's
   production-like chat layout
4. Smoke-test the QC gate path with a real ADMET workflow that
   triggers hERG > threshold (sample input set on dev)
