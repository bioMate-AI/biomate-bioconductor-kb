# Regulatory-LLM per-org adaptation — product chain handoff (2026-06-16)

End-state of the rebuild + extension sessions. The B3 per-org adaptation
feature is now a real product surface end-to-end. This doc is the
handoff: what every step does, where it lives, how to run it, how to
extend it.

## 1. The 11-step end-to-end flow

When a customer accumulates DPO pairs from their normal IND chat-edit
flow, then opens Settings → Advanced → "Re-train on my edits":

```
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 1. Customer accepts/rejects model output in chat                    │
 │    → Pair persisted to data/regulatory_training/dpo/customer_pairs  │
 │      .jsonl with meta.org_id stamped from the user record           │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 2. User clicks "Re-train on my edits" in Settings → Advanced        │
 │    Component: frontend/client/src/components/RetrainAdapterCard.tsx │
 │    Route:     POST /api/regulatory_llm/training_jobs                │
 │    Body:      {} (adaptation_mode defaults to prompt_rules)         │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 3. Node-side route handler                                          │
 │    File: frontend/server/regulatory-training-routes.ts              │
 │    Resolves user → org_id (req.user.organization or req.user.id)    │
 │    Shells out to Python CLI                                         │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 4. regulatory_training_jobs_cli.submit                              │
 │    Sanitises org_id; writes a queued TrainingJob row to             │
 │    data/regulatory_training/training_jobs.jsonl                     │
 │    Returns the job record as JSON on stdout                         │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 5. Worker tick (dev: explicit POST .../tick; prod: long-lived       │
 │    regulatory_training_worker.run_forever)                          │
 │    Dispatches on adaptation_mode:                                   │
 │      prompt_rules    → org_rule_compiler.compile_and_write          │
 │      few_shot_index  → org_fewshot_index.build_and_write            │
 │      post_train_lora → harness-witness gate; refuses without proof  │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 6. prompt_rules compiler                                            │
 │    Reads customer_pairs.jsonl filtered to this org                  │
 │    Diffs chosen vs rejected; extracts:                              │
 │      preferred_citations  (added in chosen, absent in rejected)     │
 │      preferred_phrases    (sentences customer added)                │
 │      banned_phrases       (sentences customer removed)              │
 │    Writes:                                                          │
 │      data/regulatory_training/org_rules/<org_id>.yaml               │
 │                                                                     │
 │    OR: few_shot_index builder                                       │
 │    Walks customer_pairs.jsonl; one row per accepted (chosen) text   │
 │    Writes JSONL with section_type + token bag-of-words:             │
 │      data/regulatory_training/org_fewshot/<org_id>.jsonl            │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
              ───── (later — next IND generation request) ─────
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 7. Client → POST /api/drug-discovery/<campaign>/ind-assembly        │
 │    Node proxy at frontend/server/routes.ts wildcard                 │
 │    Detects ind-assembly path → injects                              │
 │      body.org_id = req.user.organization || req.user.id             │
 │    (no-op if body already carries org_id)                           │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 8. Galaxy backend POST handler                                      │
 │    File: backend/lib/galaxy/ai/drug_discovery/api_router.py         │
 │    INDAssemblyRequest carries org_id; passed to                     │
 │      INDSectionAssembler.assemble(..., org_id=body.org_id)          │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 9. INDSectionAssembler.assemble                                     │
 │    File: backend/lib/galaxy/ai/drug_discovery/ind_assembly.py       │
 │    Builds ctx = {... region=..., org_id=...}                        │
 │    Calls 14 section methods; each invokes _llm_narrative (or the    │
 │    autoloop wrapper for citation-critical sections) with            │
 │      org_id=ctx.get("org_id")                                       │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 10. _llm_narrative                                                  │
 │     Pre-computes deterministic MRSD anchor when NOAEL+species given │
 │     Stuffs org_id + user_prompt into shallow-copy data dict         │
 │     Calls _build_rag_context(section_type, data, region)            │
 └─────────────────────────────────────────────────────────────────────┘
                                ↓
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 11. _build_rag_context                                              │
 │     Emits in order, each as a bullet block when applicable:         │
 │       (B2)  Region-specific style rules for FDA/EMA/NMPA/PMDA       │
 │       (B3a) Org-specific rules from <org>.yaml                      │
 │             Citations the org prefers + their preferred + banned    │
 │             phrasings (≤4 cit + ≤3 pref + ≤3 banned)                │
 │       (B3b) Few-shot exemplars from <org>.jsonl                     │
 │             Top-2 by token-Jaccard with user_prompt, section-       │
 │             filtered, fallback to any-section when empty            │
 │       (existing) Narrative patterns from regulatory_skills_db       │
 │       (existing) OSP benchmark context for PBPK                     │
 │                                                                     │
 │     Block is prepended to the user_prompt; LoRA/Gemini sees both    │
 │     the customer's house-style rules AND examples from their own    │
 │     accepted edits                                                  │
 └─────────────────────────────────────────────────────────────────────┘
```

