"""
BioMate Phase 2 Compliance Test Suite — 21 CFR Part 11

Tests:
  T1  : AuditStore — append and retrieve records
  T2  : AuditStore — hash chain valid after multiple appends
  T3  : AuditStore — tamper detection (field modification)
  T4  : AuditStore — tamper detection (record insertion)
  T5  : AuditStore — tamper detection (record deletion)
  T6  : TOTPService — compute and verify within window
  T7  : TOTPService — reject wrong token
  T8  : TOTPService — reject token outside time window
  T9  : ESignatureService — register user and sign action
  T10 : ESignatureService — verify signature manifest
  T11 : ESignatureService — reject unregistered user
  T12 : ESignatureService — reject invalid TOTP on sign
  T13 : ESignatureService — replay attack rejected
  T14 : ESignatureService — sign appended to audit log
  T15 : Audit middleware — INGEST_ASSAY action recorded
  T16 : Audit middleware — PROPOSE_ROUND action recorded
  T17 : Audit middleware — MODEL_VALIDATION action recorded
  T18 : Audit middleware — action derived correctly from paths
  T19 : AuditStore.get_records — filter by user_id
  T20 : AuditStore.get_records — filter by action
  T21 : AuditStore — genesis hash on empty log
  T22 : hash_payload — consistent SHA-256
  T23 : Compliance end-to-end — ingest+propose creates 2 audit records with valid chain
"""

import os
import sys
import tempfile
import time

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, "..", "..", "..", "..", ".."))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

_AI_ROOT = os.path.normpath(os.path.join(_HERE, ".."))
if _AI_ROOT not in sys.path:
    sys.path.insert(0, _AI_ROOT)


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

_passed = 0
_failed = 0


def _assert(condition: bool, label: str, extra: str = "") -> None:
    global _passed, _failed
    if condition:
        print(f"  [PASSED] {label}")
        _passed += 1
    else:
        detail = f" — {extra}" if extra else ""
        print(f"  [FAILED] {label}{detail}")
        _failed += 1


def _fresh_store():
    """Return an AuditStore backed by a temporary in-memory SQLite database."""
    import sqlite3
    from backend.lib.galaxy.ai.compliance.audit_store import AuditStore
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    tmp.close()
    store = AuditStore(db_path=tmp.name)
    return store, tmp.name


def _cleanup(path: str):
    try:
        os.unlink(path)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Imports (fail fast with a clear message if package missing)
# ---------------------------------------------------------------------------

from backend.lib.galaxy.ai.compliance.audit_store import (
    AuditStore, AuditEvent, AuditAction, hash_payload, _GENESIS_HASH,
    _derive_record_hash,
)
from backend.lib.galaxy.ai.compliance.esig import (
    TOTPService, ESignatureService, _hotp, _secret_bytes,
)
from backend.lib.galaxy.ai.compliance.audit_middleware import (
    _derive_action, _extract_campaign_id_from_path,
)


# ===========================================================================
# T1 — AuditStore: append and retrieve
# ===========================================================================
print("\n--- T1: AuditStore — append and retrieve ---")

store1, db1 = _fresh_store()

ev = AuditEvent(
    user_id="alice@biotech.com",
    action=AuditAction.INGEST_ASSAY,
    resource_type="campaign",
    resource_id="cmp-001",
    payload_hash=hash_payload(b"csv content"),
    details="test ingest",
)
rec = store1.append(ev)

_assert(rec.id == 1, "first record has id=1")
_assert(rec.action == AuditAction.INGEST_ASSAY, "action preserved")
_assert(rec.user_id == "alice@biotech.com", "user_id preserved")
_assert(rec.resource_id == "cmp-001", "resource_id preserved")
_assert(len(rec.record_hash) == 64, "record_hash is SHA-256 hex (64 chars)")
_assert(rec.previous_hash == _GENESIS_HASH, "first record references genesis hash")

records = store1.get_records()
_assert(len(records) == 1, "get_records returns 1 record")
_assert(records[0].record_hash == rec.record_hash, "retrieved record_hash matches")
_assert(store1.count() == 1, "count() == 1")
_cleanup(db1)


# ===========================================================================
# T2 — AuditStore: valid hash chain
# ===========================================================================
print("\n--- T2: AuditStore — valid hash chain ---")

store2, db2 = _fresh_store()

for i in range(5):
    store2.append(AuditEvent(
        user_id=f"user{i}",
        action=AuditAction.PROPOSE_ROUND,
        resource_type="campaign",
        resource_id=f"cmp-{i:03d}",
        payload_hash=hash_payload(f"data{i}"),
    ))

