# Regulatory LLM — Honest Audit of Current Work

**Date:** 2026-05-16
**Purpose:** Inventory all gaps in what was built across the v6/v7/feedback-loop session. The "all 6 items complete" claim in the handoff doc is overstated in places — this doc says where.
**Audience:** future-me, anyone picking this up, a reviewer who wants to know what is and isn't actually production-ready.

---

## How to read this

Each gap is flagged with a severity:

- 🔴 **Blocks first paying customer.** Must fix before a real customer touches the system.
- 🟡 **Blocks scale.** Fine for the first 1–5 customers; breaks at 10+ or under adversarial use.
- 🟢 **Polish.** Acceptable for v6/v7; will need attention eventually.

---

## 1. v6 training corpus and evaluation

### 1a. 🔴 Synthetic test split shares generator with train split

The 5 task generators (task5–9) produced 2,688 examples. The same generator emitted both train and test rows. v6 was trained on hundreds of structurally identical examples and then "evaluated" on more of the same. The 97.9% structural pass rate is **partly memorization, not generalization**.

**What's missing:** an out-of-distribution holdout. The TGA AusPAR / Canada SBD / NMPA CDE scrapers exist but have never run successfully (sandbox network-gated). Without a real-distribution test, the v6 eval numbers are an upper bound, not a measure of customer-facing quality.

**Fix:** run the scrapers on a network-connected host, build an OOD test set of 50–100 real §2.6 prose excerpts, evaluate v6 against it. Expect significantly lower pass rates (60–80% structural is my honest guess).

### 1b. 🟡 4 of 9 checkers were never exercised in v6 eval

The eval ran the 5 checkers that had direct task counterparts (skeleton, MRSD, phase_gating, tabulated, adversity). The other 4 (cross_section consistency D1/D2, citation correctness E1/E2, BM25 retrieval grounding E4, ICH corpus lookup) **were not part of `evaluate_v6.py`**. Their pass rates on v6 are unknown.

**Why it matters:** D1/D2 cross-section is the highest-stakes checker for a real FDA submission (NOAEL in narrative must match NOAEL in tabulated summary). We don't know how v6 does on this.

**Fix:** extend `evaluate_v6.py` to call all 9 checkers and produce multi-checker assessment per example. Some examples will trigger multiple checkers (e.g. a §2.6.6 example exercises structural + cross_section + citation).

### 1c. 🟢 100% verifier pass on generated training data is tautological

Every training example was constructed by the verifier. Of course they pass. This is a property of checker-first generation but should not be cited as a quality metric.

**Fix:** stop reporting "100% pass on training data" as evidence of anything. It's a sanity check that the generator is consistent with the verifier, no more.

### 1d. 🔴 No human regulatory reviewer has read v6's output

Zero. Every v6 output we have was machine-evaluated. A regulatory affairs scientist would catch issues no checker catches: tone, hedging discipline, ICH-style passive voice, implicit clinical-relevance arguments.

**Fix:** before a paying customer touches v6, get a regulatory reviewer to read 20 outputs and grade them. Pay one if needed.

### 1e. 🟢 ROUGE-L / BERTScore never recomputed for v6

We have v4's ROUGE-L (0.576) but never measured v6's. Hard to compare cross-version on prose quality vs structural compliance.

### 1f. 🟡 Phase_gating 70% pass rate is unexplained on the test set

The eval surfaced 4/9 hERG omissions and 5/9 repeat-dose-duration / carcinogenicity omissions. But **why** the model dropped these specific bullets isn't diagnosed. Token-budget exhaustion? Prompt-order bias? Both? Without diagnosis, fixes are guesses.

**Fix:** rerun the 9 failing cases with verbose generation logging. Check if the missing studies were tokens 480–512 of a 512-token output (truncation) vs missing entirely (forgetting).

---

## 2. v7 DPO

### 2a. 🔴 v7 was never actually trained

