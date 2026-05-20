# IND Port — Production Integration Plan + LLM Configuration

**Date:** 2026-05-20
**Branch:** `integration/next-phase`
**Scope:** Two parts — (1) the test plan that runs **after** `integrate-to-production.sh --apply`, and (2) how the regulatory LLM is wired in production for the customer flow.

---

# Part 1 — Production integration test plan

The sandbox is green (58/58, 30 audited screenshots, 10 fixed defects). The migration script is dry-run clean. This section is what happens *after* `--apply` runs.

## Pre-integration gates (must be green before `--apply`)

| Gate | How to verify |
|---|---|
| Sandbox suite green | `cd frontend && npx vite --config sandbox/ind-port/vite.config.ts --port 7791` then `npx playwright test --config sandbox/ind-port/playwright.config.ts` → 58/58 |
| Sandbox type-check clean | `npx tsc --noEmit -p sandbox/ind-port/tsconfig.json` → exit 0 |
| Live backend reachable on :8080 | `curl http://localhost:8080/api/healthz` returns 200 |
| Audit JSON has recent run | `jq '.passed,.total' frontend/sandbox/ind-port/.test-output/ind-suite-audit.json` shows `58 58` |
| Git status clean except sandbox | `git status` shows no unrelated changes |

## The migration step

```bash
bash frontend/sandbox/ind-port/integrate-to-production.sh --apply
```

The script copies 8 files, rewrites 7 import patterns, replaces the legacy 1,984-line `pages/ind-report.tsx`, and runs `tsc --noEmit` with revert-on-failure. If it errors out, the script leaves the tree clean.

## Post-integration test plan — `PI-1` through `PI-12`

Mirrors the structure of the sandbox e2e suite. New tests live under `frontend/e2e/ind-report-production.e2e.ts`. Each test has a stable `PI-N` ID. The full set runs against the production frontend on `http://localhost:5000` against the live Galaxy backend on `:8080`.

### Stage A — Build + serve

| ID | Title | Pass criterion |
|---|---|---|
| **PI-1** | `npm run build` succeeds | exit 0; `frontend/dist/public/` populated; bundle size delta vs. pre-merge ≤ +50 KB (CSS + new components are net-neutral after removing 1,984-line legacy) |
| **PI-2** | TS / ESLint clean | `npm run check` → exit 0 |
| **PI-3** | Dev server starts | `npm run dev` → :5000 returns 200 within 30s |

### Stage B — Route + auth wiring

| ID | Title | Pass criterion |
|---|---|---|
| **PI-4** | `/ind-report` returns the new page | `GET /ind-report` HTML contains `<div id="root">` + serves the new component (check for `ind-shell` class on next render) |
| **PI-5** | Existing `/drug-discovery-cro` route unaffected | snapshot diff on the CRO page → no visual change |
| **PI-6** | JWT auth required when `BIOMATE_REQUIRE_AUTH=1` | POST `/api/ind-report/projects/test/edit` without Bearer → 401; with valid JWT → 200 |

### Stage C — Feedback POSTs reach backend

The sandbox tests used `page.route()` stubs. Production tests must NOT stub — they assert the JSONL files on disk actually grow.

| ID | Title | Pass criterion |
|---|---|---|
| **PI-7** | Paragraph edit POST persists to `customer_pairs.jsonl` | `wc -l data/regulatory_training/dpo/customer_pairs.jsonl` increments by 1 after the test types + blurs a paragraph |
| **PI-8** | Audit dismissal persists to `checker_feedback.jsonl` | same pattern for dismissal |
| **PI-9** | Citation suggest persists to `citation_extensions.jsonl` | same for citation |
| **PI-10** | Regenerate-with-instruction persists to `prompt_tuning_signals.jsonl` | same for regenerate |

### Stage D — LLM serving

| ID | Title | Pass criterion |
|---|---|---|
| **PI-11** | Active-adapter badge updates from `GET /api/regulatory/active_adapter` | Anonymous request → `adapter_name = "regulatory_llm_v6"`. With `X-BioMate-Org-Id: acme` (if `paid_orgs.json` lists acme) → `adapter_name = "regulatory_llm_v6_acme"` |
| **PI-12** | First section regeneration produces real LLM output | Click "Regenerate as is" on §2.6.6 → wait for backend response → text changes; response time < 30s; output contains "[BioMate-generated draft]" disclaimer per `ind_assembly.DRAFT_DISCLAIMER` |

### Stage E — Browser + smoke

Manual: open `http://localhost:5000/ind-report` in Chrome + Firefox + Safari (or just Chrome if time is tight). Walk: onboarding → start → audit → dismiss → edit → cite → regenerate → sign. Console clean (no React warnings, no failed fetches).

## Rollback procedure

If anything in PI-1 through PI-12 fails:

```bash
# Restore the legacy file + revert all client/src changes
git restore --source=HEAD~1 frontend/client/src/pages/ind-report.tsx
git restore frontend/client/src/{styles/ind-report.css, lib/ind-report-api.ts}
rm -rf frontend/client/src/components/ind-report
# OR the nuclear option:
git revert HEAD  # reverts the integration commit
```

