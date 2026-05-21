# Regulatory LLM — Product & Business Model

**Date:** 2026-05-21
**Status:** Working draft. Pricing tiers are hypotheses, not decisions. Empirical questions left open per `docs/20260520_IND_PRODUCTION_INTEGRATION_PLAN.md` OQ-1..OQ-4.

---

## What the product is

A fine-tuned LLM (Qwen3-8B base + LoRA adapter, ~6 GB GPU memory at 4-bit NF4) that writes the prose body of FDA IND module sections — specifically §2.6 (Nonclinical Summaries) and adjacent subsections. The customer interacts with it through the IND Report page that just shipped to production this session:

- They click **Regenerate** on a paragraph → adapter writes fresh prose grounded in their compound's data.
- They edit the result in TipTap → every change is captured as a DPO pair.
- They click **Sign** → 21 CFR Part 11 signature freezes a SHA-256 over the final document plus the adapter version that generated each section.

The competitive thesis: regulatory writing is high-stakes, low-creativity, and bounded by a finite set of guidelines (ICH M3(R2), CDER reviewer rules, 21 CFR Part 11). A purpose-trained small model with deterministic checkers (MRSD calc, phase-gating, tabulated-vs-prose, adversity-tense) beats a frontier model with a general system prompt on:

- **Correctness against checkers** — v6 hits ≥70% checker pass rate on held-out IND sections.
- **Auditability** — every generation logs adapter version + content hash to the append-only audit chain.
- **Customer voice** — paid-tier customers' edits train an adapter to *their* phrasing and structural preferences.

Everything in the rest of this doc is downstream of those three.

---

## Two-tier model

### Public tier — `regulatory_llm_v6`

- Same adapter for every user. Trained on the shared corpus (synthetic + checker-grounded SFT + DPO from anonymous + opt-in customer edits).
- Free or freemium. Acts as the funnel for the paid tier.
- Risk: customer edits land in the shared corpus and influence everyone's next adapter. Mitigated by review-queue gating + the org-id sanitization layer that strips identifying tokens before SFT.

### Paid tier — `regulatory_llm_v6_{org_id}`

- Per-org personal adapter, fine-tuned on **that customer's own captured edits** via DPO.
- Customer sends `X-BioMate-Org-Id: acme` on every IND POST.
- Resolution chain in `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py::_resolve_adapter_path()`:
  1. `REGULATORY_LLM_ADAPTER` env override (debug only).
  2. **Per-org**: `regulatory_llm_v7_acme` → `_v6_acme` → ... if `acme` is in `paid_orgs.json`.
  3. **Public fallback**: `regulatory_llm_v7` → `v6` → ...