## 2. Where each piece lives

### Backend (Python, `backend/lib/galaxy/ai/drug_discovery/`)

| File | Purpose |
|---|---|
| `mrsd_calculator.py` | B1 deterministic MRSD/HED tool + OpenAI tool schema |
| `regulatory_region_packs.py` | B2 per-region style rules (FDA/EMA/NMPA/PMDA) |
| `ind_autoloop.py` | B4 checker→regen wrapper around `_llm_narrative` |
| `regulatory_metrics.py` | #49 in-memory call + fallback counters |
| `regulatory_training_jobs.py` | B3 queue (submit/list/get/mark_status) + JSONL persistence |
| `regulatory_training_jobs_cli.py` | B3 thin CLI for Node `execFile` |
| `regulatory_training_worker.py` | B3 worker `tick()` + dispatch on `adaptation_mode` |
| `org_rule_compiler.py` | B3 `prompt_rules` real compiler — chosen vs rejected diff |
| `org_fewshot_index.py` | B3 `few_shot_index` real index — pure-stdlib token Jaccard |
| `ind_assembly.py` | All wires: MRSD anchor + region rules + org rules + few-shot exemplars + autoloop |
| `api_router.py` | FastAPI router; `INDAssemblyRequest.org_id` forwarded to `assemble()` |

### Backend tests (`backend/lib/galaxy/ai/drug_discovery/tests/`)

| File | Count | Covers |
|---|---|---|
| `test_mrsd_calculator.py` | 9 | B1 round-trip with `mrsd_verifier` + schema shape |
| `test_region_packs.py` | 7 | B2 region rule lookups + caps + case-insensitivity |
| `test_autoloop_wrapper.py` | 4 | B4 clean-first, retry-with-constraint, max-attempts, empty |
| `test_regulatory_metrics.py` | 5 | #49 counters + p50/p95/p99 + ring buffer + fallback rate |
| `test_training_jobs.py` | 13 | B3 queue submit/list/get/mark + sanitise + count_edit_pairs |
| `test_training_worker.py` | 11 | B3 mode dispatch + harness-witness gate + legacy back-fill |
| `test_org_rule_compiler.py` | 11 | B3 prompt_rules extract + round-trip + load_block |
| `test_org_fewshot_index.py` | 13 | B3 few_shot_index build + section filter + Jaccard scoring |
| `test_ind_org_rag_integration.py` | 3 | End-to-end org_id wire → `_build_rag_context` blocks |
| **Total** | **76** | All pass. |

### Frontend (`frontend/`)

| File | Purpose |
|---|---|
| `client/src/components/RetrainAdapterCard.tsx` | Settings → Advanced UI affordance |
| `client/src/components/settings-dialog.tsx` | Mounts `RetrainAdapterCard` in Advanced tab |
| `server/regulatory-training-routes.ts` | Node-side `/api/regulatory_llm/*` proxy → Python CLI |
| `server/routes.ts` | Wildcard `/api/drug-discovery/*` proxy auto-injects `org_id` for ind-assembly POSTs |
| `e2e/_fixture-login.ts` | Shared CLAUDE.md-compliant fixture (no register, login only) |
| `e2e/auth-trust-matrix.e2e.ts` | C6.01–C6.04 active + C6.05 documented-skip |
| `e2e/memory-trust-matrix.e2e.ts` | C7.01–C7.05 incl. bug #58 contract |
| `e2e/retrain-jobs-trust-matrix.e2e.ts` | B3 R1–R6 routes |
| `e2e/retrain-adapter-card-trust-matrix.e2e.ts` | B3 Settings UI affordance |
| `e2e/sidebar-trust-matrix.e2e.ts` | C2 sidebar live JSX |
| `e2e/chat-trust-matrix.e2e.ts` | C3 chat |
| `e2e/ind-trust-matrix.e2e.ts` | C5 IND page + Path A.4 |
| `e2e/workflow-panel-trust-matrix.e2e.ts` | C1 workflow panel |

### Eval + corpus

| File | Purpose |
|---|---|
| `evaluation/runners/multitask_crossjudge_eval.py` | Cross-judge n=70 + bootstrap CIs |
| `evaluation/runners/reference_metrics.py` | Zero-cost reference-based scorer (chrF + ROUGE-L + num_match + cit_overlap) |
| `scripts/scrape_regulatory_corpus.py` | openFDA expansion (47 rows) + EMA scaffold |

