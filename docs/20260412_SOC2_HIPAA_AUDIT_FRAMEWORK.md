# 2026-04-12 — SOC2 / HIPAA Audit Framework for BioMate

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

### 2.3 HIPAA Minimum Necessary Standard

BioMate does not require PHI to function. If PHI is detected, the system:
1. Strips it from the message
2. Proceeds with the sanitized version
3. Notifies the user (via warning in the response) that PHI was removed

---

## 3. Content Safety Controls (HIPAA + SOC2 Processing Integrity)

**File**: `frontend/server/safety-guardrails.ts`

The `checkSafety()` function also evaluates non-PHI safety:

| Rule | Signals Required | Response |
|------|-----------------|----------|
| `gain_of_function` | ≥3 of: enhanced transmissibility, pathogen, airborne, lethality | Refuse + audit |
| `cbrn_synthesis` | ≥2 of: synthesis route, precursor, nerve agent family | Refuse + audit |
| `scheduled_substance_synthesis` | drug synthesis + (schedule I keyword) + not (clinical/pharmacology bypass) | Refuse + audit |
| `clinical_diagnosis` | diagnosis/treatment + patient name-like token + no research bypass | Warn + audit |

Multi-signal design prevents false positives on legitimate bioinformatics queries (e.g., "analyze pathogen genome" does not trigger — no airborne/lethality signal).

---

## 4. Audit Log Schema (SOC2 CC6.1, CC7.2)

### 4.1 Database Table: `audit_logs`

```sql
CREATE TABLE audit_logs (
  id          SERIAL PRIMARY KEY,
  timestamp   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  event_type  TEXT NOT NULL,          -- 'phi_detected', 'content_blocked', 'auth_failure', etc.
  user_id     INTEGER REFERENCES users(id),
  session_id  TEXT,
  message_hash TEXT,                  -- SHA-256, hex-encoded
  phi_types   TEXT,                   -- Comma-separated if applicable
  rule_name   TEXT,                   -- Safety rule name if content blocked
  ip_address  TEXT,
  user_agent  TEXT,
  metadata    JSONB
);
```

### 4.2 Admin Query Endpoints

**List events** (requires `isAdmin = true` on authenticated user):
```
GET /api/admin/audit-log?event_type=phi_detected&limit=100&offset=0
```

**Summary counts** (for dashboard):
```
GET /api/admin/audit-log/summary
```
Returns: `{ total, phi_detected, content_blocked, auth_failures, last_24h_by_type }`

Both endpoints require `authenticateToken` + `requireAdmin` middleware. Non-admin requests receive `403 Forbidden`.

### 4.3 Log Retention

Per HIPAA §164.316(b)(2)(i): audit logs must be retained for **6 years** from creation.

Recommended implementation:
- PostgreSQL `audit_logs` table: hot storage, 90 days
- AWS S3 Glacier export: after 90 days, daily export via Lambda + lifecycle policy → Glacier IR
- Restore SLA: within 4 hours for compliance audit requests

---

## 5. Access Control (HIPAA §164.312(a)(1), SOC2 CC6.2)

### 5.1 Authentication

- All API routes require JWT Bearer token (except public OAuth callbacks)
- Tokens signed with `JWT_SECRET` env var; HS256 algorithm
- Token expiry: 7 days (configurable via `JWT_EXPIRY_DAYS`)
- Failed auth attempts logged to `audit_logs` with `event_type = 'auth_failure'`

### 5.2 Authorization Tiers

| Role | Capabilities |
|------|-------------|
| Anonymous | Read-only public endpoints, submit chat (rate-limited) |
| Authenticated User | Full workflow access, session management, personal data only |
| Admin | All user endpoints + audit log access + user management |
| Service Account | Machine-to-machine API key auth (instruments, CI/CD) |

### 5.3 Per-User Galaxy API Keys

Each BioMate user has a personal Galaxy API key (`galaxyApiKey` in `users` table). All Galaxy operations use the requesting user's key — not a shared service key. This ensures Galaxy audit trails are attributable to individual users.

### 5.4 API Key Rotation

Instrument connectors (OpenTrons, Benchling, MinKNOW) use service account API keys stored in environment variables:
- `BENCHLING_API_KEY`, `BIOMATE_API_KEY`, `SILA2_DEVICE_IPS`
- Keys must be rotated quarterly
- Rotation procedure: update env var → restart service → verify connectivity

---

## 6. Encryption (HIPAA §164.312(a)(2)(iv), §164.312(e)(2)(ii))

### 6.1 In-Transit

- All external HTTP traffic: TLS 1.2+ enforced via AWS ALB
- Internal gRPC (SiLA2): `insecure=True` in development; production requires TLS certificates from device manufacturer
- MinKNOW connector: plain HTTP on port 9501 — acceptable only when sequencer and BioMate are on the same isolated VLAN/VPC

### 6.2 At-Rest

- PostgreSQL: AWS RDS with storage encryption (AES-256, AWS-managed KMS key)
- S3 workflow outputs: bucket-level SSE-S3 or SSE-KMS
- Audit logs: encrypted at RDS level; no additional application-layer encryption required (message hashes only, no plaintext PHI)

### 6.3 Secrets Management

All secrets use environment variables. Recommended progression:
1. **Current (dev)**: `.env` file, not committed to git (`.gitignore` enforced)
2. **Production target**: AWS Secrets Manager + parameter injection via ECS task definition

---

## 7. Availability and Disaster Recovery (SOC2 A1)

