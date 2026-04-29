# BioMate — SOC2 / HIPAA Audit Framework

**Created:** 2026-04-12
**Last updated:** 2026-04-29
**Document owner:** Engineering / Security
**Review cycle:** Quarterly
**Next review:** 2026-07-29

---

## Overview

This document defines BioMate's controls, evidence artifacts, and operational procedures for SOC2 Type II and HIPAA compliance. It is the authoritative reference for security posture, audit log queries, and evidence collection.

**Current evidence score: 13/14 controls passing.**
Latest run: `s3://biomate-compliance-evidence-399683337364/2026-04/`

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

**File:** `frontend/server/safety-guardrails.ts`

`checkSafety()` runs on every message before it reaches the AI backend:

| PHI Pattern | Regex | Action |
|-------------|-------|--------|
| SSN | `\b\d{3}-\d{2}-\d{4}\b` | Strip + audit log |
| Date of Birth | `\b(DOB|Date of Birth|Born)[:\s]+\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b` | Strip + audit log |
| Medical Record Number | `\b(MRN|Medical Record)[:\s#]+[A-Z0-9]{4,12}\b` | Strip + audit log |
| Patient ID | `\b(Patient ID|PatientID|PID)[:\s#]+[A-Z0-9\-]{4,20}\b` | Strip + audit log |
| NPI (provider) | `\bNPI[:\s#]+\d{10}\b` | Strip + audit log |
| Insurance Policy | `\b(Policy|Member ID)[:\s#]+[A-Z0-9\-]{6,20}\b` | Strip + audit log |

The sanitized message — never the original — is passed to the LLM and stored. Message hash (SHA-256) is logged, not plaintext.

### 2.2 LLM Provider — AWS Bedrock (HIPAA-eligible)

All Claude API calls route through **AWS Bedrock**. AWS has an executed BAA covering all Bedrock services, making Claude inference HIPAA-eligible. No separate Anthropic BAA required.

### 2.3 HIPAA Minimum Necessary Standard

BioMate does not require PHI to function. When PHI is detected:
1. Strip from message before any processing
2. Proceed with sanitized version
3. Notify user PHI was removed
4. Write audit log entry (hash only, no plaintext)

---

## 3. Content Safety Controls (SOC2 Processing Integrity)

**File:** `frontend/server/safety-guardrails.ts`

| Rule | Signals Required | Response |
|------|-----------------|----------|
| `gain_of_function` | ≥3 of: enhanced transmissibility, pathogen, airborne, lethality | Refuse + audit |
| `cbrn_synthesis` | ≥2 of: synthesis route, precursor, nerve agent family | Refuse + audit |
| `scheduled_substance_synthesis` | drug synthesis + Schedule I keyword (no clinical bypass) | Refuse + audit |
| `clinical_diagnosis` | diagnosis/treatment + patient name-like token + no research bypass | Warn + audit |

---

## 4. Audit Log Schema (SOC2 CC6.1, CC7.2)

### 4.1 Database Table

Migration: `frontend/migrations/0009_add_audit_logs.sql` (applied 2026-04-28)

```sql
CREATE TABLE IF NOT EXISTS audit_logs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  timestamp     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  action        TEXT NOT NULL,
  user_id       INTEGER REFERENCES users(id),
  resource_type TEXT, resource_id TEXT,
  ip_address    TEXT, user_agent TEXT, request_id TEXT, session_id TEXT,
  details       JSONB, phi_types TEXT, rule_name TEXT,
  severity      TEXT DEFAULT 'info', metadata JSONB
);
-- Indexes: user_id, timestamp DESC, action, (resource_type, resource_id)
```

### 4.2 Retention — Hot + Cold Tiers

Per HIPAA §164.316(b)(2)(i): 6-year retention required.