result = store2.verify_chain()
_assert(result.valid, "chain valid after 5 appends")
_assert(result.total_records == 5, f"total_records=5 — got {result.total_records}")
_assert(result.first_tampered_id is None, "no tampered record")

# Each record's previous_hash must equal the previous record's record_hash
records2 = store2.get_records()
ok = True
for i in range(1, len(records2)):
    if records2[i].previous_hash != records2[i - 1].record_hash:
        ok = False
        break
_assert(ok, "each previous_hash links to predecessor record_hash")
_cleanup(db2)


# ===========================================================================
# T3 — AuditStore: tamper detection — field modification
# ===========================================================================
print("\n--- T3: AuditStore — tamper detection (field modification) ---")

import sqlite3 as _sqlite3

store3, db3 = _fresh_store()
store3.append(AuditEvent("u1", AuditAction.INGEST_ASSAY, "campaign", "cmp-001", hash_payload(b"x")))
store3.append(AuditEvent("u2", AuditAction.PROPOSE_ROUND, "campaign", "cmp-001", hash_payload(b"y")))

# Tamper: change user_id of record 1 directly in SQLite
with _sqlite3.connect(db3) as conn:
    conn.execute("UPDATE audit_log SET user_id = 'attacker' WHERE id = 1")

result3 = store3.verify_chain()
_assert(not result3.valid, "chain invalid after field modification")
_assert(result3.first_tampered_id == 1, f"tamper detected at id=1 — got {result3.first_tampered_id}")
_assert("content has been modified" in (result3.error or ""), "error message mentions modification")
_cleanup(db3)


# ===========================================================================
# T4 — AuditStore: tamper detection — record insertion
# ===========================================================================
print("\n--- T4: AuditStore — tamper detection (record insertion) ---")

store4, db4 = _fresh_store()
r1 = store4.append(AuditEvent("u1", AuditAction.INGEST_ASSAY, "campaign", "c1", hash_payload(b"a")))
r2 = store4.append(AuditEvent("u2", AuditAction.PROPOSE_ROUND, "campaign", "c1", hash_payload(b"b")))

# Insert a fake record between r1 and r2 with a forged previous_hash
fake_prev = r1.record_hash
fake_hash = _derive_record_hash("2026-01-01T00:00:00", "forger", "EVIL", "campaign", "c1", "fakepayload", fake_prev)
with _sqlite3.connect(db4) as conn:
    conn.execute(
        "INSERT INTO audit_log (id, timestamp_utc, user_id, action, resource_type, resource_id, "
        "payload_hash, details, previous_hash, record_hash) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (99, "2026-01-01T00:00:00", "forger", "EVIL", "campaign", "c1",
         "fakepayload", "", fake_prev, fake_hash),
    )
    # Also update r2's previous_hash to point to the fake record (to avoid the
    # previous_hash mismatch catching r2 instead of the inserted record).
    # The verify_chain reads records ordered by id ASC, so id=2 < id=99:
    # it will trip on r2's previous_hash not matching r1's hash.
    pass  # The inserted id=99 comes after r2, so chain traversal will see: r1→r2→r99

result4 = store4.verify_chain()
_assert(not result4.valid, "chain invalid after record insertion")
_cleanup(db4)


# ===========================================================================
# T5 — AuditStore: tamper detection — record deletion
# ===========================================================================
print("\n--- T5: AuditStore — tamper detection (record deletion) ---")

store5, db5 = _fresh_store()
store5.append(AuditEvent("u1", AuditAction.INGEST_ASSAY, "campaign", "c1", hash_payload(b"a")))
store5.append(AuditEvent("u2", AuditAction.EXPORT_CRO_ORDER, "campaign", "c1", hash_payload(b"b")))
store5.append(AuditEvent("u3", AuditAction.PROPOSE_ROUND, "campaign", "c1", hash_payload(b"c")))

# Delete middle record
with _sqlite3.connect(db5) as conn:
    conn.execute("DELETE FROM audit_log WHERE id = 2")

result5 = store5.verify_chain()
_assert(not result5.valid, "chain invalid after record deletion")
# id=3's previous_hash points to id=2's hash which no longer exists →
# verify_chain sees id=3's previous_hash != id=1's record_hash
_cleanup(db5)


# ===========================================================================
# T6 — TOTPService: compute and verify within window
# ===========================================================================
print("\n--- T6: TOTPService — compute and verify ---")

