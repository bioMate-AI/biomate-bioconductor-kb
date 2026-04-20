"""
BioMate 21 CFR Part 11 Compliance Package — Phase 2 CRO Readiness

Modules:
  audit_store   — SHA-256 hash-chained append-only audit log (SQLite)
  esig          — TOTP-based electronic signatures (RFC 6238)
  audit_middleware — FastAPI dependency that records all regulated writes
"""