| Tier | Storage | Retention | Mechanism |
|------|---------|-----------|-----------|
| Hot | PostgreSQL (RDS) | 90 days | Live queries, admin API |
| Cold | S3 Glacier IR | 6 years from creation | `export_audit_logs.py` — systemd timer daily 02:00 UTC |

**S3 path:** `s3://biomate-production-data-399683337364/audit-logs-glacier/YYYYMMDD/`
**Restore SLA:** Glacier IR — within 4 hours.

### 4.3 Admin Query Endpoints

```
GET /api/admin/audit-log?event_type=phi_detected&limit=100
GET /api/admin/audit-log/summary
```
Both require `authenticateToken` + `requireAdmin`. Non-admin: `403 Forbidden`.

---

## 5. Access Control (HIPAA §164.312(a)(1), SOC2 CC6.2)

### 5.1 Authentication

| Control | Implementation | Status |
|---------|---------------|--------|
| Password hashing | bcrypt, 12 rounds | ✅ |
| JWT tokens | HS256, 15-min expiry (production), `httpOnly` + `sameSite:strict` | ✅ |
| JWT secret | 64-char hex (256-bit) — `/opt/biomate/.env`, verified 2026-04-28 | ✅ |
| Failed auth logging | `audit_logs`, `event_type='auth_failure'` | ✅ |

### 5.2 IAM Users

| User | Type | Permissions | Status |
|------|------|-------------|--------|
| `biomate-admin` | Admin | `AdministratorAccess` | ✅ Active — primary operational key as of 2026-04-29 |
| `galaxy-dev` | Service account | EC2, S3, Batch, IAM, Lambda (workflow automation + auto-fix) | ✅ In use |
| `biomate-ses-smtp` | Service account | SES only (email) | ✅ In use |
| *(root)* | Root | Unrestricted | ✅ Key deactivated 2026-04-29 — kept Inactive for recovery only |

### 5.3 Multi-Factor Authentication

TOTP-based MFA implemented and tested in `mfa-prototype/` (70/70 tests passing):
- Google Authenticator compatible, `speakeasy` library
- 5-minute one-time challenge token (JTI replay prevention)
- 5-attempt brute-force lockout → 15-minute account lock
- 8 bcrypt-hashed burn-on-use recovery codes (atomic SQLite transaction)
- TOTP secret encrypted at rest (AES-256-GCM)

**Status:** Prototype complete. Integration into main system: next sprint.

### 5.4 Authorization Tiers

| Role | Capabilities |
|------|-------------|
| Anonymous | Public endpoints, rate-limited chat |
| Authenticated User | Full workflow access, own data only |
| Admin | All endpoints + audit log + user management |
| Service Account (`galaxy-dev`) | Workflow automation, AWS resource management |

### 5.5 Galaxy API Key Encryption

`galaxy_api_key` column in PostgreSQL `users` table is encrypted with AES-256-GCM before storage.
- Encrypt: `frontend/server/field-encrypt.ts` → `encryptField()` in `auth-service.ts`
- Decrypt: `decryptField()` in `routes.ts`
- Secret: `FIELD_ENCRYPTION_SECRET` in `/opt/biomate/.env`
- Graceful fallback for existing plaintext values during rolling migration

---

## 6. Encryption (HIPAA §164.312(a)(2)(iv), §164.312(e)(2)(ii))

### 6.1 In-Transit

| Layer | Spec | Status |
|-------|------|--------|
| External HTTP | TLS 1.2+ enforced via AWS ALB | ✅ |
| Redis (ElastiCache) | TLS required — `rediss://`, `TransitEncryptionMode=required` | ✅ |
| RDS PostgreSQL | TLS in-transit (AWS default) | ✅ |
| LLM API (Bedrock) | AWS SDK mutual TLS | ✅ |
| SiLA2 gRPC | `insecure=True` — lab network only | ⚠️ Open |
| MinKNOW | Plain HTTP port 9501 — sequencer VLAN only | ⚠️ Low risk |

### 6.2 At-Rest

