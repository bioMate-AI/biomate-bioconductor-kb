# BioMate Regulatory LLM — Data Handling Policy

**Date:** 2026-05-16
**Status:** Internal policy. Surface to customers before first contract.
**Scope:** Captures customer interactions with the IND Report product (Appendix B of `docs/20260504_IND_PRODUCT_UI_REQUIREMENTS.md`) — paragraph edits, audit-finding dismissals, citation suggestions, regenerate-with-instruction prompts.
**Not in scope:** Customer compound data (SMILES, structures) — that lives in the existing BioMate pipeline data layer and follows the project's existing data policy.

---

## What we capture from customers

Four data types, written to four JSONL files under `data/regulatory_training/`:

| File | Trigger | Contents |
|---|---|---|
| `dpo/customer_pairs.jsonl` | TipTap paragraph edit (debounced 5s) | original paragraph, edited paragraph, section type, structured input prompt |
| `checker_feedback.jsonl` | Audit finding dismissed | rule id, dismissal reason, optional free-text rationale, document state hash |
| `citation_extensions.jsonl` | Customer-suggested missing citation | guideline ID, customer's rationale |
| `prompt_tuning_signals.jsonl` | Regenerate-with-instruction | section type, customer's instruction, before/after text |

All four files include `created_at`, optional `org_id`, and an opaque `id`. Customer-edit and prompt-tuning payloads contain customer-authored regulatory prose that may include drug names, study identifiers, indication, and section context.

---

## Tier-based handling

### Free tier (default)

- `org_id` is `null` in every record
- `feedback_io.strip_pii()` runs on edit and rejected text before write to `customer_pairs.jsonl` only
- Stripping replaces drug-name suffixes (-mab, -tinib, -tide, -azole, -vir, -olol, -pril, -sartan, -statin, -cept, -stim, -kine, -ximab, -izumab, -lukast) and study-ID patterns (`[A-Z]{2,5}-\d{2,4}(?:-\w{1,4})?`) with neutral placeholders
- **Known limitation:** brand names without typical suffixes (e.g. Tadalafil, Aspirin), patient identifiers (medical record numbers), investigator names, and lot numbers **are not stripped**. The free tier is therefore appropriate only for customers willing to share data, e.g. academic users or early-access pilots
- Free-tier data may be merged into the shared training pool for future model versions (`build_dpo_pairs.py --mode customer-edits`)

### Paid tier (per-org isolation)

- Customers receive an `org_id` at contract signing
- All requests include `X-BioMate-Org-Id: <org_id>` header
- Records written with `org_id` set are isolated in the JSONL files (filter on read)
- `feedback_io.strip_pii()` is **bypassed** for paid-tier records (originals preserved for downstream per-customer training)
- Paid-tier data is **never** merged into the shared training pool
- Per-customer LoRA adapter is offered after ≥200 high-quality edits across ≥3 projects (resolved by `_resolve_adapter_path(org_id=...)` only when the org is on the paid-orgs entitlement list)

---

## Retention

- Default retention: **90 days** from `created_at`. After 90 days, records are removed unless explicitly preserved for an open regulatory science review.
- A nightly job (`scripts/cron/purge_expired_feedback.sh` — TODO) drops expired rows. Until that job is built, retention is currently **unbounded** — this is a known gap.
- Customers may request deletion at any time via support; current implementation is manual (operator removes rows by `org_id` filter).

---

## Right to deletion

Implemented endpoint pattern (TODO — not yet built):

```
DELETE /api/regulatory/data/by_org/{org_id}
  Authorization: Bearer <internal_key>
```

Removes all rows from all four JSONL files where `org_id` matches. Caller is the BioMate operator team responding to a customer request; not a self-service customer endpoint (avoid accidental deletion).

The right-to-deletion path is currently **manual** — operator runs a one-liner per request. Promote to a real endpoint once volume justifies.

---

## Geographic data residency

- All JSONL files currently live on the production EC2 instance in `us-west-2`. There is no EU-region equivalent.
- For EU customers, data residency is **not yet met**. Either (a) decline EU customers until an EU instance exists, or (b) explicitly contract around it.
- China (NMPA) customers may have additional cross-border data restrictions; defer to legal review before signing.

---

## Encryption

- **At rest:** EC2 EBS volumes are encrypted by default (AWS-managed keys). JSONL files inherit. No customer-managed key per org yet.
- **In transit:** All API endpoints are HTTPS-only behind the existing BioMate load balancer.

---

## Audit trail

Every customer-feedback POST is logged (`log.info(...)`) with: user_id (from JWT), project_id or finding_id, row_id, timestamp. Logs retained per the existing BioMate logging policy (currently 30 days on CloudWatch).

The JSONL records themselves include `created_at` and (where applicable) `document_state_hash` for traceability to the document version at the time of the edit.

---

## What customers see (transparency)

The customer UI must surface:

1. A "Contribute edits to model improvement" setting (default ON for free tier, OFF for paid tier)
2. The "edited — saved for model improvement" hint on edited paragraphs
3. A link to a public version of this policy from Project Settings
4. The Active Model badge identifying whether the public or a customized adapter is serving

The customer does **NOT** see:
- The internal review queue
- Other customers' data
- Model retraining schedule

---

## Compliance posture (current honest state)

| Standard | Posture |
|---|---|
| GDPR | Partial — retention/deletion mechanisms are manual. EU residency not met. |
| HIPAA | **Out of scope** — BioMate does not process PHI in this product. Customers must not upload PHI. Make this explicit in the customer agreement. |
| 21 CFR Part 11 | Out of scope for the *training* data capture (this doc). Applies to the *signed-and-frozen* IND document itself (covered by existing eSig flow in the IND Report product). |
| SOC 2 | Not currently certified. |

---

## Required customer agreement clauses

Before first paying customer signs, the contract must include:

1. Free-tier customers explicitly consent to training-pool contribution
2. Paid-tier customers receive per-org isolation guarantee
3. Customers warrant they will not upload PHI / personal data of identifiable subjects
4. Customers warrant they own the data they upload (or have rights to it)
5. BioMate retention default (90 days) and right-to-deletion process
6. No warranty: BioMate output is a computational draft; customer is responsible for human regulatory review before submission

---

## Known gaps (audit item 8a)

These remain open and should be closed before the first paying customer:

- [ ] Retention purge cron not implemented
- [ ] Right-to-deletion endpoint not implemented (manual only)
- [ ] EU-region deployment not available
- [ ] Customer-managed encryption keys not supported
- [ ] PII stripping regex is incomplete (brand names, patient IDs not caught)
- [ ] Customer-facing policy page (public URL) does not yet exist
- [ ] Contract template does not yet include the clauses listed above