## 3. Demo path on local dev

```bash
# Backend tests
cd backend
PYTHONPATH=lib .venv/bin/python -m pytest \
  lib/galaxy/ai/drug_discovery/tests/test_{mrsd_calculator,region_packs,autoloop_wrapper,regulatory_metrics,training_jobs,training_worker,org_rule_compiler,org_fewshot_index,ind_org_rag_integration}.py -q

# Submit a job from the CLI
PYTHONPATH=lib .venv/bin/python -m galaxy.ai.drug_discovery.regulatory_training_jobs_cli \
  submit <user_id> <org_id> prompt_rules

# Run the worker once
PYTHONPATH=lib .venv/bin/python -m galaxy.ai.drug_discovery.regulatory_training_jobs_cli \
  tick 1

# Inspect the artifact the next inference call will load
cat data/regulatory_training/org_rules/<org_id>.yaml
cat data/regulatory_training/org_fewshot/<org_id>.jsonl
```

## 4. Test gates

| Gate | Result |
|---|---|
| Backend pytest (9 modules / 76 tests) | **76/76 ✅** |
| Frontend tsc clean | **clean ✅** |
| Python module-load smoke | **9/9 ✅** |
| Dev-server boot on merged tree | **✅** |
| Runtime curl smoke (B3 + #58 + auth/me) | **9/9 expected codes ✅** |
| Trust matrices on production dev `:5000` | **21/21 + 4 documented skip ✅** |

## 5. Open items (by category)

### Budget-gated (require user approval)

- **n=30/task cross-judge expansion** — gates the B5 per-section model
  routing decision. ~$90, ~1hr runtime against `multitask_crossjudge_eval.py`.
- **Re-eval with all wires hot** — apples-to-apples cross-judge with B1
  + B2 + B4 + B3 prompt_rules + B3 few_shot active. Verifies:
    - mrsd_computation lifts to ~1.0 (deterministic MRSD anchor)
    - region_adaptation lifts above 0.388 (region packs)
    - citation_accuracy on pbpk/genotox/cardiac → ~1.0 (autoloop)
    - house-style match on customer test set (org_rules + few_shot)
  ~$30, ~30min.
- **B5 per-section model routing** — blocked on the harness witness.

### Externally blocked

- **EMA EPAR scraper** — endpoint URL scheme moved; the scraper is
  scaffolded but returns `[]` until EMA publishes a stable URL.

### Operational (whoever next interacts)

- **Customer pair recording** — the chat-edit flow that produces the
  rows the worker reads. Today the pairs file is seeded with examples;
  the production wire from chat edit → JSONL row is the missing piece
  before the prompt_rules + few_shot_index modes have real customer
  signal to compile.
- **post_train_lora real worker** — currently refuses to run without
  `models/regulatory_llm_eval_witness.json`. When the harness shows
  local > frontier on a section, drop the witness file and the worker
  will perform real GPU SFT/DPO into `models/regulatory_llm_v7_<org>/
  lora_adapter`.
- **Playwright SPA-auth cookie quirk** — Playwright tests against
  ephemeral ports fail `loginAsFixture` (SPA auth state needs
  navigation; cookie-attach alone doesn't trigger it). Harmless for
  production where tests run against `:5000`; investigate only if you
  want per-PR matrix runs on an isolated port.

## 6. Git state

| Branch | Tip | Purpose |
|---|---|---|
| `origin/integration/next-phase` | `6317b74d1d` | main — full feature set landed |
| `origin/session/regllm-rebuild-20260612` | `8e70112c8` | topic branch preserved as reference |

To bring an unrelated feature branch up to speed: `git merge origin/integration/next-phase` from that branch.

## 7. Past session docs (chronological)

- `docs/20260606_GEMMA_EVAL_LAUNCH_LESSONS.md` — 7 GPU launch failures, R1–R8 rules for next-time
- `docs/20260609_GEMMA_CROSSJUDGE_RESULT.md` — Gemma 3 12B base macro 0.255 [0.231, 0.283]
- `docs/20260609_PARALLEL_WORK_PLAN.md` — Lane A/B/C planning doc
- `docs/20260610_ZERO_COST_EVAL_PIVOT.md` — Reference-based vs cross-judge disagreement
- `docs/20260612_REGULATORY_LLM_REBUILD_SESSION.md` — First rebuild write-up
- `docs/20260612_SESSION_CLOSE.md` — Pre-loss snapshot
- `docs/20260614_REGULATORY_LLM_FINAL_VERIFICATION.md` — End-of-rebuild test gates
- **`docs/20260616_REGULATORY_LLM_PRODUCT_CHAIN.md`** — this file