### 7.1 Current Architecture

| Component | HA Strategy |
|-----------|------------|
| Frontend / API (gunicorn) | Single EC2 (`dev-public`); target: ECS Fargate multi-AZ |
| PostgreSQL | RDS with Multi-AZ standby (auto-failover < 60s) |
| Nextflow execution | AWS Batch — inherently distributed; no single point of failure |
| S3 workflow outputs | 99.999999999% durability (AWS SLA) |

### 7.2 RTO / RPO Targets

| Metric | Target | Current Status |
|--------|--------|---------------|
| RTO (Recovery Time Objective) | < 4 hours | Not formally tested |
| RPO (Recovery Point Objective) | < 1 hour | RDS automated backups every 1 hour |

### 7.3 Backup Verification

Monthly: restore RDS snapshot to test instance, run DB integrity check, verify row counts for `sessions`, `workflows`, `audit_logs`.

---

## 8. Incident Response Procedures (HIPAA §164.308(a)(6))

### 8.1 PHI Breach Detection

A PHI breach occurs if:
- PHI is sent to an LLM despite the stripping layer (e.g., stripping bug)
- Audit logs are accessed by unauthorized users
- An attacker exfiltrates the `users` or `sessions` table

Detection signals:
- `audit_logs` query: `SELECT * FROM audit_logs WHERE event_type = 'phi_detected' AND timestamp > NOW() - INTERVAL '1 day'`
- CloudTrail alert on unexpected S3 `GetObject` on audit export bucket
- Anomaly alert: >100 `phi_detected` events from same `user_id` in 1 hour

### 8.2 Breach Response Timeline

| Hour | Action |
|------|--------|
| 0–1 | Identify scope: which users, which messages, which PHI types |
| 1–4 | Contain: revoke affected API keys, rotate JWT secret, force re-login |
| 4–24 | Assess: determine if PHI reached external services (LLM, S3 logs) |
| 24–72 | HIPAA notification to affected individuals (if >500: also notify HHS + media) |
| 72+ | Root cause analysis, control improvement, regulator report |

### 8.3 Breach Notification

HIPAA Breach Notification Rule (45 CFR §§ 164.400–414):
- Individual notification: within **60 days** of discovery
- HHS notification: same timeline (for breaches <500) or immediate for >500
- Media notification: if >500 individuals in a state — contact prominent media outlets in that state

---

## 9. Business Associate Agreement (BAA) Requirements (HIPAA §164.308(b))

BioMate must execute BAAs with:
- **AWS** (available as standard click-through in AWS Console → Account → Agreements)
- **Anthropic** (required before processing PHI via Claude API — contact enterprise@anthropic.com)
- Any downstream cloud provider that processes PHI

BioMate acts as a **Business Associate** when deployed for covered entities (hospitals, clinical labs, pharma with patient data).

---

## 10. Evidence Collection Checklist for SOC2 Audit

| Control | Evidence Artifact | Location |
|---------|------------------|----------|
| PHI stripping implemented | Code review of `safety-guardrails.ts` | `frontend/server/safety-guardrails.ts` |
| Audit logging active | DB query of `audit_logs` table (last 30 days) | RDS `biomate` db |
| Access control enforced | Penetration test report | `docs/security/` |
| TLS in transit | ALB listener configuration (HTTPS 443 only) | AWS Console |
| Encryption at rest | RDS/S3 encryption settings screenshot | AWS Console |
| JWT auth on all routes | Code review of `routes.ts` `authenticateToken` usage | `frontend/server/routes.ts` |
| Per-user API key isolation | DB query: `SELECT DISTINCT galaxy_api_key FROM users LIMIT 5` | RDS |
| PHI detection test | Unit test suite pass for `safety-guardrails.ts` | `frontend/server/__tests__/` |
| Incident response plan | This document | `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` |
| BAA with AWS | AWS Agreement PDF | Legal folder (not in git) |

---

## 11. Security Testing Cadence

| Test | Frequency | Owner |
|------|-----------|-------|
| PHI guardrail unit tests | Every CI run | Engineering |
| Dependency vulnerability scan (`npm audit`, `pip-audit`) | Weekly | DevOps |
| OWASP ZAP dynamic scan | Monthly | Security |
| Penetration test (external) | Annually | Third-party firm |
| SOC2 readiness assessment | Annually | Compliance team |
| HIPAA risk analysis (SRA) | Annually + after material changes | Privacy Officer |

---

## 12. Open Gaps (as of 2026-04-12)

| Gap | Risk | Remediation |
|-----|------|-------------|
| SiLA2 gRPC uses `insecure=True` | Medium — lab network only | Issue TLS certs per device; add cert path to `SiLA2Device.connect()` |
| MinKNOW plain HTTP | Low — sequencer VLAN | VLAN isolation + firewall rule; log if off-subnet |
| Audit log retention policy not enforced | Medium | Implement S3 Glacier export Lambda |
| No multi-factor authentication | High for production | Add MFA via TOTP (speakeasy) or AWS Cognito |
| `JWT_SECRET` default empty in dev | Critical if deployed without setting | Fail-fast: raise on startup if `JWT_SECRET` not set in production |
| No BAA with Anthropic | High if PHI in prompts | Execute BAA before production go-live with clinical customers |
| Audit log table not yet created in schema | High | Add Drizzle migration for `audit_logs` table |

---

*Document owner: Engineering / Security*
*Review cycle: Quarterly*
*Next review: 2026-07-12*