The sandbox stays intact at `frontend/sandbox/ind-port/` — fix forward there, re-run, re-apply.

---

# Part 2 — Regulatory LLM configuration

The IND port's value depends on the regulatory LLM. Without it, the page renders but every section is "[NO DATA AVAILABLE]". Here's how the LLM gets wired in production.

## Inventory

| Asset | Path | Purpose |
|---|---|---|
| Public v6 adapter | `models/regulatory_llm_v6/lora_adapter/` | Default adapter served to all customers |
| Per-org adapters (future) | `models/regulatory_llm_v6_{org_id}/lora_adapter/` | Paid-tier customizations |
| Paid-org allowlist | `data/regulatory_training/paid_orgs.json` | Gates org-specific adapter routing |
| Base model | Qwen3-8B (HuggingFace) | Cached locally on first load |
| Inference container | `biomate/regulatory-llm-train:latest` | Docker image with PyTorch + bitsandbytes + PEFT + TRL |
| Quantization | 4-bit NF4 via `bnb_4bit_compute_dtype=bfloat16` | Fits Qwen3-8B in ~6GB GPU memory |

## How a customer hits the LLM

```
Customer types in §2.6.6 paragraph
    │
    ▼
TipTap onBlur → captureEdit POST /api/ind-report/projects/:id/edit
    │
    ▼
feedback_io.record_customer_edit() → append to customer_pairs.jsonl
    │
    ▼ (separately, when customer clicks Regenerate)
Frontend POST /api/ind-report/sections/2.6.6/regenerate
    │
    ▼
api_router.py / ind-assembly handler calls _llm_narrative("tox_overview", ctx, region, instruction=...)
    │
    ▼
_call_local_regulatory_llm() lazy-loads via _load_local_llm():
    1. _resolve_adapter_path(org_id=X-BioMate-Org-Id) → returns the right adapter path
       • If org_id is in paid_orgs.json AND models/regulatory_llm_v6_{org}/ exists → that
       • Otherwise → models/regulatory_llm_v6/lora_adapter
    2. Loads Qwen3-8B base in 4-bit NF4 + PEFT adapter on top
    3. tokenizer.apply_chat_template(messages, enable_thinking=False)
    4. model.generate(max_new_tokens=400, temperature=0.3, top_p=0.9)
    5. Returns prose; on failure, returns "" → caller falls back to Gemini
    │
    ▼
Response includes DRAFT_DISCLAIMER prepended (audit item 8b)
    │
    ▼
TipTap re-renders the paragraph
```

## Resolution order (`_resolve_adapter_path()`)

In `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py`:

1. `REGULATORY_LLM_ADAPTER` env override (dev/debug)
2. **Per-org**: `regulatory_llm_v7_{org_id}` → `_v6_{org_id}` → `_v4_{org_id}` → ... (only if entitled per `paid_orgs.json`)
3. **Public**: `regulatory_llm_v7` → `v6` → `v4` → `v3` → `v2` → `v1`
4. Fallback to `regulatory_llm_v1` (which may not exist → caller falls back to Gemini)

The `org_id` is sanitized to `[A-Za-z0-9_-]{1,32}` to prevent path traversal.

## Environment variables (production)

| Variable | Required | Default | Effect |
|---|---|---|---|
| `BIOMATE_REQUIRE_AUTH` | **yes in prod** | `0` (dev) | When `=1`, JWT bearer is mandatory on all POST endpoints |
| `BIOMATE_INTERNAL_KEY` | **yes in prod** | unset → fail closed | Bearer token for `/api/regulatory/feedback/queue` |
| `REGULATORY_LLM_ADAPTER` | no | unset | Override the adapter path (debug only) |
| `JWT_SECRET_KEY` | yes | `CHANGE_ME_IN_PRODUCTION` | Used by `AuthService.verify_jwt_token` |
| `BIOMATE_ORG_ID_HEADER` | no | `X-BioMate-Org-Id` | Header name used by the org-aware resolver |

## paid_orgs.json schema

```json
{
  "paid_orgs": [
    "acme-therapeutics",
    "novobio-2026",
    "..."
  ]
}
```

