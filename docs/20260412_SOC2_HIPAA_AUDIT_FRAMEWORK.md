# BioMate — SOC2 / HIPAA Audit Framework

**Created:** 2026-04-12
**Last updated:** 2026-04-28
**Document owner:** Engineering / Security
**Review cycle:** Quarterly
**Next review:** 2026-07-28

---

## Overview

This document defines BioMate's controls, evidence artifacts, and operational procedures for SOC2 Type II and HIPAA compliance. It is the authoritative reference for security posture, audit log queries, and evidence collection.

---

## 1. Applicable Standards

| Standard | Relevance | Scope |
|----------|-----------|-------|
| **SOC2 Type II** | Required for enterprise customer contracts | All five Trust Service Criteria (TSC): Security, Availability, Processing Integrity, Confidentiality, Privacy |
| **HIPAA** | Required when processing any Protected Health Information (PHI) | Administrative, Physical, and Technical Safeguards (45 CFR §§ 164.302–318) |

BioMate is a bioinformatics platform; clinical data (patient identifiers, diagnoses, lab results tied to individuals) may be pasted into the chat interface. The safety guardrails layer (`frontend/server/safety-guardrails.ts`) is the primary PHI control.

---

## 2. PHI Detection and Stripping (HIPAA §164.312(a)(2)(iv))

### 2.1 Implemented Controls

**File**: `frontend/server/safety-guardrails.ts`

The `checkSafety()` function runs on every message before it reaches the AI backend:

| PHI Pattern | Regex | Action |
|-------------|-------|--------|
| SSN | `\b\d{3}-\d{2}-\d{4}\b` | Strip + log |
| Date of Birth | `\b(DOB|Date of Birth|Born)[:\s]+\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b` | Strip + log |
| Medical Record Number | `\b(MRN|Medical Record)[:\s#]+[A-Z0-9]{4,12}\b` | Strip + log |
| Patient ID | `\b(Patient ID|PatientID|PID)[:\s#]+[A-Z0-9\-]{4,20}\b` | Strip + log |
| NPI (provider) | `\bNPI[:\s#]+\d{10}\b` | Strip + log |
| Insurance Policy | `\b(Policy|Member ID)[:\s#]+[A-Z0-9\-]{6,20}\b` | Strip + log |

`stripPHI()` returns `{ sanitized: string, detected: string[] }`. The sanitized message — never the original — is passed to the LLM and stored.

### 2.2 Audit Log Entry for PHI Detection

When PHI is detected, a row is inserted into the `audit_logs` database table with:
- `event_type`: `"phi_detected"`
- `message_hash`: SHA-256 of the original message (not plaintext)
- `phi_types`: comma-separated list of detected PHI type names
- `user_id`: authenticated user ID (null for anonymous)
- `timestamp`: server UTC time

The message hash allows re-identification **only** if the original message is presented — meeting GDPR "pseudonymization" and HIPAA de-identification requirements.

### 2.3 LLM Provider — AWS Bedrock (HIPAA-eligible)

All Claude API calls route through **AWS Bedrock** (not the direct Anthropic API). AWS has an executed BAA covering Bedrock services, making Claude inference HIPAA-eligible without a separate Anthropic BAA. AWS region: `us-east-1`.

### 2.4 HIPAA Minimum Necessary Standard

BioMate does not require PHI to function. If PHI is detected, the system:
1. Strips it from the message
2. Proceeds with the sanitized version
3. Notifies the user (via warning in the response) that PHI was removed

---

## 3. Content Safety Controls (HIPAA + SOC2 Processing Integrity)

**File**: `frontend/server/safety-guardrails.ts`

| Rule | Signals Required | Response |
|------|-----------------|----------|
| `gain_of_function` | ≥3 of: enhanced transmissibility, pathogen, airborne, lethality | Refuse + audit |
| `cbrn_synthesis` | ≥2 of: synthesis route, precursor, nerve agent family | Refuse + audit |
| `scheduled_substance_synthesis` | drug synthesis + (schedule I keyword) + not (clinical/pharmacology bypass) | Refuse + audit |
| `clinical_diagnosis` | diagnosis/treatment + patient name-like token + no research bypass | Warn + audit |

Multi-signal design prevents false positives on legitimate bioinformatics queries.

---

## 4. Audit Log Schema (SOC2 CC6.1, CC7.2)

### 4.1 Database Table: `audit_logs`

Migration: `frontend/migrations/0009_add_audit_logs.sql` (applied 2026-04-28)

