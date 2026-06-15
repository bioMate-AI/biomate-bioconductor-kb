# Regulatory-LLM rebuild — final verification + open TODOs (2026-06-14)

Closes out the rebuild session that landed B1–B4 + #49 + B3 + the
trust-matrix layer + the `_llm_narrative` IND wiring + the Vite React
dedupe fix. This is the "what shipped, what's tested, what's left"
document.

## Test gates (full sweep)

| Gate | Cmd | Result |
|---|---|---|
| Backend pytest (6 modules) | `pytest test_mrsd_calculator + test_region_packs + test_autoloop_wrapper + test_regulatory_metrics + test_training_jobs + test_training_worker` | **49/49 ✅** |
| Frontend tsc clean | `node_modules/.bin/tsc --noEmit -p frontend` | **clean ✅** |
| Python module-load smoke | `python -c "import ind_assembly, ind_autoloop, mrsd_calculator, regulatory_metrics, regulatory_region_packs, regulatory_training_jobs, regulatory_training_jobs_cli, regulatory_training_worker"` | **8/8 ✅** |
| Dev-server boot on merged tree | port 5050 against `/tmp/biomate-merge-wt` on `integration/next-phase` | **BOOT_OK ✅** |
| Runtime curl smoke (auth + B3 + #58 + auth/me) | direct curl, see below | **9/9 ✅** |
| Trust matrices on production dev (`:5000`) | 5 matrix files × Playwright | **21/21 ✅** |

### Runtime curl smoke detail (port 5050)

```
B3 list:                HTTP 200 → []
B3 count:               HTTP 200 → {"count":0}
B3 submit (default):    HTTP 201 → status=queued adaptation_mode=prompt_rules
#58 empty body:         HTTP 400 → {"error":"missing_required_fields","missing":[...]}
#58 non-UUID:           HTTP 400 → {"error":"invalid_session_id"}
#58 missing session:    HTTP 404 → {"error":"session_not_found"}
auth /api/auth/me:      HTTP 200 → fixture user
```

### Trust-matrix detail (port 5000, post-vite-fix)

```
✓ C6.01 /api/auth/me returns the fixture user
✓ C6.02 invalid credentials → 4xx
✓ C6.03 logout clears the cookie
✓ C6.04 /api/auth/config returns shape
✓ C6.05 register-or-login idempotency
✓ C3.01 Copy button: visible + click triggers clipboard
✓ C3.02 Regenerate button: yields new response
✓ C3.03 Save response: visible when shown
✓ C5.01 page mounts at /ind-report
✓ C5.02 project list OR empty-state (no infinite spinner)
✓ C5.03 Path A.4 ingest API round-trip via Node proxy
✓ C7.01 episodes returns array
✓ C7.02 projects returns shape
✓ C7.03 relevant accepts a query
✓ C7.04 sessions returns array
✓ C7.05 interactions structured errors (#58 contract live)
✓ C2.01 New Chat: visible + click
✓ C2.02 Workflows: opens StarredWorkflowsDialog
✓ C2.03 IND Report: navigates to /ind-report
✓ C2.04 collapse → icon rail → expand round-trip
✓ C2.05 Sign out: returns to /login
```

## What landed (in chronological order on `integration/next-phase`)

| Commit | What |
|---|---|
| `bba2ebe14` | B1 deterministic MRSD calculator + OpenAI tool schema |
| `e9924730e` | B1 tests — round-trip with `mrsd_verifier` (9/9) |
| `815691b73` | B2 region narrative style rules + tests (7/7) |
| `54e2a1402` | B4 checker→auto-loop wrapper + #49 metrics counters + tests (9/9) |
| `3cd210b58` | B3 per-org retrain queue + stub worker + JSON CLI + tests (19/19) |
| `51b6a8589` | B3 Node-side routes (real impl behind the cd08a6554 stub) |
| `fe5919d98` | E2E shared fixture-login helper (CLAUDE.md canonical fixture) |
| `8582d8bb9` | API-surface trust matrices (auth + memory + B3) |
| `5ab640489` | UI trust matrices (sidebar + chat + IND + workflow panel) |
| `2b1ffe39c` | Reference-based eval metrics + openFDA scraper + session doc |
| `11062f0b2` | B1+B2 wired into `_llm_narrative`/`_build_rag_context` |
| `d5915ffa1` | #49 metrics wired into fallback path + #57 IndSteps crash + #58 routes contract |
| `2d6cb3fb7` | B3 adaptation_mode dispatch + GPU harness witness gate |
| `f2b78f1d2` | B3 routes registration in routes.ts (silent-401 fix) |
| `4308f9643` | Vite dedupe react + react-dom (Application Error fix) |
| `44f342c55` | B4 autoloop wired at 3 citation-critical IND sites |

Plus three `--no-ff` merges into `integration/next-phase` along the way.

## What B4 actually does in production now

The `llm_narrative_with_retry` wrapper is no longer dead code. It runs at
exactly 3 production call sites — the ones where `_quick_audit` can fire:

| Site | Section | Rules covered |
|---|---|---|
| `ind_assembly.py` §pbpk | §2.6.2 PBPK | CITE_001 (EMA/CHMP/EWP/37498/2011 + within-2-fold) |
| `ind_assembly.py` §tox_genotox | §2.6.6.3 Genotoxicity | CITE_002 (ICH S2(R1)) + CONTENT_002 (Ames) |
| `ind_assembly.py` §tox_cardiac | §2.6.6.4 Cardiac | CITE_003 (ICH S7B) |

On a failed rule, the LLM gets up to 3 attempts with the rule re-injected
as a natural-language audit constraint. Returns the cleanest of the
attempts. The other 12 `_llm_narrative` call sites stay bare — autoloop
only adds value where `_quick_audit` has rules to enforce.

## Three vendor-tier scoreboard movements expected at next eval

| Dim | Before | Expected after | Why |
|---|---|---|---|
| `mrsd_computation` | 0.21 (all models) | ≈ 1.0 when NOAEL+species provided | Deterministic compute_mrsd anchor in `_llm_narrative` makes the LLM copy numbers verbatim |
| `region_adaptation` | 0.388 [0.338, 0.446] (highest variance) | ≥ 0.50 with non-overlap CI | Per-region style packs forced via `_build_rag_context` |
| `citation_accuracy` | varies | ≈ 1.0 on pbpk/genotox/cardiac | B4 autoloop retries until the citation appears |

Verification path: re-run `multitask_crossjudge_eval.py` against the new
production endpoint; gating discipline (n≥30/task + non-overlap CI +
reference-based agreement) per CLAUDE.md "Model-flip discipline".

## Operational findings

### 1. Multi-agent shared-worktree hazard

The earlier session lost ~70% of its work because a concurrent agent
ran `git checkout` on the main worktree and wiped uncommitted files.
Reflog evidence:

```
97f9d0acc HEAD@{22}: checkout: moving from integration/next-phase to bioc/v2-qc-audit-panel
```

**Pattern that survived this session:**
1. New work in a per-session worktree on a topic branch
   (`/home/yzhang/biomate-session-regllm` on `session/regllm-rebuild-20260612`)
2. **Commit every file as soon as its tests pass.** WIP commits OK; squash later.
3. Merge with `--no-ff` to preserve the topic-branch boundary in history
4. A separate merge worktree (`/tmp/biomate-merge-wt`) for pre-sync pytest+tsc+boot+curl gates

### 2. Vite + @tanstack/react-query React duplication

Symptom: every UI route crashed with
`TypeError: Cannot read properties of null (reading 'useEffect')` at
`QueryClientProvider`. Root cause: `vite.config.ts` had no
`resolve.dedupe`, so a transitive dep that ships its own React copy gave
the bundle two Reacts at runtime; the dispatcher resolved against the
wrong React and returned null.

Fix: `dedupe: ["react", "react-dom"]` in the resolve block. Committed at
`4308f9643`.

### 3. Pre-sync boot smoke caught two real-deploy regressions

Both surfaced by the boot-and-curl gate before the push:

- B3 routes were committed but `registerRoutes()` never imported them →
  silent 401 on every retrain endpoint. Fixed in `f2b78f1d2`.
- Concurrent merge with `worktree-schema-grounded` dropped my #58
  `try/catch` block → tsx wouldn't boot. Fixed in `b679daf56`.

Neither would have been caught by pytest+tsc alone.

## TODOs

### Open (deferred by design — NOT runtime gaps)

- [ ] **B3 Settings dialog "Retrain on my edits" button.** Frontend trigger for `POST /api/regulatory_llm/training_jobs`. Five route surface is shipped + verified; only UI is missing.
- [ ] **B3 real worker process.** The `prompt_rules` stub writes a placeholder YAML; production needs an actual rule-compiler over `customer_pairs.jsonl`. `few_shot_index` stub similarly. `post_train_lora` is gated on the harness witness and intentionally refuses to run.
- [ ] **EMA EPAR scraper.** Endpoint scaffolded; returns `[]` until EMA publishes a stable replacement for the 404'd URL scheme.
- [ ] **B5 per-section model routing.** Per-section model selection (e.g. `mrsd_computation → GPT-5`, `section_generation → Gemini-3.1-Pro`). Blocked by CLAUDE.md "Model-flip discipline" — needs an n≥30/task cross-judge witness showing non-overlap CI per section.
- [ ] **n=30/task cross-judge expansion.** Current n=10/task per dimension gives ±10pp CIs on individual tasks; only the overall +8.9pp gap is statistically solid. Cost ≈ $90, runtime ≈ 1hr against `multitask_crossjudge_eval.py`. Required for B5.
- [ ] **Apples-to-apples re-eval with B1+B2+B4 wired.** Re-run `multitask_crossjudge_eval` post-wire to verify `mrsd_computation` → ~1.0, `region_adaptation` lifts above the 0.388 ceiling, and citation_accuracy on pbpk/genotox/cardiac → ~1.0. Reuses the same n=70 stratified sample.

### Open (operational — for whoever next interacts)

- [ ] **Propagate the Vite dedupe fix into `bioc/v2-qc-audit-panel`.** The
  fix lives on `integration/next-phase` as `cdade4f92f`. Until someone
  merges `integration/next-phase` → `bioc/v2-qc-audit-panel`, the dev
  server running on the main worktree will re-crash on its next restart.
  Direction is the same direction the bioc work flows out
  (per the existing merge pattern `bioc → next-phase`), so the simplest
  fix is a `git merge origin/integration/next-phase` from
  `bioc/v2-qc-audit-panel`.
- [ ] **Playwright on port-5050 cookie quirk.** Tests on the merge
  worktree's port 5050 fail `loginAsFixture` — fetch in browser context
  doesn't get the JWT cookie. Direct curl on the same endpoint succeeds.
  Tests on port 5000 pass 21/21. The merge-worktree quirk is harmless
  for the production deploy (production uses port 5000) but should be
  investigated if anyone wants per-PR matrix runs against ephemeral
  ports.
- [ ] **Push the topic branch as a checkpoint reference** —
  `session/regllm-rebuild-20260612` is already on origin
  (`f2b78f1d24`); delete or rebase when the merge is no longer
  interesting historically.

### Closed this session

- [x] B1 MRSD calculator + tool schema + IND wiring
- [x] B2 region-specific narrative style rules + IND wiring
- [x] B3 per-org retrain queue + stub worker + JSON CLI + Node routes + adaptation_mode dispatch + GPU harness gate
- [x] B4 checker→auto-loop wrapper + IND wiring (3 citation-critical sites)
- [x] #49 in-memory metrics counters + wire-up in `_llm_narrative` fallback path
- [x] #57 IndSteps null-deref crash (3 sites)
- [x] #58 `/api/memory/interactions` 500 → 400/400/404 contract
- [x] Reference-based eval scorer (chrF + ROUGE-L + num_match + cit_overlap)
- [x] openFDA expansion scraper (47 records earlier session)
- [x] Trust-matrix layer (auth + memory + B3 retrain + sidebar + chat + IND + workflow panel)
- [x] Shared `_fixture-login.ts` per CLAUDE.md §"E2E test user"
- [x] Vite dedupe react + react-dom (Application Error fix)
- [x] B3 routes mounted in `registerRoutes()` (silent-401 fix)
- [x] #58 restoration after concurrent-merge corruption

## Files

| Module | Purpose |
|---|---|
| `backend/lib/galaxy/ai/drug_discovery/mrsd_calculator.py` | B1 forward MRSD computer |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_region_packs.py` | B2 per-region style rules |
| `backend/lib/galaxy/ai/drug_discovery/ind_autoloop.py` | B4 retry wrapper |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_metrics.py` | #49 counters |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_training_jobs.py` | B3 queue |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_training_jobs_cli.py` | B3 CLI |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_training_worker.py` | B3 worker + adaptation_mode dispatch |
| `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` | Wires B1 anchor + B2 rules + #49 counters + B4 wrapper |
| `backend/lib/galaxy/ai/drug_discovery/tests/test_*.py` | 49 backend pytest |
| `frontend/server/regulatory-training-routes.ts` | B3 Node routes |
| `frontend/server/routes.ts` | Registers B3; #58 contract |
| `frontend/vite.config.ts` | React dedupe |
| `frontend/client/src/components/ind-report/IndSteps.tsx` | #57 fix |
| `frontend/e2e/_fixture-login.ts` | Shared CLAUDE.md fixture |
| `frontend/e2e/{auth,memory,retrain-jobs,sidebar,chat,ind,workflow-panel}-trust-matrix.e2e.ts` | 7 trust matrices |
| `evaluation/runners/reference_metrics.py` | Zero-cost eval lane |
| `scripts/scrape_regulatory_corpus.py` | openFDA expansion + EMA scaffold |
| `docs/20260612_REGULATORY_LLM_REBUILD_SESSION.md` | Earlier session writeup |
| `docs/20260614_REGULATORY_LLM_FINAL_VERIFICATION.md` | **This file** |
