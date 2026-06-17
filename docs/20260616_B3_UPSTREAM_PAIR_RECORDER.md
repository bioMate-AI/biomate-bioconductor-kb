# B3 upstream — pair recorder (closes the feedback loop) — 2026-06-16 PM

Companion to `docs/20260616_REGULATORY_LLM_PRODUCT_CHAIN.md` (AM session).
That doc covered the downstream half (job queue → worker → compile →
RAG injection). This doc covers the upstream half (chat edit → pair
recorder → JSONL append) that just shipped.

## What was missing this morning

The product-chain doc described an 11-step flow that started at
"customer accumulates DPO pairs from their normal IND chat-edit flow."
That first step was load-bearing — and there was no production wire
into it. Pairs had to be hand-seeded into
`data/regulatory_training/dpo/customer_pairs.jsonl`. Without that wire,
the worker had nothing to compile.

## What landed (commit `4494ae0dda`)

### 1. `backend/lib/galaxy/ai/drug_discovery/regulatory_pair_recorder.py`

Single owner of the on-disk path + JSONL format. Functions:

- `record_pair(user_id, org_id, chosen, rejected, section_type, task,
  prompt, meta_extra, pairs_path=None) → dict`

  Validates + sanitises + appends one DPO row. Returns the persisted
  row with `meta.row_id` (UUID) and `meta.recorded_at` (unix epoch).
  Sanitises `org_id` with the same regex `regulatory_training_worker`
  uses (`[^A-Za-z0-9_\-]` stripped, capped at 32 chars) so writes land
  where the worker reads. Caps each text side at 8K chars. Raises
  `ValueError` on empty `user_id`, invalid `org_id`, or both
  `chosen`+`rejected` empty.

- `count_for_org(org_id, pairs_path=None) → int`

  Matches `regulatory_training_jobs.count_edit_pairs` semantics:
  rows with `meta.org_id == org_id` plus untagged rows (treated as
  global/seed pairs) both count.

Notable: the `pairs_path` defaults are `None` (resolved to module-level
`PAIRS_PATH` at call time), NOT `pairs_path=PAIRS_PATH`. That avoids
the Python late-binding gotcha where `monkeypatch.setattr` on the
module global doesn't reach a default frozen at function definition.

### 2. `record_pair` CLI verb

`backend/lib/galaxy/ai/drug_discovery/regulatory_training_jobs_cli.py`
gains the verb so the Node side can shell out:

```
echo '{"chosen":"...","rejected":"...","section_type":"pbpk"}' \
  | python -m galaxy.ai.drug_discovery.regulatory_training_jobs_cli \
      record_pair <user_id> <org_id>
```

Body shape: `{chosen, rejected, section_type?, task?, prompt?, meta?}`.
Reads from stdin so multi-line text doesn't fight shell quoting.

### 3. Node route — `POST /api/regulatory_llm/pairs`

In `frontend/server/regulatory-training-routes.ts`:

- `authenticateToken`
- Server-side `orgFor(req.user)` stamping — the client cannot supply
  `org_id` (anti-spoofing; a user can only record pairs for their own
  org)
- Empty `chosen` and empty `rejected` → `400 missing_chosen_or_rejected`
- CLI failure → `400 record_failed` with `stderr` in `detail`
- Success → `201` + the persisted row

Uses a new `runCliWithStdin` helper (next to the existing `runCli`)
that pipes the body JSON into the child process's stdin.

### 4. Tests (11 new, total 87/87 backend)

`backend/lib/galaxy/ai/drug_discovery/tests/test_regulatory_pair_recorder.py`:

| Test | Asserts |
|---|---|
| `test_record_pair_writes_row` | Returned row + persisted line match; `row_id` + `recorded_at` populated |
| `test_record_pair_sanitises_org_id` | `acme'inc!@#` → `acmeinc` |
| `test_record_pair_rejects_invalid_org_id` | `!!!` → `ValueError(invalid org_id)` |
| `test_record_pair_rejects_empty_user` | empty `user_id` → `ValueError(user_id required)` |
| `test_record_pair_rejects_both_sides_empty` | empty chosen + empty rejected → `ValueError(at least one)` |
| `test_record_pair_truncates_runaway_input` | 50000-char chosen → truncated to 8000 |
| `test_record_pair_appends_does_not_overwrite` | 3 calls → 3 lines on disk |
| `test_count_for_org_matches_org_and_global` | `acme` rows + untagged global = 2; `unknown` org = 1 (just global) |
| `test_count_for_org_missing_file_returns_zero` | absent path → 0, no crash |
| `test_meta_extra_merged` | `meta_extra={campaign_id, noael_mg_per_kg}` merged into row meta |
| `test_full_round_trip_recorder_to_worker_to_compiler` | record_pair → `rj.count_edit_pairs` → worker tick → `org_rule_compiler` extracts the citation we recorded |

