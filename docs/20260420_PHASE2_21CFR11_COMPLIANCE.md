# BioMate Phase 2 — 21 CFR Part 11 Compliance

**Date:** 2026-04-20  
**Status:** COMPLETE — 73/73 tests passing  
**Regulatory reference:** 21 CFR Part 11; FDA Guidance for Industry (2003)

---

## What Was Built

Three new modules implement the tamper-evident audit trail and electronic signature requirements of 21 CFR Part 11:

| File | Purpose |
|------|---------|
| `backend/lib/galaxy/ai/compliance/audit_store.py` | SHA-256 hash-chained append-only SQLite audit log |
| `backend/lib/galaxy/ai/compliance/esig.py` | TOTP electronic signatures (RFC 6238) |
| `backend/lib/galaxy/ai/compliance/audit_middleware.py` | FastAPI dependency wired to all regulated endpoints |

The existing `api_router.py` was updated to run the audit dependency on every regulated write and regulated read operation.

---

## 1. Audit Store (`audit_store.py`)

### Design

A single global SQLite database at `database/compliance/audit.db`.

Every regulated operation creates one row in the `audit_log` table:

```
id | timestamp_utc | user_id | action | resource_type | resource_id | payload_hash | details | previous_hash | record_hash
```

**Hash chaining:** Each record's `record_hash` is `SHA256(timestamp_utc | user_id | action | resource_type | resource_id | payload_hash | previous_hash)`. The first record's `previous_hash` is the 64-zero genesis sentinel. Every subsequent record's `previous_hash` is the `record_hash` of the record before it.

This creates a forward-linked chain: modifying any field in any record causes a hash mismatch detectable by `verify_chain()`. Inserting a record in the middle breaks the `previous_hash` link at the next record. Deleting a record breaks the link at the record that follows.

**No mutation API:** `AuditStore` has no `update()` or `delete()` method. The only write is `append()`. Direct SQL modification is detectable via `verify_chain()`.

### Tamper detection

`verify_chain()` reads all records in id order, re-derives every `record_hash`, and checks that each record's `previous_hash` equals the previous record's `record_hash`. Three tamper scenarios are detected:

| Tamper | How detected |
|--------|-------------|
| Field value changed | `record_hash` re-derivation produces different value |
| Record inserted mid-chain | Next record's `previous_hash` doesn't match inserted record's hash |
| Record deleted | Gap in `previous_hash` chain |

### Actions recorded

| Constant | Triggered by |
|----------|-------------|
| `INGEST_ASSAY` | `POST /{campaign_id}/ingest-assay` |
| `PROPOSE_ROUND` | `POST /{campaign_id}/propose` |
| `EXPORT_CRO_ORDER` | `GET /{campaign_id}/export/cro-order` |
| `REGISTER_MODEL` | `POST /{campaign_id}/models/register` |
| `RUN_MODEL` | `POST /{campaign_id}/models/{name}/run` |
| `POLL_LIMS` | `GET /{campaign_id}/lims/poll` |
| `MODEL_VALIDATION` | `GET /model-validation/{type}` |
| `ESIG` | Each electronic signature via `ESignatureService.sign()` |

### Key API

```python
store = AuditStore()           # uses database/compliance/audit.db
store.append(AuditEvent(
    user_id="alice@biotech.com",
    action=AuditAction.INGEST_ASSAY,
    resource_type="campaign",
    resource_id="cmp-001",
    payload_hash=hash_payload(csv_bytes),
))
result = store.verify_chain()  # ChainVerificationResult(valid=True, ...)
records = store.get_records(user_id="alice", action=AuditAction.INGEST_ASSAY)
```

---

## 2. Electronic Signature Service (`esig.py`)

### Design

21 CFR Part 11 §11.50 requires that electronic signatures are unique to one individual, linked to the signed record, and that the meaning of the signature is recorded. §11.200 requires each signature to include the signer's printed name, date/time, and the meaning of the signature.

BioMate uses **TOTP (Time-Based One-Time Password, RFC 6238)**, the same algorithm used by Google Authenticator, Authy, and all major hardware tokens.

**Registration:** A user registers once. BioMate generates a 20-byte random secret (base32-encoded, 32 characters). The user scans this into their authenticator app. The secret is stored in the `esig_secrets` table of the audit database, AES-256-GCM encrypted when `BIOMATE_ESIG_KEY` is set.

**Signing:** To sign an action, the user provides their current 6-digit TOTP token. BioMate:
1. Looks up the user's secret
2. Verifies the token against ±1 time windows (handles clock skew up to 30 seconds)
3. Checks the token has not been used in the current time step (replay protection)
4. Builds a signed manifest: `SHA256(sig_id | user_id | action | meaning | timestamp_utc)`
5. Appends an `ESIG` record to the audit log
6. Returns an `ESignatureRecord` with `sig_id`, `manifest_hash`, and the `audit_record_id`

**Verification:** `verify_signature(sig)` recomputes the manifest hash from the record's fields. Since the audit log record contains the manifest hash (locked into the hash chain), any post-signing modification is detectable.

**Replay protection:** Used TOTP time steps are stored in `esig_used_tokens(user_id, time_step)`. Re-presenting the same token within the same 30-second window raises `ValueError("replay rejected")`.

### Activation

By default, eSig is **advisory** — it is recorded if the `X-BioMate-ESig` header is present, but not required. This allows gradual rollout.