Two TRL API compatibility bugs were fixed (`FSDPModule` shim, adaptive `DPOConfig` kwargs). Training started — DPO pairs loaded, "Starting DPO training" logged. But **a single step projected to 20–40hr** on sm_121 due to per-shape PTX recompile. The container was killed.

There is no v7 adapter. The `models/regulatory_llm_v7/` directory does not exist. Claims of "v7 pipeline ready" only mean the code path doesn't crash on import.

**Fix options:**
- (a) Run on better hardware (sm_80/86/90 has stable PyTorch). Easy if budget allows.
- (b) Reduce DPO to a much smaller subset (200 pairs, 1 epoch). Less informative but testable.
- (c) Defer DPO entirely. v6 is already 4/5 above target; the value of DPO is incremental.

### 2b. 🟡 Synthetic DPO pairs may not match v6's actual failure distribution

The 2,658 synthetic pairs use deterministic mutators (drop a bullet, swap an adversity category). v6's actual failures are different — e.g. forgetting hERG specifically, not "drop a random bullet". DPO trains the model to avoid the mutators it saw, which may or may not transfer to real failure modes.

**Fix:** rejection-sampling from dev split yielded only 1 contrastive pair (low yield because v6 generations on simple prompts often all pass). For v7 to actually help, we need either real customer failure pairs (Appendix B feedback loop) or a smarter mutator that mimics v6's actual mistakes.

### 2c. 🟢 Rejection-sample yield ratio (1/30) was never root-caused

Predicted yield was ~22/30 based on v6's 70% phase_gating pass rate. Actual was 1/30. The discrepancy was hand-waved as "v6 too good at temp=0.9". A real diagnosis would inspect the 29 prompts that didn't yield contrastive pairs and explain why.

---

## 3. Customer feedback loop backend

### 3a. 🔴 No authentication on the customer POST endpoints

`POST /api/ind-report/projects/:id/edit` accepts an `X-BioMate-Org-Id` header without verifying that the caller actually belongs to that org. Anyone hitting the endpoint writes to the training pool.

A malicious actor could:
- Spam the pool with garbage to degrade future v7+ training
- Inject jailbreak prompts as "chosen" outputs
- Pollute `citation_extensions.jsonl` with bogus guidelines that then get BM25-indexed

**Fix:** the existing BioMate auth middleware (JWT bearer) must wrap these endpoints. Add a project-ownership check: the JWT's user must own the project_id in the path.

### 3b. 🟡 No rate limiting

A determined attacker (or a buggy frontend) can pump thousands of POSTs per second. No bound on file size, no per-org rate limit. JSONL files would grow unbounded.

**Fix:** add `slowapi` or similar rate-limiter middleware. 60 req/min per IP, 600 req/min per authenticated user is a starting point.

### 3c. 🔴 PII stripping is a thin regex heuristic

`strip_pii()` catches drug-name suffixes (-mab, -tinib, -tide) and study-ID patterns. **Misses:**
- Brand names without typical suffixes (Tadalafil, Aspirin, Zoloft)
- Patient identifiers (medical record numbers, sponsor codes)
- Investigator names
- Site addresses
- Manufacturer-specific lot numbers
- CMC details that are trade secrets

The "PII stripped" claim is mostly aspirational. A customer-edit row reaching the free-tier shared pool with "Aspirin" + "patient #12345" in it would not be redacted.

**Fix:** for the free tier, the right answer is probably "don't auto-publish to shared pool — require explicit reg-science approval per row". The whole point of strip_pii was to avoid manual review; it doesn't work well enough to skip the review.

### 3d. 🟡 `_check_internal_auth` fails open

When `BIOMATE_INTERNAL_KEY` env var is unset, the internal endpoints (`/api/regulatory/feedback/queue`) return data with no auth. Fine for dev; dangerous if deployed without setting the var.

**Fix:** in production startup, refuse to launch if `BIOMATE_INTERNAL_KEY` is empty. Hard fail, not soft fail.