Located at `data/regulatory_training/paid_orgs.json`. Absent → empty allowlist → all org-id headers fall back to the public adapter (no covert access to a customer's personal adapter by guessing their org_id — security gap 3e from the audit doc, now closed).

## Inference container deployment

The Docker image `biomate/regulatory-llm-train:latest` doubles as the inference container. Production runs it with:

```bash
docker run --rm -d --name biomate-llm-inference \
  --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
  -v /opt/biomate/models:/workspace/models:ro \
  -v /opt/biomate/data/regulatory_training:/workspace/data/regulatory_training:rw \
  -e BIOMATE_REQUIRE_AUTH=1 \
  -e BIOMATE_INTERNAL_KEY="$BIOMATE_INTERNAL_KEY" \
  -e JWT_SECRET_KEY="$JWT_SECRET_KEY" \
  -p 8080:8080 \
  biomate/regulatory-llm-train:latest \
  python -m galaxy.webapps.galaxy.api.serve --port 8080
```

GPU requirements: ~6 GB free VRAM with 4-bit quantization (Qwen3-8B base + LoRA adapter). The training Docker image's PyTorch has sm_121 PTX support for the GB10.

## Generation params (the page's calls)

Default in `_call_local_regulatory_llm`:
- `max_new_tokens=400`
- `temperature=0.3` (deterministic-ish)
- `top_p=0.9`
- `repetition_penalty=1.1`
- `enable_thinking=False` — Qwen3-specific; eliminates the `<think>...</think>` chain-of-thought which would burn tokens and break checker pattern matching

Sections that need longer output (e.g. §2.6.4 PK written with 9 subsections) drive multiple sequential calls, one per subsection.

## Per-customer fine-tuning (the moat)

Documented in Appendix B of `docs/20260504_IND_PRODUCT_UI_REQUIREMENTS.md`. When a paid customer accumulates ≥200 high-quality edits across ≥3 projects:

1. Reg-science team queues a training run via `scripts/build_dpo_pairs.py --mode customer-edits --org-id acme` (filter to that org's pairs)
2. `scripts/train_v7.sh data/regulatory_training/dpo/customer_validated_pairs_acme.jsonl --output models/regulatory_llm_v6_acme`
3. Adapter lands at `models/regulatory_llm_v6_acme/lora_adapter`
4. Add `acme` to `paid_orgs.json`
5. Customer's next request automatically routes to the personal adapter (no further code changes)

This is the closed loop: customer edits → DPO pairs → personal adapter → customer sees their preferences reflected.

## Weekly retrain cron

`scripts/cron/weekly_v7_retrain.sh` (already deployed):

1. Merge synthetic + rejection-sampled + customer-validated pairs
2. Skip if `< MIN_NEW_CUSTOMER_PAIRS` (25) new pairs since last run
3. Launch DPO training (3 epochs, lr=2e-4, batch 1 × grad-accum 16)
4. Evaluate against test split
5. **Auto-promote** v6→v7 only if every checker pass rate (MRSD, structural, phase-gating, tabulated, adversity) is ≥ v6 baseline within 0.5pp tolerance
6. Quarantine + alert on regression

`_resolve_adapter_path()` auto-picks the higher version on next request — no restart needed.

## Failure modes + graceful degradation

| Failure | What happens |
|---|---|
| LLM container down | `_load_local_llm()` returns False → empty string → caller falls back to Gemini (`callGeminiFlash` in `routes.ts`) |
| Adapter corrupted | `PeftModel.from_pretrained` raises → caught in `_load_local_llm` → falls back to next-best adapter (v4) → same fallback chain |
| Customer JWT expired | 401 from `/api/ind-report/*` endpoints → frontend shows reauthenticate prompt |
| GPU OOM | Generation raises; retry once with smaller `max_new_tokens=200`; on persistent failure, fall back to Gemini |
| Rate limit (60 rpm/IP) | 429 → frontend backs off + retries after `Retry-After` seconds |
| `paid_orgs.json` missing | All org-id headers fall back to public adapter (fails safe, not exposed) |

## Audit trail for regulatory compliance

Every LLM call is logged via the existing `_audit_fn` middleware in `api_router.py`. Each `POST /api/ind-report/sections/:id/regenerate` produces:

- Timestamp + user_id from JWT
- Section ID + customer instruction
- Adapter version + name (`regulatory_llm_v6` or `regulatory_llm_v6_acme`)
- SHA-256 of the generated output
- Append-only to the audit chain (visible via `/api/regulatory/feedback/queue?kind=prompt_tuning`)

Per 21 CFR Part 11, the audit trail is non-repudiable: signing the document freezes a SHA-256 over the body, the user's TOTP-validated signature, the adapter version that generated each section, and a timestamp. The sign overlay's "Audit Trail PDF" download materializes this for the customer.

---

## Decision points the team must make before going live

1. **Is the public v6 model good enough for the first paying customer?** Re-look at the v2 checklist: MRSD 92%, structural 98%, adversity 100%, phase-gating 70%, tabulated 83%. The 70% phase-gating is the weakest — v7 DPO targets this but isn't trained yet.
2. **Per-customer fine-tuning pricing.** When/how to offer the personal-adapter tier? Trigger threshold (200 edits is a guess), price markup, training cost recovery model.
3. **Gemini fallback boundary.** Is it acceptable for a paid customer to receive Gemini output when the local LLM fails? They might want strict local-only. Add an opt-out flag in `paid_orgs.json`.
4. **Data residency.** Customer edits land in `data/regulatory_training/dpo/customer_pairs.jsonl` on the inference host. For an EU customer, this may need to live in `eu-west-1`. Out of scope here — flagged in `docs/20260516_DATA_HANDLING_POLICY.md`.

These four are product/legal decisions, not engineering. Once decided, the integration is mechanical.