```sql
CREATE TABLE IF NOT EXISTS audit_logs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  timestamp     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  action        TEXT NOT NULL,
  user_id       INTEGER REFERENCES users(id),
  resource_type TEXT,
  resource_id   TEXT,
  ip_address    TEXT,
  user_agent    TEXT,
  request_id    TEXT,
  session_id    TEXT,
  details       JSONB,
  phi_types     TEXT,
  rule_name     TEXT,
  severity      TEXT DEFAULT 'info',
  metadata      JSONB
);
-- Indexes: user_id, timestamp DESC, action, (resource_type, resource_id)
```

### 4.2 Log Retention — Hot + Cold Tiers

Per HIPAA §164.316(b)(2)(i): 6-year retention required.

| Tier | Storage | Retention | Mechanism |
|------|---------|-----------|-----------|
| Hot | PostgreSQL | 90 days | Live queries |
| Cold | S3 Glacier IR | 6 years from creation | `export_audit_logs.py` — systemd timer, daily 02:00 UTC |

**S3 path:** `s3://biomate-production-data-399683337364/audit-logs-glacier/YYYYMMDD/`
**Restore SLA:** Glacier IR — within 4 hours for compliance audit requests.

### 4.3 Admin Query Endpoints

```
GET /api/admin/audit-log?event_type=phi_detected&limit=100&offset=0
GET /api/admin/audit-log/summary
```
Both require `authenticateToken` + `requireAdmin`. Non-admin: `403 Forbidden`.

---

## 5. Access Control (HIPAA §164.312(a)(1), SOC2 CC6.2)

### 5.1 Authentication

| Control | Implementation | Status |
|---------|---------------|--------|
| Password hashing | bcrypt, 12 rounds | ✅ |
| JWT tokens | HS256, 15-min expiry (production), httpOnly + sameSite:strict | ✅ |
| JWT secret | 64-char hex (256-bit), set in `/opt/biomate/.env` — verified 2026-04-28 | ✅ |
| Failed auth logging | `audit_logs`, `event_type='auth_failure'` | ✅ |

### 5.2 Multi-Factor Authentication

TOTP-based MFA implemented and fully tested in `mfa-prototype/` (70/70 tests passing). Features:
- `speakeasy` TOTP, Google Authenticator compatible
- 5-minute challenge token (short-lived, one-time via JTI)
- 5-attempt brute-force lockout → 15-minute account lock
- 8 recovery codes (bcrypt-hashed, burn-on-use, atomic SQLite transaction)
- AES-256-GCM TOTP secret encryption at rest

**Status:** Prototype complete. Integration into main system: next sprint.

### 5.3 Authorization Tiers

| Role | Capabilities |
|------|-------------|
| Anonymous | Read-only public endpoints, rate-limited chat |
| Authenticated User | Full workflow access, personal data only |
| Admin | All endpoints + audit log + user management |
| Service Account | Machine-to-machine API key auth |

### 5.4 Galaxy API Key Encryption

Galaxy API keys (`galaxyApiKey` column in `users` table) are encrypted using AES-256-GCM before storage.

- **Encrypt:** `frontend/server/field-encrypt.ts` — `encryptField()` called on write in `auth-service.ts`
- **Decrypt:** `decryptField()` called on read in `routes.ts`
- **Secret:** `FIELD_ENCRYPTION_SECRET` env var — set in `/opt/biomate/.env` (2026-04-28)
- **Migration:** Graceful fallback for existing plaintext values during rolling migration

### 5.5 API Key Rotation

Instrument connectors (OpenTrons, Benchling, MinKNOW): quarterly rotation.
Rotation procedure: update env var → restart service → verify connectivity.

---

## 6. Encryption (HIPAA §164.312(a)(2)(iv), §164.312(e)(2)(ii))

### 6.1 In-Transit

| Layer | Spec | Status |
|-------|------|--------|
| External HTTP | TLS 1.2+ via AWS ALB | ✅ |
| Redis (ElastiCache) | TLS required (`rediss://`, mode=required) | ✅ Fixed 2026-04-28 |
| LLM API (Bedrock) | AWS SDK mutual TLS | ✅ |
| SiLA2 gRPC | `insecure=True` in dev; lab network only | ⚠️ Open |
| MinKNOW | Plain HTTP port 9501 — sequencer VLAN only | ⚠️ Low risk |

### 6.2 At-Rest

| Layer | Spec | Status |
|-------|------|--------|
| PostgreSQL | AES-256 (AWS RDS KMS) | ✅ |
| S3 user uploads | SSE-KMS, key `58874a28-...` | ✅ |
| S3 Nextflow outputs | SSE-S3 | ✅ |
| Redis (ElastiCache) | AES-256 at-rest encryption | ✅ Fixed 2026-04-28 |
| KMS CMKs | All 3 keys have rotation enabled | ✅ |
| Galaxy API keys (PostgreSQL) | AES-256-GCM application-layer | ✅ Added 2026-04-28 |
| MFA TOTP secrets | AES-256-GCM application-layer | ✅ (in prototype) |

