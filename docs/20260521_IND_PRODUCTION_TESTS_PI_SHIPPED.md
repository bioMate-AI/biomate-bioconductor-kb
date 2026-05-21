# IND Port — Production Integration Tests (PI-1..PI-12) Shipped

**Date:** 2026-05-21
**Branch:** `integration/next-phase`
**Continues:** `docs/20260520_IND_PRODUCTION_INTEGRATION_PLAN.md`
**Status:** Test suite landed. 8/8 runnable tests green. 4 tests intentionally env-gated.

---

## What landed

Two artifacts:

1. **`frontend/e2e/ind-report-production.e2e.ts`** — the PI-1..PI-12 suite from the integration plan, made real.
2. **`frontend/server/routes.ts`** — a 5-route proxy block from the Node frontend (`:5000`) to the Galaxy backend (`:8081`) for `/api/ind-report/*` and `/api/regulatory/active_adapter`.

The proxy was missing — the new IND API client (`frontend/client/src/lib/ind-report-api.ts`) uses same-origin relative URLs, so browser POSTs would have 404'd at `:5000`. The integration plan doc didn't catch this; the test suite did.

---

## Test results

```
8 passed   4 skipped   0 failed   (4.9s wall clock)
```

| ID | What it proves | Result |
|---|---|---|
| PI-1 | `npm run build` exit 0, bundle delta ≤ +50 KB | Skipped (env-gated; ran once at session start: exit 0, 9.4s, `index-*.js` 3.28 MB / gzip 861 KB) |
| PI-2 | `tsc --noEmit` exit 0 | Skipped (env-gated; ran once: exit 0) |
| PI-3 | Dev server on `:5000` returns 200 | ✅ |
| PI-4 | `/ind-report` serves new IND shell post-auth | ✅ |
| PI-5 | `/drug-discovery-cro` unaffected by integration | ✅ |
| PI-6 | `BIOMATE_REQUIRE_AUTH=1` → 401 without Bearer | Skipped (needs env flip on backend; see "Deferred" below) |
| PI-7 | Paragraph edit POST appends to `dpo/customer_pairs.jsonl` | ✅ |
| PI-8 | Audit dismissal POST appends to `checker_feedback.jsonl` | ✅ |
| PI-9 | Citation suggest POST appends to `citation_extensions.jsonl` | ✅ |
| PI-10 | Regenerate POST appends to `prompt_tuning_signals.jsonl` | ✅ |
| PI-11 | `GET /api/regulatory/active_adapter` resolves anon + paid-org | ✅ |
| PI-12 | Live LLM regeneration produces real prose | Skipped (needs Qwen3-8B inference container; see "Deferred") |

The Stage C tests are the meaty signal — they hit the Node proxy → Galaxy → on-disk JSONL path with no `page.route()` stubs, assert the file grew by exactly one line, and complete in ~13–25 ms each.

---

## Corrections vs. the integration plan

The plan doc `docs/20260520_IND_PRODUCTION_INTEGRATION_PLAN.md` had two factual errors that the test suite exposed:

1. **Plan port `:8080` → reality `:8081`.** Per `CLAUDE.md "Local Service Map"`, Galaxy backend runs on `:8081`. The `:8080` figure was lifted from the Docker container example in Part 2 of the plan (which is a production deployment template, not the local dev port).
2. **Missing Node proxy.** The plan assumed `/api/ind-report/*` would be reachable from the browser at `:5000`. It wasn't, until this session's `routes.ts` edit. The proxy block is at the end of `registerRoutes()` and forwards verbatim while preserving `Authorization` + `X-BioMate-Org-Id`.

Neither was caught by the sandbox tests because they ran against a stand-alone Vite server on `:7791` with `page.route()` stubs.

---

## What "paid customers" means in this context

When PI-6 is described as load-bearing "for paid customers," that's the org-tier LLM routing already implemented in `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py::_resolve_adapter_path()`. The relevant bit:

- **Public tier** — every user gets the shared `models/regulatory_llm_v6/lora_adapter`.
- **Paid tier** — orgs listed in `data/regulatory_training/paid_orgs.json` get a personal adapter at `models/regulatory_llm_v6_{org_id}/lora_adapter`, fine-tuned on *that org's own captured edits*.