### 3e. 🟡 Org-id adapter routing doesn't check billing tier

`_resolve_adapter_path(org_id="acme")` will use `models/regulatory_llm_v6_acme/` if it exists, with no check that "acme" actually paid for the personal-adapter tier. If we ever ship a personal adapter for one customer, every customer who guesses or learns that org_id gets it.

**Fix:** keep a `paid_orgs.json` (or DB table) and check entitlement at resolve time.

### 3f. 🟢 Regenerate-with-instruction endpoint is half-built

The POST writes a row with `pending_completion: true` and `before: ""`, `after: ""`. The corresponding `/complete` endpoint that the script's comment promises does not exist. The flow can't actually close from the client side without it.

**Fix:** either build the `/complete` endpoint or merge the regenerate + complete into a single call that takes both `instruction` and the eventual generated text.

### 3g. 🔴 No end-to-end tests for any of the 6 endpoints

Every commit says "smoke tested". The smoke tests are Python imports + direct function calls. **No HTTP-level test exists.** A real FastAPI TestClient test that POSTs to `/api/ind-report/projects/{id}/edit` and verifies the JSONL row appears — doesn't exist.

**Fix:** add `backend/lib/galaxy/ai/drug_discovery/tests/test_feedback_router.py` with TestClient-based tests for all 6 endpoints. Standard practice; missing.

### 3h. 🟢 JSONL schema has no versioning

If we change a field name later, old rows become unreadable. No `schema_version` key in any record.

**Fix:** add `schema_version: 1` to every appended record. Cheap insurance.

---

## 4. Production wiring

### 4a. 🟡 v6 was never actually loaded at request time

`_resolve_adapter_path()` was unit-tested to return the v6 path. The Galaxy backend was **never restarted** after the wiring change. The first real backend reload could surface an issue (CUDA OOM, adapter format mismatch, PEFT version) that the unit test couldn't catch.

**Fix:** on the dev EC2 instance, `kill -HUP $(pgrep -f "gunicorn.*8081")` and call `_call_local_regulatory_llm` via `/api/ai_assistant/...` to confirm v6 actually generates.

### 4b. 🟡 No fallback when v6 adapter is corrupted or missing

If `models/regulatory_llm_v6/lora_adapter/adapter_config.json` is somehow corrupted or partially synced, `_load_local_llm()` crashes. There's no graceful fallback to Gemini or to v4.

**Fix:** wrap `PeftModel.from_pretrained` in try/except, fall back to next-best adapter on failure. Log loudly so the issue is visible.

### 4c. 🟢 No model-version audit trail

Filesystem name (`regulatory_llm_v6`) is the only versioning. Which training run produced it, which corpus version, which hyperparameters — all in the commit history but not bundled with the adapter.

**Fix:** the existing `eval_metrics.json` next to each adapter is a start; add `training_manifest.json` with corpus hash + git SHA + hyperparams.

---

## 5. Documentation

### 5a. 🟢 5 separate docs, some overlap, no canonical entry point

We have:
- `docs/20260512_REGULATORY_LLM_V6_V7_PIPELINE.md` — architecture
- `docs/20260509_FDA_REVIEWER_CHECKLIST_V2.md` — checker spec
- `docs/20260510_DOCUMENT_GENERATION_APPROACH.md` — methodology
- `docs/20260514_REGULATORY_LLM_IMPLEMENTATION_HANDOFF.md` — pickup-cold reference
- `docs/20260516_REGULATORY_LLM_V9_MODALITY_ROADMAP.md` — future work

Plus 2 UI design docs (studio + customer product). 7 docs total. Some content overlaps (e.g. checker stack described in 3 places).

**Fix:** add a `docs/REGULATORY_LLM_INDEX.md` (or update CLAUDE.md) with a 1-line summary + read-order for each doc. The handoff doc has a "Critical files for handoff" section that's a partial start.