secret = TOTPService.generate_secret()
_assert(len(secret) >= 16, f"secret at least 16 chars — got {len(secret)}")
_assert(secret == secret.upper(), "secret is uppercase base32")

token = TOTPService.compute(secret)
_assert(len(token) == 6, f"token is 6 digits — got len={len(token)}")
_assert(token.isdigit(), "token contains only digits")

valid = TOTPService.verify(secret, token, window=1)
_assert(valid, "current token verifies")

# Verify with the same secret and manually computed step
current_step = int(time.time()) // 30
sb = _secret_bytes(secret)
manual_token = _hotp(sb, current_step, 6)
_assert(TOTPService.verify(secret, manual_token, window=0), "manual HOTP computation matches TOTPService")


# ===========================================================================
# T7 — TOTPService: reject wrong token
# ===========================================================================
print("\n--- T7: TOTPService — reject wrong token ---")

secret7 = TOTPService.generate_secret()
_assert(not TOTPService.verify(secret7, "000000", window=0), "all-zeros token rejected")
_assert(not TOTPService.verify(secret7, "999999", window=0), "all-nines token rejected — likely wrong")
_assert(not TOTPService.verify(secret7, "abc123", window=0), "non-numeric token rejected")
_assert(not TOTPService.verify(secret7, "12345", window=0), "5-digit token rejected (wrong length)")


# ===========================================================================
# T8 — TOTPService: reject token outside time window
# ===========================================================================
print("\n--- T8: TOTPService — window boundary ---")

secret8 = TOTPService.generate_secret()
sb8 = _secret_bytes(secret8)

# A token from a time step 10 windows ago should be rejected with window=1
old_step = int(time.time()) // 30 - 10
old_token = _hotp(sb8, old_step, 6)
_assert(not TOTPService.verify(secret8, old_token, window=1), "stale token (10 steps ago) rejected")

# Token from current step must pass with window=0
current_token = TOTPService.compute(secret8)
_assert(TOTPService.verify(secret8, current_token, window=0), "current token passes with window=0")


# ===========================================================================
# T9 — ESignatureService: register user and sign
# ===========================================================================
print("\n--- T9: ESignatureService — register user and sign ---")

store9, db9 = _fresh_store()
svc9 = ESignatureService(store9)

_assert(not svc9.is_registered("bob@biotech.com"), "unregistered user returns False")
bob_secret = svc9.register_user("bob@biotech.com")
_assert(svc9.is_registered("bob@biotech.com"), "user registered")
_assert(len(bob_secret) >= 16, "register returns non-empty secret")

# Generate a valid TOTP token from the returned secret
bob_token = TOTPService.compute(bob_secret)
sig = svc9.sign(
    user_id="bob@biotech.com",
    action="EXPORT_CRO_ORDER",
    meaning="I approve the synthesis order for campaign cmp-test",
    totp_token=bob_token,
)

_assert(sig.user_id == "bob@biotech.com", "sig.user_id correct")
_assert(sig.action == "EXPORT_CRO_ORDER", "sig.action correct")
_assert(len(sig.sig_id) == 32, "sig_id is 32-char hex")
_assert(len(sig.manifest_hash) == 64, "manifest_hash is SHA-256")
_assert(sig.audit_record_id > 0, "audit_record_id is set")
_cleanup(db9)


# ===========================================================================
# T10 — ESignatureService: verify signature manifest
# ===========================================================================
print("\n--- T10: ESignatureService — verify signature manifest ---")

store10, db10 = _fresh_store()
svc10 = ESignatureService(store10)
sec10 = svc10.register_user("carol@biotech.com")
tok10 = TOTPService.compute(sec10)

sig10 = svc10.sign(
    user_id="carol@biotech.com",
    action="PROPOSE_ROUND",
    meaning="I approve round 3 proposals",
    totp_token=tok10,
)

_assert(svc10.verify_signature(sig10), "valid signature verifies")

# Tamper with meaning
import copy as _copy
tampered = _copy.copy(sig10)
tampered.meaning = "I approve round 99 proposals"
_assert(not svc10.verify_signature(tampered), "tampered meaning fails verification")
_cleanup(db10)


# ===========================================================================
# T11 — ESignatureService: reject unregistered user
# ===========================================================================
print("\n--- T11: ESignatureService — reject unregistered user ---")