| Layer | Spec | Status |
|-------|------|--------|
| PostgreSQL (RDS) | AWS RDS storage encryption, AES-256, KMS-managed | ✅ |
| S3 user uploads | SSE-KMS, key `58874a28-37a4-4b2c-9e78-7463c34c772b` | ✅ |
| S3 Nextflow outputs | SSE-S3 | ✅ |
| Redis (ElastiCache) | AES-256 at-rest — `biomate-redis-enc` | ✅ |
| KMS CMKs | All 3 customer keys have annual rotation enabled | ✅ |
| Galaxy API keys | AES-256-GCM application-layer in PostgreSQL | ✅ |
| MFA TOTP secrets | AES-256-GCM application-layer (prototype) | ✅ |

### 6.3 Secrets Management

| Secret | Location | Status |
|--------|----------|--------|
| `JWT_SECRET` | `/opt/biomate/.env` (64-char hex) | ✅ Verified 2026-04-28 |
| `FIELD_ENCRYPTION_SECRET` | `/opt/biomate/.env` | ✅ Set 2026-04-28 |
| `MFA_ENCRYPTION_SECRET` | `/opt/biomate/.env` | ✅ Set 2026-04-28 |
| `biomate/billing/api-key` | AWS Secrets Manager (us-west-2) | ✅ Migrated 2026-04-29 |
| `biomate/lago/api-key` | AWS Secrets Manager (us-west-2) | ✅ Migrated 2026-04-29 |
| `biomate/rds/master-password` | AWS Secrets Manager (us-west-2) | ✅ Set 2026-04-29 |
| GitHub Actions AWS credentials | GitHub Secrets — `biomate-admin` key | ✅ Updated 2026-04-29 |
| All remaining secrets | Target: AWS Secrets Manager full migration | Planned Q3 2026 |

---

## 7. Availability and Disaster Recovery (SOC2 A1)

| Component | HA Strategy | Status |
|-----------|------------|--------|
| Frontend / API | Single EC2 (`BioMate-Production`, 52.42.49.175) — target: ECS Fargate multi-AZ | ⚠️ Single point |
| PostgreSQL | AWS RDS `biomate-postgres` (db.t3.micro, us-west-2a) — target: Multi-AZ | ⚠️ Single-AZ |
| Redis | ElastiCache `biomate-redis-enc` (cache.t4g.small, single-node) | ⚠️ Single-node |
| Nextflow execution | AWS Batch — distributed, no single point of failure | ✅ |
| S3 outputs | 99.999999999% durability (AWS SLA) | ✅ |

| Metric | Target | Current |
|--------|--------|---------|
| RTO | < 4 hours | Not formally tested |
| RPO | < 1 hour | RDS automated backup every 1 hour (retention: 7 days) |

### 7.1 Backup Schedule

| Resource | Mechanism | Frequency | Retention | Status |
|----------|-----------|-----------|-----------|--------|
| PostgreSQL (RDS) | AWS automated backup | Continuous | 7 days | ✅ Active |
| EC2 EBS volumes | AWS DLM policy `policy-0f50e1cdeec6242c4` | Daily 03:00 UTC | 7 snapshots | ✅ Active |
| Audit logs | `export_audit_logs.py` → S3 Glacier IR | Daily 02:00 UTC | 6 years | ✅ Active (systemd timer) |
| S3 workflow data | S3 versioning + 11x durability | Continuous | Indefinite | ✅ |

---

## 8. Incident Response (HIPAA §164.308(a)(6))

### 8.1 PHI Breach Detection

Detection signals:
- Audit log: `SELECT * FROM audit_logs WHERE action = 'phi_detected' AND timestamp > NOW() - INTERVAL '1 day'`
- CloudWatch alarm `biomate-auth-failures-alarm` → SNS `biomate-compliance-alerts` → `yaoyun.zhang@biomate.ai`
- S3 CloudTrail alert on unexpected `GetObject` on audit Glacier bucket
- Anomaly: >100 `phi_detected` events from same `user_id` in 1 hour