The customer's browser sends `X-BioMate-Org-Id: acme` on every IND POST; the resolver routes:

1. If `acme` is in `paid_orgs.json` AND `models/regulatory_llm_v6_acme/` exists → personal adapter.
2. Otherwise → public adapter (silent fallback; no covert access to other orgs' adapters by guessing IDs).

PI-6 (the auth gate) matters most for the paid tier because their edits feed back into *their* training corpus via `feedback_io.record_customer_edit(..., org_id=acme)`. If `BIOMATE_REQUIRE_AUTH` is silently off in production, an unauthenticated client could POST edits tagged as `acme` and poison the acme adapter's next retrain. The 401 is the lock on that door.

For public-tier users alone, the risk is lower — edits land in a shared corpus that goes through review queue + checker validation before any retrain.

---

## Deferred (env-gated, not code-blocked)

### PI-1 / PI-2 — `PI_RUN_BUILD=1` / `PI_RUN_TSC=1`

Both ran cleanly at session start. Skipping in the e2e suite avoids burning ~50s on every PR check. Set the env var to re-run on demand.

### PI-6 — `BIOMATE_REQUIRE_AUTH=1`

The current dev backend runs with `BIOMATE_REQUIRE_AUTH` unset. To exercise the gate, restart Galaxy with the env var exported:

```bash
BIOMATE_REQUIRE_AUTH=1 bash backend/start_backend.sh
BIOMATE_REQUIRE_AUTH=1 npx playwright test e2e/ind-report-production.e2e.ts
```

The test then asserts:
- POST without `Authorization: Bearer …` → 401
- (positive-case round-trip with valid JWT is covered by Stage C tests, which are auth-pass-through under dev mode)

This is a prerequisite for any **paid customer** going live. Public-tier launch can ship without it; multi-tenant launch cannot.

### PI-12 — `PI_REQUIRE_LOCAL_LLM=1`

Requires the Qwen3-8B + LoRA adapter inference container running. Today only `/api/ind-report/sections/:id/regenerate` (the *signal capture* route) is wired; the actual prose-generation route from `ind_assembly._llm_narrative()` is invoked elsewhere in the IND pipeline. PI-12 is the smoke check that the live LLM is producing real text, not just an empty fallback. Enable when the Qwen3 container is provisioned on the dev EC2.

---

## Operational notes from this session

- Galaxy gunicorn workers were wedged at session start (every request hung to timeout). Restart via `bash backend/start_backend.sh` cleared it. Root cause not investigated — flagging for follow-up if it recurs.
- Node `tsx server/index.ts` is **not** in watch mode, so changes to `routes.ts` require a full process restart, not a HUP. Plan for this when iterating on the proxy.
- `frontend/e2e/test-results/` had root-owned subdirs from an old run, blocking the default Playwright reporter. Worked around with `--output=/tmp/pi-test-results`. Cleanup is a separate chore.

---

## Files touched

| File | Change | Lines |
|---|---|---|
| `frontend/e2e/ind-report-production.e2e.ts` | NEW — PI-1..PI-12 suite | ~290 |
| `frontend/server/routes.ts` | EDIT — 5 IND proxy routes appended at end of `registerRoutes()` | +43 |
| `docs/20260521_IND_PRODUCTION_TESTS_PI_SHIPPED.md` | NEW — this doc | — |

`npm run check` clean.

---

## Next moves (not in this session)

1. **Wire the live LLM container** so PI-12 turns green. Needs Qwen3-8B + LoRA adapter on a GPU box reachable from the backend.
2. **Flip `BIOMATE_REQUIRE_AUTH=1`** on the dev backend and verify PI-6 + that the Stage C tests still pass when a valid JWT is sent.
3. **Connect the `/regenerate` signal capture to real LLM regeneration** — today the route only records the prompt-tuning signal; it doesn't return generated prose. The pipeline regeneration endpoints in `api_router.py` need to be reachable from the IND port UI, or `/regenerate` needs to be extended.
4. **Onboard the first paid org** to `paid_orgs.json` once OQ-1 from the integration plan has data (median edits per 1000 chars ≤ 30).