store11, db11 = _fresh_store()
svc11 = ESignatureService(store11)
raised = False
try:
    svc11.sign("ghost@biotech.com", "INGEST_ASSAY", "meaning", "123456")
except ValueError as e:
    raised = "not registered" in str(e)
_assert(raised, "ValueError raised for unregistered user")
_cleanup(db11)


# ===========================================================================
# T12 — ESignatureService: reject invalid TOTP on sign
# ===========================================================================
print("\n--- T12: ESignatureService — reject invalid TOTP ---")

store12, db12 = _fresh_store()
svc12 = ESignatureService(store12)
svc12.register_user("dave@biotech.com")
raised12 = False
try:
    svc12.sign("dave@biotech.com", "INGEST_ASSAY", "meaning", "000000")
except ValueError as e:
    raised12 = "invalid or expired" in str(e)
_assert(raised12, "ValueError raised for invalid TOTP token")
_cleanup(db12)


# ===========================================================================
# T13 — ESignatureService: replay attack rejected
# ===========================================================================
print("\n--- T13: ESignatureService — replay attack rejected ---")

store13, db13 = _fresh_store()
svc13 = ESignatureService(store13)
sec13 = svc13.register_user("eve@biotech.com")
tok13 = TOTPService.compute(sec13)

# First sign succeeds
svc13.sign("eve@biotech.com", "EXPORT_CRO_ORDER", "first sign", tok13)

# Second use of the same token (same time step) must fail
raised13 = False
try:
    svc13.sign("eve@biotech.com", "EXPORT_CRO_ORDER", "replay attempt", tok13)
except ValueError as e:
    raised13 = "replay" in str(e).lower() or "already been used" in str(e)
_assert(raised13, "replay with same TOTP token rejected")
_cleanup(db13)


# ===========================================================================
# T14 — ESignatureService: sign appended to audit log
# ===========================================================================
print("\n--- T14: ESignatureService — sign creates ESIG audit record ---")

store14, db14 = _fresh_store()
svc14 = ESignatureService(store14)
sec14 = svc14.register_user("frank@biotech.com")
tok14 = TOTPService.compute(sec14)

count_before = store14.count()
sig14 = svc14.sign("frank@biotech.com", "PROPOSE_ROUND", "approved", tok14)
count_after = store14.count()

_assert(count_after == count_before + 1, "one audit record created by sign()")

esig_records = store14.get_records(action=AuditAction.ESIG)
_assert(len(esig_records) == 1, "ESIG record in audit log")
_assert(esig_records[0].user_id == "frank@biotech.com", "ESIG record has correct user_id")
_assert(esig_records[0].payload_hash == sig14.manifest_hash, "ESIG record payload_hash == manifest_hash")

chain14 = store14.verify_chain()
_assert(chain14.valid, "chain valid after ESIG record")
_cleanup(db14)


# ===========================================================================
# T15-T17 — Audit middleware: action derivation
# ===========================================================================
print("\n--- T15-T17: Audit middleware — action derivation ---")

_assert(
    _derive_action("POST", "/api/drug-discovery/cmp-001/ingest-assay") == AuditAction.INGEST_ASSAY,
    "ingest-assay → INGEST_ASSAY",
)
_assert(
    _derive_action("POST", "/api/drug-discovery/cmp-001/propose") == AuditAction.PROPOSE_ROUND,
    "propose → PROPOSE_ROUND",
)
_assert(
    _derive_action("GET", "/api/drug-discovery/cmp-001/export/cro-order") == AuditAction.EXPORT_CRO_ORDER,
    "export/cro-order → EXPORT_CRO_ORDER",
)
_assert(
    _derive_action("GET", "/api/drug-discovery/cmp-001/lims/poll") == AuditAction.POLL_LIMS,
    "lims/poll → POLL_LIMS",
)
_assert(
    _derive_action("POST", "/api/drug-discovery/cmp-001/models/register") == AuditAction.REGISTER_MODEL,
    "models/register → REGISTER_MODEL",
)
_assert(
    _derive_action("POST", "/api/drug-discovery/cmp-001/models/my_model/run") == AuditAction.RUN_MODEL,
    "models/{name}/run → RUN_MODEL",
)
_assert(
    _derive_action("GET", "/api/drug-discovery/model-validation/pbpk") == AuditAction.MODEL_VALIDATION,
    "model-validation → MODEL_VALIDATION",
)


# ===========================================================================
# T18 — Audit middleware: campaign_id extraction from path
# ===========================================================================
print("\n--- T18: Audit middleware — campaign_id extraction ---")