## Test gates (full)

| Gate | Result |
|---|---|
| Backend pytest (10 modules / 87 tests) | **87/87 ✅** |
| Frontend tsc clean | **clean ✅** |
| Python module-load smoke | **9/9 ✅** |
| CLI smoke (`record_pair smoke-user smoke-org` via stdin JSON) | **persisted row visible on disk; cleaned up after** |

## Full per-org adaptation loop (now closed)

```
1.  Customer edits an IND prose draft in chat
                ↓
2.  Frontend POSTs /api/regulatory_llm/pairs with {chosen, rejected, section_type}
                ↓
3.  Node route stamps org_id from req.user (anti-spoofing) →
    shells to record_pair CLI verb
                ↓
4.  regulatory_pair_recorder.record_pair appends to
    data/regulatory_training/dpo/customer_pairs.jsonl
                ↓
        (time passes; customer accumulates pairs)
                ↓
5.  Customer clicks "Re-train on my edits" in Settings → Advanced
                ↓
6.  POST /api/regulatory_llm/training_jobs (mode = prompt_rules by default)
                ↓
7.  Worker tick → prompt_rules compiler + few_shot_index builder
    (both real impls — chosen-vs-rejected diff + token-overlap retrieval)
                ↓
8.  Artifacts land at data/regulatory_training/{org_rules,org_fewshot}/<org>.yaml/jsonl
                ↓
        (next IND assembly request)
                ↓
9.  POST /api/drug-discovery/<campaign>/ind-assembly
                ↓
10. Node proxy auto-injects body.org_id = req.user.organization
                ↓
11. INDSectionAssembler.assemble(..., org_id=...) → ctx['org_id']
                ↓
12. 14 _llm_narrative + autoloop call sites forward org_id
                ↓
13. _build_rag_context emits:
      • Region-specific style rules (B2)
      • Org-specific rules from <org>.yaml (B3a)
      • Top-K few-shot exemplars from <org>.jsonl (B3b)
      • Skills-DB narrative patterns (existing)
      • OSP benchmark context for PBPK (existing)
                ↓
14. LLM sees both the customer's house-style rules AND examples
    from their own accepted edits → adapted output
```

## What's still upstream-missing (operational)

The recorder is wired and tested, but the chat-edit UI doesn't yet
emit the call. The two natural production callsites for `POST
/api/regulatory_llm/pairs`:

1. **Chat-message edit affordance** — when a user edits the assistant
   message, the original message is `rejected` and the edited version
   is `chosen`. Single network call on save.
2. **IND prose section edit affordance** — same idea but scoped to the
   IND assembly document panel. Has the advantage of carrying
   `section_type` cleanly (the user is editing pbpk vs tox_genotox vs
   admet, not a generic chat reply).

Either one is a one-handler addition. The recorder + route + CLI
verbs + tests are all already in place to consume them.

## What's still gated (budget / external)

| Item | Blocker |
|---|---|
| EMA EPAR scraper | EMA URL scheme moved; scaffolded, returns `[]` until stable URL |
| n=30/task cross-judge expansion | ~$90 budget |
| Re-eval with all wires hot | ~$30 budget |
| B5 per-section model routing | n=30/task harness witness |
| `post_train_lora` real GPU worker | harness witness + GPU budget |

## Files added / changed (this commit)

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/drug_discovery/regulatory_pair_recorder.py` | NEW |
| `backend/lib/galaxy/ai/drug_discovery/regulatory_training_jobs_cli.py` | added `record_pair` verb |
| `backend/lib/galaxy/ai/drug_discovery/tests/test_regulatory_pair_recorder.py` | NEW (11 tests) |
| `frontend/server/regulatory-training-routes.ts` | added `runCliWithStdin` + `POST /api/regulatory_llm/pairs` |
| `docs/20260616_B3_UPSTREAM_PAIR_RECORDER.md` | NEW — this file |

## Git tip after this commit

```
origin/integration/next-phase: 4494ae0dda
origin/session/regllm-rebuild-20260612: <same — fully merged>
```