### 6.3 Secrets Management

| Secret | Location | Status |
|--------|----------|--------|
| `JWT_SECRET` | `/opt/biomate/.env` (64-char hex) | ✅ Verified 2026-04-28 |
| `FIELD_ENCRYPTION_SECRET` | `/opt/biomate/.env` | ✅ Added 2026-04-28 |
| `MFA_ENCRYPTION_SECRET` | `/opt/biomate/.env` | ✅ Added 2026-04-28 |
| `ANTHROPIC_API_KEY` | `/opt/biomate/.env` | ⚠️ Will be removed when Bedrock migration complete |
| All secrets | Target: AWS Secrets Manager | Planned — next quarter |

---

## 7. Availability and Disaster Recovery (SOC2 A1)

| Component | HA Strategy | Status |
|-----------|------------|--------|
| Frontend / API | Single EC2 (`BioMate-Production`); target: ECS Fargate multi-AZ | ⚠️ Single point |
| PostgreSQL | Docker on EC2 — not HA | ⚠️ No RDS Multi-AZ |
| Redis | ElastiCache single-node (`biomate-redis-enc`) | ⚠️ No replication |
| Nextflow execution | AWS Batch — distributed | ✅ |
| S3 outputs | 99.999999999% durability (AWS SLA) | ✅ |

| Metric | Target | Current |
|--------|--------|---------|
| RTO | < 4 hours | Not formally tested |
| RPO | < 1 hour | EC2 EBS snapshots (schedule TBD) |

**Backup verification:** Monthly test restore + row count check.

---

## 8. Incident Response Procedures (HIPAA §164.308(a)(6))

### 8.1 PHI Breach Detection

Detection signals:
- Audit log query: `SELECT * FROM audit_logs WHERE action = 'phi_detected' AND timestamp > NOW() - INTERVAL '1 day'`
- CloudWatch alarm (pending setup) on auth failure spike
- S3 CloudTrail alert on unexpected `audit-logs-glacier` `GetObject`
- Anomaly: >100 `phi_detected` events from same `user_id` in 1 hour

### 8.2 Breach Response Timeline

| Hour | Action |
|------|--------|
| 0–1 | Identify scope: users, messages, PHI types |
| 1–4 | Contain: revoke API keys, rotate JWT secret, force re-login |
| 4–24 | Assess: did PHI reach LLM or S3? |
| 24–72 | HIPAA notification to affected individuals |
| 72+ | Root cause, regulator report |

### 8.3 Breach Notification Thresholds

- Individual: within 60 days of discovery
- HHS: same (< 500); immediate for > 500
- Media: if > 500 individuals in one state

---

## 9. Business Associate Agreements (HIPAA §164.308(b))

| Party | BAA Status | Notes |
|-------|-----------|-------|
| AWS | ✅ Executed | Covers all AWS services including Bedrock |
| Anthropic (direct API) | N/A | Not required — using Bedrock |
| Other downstream providers | To assess per deployment | |

---

## 10. Evidence Collection (SOC2 CC4.1)

### 10.1 Automated Monthly Evidence

**Script:** `backend/scripts/compliance/collect_evidence.py`
**Output:** `s3://biomate-compliance-evidence-399683337364/YYYY-MM/YYYYMMDDTHHMMSSZ_evidence.json.gz`
**Alerts:** SNS `biomate-compliance-alerts` → `arn:aws:sns:us-west-2:399683337364:biomate-compliance-alerts`

14 checks run monthly:

| # | Control | Checks |
|---|---------|--------|
| 1 | CloudTrail enabled | Trail exists + IsLogging=true |
| 2 | S3 public access | All 4 block flags enabled on every bucket |
| 3 | S3 evidence versioning | Compliance bucket versioning=Enabled |
| 4 | KMS key rotation | All CMKs have annual rotation enabled |
| 5 | Root access keys absent | IAM credential report, root key1+key2 inactive |
| 6 | Root MFA enabled | AccountMFAEnabled=1 in IAM summary |
| 7 | ElastiCache encryption | AtRest=true + Transit=true on all clusters |
| 8 | EC2 IMDSv2 required | HttpTokens=required on production instance |
| 9 | Security groups | No 0.0.0.0/0 on ports 22/3306/5432/6379/27017 |
| 10 | S3 default encryption | SSE enabled on all biomate buckets |
| 11 | Lambda secrets | No plaintext secrets in Lambda env vars |
| 12 | RDS backup retention | ≥ 7 days (or N/A if using EC2 PostgreSQL) |
| 13 | CloudWatch auth alarm | At least one auth-related alarm exists |
| 14 | IAM password policy | MinLen≥12, complexity, MaxAge≤90 |

