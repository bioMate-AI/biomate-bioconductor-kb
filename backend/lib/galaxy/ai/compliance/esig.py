"""
BioMate Electronic Signature Service — Phase 2 CRO Compliance

21 CFR Part 11 §11.50 / §11.200 require electronic signatures that are:
  - Unique to one individual
  - Not reusable / reassignable
  - Linked to the signed record

Implementation:
  TOTP (RFC 6238): a time-based one-time password derived from a shared secret
  and the current 30-second time window.  The user registers a secret once
  (stored per-user in the audit DB); every signing action requires a fresh
  6-digit TOTP token.  The signed manifest is appended to the audit log as an
  ESIG record so the signature is tamper-evident.

  TOTP is algorithm-compatible with Google Authenticator, Authy, and
  hardware tokens.  The shared secret is stored encrypted at rest (AES-256-GCM
  via the BIOMATE_ESIG_KEY env var, a 32-byte hex key).

Replay protection:
  Each TOTP token is single-use within the same time window.  Used tokens are
  recorded in the esig_used_tokens table and rejected on re-presentation.

References:
  RFC 6238 — TOTP: Time-Based One-Time Password Algorithm
  RFC 4226 — HOTP: An HMAC-Based One-Time Password Algorithm
  21 CFR Part 11 §11.50 — Signed electronic records
  21 CFR Part 11 §11.200 — Electronic signature components
"""

import base64
import hashlib
import hmac
import logging
import os
import secrets
import sqlite3
import struct
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# TOTP (RFC 6238) — no external dependencies
# ---------------------------------------------------------------------------

def _hotp(secret_bytes: bytes, counter: int, digits: int = 6) -> str:
    """HMAC-SHA1 one-time password for a given counter (RFC 4226)."""
    msg = struct.pack(">Q", counter)
    digest = hmac.new(secret_bytes, msg, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFF_FFFF
    return str(code % (10 ** digits)).zfill(digits)


def _totp(
    secret_bytes: bytes,
    time_step: Optional[int] = None,
    period: int = 30,
    digits: int = 6,
) -> str:
    """Current TOTP code (RFC 6238).  Uses wall-clock time if time_step is None."""
    if time_step is None:
        time_step = int(time.time()) // period
    return _hotp(secret_bytes, time_step, digits)


def _secret_bytes(secret_b32: str) -> bytes:
    """Decode a base32-encoded secret string to bytes."""
    # Pad to a multiple of 8 characters as required by base32
    padding = (8 - len(secret_b32) % 8) % 8
    return base64.b32decode(secret_b32.upper() + "=" * padding)


class TOTPService:
    """Low-level TOTP operations (generate / verify codes)."""

    PERIOD = 30    # seconds per time window
    DIGITS = 6
    WINDOW = 1     # accept ±1 time step to tolerate clock skew

    @staticmethod
    def generate_secret() -> str:
        """Generate a new random TOTP secret (base32, 20 bytes = 160 bits)."""
        raw = secrets.token_bytes(20)
        return base64.b32encode(raw).decode("ascii")

    @classmethod
    def compute(cls, secret_b32: str, time_step: Optional[int] = None) -> str:
        """Return the current TOTP code for a secret."""
        return _totp(_secret_bytes(secret_b32), time_step, cls.PERIOD, cls.DIGITS)

    @classmethod
    def verify(cls, secret_b32: str, token: str, window: Optional[int] = None) -> bool:
        """
        Return True if token matches any code within ±window time steps.

        window=None uses the class default (WINDOW = 1).
        """
        if window is None:
            window = cls.WINDOW
        if len(token) != cls.DIGITS or not token.isdigit():
            return False
        current_step = int(time.time()) // cls.PERIOD
        sb = _secret_bytes(secret_b32)
        for delta in range(-window, window + 1):
            expected = _hotp(sb, current_step + delta, cls.DIGITS)
            if hmac.compare_digest(expected, token):
                return True
        return False


# ---------------------------------------------------------------------------
# Encryption helpers (AES-256-GCM via stdlib only — no pycryptodome required)
# ---------------------------------------------------------------------------
# We use Python's hashlib + os.urandom; actual AES-GCM requires the `cryptography`
# package.  If unavailable, secrets are stored as plaintext with a warning.

def _try_import_cryptography():
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        return AESGCM
    except ImportError:
        return None


def _get_encryption_key() -> Optional[bytes]:
    hex_key = os.environ.get("BIOMATE_ESIG_KEY", "")
    if len(hex_key) == 64:
        return bytes.fromhex(hex_key)
    return None


def _encrypt_secret(plaintext: str) -> str:
    """Encrypt a TOTP secret for DB storage.  Returns hex(nonce+ciphertext)."""
    AESGCM = _try_import_cryptography()
    key = _get_encryption_key()
    if AESGCM is None or key is None:
        log.warning(
            "TOTP secrets stored as plaintext — set BIOMATE_ESIG_KEY (32-byte hex) "
            "and install `cryptography` for encrypted storage"
        )
        return plaintext
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext.encode(), None)
    return (nonce + ct).hex()