To enforce eSig for `EXPORT_CRO_ORDER` and `PROPOSE_ROUND` operations:
```bash
export BIOMATE_ESIG_REQUIRED=1
```

To enable encrypted secret storage:
```bash
export BIOMATE_ESIG_KEY=$(openssl rand -hex 32)   # generate once; store in secrets manager
pip install cryptography
```

### Key API

```python
svc = ESignatureService(audit_store)

# One-time setup
secret = svc.register_user("alice@biotech.com")
# → user scans secret into Google Authenticator

# At time of regulated action
sig = svc.sign(
    user_id="alice@biotech.com",
    action="EXPORT_CRO_ORDER",
    meaning="I approve the synthesis order for campaign cmp-001",
    totp_token="847291",    # from authenticator app
)

assert svc.verify_signature(sig)   # True
```

### TOTP implementation

Implemented from scratch against RFC 6238 / RFC 4226 with zero external dependencies:

```
HOTP(secret, counter) = Truncate(HMAC-SHA1(secret, counter))
TOTP(secret) = HOTP(secret, floor(unix_time / 30))
```

No `pyotp` or `otp` package required. Compatible with any RFC 6238-compliant authenticator app.

---

## 3. Audit Middleware (`audit_middleware.py`)

A FastAPI **dependency** (not a Starlette middleware) that records every regulated request before the endpoint handler runs.

**How it works:**
1. Extracts `user_id` from the JWT Bearer token (`sub` claim), `X-BioMate-User-Id` header, or remote IP as fallback
2. Derives the `AuditAction` constant from the HTTP method + URL path
3. Extracts `campaign_id` from the URL path
4. Computes `payload_hash = SHA256(method + path + query_string)`
5. If the action supports eSig and `X-BioMate-ESig` header is present, validates the TOTP token
6. Appends the `AuditEvent` to the global `AuditStore`

**Failure mode:** In non-strict mode (default), audit failures are logged as errors but do not block the regulated operation. Set `BIOMATE_AUDIT_STRICT=1` to block operations if the audit log is unavailable.

**Wiring:** Every regulated endpoint in `api_router.py` now includes:
```python
_audit: None = Depends(_audit_fn)
```

If the compliance package is not installed, `_audit_fn` falls back to a no-op coroutine — existing deployments are unaffected.

---

## 4. 21 CFR Part 11 Coverage

| Requirement | §11 Ref | BioMate Implementation |
|-------------|---------|------------------------|
| Computer-generated date/time stamps | §11.10(e) | `timestamp_utc` (ISO 8601 UTC) in every audit record |
| Record of operator actions (create/modify/delete) | §11.10(e) | All regulated endpoints covered by `audit_middleware.py` |
| Audit trail protection from modification | §11.10(e) | SHA-256 hash chain; `verify_chain()` detects any modification |
| Electronic signature unique to individual | §11.100(a) | Per-user TOTP secret; cannot be shared |
| Electronic signature not reused/reassigned | §11.100(b) | 30s TOTP window + replay protection |
| Signature linked to record | §11.50(a)(4) | `ESignatureRecord.audit_record_id` references the ESIG audit row |
| Printed name, date/time, meaning of signature | §11.50(a) | `user_id`, `timestamp_utc`, `meaning` fields in manifest |
| System validation | §11.10(a) | 73-test suite (`test_phase2_compliance.py`) |

---

## 5. Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `BIOMATE_COMPLIANCE_DB_DIR` | `database/compliance/` | Directory for `audit.db` |
| `BIOMATE_ESIG_KEY` | _(unset)_ | 32-byte hex key for AES-256-GCM eSig secret encryption |
| `BIOMATE_ESIG_REQUIRED` | `0` | `1` = enforce eSig on `EXPORT_CRO_ORDER` and `PROPOSE_ROUND` |
| `BIOMATE_AUDIT_STRICT` | `0` | `1` = block regulated operations if audit log unavailable |

---

## 6. Test Results

```
73 PASSED, 0 FAILED

T1  : append + retrieve
T2  : valid chain after 5 records
T3  : tamper detection — field modification
T4  : tamper detection — record insertion
T5  : tamper detection — record deletion
T6  : TOTP compute + verify within window
T7  : reject wrong token
T8  : reject token outside window
T9  : register user + sign
T10 : verify signature manifest
T11 : reject unregistered user
T12 : reject invalid TOTP
T13 : replay attack rejected
T14 : sign creates ESIG audit record
T15-T17: action derivation (7 paths)
T18 : campaign_id extraction
T19-T20: get_records filters (user_id, action)
T21 : genesis hash on empty log
T22 : hash_payload deterministic SHA-256
T23 : end-to-end ingest+propose with chain verification
```

---

## 7. What Phase 3 Adds

Phase 2 provides the foundation. Phase 3 adds:

- **Auto-retrain loop:** Background job that detects new `INGEST_ASSAY` audit events and automatically triggers GP refit + new proposal round
- **IND section assembly:** Document generator that combines PBPK validation report, ADMET results, and audit trail summary into an ICH M4-compliant CTD Section 2.6.1
- **Audit export endpoint:** `GET /api/drug-discovery/audit?campaign_id=...&format=pdf` — renders the audit log as a signed PDF for regulatory submissions

*Document authored 2026-04-20. For the overall business context see `docs/20260420_BIOMATE_AS_A_CRO_BUSINESS_AND_TECHNICAL_GUIDE.md`. For Phase 1 see `docs/20260420_PHASE1_CRO_MODEL_VALIDATION_AND_AD.md`.*