### 8.2 Breach Response Timeline

| Hour | Action |
|------|--------|
| 0–1 | Identify scope: users, messages, PHI types |
| 1–4 | Contain: revoke API keys, rotate JWT secret, force re-login |
| 4–24 | Assess: did PHI reach Bedrock or S3? |
| 24–72 | HIPAA notification to affected individuals |
| 72+ | Root cause analysis, regulator report |

### 8.3 Breach Notification Thresholds (45 CFR §§ 164.400–414)

- Individual notification: within 60 days of discovery
- HHS: same timeline (< 500 individuals); immediate for > 500
- Media: if > 500 individuals in one state

---

## 9. Business Associate Agreements (HIPAA §164.308(b))

| Party | BAA Status |
|-------|-----------|
| AWS | ✅ Executed — covers RDS, S3, Bedrock, ElastiCache, Lambda |
| Anthropic (direct API) | N/A — using AWS Bedrock |

---

## 10. Automated Evidence Collection (SOC2 CC4.1)

### 10.1 Monthly Evidence Script

**Script:** `backend/scripts/compliance/collect_evidence.py`
**Schedule:** Monthly Lambda (or manual run)
**Output:** `s3://biomate-compliance-evidence-399683337364/YYYY-MM/YYYYMMDDTHHMMSSZ_evidence.json.gz`
**Alerts:** SNS → `yaoyun.zhang@biomate.ai`

### 10.2 Current Scores (last run: 2026-04-29)

| # | Control | Result | Detail |
|---|---------|--------|--------|
| 1 | CloudTrail enabled | ✅ | `biomate-audit-trail` — multi-region, log validation |
| 2 | S3 public access blocked | ✅ | 15 buckets, all fully blocked |
| 3 | S3 evidence versioning | ✅ | `biomate-compliance-evidence-*` versioning enabled |
| 4 | KMS key rotation | ✅ | All 3 CMKs have annual rotation enabled |
| 5 | Root access keys absent | ✅ | Root key deactivated 2026-04-29 |
| 6 | Root MFA enabled | ✅ | Console MFA active |
| 7 | ElastiCache encrypted | ✅ | `biomate-redis-enc` — AtRest=true, Transit=required |
| 8 | EC2 IMDSv2 required | ✅ | `HttpTokens=required` on BioMate-Production |
| 9 | SG no public dangerous ports | ❌ | Port 22 on 5 builder SGs — accepted risk (see §12) |
| 10 | S3 default encryption | ✅ | All 11 biomate buckets encrypted |
| 11 | Lambda no plaintext secrets | ✅ | 0 plaintext secrets in Lambda env vars |
| 12 | RDS backup retention | ✅ | `biomate-postgres` — 7-day retention |
| 13 | CloudWatch auth alarm | ✅ | `biomate-auth-failures-alarm` active |
| 14 | IAM password policy | ✅ | MinLen=14, complexity, MaxAge=90, reuse-prevention=12 |

**Score: 13/14**

### 10.3 AWS Config Rules (7 rules, continuous monitoring)

| Rule Name | Managed Rule | Triggers SNS on failure |
|-----------|-------------|------------------------|
| `biomate-s3-public-read-prohibited` | `S3_BUCKET_PUBLIC_READ_PROHIBITED` | ✅ |
| `biomate-s3-encryption` | `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED` | ✅ |
| `biomate-root-mfa` | `ROOT_ACCOUNT_MFA_ENABLED` | ✅ |
| `biomate-cloudtrail-enabled` | `CLOUD_TRAIL_ENABLED` | ✅ |
| `biomate-kms-rotation` | `CMK_BACKING_KEY_ROTATION_ENABLED` | ✅ |
| `biomate-rds-encryption` | `RDS_STORAGE_ENCRYPTED` | ✅ |
| `biomate-iam-password-policy` | `IAM_PASSWORD_POLICY` | ✅ |