def _decrypt_secret(stored: str) -> str:
    """Decrypt a stored TOTP secret.  Returns plaintext."""
    AESGCM = _try_import_cryptography()
    key = _get_encryption_key()
    if AESGCM is None or key is None:
        return stored   # stored as plaintext
    raw = bytes.fromhex(stored)
    nonce, ct = raw[:12], raw[12:]
    return AESGCM(key).decrypt(nonce, ct, None).decode()


# ---------------------------------------------------------------------------
# Electronic Signature data classes
# ---------------------------------------------------------------------------

@dataclass
class ESignatureRecord:
    """Returned by ESignatureService.sign(); also stored in the audit log."""
    sig_id: str          # unique identifier for this signature
    user_id: str
    action: str          # what was signed (e.g. "EXPORT_CRO_ORDER")
    meaning: str         # human-readable statement of intent
    timestamp_utc: str
    manifest_hash: str   # SHA-256 of (sig_id + user_id + action + meaning + timestamp_utc)
    audit_record_id: int # id of the ESIG record in the audit log


# ---------------------------------------------------------------------------
# Electronic Signature Service
# ---------------------------------------------------------------------------

class ESignatureService:
    """
    Register users for TOTP, sign regulatory actions, verify signatures.

    Usage:
        svc = ESignatureService(audit_store)

        # One-time user registration (returns base32 secret for authenticator app)
        secret = svc.register_user("alice@biotech.com")

        # Sign an action
        sig = svc.sign(
            user_id="alice@biotech.com",
            action="EXPORT_CRO_ORDER",
            meaning="I approve the synthesis order for campaign cmp-001",
            totp_token="123456",
        )

        # Verify a signature record
        assert svc.verify_signature(sig)
    """

    def __init__(self, audit_store):
        """
        Args:
            audit_store: an AuditStore instance (used for persistence + audit ESIG records).
        """
        self._store = audit_store
        self._init_esig_tables()

    def _init_esig_tables(self) -> None:
        with self._store._connect() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS esig_secrets (
                    user_id       TEXT PRIMARY KEY,
                    secret_enc    TEXT NOT NULL,   -- encrypted TOTP secret
                    registered_at TEXT NOT NULL
                );

                -- Single-use token enforcement: one record per (user, time_step)
                CREATE TABLE IF NOT EXISTS esig_used_tokens (
                    user_id   TEXT NOT NULL,
                    time_step INTEGER NOT NULL,
                    used_at   TEXT NOT NULL,
                    PRIMARY KEY (user_id, time_step)
                );
            """)

    # ------------------------------------------------------------------
    # User registration
    # ------------------------------------------------------------------

    def register_user(self, user_id: str) -> str:
        """
        Register a user for TOTP eSig.  Returns the base32 secret to be
        scanned into an authenticator app.  Re-registration overwrites
        the existing secret (use with admin confirmation only).
        """
        secret = TOTPService.generate_secret()
        encrypted = _encrypt_secret(secret)
        ts = datetime.now(timezone.utc).isoformat()
        with self._store._connect() as conn:
            conn.execute(
                """
                INSERT INTO esig_secrets (user_id, secret_enc, registered_at)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET
                    secret_enc = excluded.secret_enc,
                    registered_at = excluded.registered_at
                """,
                (user_id, encrypted, ts),
            )
        log.info("eSig secret registered for user %s", user_id)
        return secret

    def is_registered(self, user_id: str) -> bool:
        with self._store._connect() as conn:
            row = conn.execute(
                "SELECT 1 FROM esig_secrets WHERE user_id = ?", (user_id,)
            ).fetchone()
        return row is not None

    def _load_secret(self, user_id: str) -> Optional[str]:
        with self._store._connect() as conn:
            row = conn.execute(
                "SELECT secret_enc FROM esig_secrets WHERE user_id = ?", (user_id,)
            ).fetchone()
        if row is None:
            return None
        return _decrypt_secret(row[0])

    # ------------------------------------------------------------------
    # Signing
    # ------------------------------------------------------------------

    def sign(
        self,
        user_id: str,
        action: str,
        meaning: str,
        totp_token: str,
    ) -> ESignatureRecord:
        """
        Sign an action with a TOTP token.

        Raises:
            ValueError: user not registered, token invalid, or replay detected.
        """
        secret = self._load_secret(user_id)
        if secret is None:
            raise ValueError(f"User '{user_id}' is not registered for eSig")

        # Validate TOTP within the window
        current_step = int(time.time()) // TOTPService.PERIOD
        verified_step = None
        sb = _secret_bytes(secret)
        for delta in range(-TOTPService.WINDOW, TOTPService.WINDOW + 1):
            step = current_step + delta
            expected = _hotp(sb, step, TOTPService.DIGITS)
            if hmac.compare_digest(expected, totp_token):
                verified_step = step
                break

        if verified_step is None:
            raise ValueError("TOTP token is invalid or expired")

        # Replay check
        ts_now = datetime.now(timezone.utc).isoformat()
        with self._store._connect() as conn:
            existing = conn.execute(
                "SELECT 1 FROM esig_used_tokens WHERE user_id = ? AND time_step = ?",
                (user_id, verified_step),
            ).fetchone()
            if existing:
                raise ValueError("TOTP token has already been used (replay rejected)")
            conn.execute(
                "INSERT INTO esig_used_tokens (user_id, time_step, used_at) VALUES (?, ?, ?)",
                (user_id, verified_step, ts_now),
            )

        # Build signature manifest
        sig_id = secrets.token_hex(16)
        manifest_hash = hashlib.sha256(
            f"{sig_id}|{user_id}|{action}|{meaning}|{ts_now}".encode()
        ).hexdigest()

        # Append ESIG record to audit log
        from .audit_store import AuditAction, AuditEvent, hash_payload
        audit_record = self._store.append(
            AuditEvent(
                user_id=user_id,
                action=AuditAction.ESIG,
                resource_type="esig",
                resource_id=sig_id,
                payload_hash=manifest_hash,
                details=f"action={action} meaning={meaning[:120]}",
            )
        )

        return ESignatureRecord(
            sig_id=sig_id,
            user_id=user_id,
            action=action,
            meaning=meaning,
            timestamp_utc=ts_now,
            manifest_hash=manifest_hash,
            audit_record_id=audit_record.id,
        )

    # ------------------------------------------------------------------
    # Verification
    # ------------------------------------------------------------------

    def verify_signature(self, sig: ESignatureRecord) -> bool:
        """
        Verify that a signature record's manifest_hash is internally consistent.
        Does NOT re-verify the TOTP (token is single-use and may be expired).
        """
        expected = hashlib.sha256(
            f"{sig.sig_id}|{sig.user_id}|{sig.action}|{sig.meaning}|{sig.timestamp_utc}".encode()
        ).hexdigest()
        return hmac.compare_digest(expected, sig.manifest_hash)