_assert(
    _extract_campaign_id_from_path("/api/drug-discovery/cmp-001/propose") == "cmp-001",
    "campaign_id extracted from propose path",
)
_assert(
    _extract_campaign_id_from_path("/api/drug-discovery/my-campaign/ingest-assay") == "my-campaign",
    "campaign_id extracted from ingest-assay path",
)
_assert(
    _extract_campaign_id_from_path("/api/drug-discovery/model-validation/pbpk") == "model-validation",
    "model-validation path: resource segment extracted",
)


# ===========================================================================
# T19-T20 — AuditStore.get_records: filters
# ===========================================================================
print("\n--- T19-T20: AuditStore.get_records — filters ---")

store19, db19 = _fresh_store()
store19.append(AuditEvent("alice", AuditAction.INGEST_ASSAY, "campaign", "c1", hash_payload(b"a")))
store19.append(AuditEvent("bob", AuditAction.PROPOSE_ROUND, "campaign", "c1", hash_payload(b"b")))
store19.append(AuditEvent("alice", AuditAction.EXPORT_CRO_ORDER, "campaign", "c1", hash_payload(b"c")))

alice_records = store19.get_records(user_id="alice")
_assert(len(alice_records) == 2, f"filter by user_id='alice' returns 2 records — got {len(alice_records)}")

propose_records = store19.get_records(action=AuditAction.PROPOSE_ROUND)
_assert(len(propose_records) == 1, f"filter by action=PROPOSE_ROUND returns 1 record — got {len(propose_records)}")
_assert(propose_records[0].user_id == "bob", "PROPOSE_ROUND record belongs to bob")
_cleanup(db19)


# ===========================================================================
# T21 — AuditStore: genesis hash on empty log
# ===========================================================================
print("\n--- T21: AuditStore — genesis hash on empty log ---")

store21, db21 = _fresh_store()
result21 = store21.verify_chain()
_assert(result21.valid, "empty log reports valid")
_assert(result21.total_records == 0, "total_records=0 on empty log")
_cleanup(db21)


# ===========================================================================
# T22 — hash_payload: deterministic SHA-256
# ===========================================================================
print("\n--- T22: hash_payload — deterministic SHA-256 ---")

import hashlib as _hashlib

data = b"SMILES=CCO,IC50=0.5uM"
expected = _hashlib.sha256(data).hexdigest()
_assert(hash_payload(data) == expected, "hash_payload matches manual SHA-256")
_assert(hash_payload(data) == hash_payload(data), "hash_payload is deterministic")
_assert(hash_payload(b"x") != hash_payload(b"y"), "different inputs produce different hashes")


# ===========================================================================
# T23 — End-to-end: 2 audit events + valid chain
# ===========================================================================
print("\n--- T23: End-to-end — 2 events, chain verification ---")

store23, db23 = _fresh_store()

# Simulate: user ingests assay data
store23.append(AuditEvent(
    user_id="scientist@biotech.com",
    action=AuditAction.INGEST_ASSAY,
    resource_type="campaign",
    resource_id="cmp-e2e",
    payload_hash=hash_payload(b"assay_csv_content"),
    details="10 IC50 measurements",
))

# Simulate: user proposes next round
store23.append(AuditEvent(
    user_id="scientist@biotech.com",
    action=AuditAction.PROPOSE_ROUND,
    resource_type="campaign",
    resource_id="cmp-e2e",
    payload_hash=hash_payload(b"virtual_library_10k"),
    details="n_propose=5",
))

r23 = store23.verify_chain()
_assert(r23.valid, "chain valid after ingest + propose")
_assert(r23.total_records == 2, f"total_records=2 — got {r23.total_records}")
_assert(r23.first_tampered_id is None, "no tampered record")

records23 = store23.get_records(resource_id="cmp-e2e")
_assert(len(records23) == 2, "both records retrievable by resource_id")
_assert(records23[0].action == AuditAction.INGEST_ASSAY, "first record is INGEST_ASSAY")
_assert(records23[1].action == AuditAction.PROPOSE_ROUND, "second record is PROPOSE_ROUND")
_assert(records23[1].previous_hash == records23[0].record_hash, "propose links to ingest hash")
_cleanup(db23)


# ===========================================================================
# Summary
# ===========================================================================
print(f"\n{'=' * 60}")
print(f"Results: {_passed} PASSED, {_failed} FAILED")
print(f"{'=' * 60}")

if _failed > 0:
    sys.exit(1)