---

## 11. Security Testing Cadence

| Test | Frequency | Owner |
|------|-----------|-------|
| PHI guardrail unit tests | Every CI run | Engineering |
| MFA prototype test suite (70 tests) | Every CI run | Engineering |
| Dependency scan (`npm audit`, `pip-audit`) | Weekly | DevOps |
| Evidence collector (`collect_evidence.py`) | Monthly | DevOps |
| OWASP ZAP dynamic scan | Monthly | Security |
| Penetration test (external) | Annually | Third-party |
| SOC2 readiness assessment | Annually | Compliance |
| HIPAA risk analysis (SRA) | Annually + after material changes | Privacy Officer |

---

## 12. Open Items (as of 2026-04-29)

### 12.1 Accepted Risks

| Item | Risk | Rationale |
|------|------|-----------|
| Port 22 on 5 builder SGs | Low | Instances are ephemeral build/HPC nodes, not production. VPN planned Q3 2026 to replace. |
| Root key Inactive (not deleted) | Low | Kept as emergency recovery mechanism. Delete after 30-day observation period with `biomate-admin`. |
| SiLA2 gRPC `insecure=True` | Medium | Lab hardware — lab network only, no internet exposure. TLS certs pending device manufacturer. |
| MinKNOW plain HTTP | Low | Sequencer VLAN only. Firewall isolation acceptable. |
| Single-AZ RDS | Medium | db.t3.micro — upgrade to Multi-AZ when moving to production scale. |

### 12.2 Planned Work

| Item | Target | Notes |
|------|--------|-------|
| MFA integration into main app | Next sprint | Prototype complete, 70/70 tests |
| AWS Secrets Manager full migration | Q3 2026 | All `.env` secrets → SM |
| VPN setup | Q3 2026 | Replace SSH IP whitelist |
| ECS Fargate multi-AZ | Q4 2026 | Replace single EC2 frontend |
| RDS Multi-AZ | Q4 2026 | Upgrade from t3.micro single-AZ |

---

## 13. Changelog

| Date | Change |
|------|--------|
| 2026-04-29 | RDS PostgreSQL `biomate-postgres` created; 418,913 rows migrated from Docker; `DATABASE_URL` cut over; EBS snapshot policy active |
| 2026-04-29 | Lambda secrets migrated to Secrets Manager (`biomate/billing/api-key`, `biomate/lago/api-key`); plaintext env vars removed; `BillingSecretsReadPolicy` attached |
| 2026-04-29 | Root IAM key deactivated; `biomate-admin` user operational; GitHub Actions secrets updated |
| 2026-04-29 | `biomate-sg` SSH restricted from `0.0.0.0/0` to `104.63.31.236/32` (team IP whitelist) |
| 2026-04-28 | CloudTrail `biomate-audit-trail` created; EC2 IMDSv2 enforced; Redis recreated with full encryption; PostgreSQL 5432 removed from public SG; IAM password policy set; CloudWatch auth alarm created; Secrets Manager secrets for billing created; AWS Config 7 rules active; `.gitignore` fixed (large files purged from git history) |
| 2026-04-28 | `audit_logs` Drizzle migration added; Galaxy API key AES-256-GCM encryption; Privacy Policy updated; `export_audit_logs.py` deployed with systemd timer |
| 2026-04-28 | MFA prototype complete: 70/70 tests, brute-force lockout, JTI replay prevention, atomic recovery code burn |
| 2026-04-12 | Initial SOC2/HIPAA framework document created |

---

*Document owner: Engineering / Security*
*Review cycle: Quarterly — next review 2026-07-29*
*Evidence bucket: `s3://biomate-compliance-evidence-399683337364/`*
*Alerts: `arn:aws:sns:us-west-2:399683337364:biomate-compliance-alerts`*