- Org ID is sanitized to `[A-Za-z0-9_-]{1,32}` to prevent path traversal.
- An unentitled org-id silently falls back to public (no probing for other orgs' personal adapters by guessing names).

The paid-tier promise to the customer: *"The model writes the way your regulatory team writes."*

---

## The feedback flywheel (the moat)

This is the central loop. It already exists in code (`feedback_router.py` + `feedback_io.py`); pricing decides who is allowed to ride it.

```
Customer types in IND Report TipTap editor
        │
        ▼
POST /api/ind-report/projects/:id/edit          (PI-7, just verified green)
        │
        ▼
record_customer_edit() appends to customer_pairs.jsonl
        │
        ▼ (weekly cron: scripts/cron/weekly_v7_retrain.sh)
DPO training over (chosen=edited, rejected=original) pairs
        │
        ▼
Auto-promote adapter only if every checker pass-rate ≥ baseline within 0.5pp
        │
        ▼
Next customer regenerate → reflects their preferences
```

**Reinforced surfaces** (each turns into a different DPO/SFT signal):
- Paragraph edits → DPO chosen/rejected pairs.
- Audit-finding dismissals (with reason enum) → checker rule refinement signal.
- Citation suggestions → corpus-extension review queue.
- Regenerate-with-instruction → prompt-tuning signal.

For the public tier, all four streams enter a single shared training set. For the paid tier, each org's stream is held separately and trains *only their adapter*, gated by entitlement (`paid_orgs.json`).

---

## What's actually built today

| Asset | Status |
|---|---|
| Public adapter `regulatory_llm_v6` | ✅ trained, on disk, served (PI-11 green) |
| 9 deterministic checkers (MRSD, phase-gating, tabulated, adversity, ...) | ✅ wired |
| 4 feedback POSTs landing in JSONL | ✅ PI-7..10 green |
| `paid_orgs.json` entitlement gate | ✅ code exists, file is empty (no paid customers yet) |
| Per-org adapter `_v6_acme` style training pipeline | ✅ `scripts/build_dpo_pairs.py --org-id` exists |
| Weekly retrain cron `weekly_v7_retrain.sh` | ✅ deployed |
| Auto-promote on checker non-regression | ✅ implemented |
| 21 CFR Part 11 signature + audit chain | ✅ shipped this session |
| Active-adapter badge in UI | ✅ shipped this session (PI-11 verified the endpoint) |
| **Live LLM regeneration in the IND Report UI** | ⚠️ signal capture wired; prose generation route still needs to connect through |
| **Auth gate for production** (`BIOMATE_REQUIRE_AUTH=1`) | ⚠️ code exists, not yet enabled — PI-6 deferred |
| **Per-org GPU isolation / data residency** | ⚠️ all data in `us-west-2` today; EU residency deferred until first EU customer (OQ-4) |

The MVP for paid GA is gated on three of those ⚠️ items — not on training a better model.

---

## Pricing hypotheses (to be validated, not decided in a room)

These are **starting points for negotiation**, not list prices. Per OQ-2, the right per-customer tier is the inflection point where their captured edits start to outperform the public adapter on their own holdout. Until at least one customer crosses ~100 captured pairs, we're guessing.

### Public tier

- **Free or freemium.** Caps on regenerations/day. Audit log is shared-corpus-visible (their edits feed the public adapter).
- Conversion driver: customer hits the caps, or wants to keep their edits private to their own adapter.

### Paid tier

- **Subscription, per-org.** Indicative band $50-150K/yr per mid-size biotech (see `docs/20260420_CRO_CDMO_POSITIONING_AND_PLAN.md`). Justified by:
  - One IND filing internally costs $200K-$500K in regulatory-writing FTE time.
  - We compress the §2.6 drafting phase from weeks to days.
- Includes:
  - Personal adapter trained on their edits.
  - Audit trail visible only to them.
  - Customer-data isolation (separate JSONL, separate adapter binary).
  - SLA on regeneration latency + uptime.

### Enterprise (TBD)

- On-prem or VPC-isolated deployment. Triggered by the first customer who refuses cloud hosting.
- Data residency clauses (EU, China).
- Direct line to the reg-science team for adapter customization beyond automated DPO.

---

## The four open empirical questions

Carried forward from the integration plan. Each has instrumentation wired; the answer is a property of usage data.

| OQ | Question | When the answer arrives |
|---|---|---|
| **OQ-1** | Is v6 quality sufficient for a real paid customer, or do we need v7 first? | After 2 weeks of first-pilot usage. Signal: median edits per 1000 generated chars ≤ 30. |
| **OQ-2** | What's the right edit-volume threshold to offer a personal adapter? | After one customer crosses ~100 captured pairs. Inflection point on holdout lift. |
| **OQ-3** | Should paid customers ever see the Gemini fallback when local LLM is down? | First production fallback event. Per-org `disable_fallback: true` if acceptance < 30%. |
| **OQ-4** | Where should EU customer data physically live? | First EU contract negotiation. Schema already extensible. |

The principle is: instrument the system, ship to a pilot, read the data, then decide pricing and tier boundaries. Don't try to derive them from a whiteboard.

---

## Risks that aren't model risks

1. **Customer trust on closed-loop training.** Even paid customers may be uncomfortable with their edits training a model — even if it's *their* adapter. Mitigated by: explicit opt-in toggle per project, a "this generation used edit X from project Y" provenance trail, and an export-and-delete option.
2. **Regulatory acceptance.** FDA reviewers don't (yet) require disclosure of LLM-assisted drafting, but if they start, "we used a fine-tuned model with a checker pass-rate of N%" is a defensible position. "We used GPT-4 with a system prompt" is not.
3. **Concentration.** First customer is a single point of failure for OQ-1 signal. We need at least two pilots in parallel to disambiguate "v6 quality issue" from "this one customer's writing style is unusual."
4. **Drift.** Weekly retrain auto-promotes only on checker non-regression — but checkers cover ~5 dimensions, not the long tail. Quarterly hold-out review by reg-science team is the safety net.

---

## What this doc is not

- Not a final pricing sheet. Numbers above are bands for sales-conversation framing.
- Not a launch plan. Launch needs PI-6 + the live LLM-regeneration wiring + at least one signed pilot. Tracked in `docs/20260520_IND_PRODUCTION_INTEGRATION_PLAN.md`.
- Not a competitive analysis. That's `docs/20260420_GPT_ROSALIND_VS_BIOMATE_STRATEGIC_ANALYSIS.md` and `docs/20260501_BIOMATE_IND_PRODUCT_STRATEGY.md`.

---

## TL;DR

- The LLM writes IND module §2.6 prose, checker-graded, auditable.
- Free public adapter funnels into a paid personal-adapter tier.
- Personal adapters are trained on the customer's own captured edits via a feedback loop that's already in code and just had its persistence layer verified by PI-7..10.
- Pricing tier thresholds are empirical, not a priori. Instrument; ship to pilot; read the data.
- Three blockers to paid GA: PI-6 (auth gate), live LLM regeneration wiring, signed pilot customer.