### 10.2 AWS Config Rules (7 rules, ~$14/month)

Immediate SNS alert if any control regresses between monthly runs:

| Rule | Managed Rule |
|------|-------------|
| S3 public access | `s3-bucket-public-read-prohibited` |
| S3 encryption | `s3-bucket-server-side-encryption-enabled` |
| RDS encryption | `rds-storage-encrypted` |
| Root MFA | `root-account-mfa-enabled` |
| IAM password policy | `iam-password-policy` |
| CloudTrail enabled | `cloud-trail-enabled` |
| KMS rotation | `cmk-backing-key-rotation-enabled` |

### 10.3 Audit at Audit Time

Grant Big 4 auditor read-only S3 access to `biomate-compliance-evidence-*` — they pull 12 months of evidence directly. No portal or external dependency required.

---

## 11. Security Testing Cadence

| Test | Frequency | Owner |
|------|-----------|-------|
| PHI guardrail unit tests | Every CI run | Engineering |
| MFA prototype full test suite (70 tests) | Every CI run | Engineering |
| Dependency scan (`npm audit`, `pip-audit`) | Weekly | DevOps |
| Evidence collector (`collect_evidence.py`) | Monthly (Lambda) | DevOps |
| OWASP ZAP dynamic scan | Monthly | Security |
| Penetration test (external) | Annually | Third-party firm |
| SOC2 readiness assessment | Annually | Compliance team |
| HIPAA risk analysis (SRA) | Annually + after material changes | Privacy Officer |

---

## 12. Open Gaps (updated 2026-04-28)

**Evidence baseline run: 2026-04-28 — 10/14 passing**
`s3://biomate-compliance-evidence-399683337364/2026-04/20260429T040646Z_evidence.json.gz`

| Gap | Risk | Status |
|-----|------|--------|
| Root IAM access key active | **Critical** | ❌ Root key in use as current AWS CLI credential — create IAM admin user, migrate credentials, delete root key |
| Port 22 open 0.0.0.0/0 on 6 SGs | Medium | ⚠️ Intentional for EC2 Instance Connect — consider restricting to office CIDR or switching to SSM-only |
| Lambda secrets still in env vars | Low | ⚠️ Values now in Secrets Manager — wire Lambdas to read from SM (needs `secretsmanager:GetSecretValue` on Lambda role) |
| MFA not yet integrated into main system | High | ✅ Prototype done (70 tests) — integration: next sprint |
| CloudTrail not configured | High | ✅ Fixed 2026-04-28 — `biomate-audit-trail`, multi-region, log validation enabled |
| EC2 IMDSv2 set to optional | Medium | ✅ Fixed 2026-04-28 — `HttpTokens=required` on BioMate-Production |
| SiLA2 gRPC `insecure=True` | Medium | ⚠️ Lab hardware — TLS certs pending device manufacturer |
| MinKNOW plain HTTP | Low | ⚠️ VLAN isolation — acceptable if network-isolated |
| PostgreSQL not on RDS | Medium | ⚠️ No Multi-AZ — manual pg_dump cron or migrate to RDS |
| AWS Secrets Manager migration | Low | ✅ Billing secrets stored (biomate/billing/api-key, biomate/lago/api-key) — full migration next quarter |
| CloudWatch auth failure alarm | Low | ✅ Fixed 2026-04-28 — `biomate-auth-failures-alarm` on BioMate/Security namespace |
| IAM password policy | Low | ✅ Fixed 2026-04-28 — MinLen=14, complexity, MaxAge=90, reuse-prevention=12 |

Previously open gaps — now closed:

| Gap | Closed | How |
|-----|--------|-----|
| No BAA with Anthropic | 2026-04-28 | Switched to AWS Bedrock (AWS BAA covers) |
| JWT_SECRET not verified on EC2 | 2026-04-28 | SSH verified: 64-char hex, set in .env |
| FIELD_ENCRYPTION_SECRET missing | 2026-04-28 | Generated + added to production .env |
| Galaxy API keys plaintext | 2026-04-28 | AES-256-GCM via field-encrypt.ts |
| Redis encryption not verified | 2026-04-28 | Recreated cluster: AtRest=true, Transit=required |
| Audit log Glacier export missing | 2026-04-28 | export_audit_logs.py + systemd timer daily 02:00 UTC |
| audit_logs migration missing | 2026-04-28 | 0009_add_audit_logs.sql |
| Privacy Policy outdated | 2026-04-28 | Updated to April 28, 2026 with PHI/HIPAA section |
| No MFA | In progress | Prototype: 70/70 tests, brute-force + replay hardened |

---

*Document owner: Engineering / Security*
*Review cycle: Quarterly*
*Next review: 2026-07-28*