### 5b. 🟡 Handoff doc claims "all 6 items complete" — overstated

Items 1–3, 5, 6 have code paths that work in isolation. Item 4 (overrides loader) actually changes behavior end-to-end (verified). But none of items 1–6 have HTTP-level tests, none have been deployed to dev EC2, none have been touched by a real customer. "Complete" should mean "shipped and exercised", not "code exists".

**Fix:** add an explicit "exercised" column to the status table — Code / HTTP-tested / Deployed / Customer-validated.

---

## 6. Real-data scrapers

### 6a. 🔴 None of the 3 scrapers have ever run successfully end-to-end

`scrape_auspar_nonclinical.py`, `scrape_canada_sbd.py`, `scrape_nmpa_cde_reviews.py` — all committed, none have produced a single record. Sandbox blocks egress to all three sites.

The section-extraction regex patterns are **guesses** based on URL conventions and 2-3 web search descriptions. The actual layout of TGA PDF / HC HTML / CDE HTML has never been inspected with the scraper code.

**Fix:** run on a network-connected host. Inspect first 3 documents per source manually. Adjust regex. Iterate until extraction works.

### 6b. 🔴 NMPA CDE seed URLs are placeholders

`SEED_URLS` in `scrape_nmpa_cde_reviews.py` contains hand-typed hex strings that don't correspond to real CDE document IDs. The script will 404 on every URL until the seed list is replaced with real IDs from `https://www.cde.org.cn/main/xxgk/listpage/`.

The script is staged code, not staged data.

---

## 7. Biologics MABEL checker

### 7a. 🟡 Only 4 hand-crafted test cases

The smoke test has 4 cases. The checker has not been tested against real biologic §2.6 prose. The regex patterns may fail on phrasings the test cases didn't anticipate.

**Fix:** when we have a real biologic customer, run their first 20 §2.6 outputs through the checker, hand-grade discrepancies, fix patterns.

### 7b. 🟡 Not wired into any generator yet

There's no `task10_mabel_computation.jsonl`. Without an SFT task, v6+1 won't learn to produce MABEL outputs that pass this checker. The checker is currently aspirational for evaluation only.

**Fix:** mirror task5's structure: parametric sampler over target type, RO threshold, EC50, safety factor; one prose realizer per derivation method.

### 7c. 🟢 `phase_gating.py` not yet aware of biologics modality

For full biologic support, `required_studies()` needs a `modality="biologic"` branch that swaps M3(R2) requirements for S6(R1) (1 species OK, no traditional genotox, immunogenicity assessment). Currently the function defaults to M3(R2) regardless of modality.

---

## 8. Cross-cutting / things outside any single component

### 8a. 🔴 No GDPR / HIPAA review for customer data capture

The customer-edit JSONL pool captures arbitrary customer text including (potentially) drug names, study IDs, sponsor codes, possibly even patient identifiers. We have no:
- Data Processing Agreement template
- Customer-facing privacy notice
- Data retention policy (how long do we keep edits?)
- Right-to-deletion path (if a customer leaves, do we purge their pairs?)
- Geographic data residency (where do the JSONL files live?)

For a US/EU customer, this is a real compliance gap. For a pharma customer, **double-real**.

**Fix:** before first paying customer, draft a one-page data handling policy. At minimum: encryption at rest, 90-day retention default, right-to-deletion endpoint, US/EU region pin.

### 8b. 🔴 No "DRAFT — human review required" disclaimer enforced in output

The §2.6 documents we generate could be downloaded as DOCX and pasted into a real IND submission. Without a mandatory disclaimer ("This is a computational draft. Regulatory affairs review and electronic signature required before submission to FDA/EMA/NMPA"), we have liability exposure if a customer ever submits an unedited output.

**Fix:** prepend a disclaimer paragraph to every section. Make it part of the structural validator (required first paragraph). Customer can move it during editing but can't strip it without conscious effort.

### 8c. 🟡 No load / scale testing

Backend was never tested with concurrent requests, GPU OOM, or sustained traffic. Single-user mode only.

**Fix:** simple `locust` or `wrk` test against the running backend with 10 concurrent customers. Spot the bottleneck (likely the LLM call, not the feedback endpoints).

### 8d. 🟡 No metrics dashboard / alerting

If v6 starts producing garbage at request time (CUDA error, OOM, partial generation), nobody knows. No Prometheus metrics, no alert routing.

**Fix:** at minimum, increment counters in `_call_local_regulatory_llm` (success / fail / fallback / timeout) and expose via the existing BioMate metrics surface.

### 8e. 🟢 No customer onboarding playbook

When the first customer arrives, the steps from "they sign up" to "they see their first §2.6 draft" are not written down anywhere.

**Fix:** a single page in `docs/customer_onboarding.md`. Maybe a checklist of: project setup, SMILES upload, modality selection, region selection, run pipeline, review draft, edit, sign.

### 8f. 🟢 No pricing model in any committed doc

`docs/20260430_PRODUCTIZATION_ASSESSMENT.md` mentions "$15–40K per compound per IND package" as a guess. Nothing committed says what we actually charge or how billing works.

### 8g. 🔴 Frontend integration: ZERO

`regulatory-document-editor.tsx` exists. `ind-report.tsx` exists. Neither has been visually verified against v6 output. Neither has the feedback-loop UI surfaces (edit hint, dismissal picker, citation [+], regenerate-with-instruction) from Appendix B implemented.

Until Claude Design completes UI build and we wire it, the customer never sees v6.

---

## 9. v8+ entirely on paper

### 9a. 🟢 v8 RL training with composite checker reward

Mentioned in multiple docs as "the next step after v7". No code path exists. The reward function isn't designed beyond the weighted-sum sketch in `20260509_FDA_REVIEWER_CHECKLIST_V2.md` §RL reward design.

### 9b. 🟢 Per-customer fine-tuning pipeline

Appendix B describes the moat. Backend resolver supports it. But no script trains a per-customer adapter. No data pipeline collects "this customer's edits → these are their pair files". The moat is currently architectural, not operational.

---

## Severity tally

| Severity | Count | Examples |
|---|---|---|
| 🔴 Blocks first paying customer | 9 | No auth, no PII review, no human reviewer test, v7 never trained, OOD test absent, frontend zero, GDPR/HIPAA gap, no draft disclaimer, scrapers never run |
| 🟡 Blocks scale | 11 | No rate limit, no scale testing, 4 checkers not evaluated, biologics not wired into generator, no fallback, etc. |
| 🟢 Polish | 9 | Doc index, schema versioning, ROUGE comparison, etc. |

**Total: 29 gaps.** The "all 6 items complete" framing of the handoff doc is **directionally true (code paths exist)** but **practically misleading (no HTTP tests, no deployment, no customer-validated flow)**.

---

## Top 5 to fix before any customer touches this

1. **Auth + rate limiting on POST endpoints** (3a, 3b) — half a day
2. **Draft disclaimer enforced in output** (8b) — half a day
3. **GDPR/HIPAA one-pager + retention policy** (8a) — half a day (mostly text)
4. **HTTP-level end-to-end tests for all 6 endpoints** (3g) — one day
5. **Run scrapers, build real OOD holdout, re-evaluate v6** (1a, 6a) — two days

Total: ~5 working days of focused fix work before the system is honest enough to put in front of a real customer.

---

## What this audit doesn't catch

Things that probably exist that I haven't noticed:
- LLM hallucination patterns specific to the regulatory domain that no checker catches
- Token-budget edge cases (a long input might never produce a complete §2.6.6)
- Behavior under genuinely adversarial customer input (jailbreak attempts, prompt injection in study reports)
- Drift over time as Qwen3 base model gets new releases

The audit is honest about what I built. There are categories of unknown unknowns that only real customer exposure surfaces.
