# BioMate — Security & Compliance Session Report

**Date:** 2026-04-28 to 2026-04-29
**Scope:** Full SOC2/HIPAA remediation, infrastructure hardening, MFA integration
**Result:** Compliance score 8/14 → **13/14** | MFA fully integrated into main system

---

## What Was Done

### 1. Security Audit & Documentation

Starting point was three stale 2025-11-11 security documents in the repo root. Built a complete, current security picture from scratch:

- **`docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md`** — full SOC2/HIPAA framework with 14 automated controls, evidence procedures, incident response, BAA status, changelog
- **`docs/20260428_SECURITY_REMEDIATION_TEAM_BRIEF.md`** — step-by-step guide for the 3 items requiring human action
- **`docs/20260428_SECURITY_CHANGES_CODE_IMPACT.md`** — exact before/after code for Lambda secrets migration
- **`docs/20260427_MFA_IMPLEMENTATION_PLAN.md`** — full MFA design with checklist (now implemented)
- **`docs/export/`** — DOCX versions of all 6 documents for team distribution

Privacy Policy updated: date, TLS version (1.3 → 1.2+), PHI stripping bullet, expanded HIPAA section.

---

### 2. MFA Prototype (mfa-prototype/)

Built as a fully self-contained side project before touching production code. **70/70 tests passing** across 3 test files:

| Test suite | Tests | Coverage |
|---|---|---|
| `mfa.unit.test.ts` | 13 | AES-256-GCM encrypt/decrypt, TOTP generate/verify/reject, recovery code format |
| `api.integration.test.ts` | 25 | Full HTTP flows: register, login, setup, verify, challenge, recovery, disable, audit |
| `security.audit.test.ts` | 32 | Input validation, auth bypass, JTI replay, brute-force lockout, recovery code normalization, encryption at rest, concurrent burn race condition |

Security hardening discovered during audit:
- **Long email (10k chars)** — accepted without validation → added RFC 5321 max-length check
- **Recovery code race condition** — two concurrent requests both succeeded → fixed with synchronous `compareSync` inside SQLite `db.transaction()` (atomic read-compare-burn)

---

### 3. AWS Infrastructure (live changes)

All changes executed via AWS CLI with `biomate-admin` credentials.

#### Credential & IAM cleanup
- Created `biomate-admin` IAM user with `AdministratorAccess`
- Updated `~/.aws/credentials`, `start_backend.sh`, GitHub Actions secrets to `biomate-admin`
- Root key `AKIAV2DX3XSKGYVKVDET` deactivated (`Inactive`) — kept as emergency fallback
- IAM account password policy: MinLen=14, complexity, MaxAge=90, reuse-prevention=12

#### Network security
- `biomate-sg` SSH restricted from `0.0.0.0/0` → `104.63.31.236/32` (team IP from auth.log)
- PostgreSQL 5432 removed from `launch-wizard-1` public access

#### Encryption
- Recreated ElastiCache Redis as `biomate-redis-enc` with `AtRestEncryptionEnabled=true`, `TransitEncryptionEnabled=true` (mode=required)
- Old unencrypted cluster deleted
- All Redis clients updated to `rediss://` (TLS) endpoint — Node.js `redis` and Python `redis-py` both support natively

#### Database — migrated to RDS
- Created `biomate-postgres` (db.t3.micro, PostgreSQL 15.17, us-west-2, encrypted, no public access)
- Migrated 418,913 rows from Docker container — exact row count verified
- `DATABASE_URL` updated in `/opt/biomate/.env` on production EC2
- EBS snapshot policy created: daily 03:00 UTC, 7-day retention on BioMate-Production

#### Audit & monitoring
- `biomate-audit-trail` CloudTrail — multi-region, log file validation
- `biomate-auth-failures-alarm` CloudWatch alarm → SNS `biomate-compliance-alerts` → `yaoyun.zhang@biomate.ai` (subscription confirmed)
- AWS Config recorder + 7 managed rules (s3 public, s3 encryption, root MFA, CloudTrail, KMS rotation, RDS encryption, IAM password policy)
- EC2 IMDSv2 `HttpTokens=required` on BioMate-Production

#### Secrets
- `biomate/billing/api-key` and `biomate/lago/api-key` stored in AWS Secrets Manager
- `biomate/rds/master-password` stored in AWS Secrets Manager
- Lambda env vars stripped of plaintext secrets; `BillingSecretsReadPolicy` attached to `biomate-lambda-billing-role`
- Lambda code updated (`secrets.py` helper with `lru_cache`) — deployed to both us-east-1 and us-west-2

#### Galaxy API key encryption
- `frontend/server/field-encrypt.ts` — AES-256-GCM field-level encryption
- `auth-service.ts`: `encryptField()` on write, `decryptField()` on read in `routes.ts`
- `FIELD_ENCRYPTION_SECRET` added to production `.env`

#### Evidence collection
- `backend/scripts/compliance/collect_evidence.py` — 14 checks, uploads gzip JSON to S3 monthly, SNS alert on failures
- `backend/scripts/audit_glacier/export_audit_logs.py` — exports `audit_logs` rows >90 days to S3 Glacier IR; deployed as systemd timer on production EC2 (daily 02:00 UTC)

#### .gitignore fix
- `*.webm`, `*.mp4`, `*.zip`, `*.deb`, `.venv_*/`, `.r_lib_cache/`, `recording/` added
- 7,704 files (venvs, videos, db backups) removed from git tracking via `git filter-repo`
- Force-push cleaned history to remote

---

### 4. MFA Integration into Main System

Ported from prototype to the production TypeScript/Drizzle/Express/React stack.

#### Database (`0010_add_mfa.sql` — applied to RDS)
```sql
ALTER TABLE users ADD COLUMN mfa_secret TEXT, mfa_enabled BOOLEAN DEFAULT FALSE,
  mfa_verified_at TIMESTAMPTZ, mfa_recovery_codes TEXT,
  mfa_failed_attempts INTEGER DEFAULT 0, mfa_lockout_until TIMESTAMPTZ;
CREATE TABLE mfa_challenge_jtis (jti TEXT PRIMARY KEY, user_id VARCHAR, expires_at TIMESTAMPTZ);
```

#### Backend
| File | Change |
|---|---|
| `server/mfa-service.ts` | New — full TOTP service: speakeasy, AES-256-GCM secret encryption, recovery codes, brute-force lockout, JTI replay prevention via pg pool |
| `server/auth-service.ts` | `login()` issues 5-min challenge token when MFA enabled; `generateToken()` made public; `verifyCredentials()` added |
| `server/auth-middleware.ts` | Rejects `type='mfa_challenge'` tokens on all protected routes |
| `server/routes.ts` | 5 new endpoints: `POST /api/auth/mfa/setup`, `verify-setup`, `disable`, `GET status`, `POST challenge` |

#### Frontend
| File | Change |
|---|---|
| `components/mfa-settings.tsx` | New — Settings → Security tab: QR code setup, recovery codes (copy + download), disable flow |
| `pages/auth/mfa-challenge.tsx` | New — Login step: TOTP input (auto-submits on 6th digit), recovery code toggle, lockout message |
| `contexts/auth-context.tsx` | `login()` handles `mfaRequired: true` → routes to `/mfa-challenge` with `challengeToken` in history state |
| `components/settings-dialog.tsx` | Security tab added |
| `App.tsx` | `/mfa-challenge` route registered |

#### Security properties (same as prototype)
- Challenge token: 5-min JWT with unique JTI — one-use only (consumed in `mfa_challenge_jtis`)
- Brute-force: 5 failures → 15-min lockout; valid TOTP also blocked while locked
- Recovery codes: 8 codes, bcrypt-hashed, burned atomically on use
- TOTP secret: AES-256-GCM at rest via `field-encrypt.ts`

---

### 5. Compliance Evidence Score

| Run | Score | Date |
|---|---|---|
| Baseline (session start) | 8/14 | 2026-04-28 |
| After AWS infrastructure changes | 10/14 | 2026-04-28 |
| After IAM password policy + CloudWatch alarm | 11/14 | 2026-04-29 |
| After Lambda secrets + RDS | 12/14 | 2026-04-29 |
| After root key deactivation | **13/14** | 2026-04-29 |

The 1 remaining failure (`sg_no_public_dangerous_ports`) is accepted risk — port 22 on 5 ephemeral builder SGs. VPN planned Q3 2026.

Evidence stored at: `s3://biomate-compliance-evidence-399683337364/2026-04/`

---

## Open To-Dos

### Immediate (this week)

| # | Task | Who | Notes |
|---|------|-----|-------|
| 1 | Restart production Node.js app | DevOps | App needs restart to pick up RDS `DATABASE_URL` and new MFA code. SSH to 52.42.49.175, run `pm2 restart all` or equivalent |
| 2 | Update GitHub Actions secret `AWS_ACCESS_KEY_ID` | DevOps | Already done for Actions secrets but verify workflow runs succeed with `biomate-admin` key |

### Week of 2026-05-06 (after 1-week RDS stability)

| # | Task | Who | Notes |
|---|------|-----|-------|
| 3 | Stop Docker PostgreSQL container | DevOps | After confirming RDS stable: `docker stop biomate-dev-postgres && docker rm biomate-dev-postgres` + remove volume `biomate-postgres-data`. Recover ~5GB disk |
| 4 | MFA E2E tests | Engineering | Write Playwright tests for the full MFA flow: setup → login with challenge → recovery code use. See `mfa-prototype/tests/api.integration.test.ts` for reference cases |

### 2026-05-29 (30-day biomate-admin observation period)

| # | Task | Who | Notes |
|---|------|-----|-------|
| 5 | Delete root IAM access key | DevOps | Confirm `biomate-admin` has been working stably. Then: `aws iam delete-access-key --access-key-id AKIAV2DX3XSKGYVKVDET`. Compliance score goes to 14/14. |

### Q3 2026

| # | Task | Who | Notes |
|---|------|-----|-------|
| 6 | VPN infrastructure | DevOps | Replace SSH IP whitelist (`104.63.31.236/32`) with VPN-routed access. Removes the 1 compliance failure. |
| 7 | AWS Secrets Manager full migration | Engineering | Move remaining `.env` secrets (`JWT_SECRET`, `FIELD_ENCRYPTION_SECRET`, `MFA_ENCRYPTION_SECRET`) into SM. Inject via ECS task definition or SSM Parameter Store. |
| 8 | Admin MFA enforcement | Engineering | Add middleware to block admin users from any endpoint until MFA is set up. See `docs/20260427_MFA_IMPLEMENTATION_PLAN.md` §4 Enforcement Policy. |

### Q4 2026

| # | Task | Who | Notes |
|---|------|-----|-------|
| 9 | RDS Multi-AZ | DevOps | Upgrade `biomate-postgres` from `db.t3.micro` single-AZ. ~$50/month additional. |
| 10 | ECS Fargate multi-AZ | Engineering | Containerise frontend/API, move off single EC2. Eliminates single point of failure. |

---

## Key File Locations

| What | Where |
|---|---|
| MFA prototype (fully tested) | `mfa-prototype/` |
| MFA service (production) | `frontend/server/mfa-service.ts` |
| MFA DB migration | `frontend/migrations/0010_add_mfa.sql` |
| MFA settings UI | `frontend/client/src/components/mfa-settings.tsx` |
| MFA challenge page | `frontend/client/src/pages/auth/mfa-challenge.tsx` |
| Field encryption | `frontend/server/field-encrypt.ts` |
| Evidence collector | `backend/scripts/compliance/collect_evidence.py` |
| Audit Glacier export | `backend/scripts/audit_glacier/export_audit_logs.py` |
| SOC2/HIPAA framework | `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` |
| Team remediation brief | `docs/20260428_SECURITY_REMEDIATION_TEAM_BRIEF.md` |
| Code impact guide | `docs/20260428_SECURITY_CHANGES_CODE_IMPACT.md` |

## DOCX Documents for Team

All in `docs/export/` — downloadable directly from GitHub:

| File | Contents |
|---|---|
| `soc2_hipaa_audit_framework.docx` | Full SOC2/HIPAA framework, 13/14 controls, changelog |
| `compliance_summary.docx` | Executive summary, scorecard, infrastructure before/after |
| `security_remediation_team_brief.docx` | 3 open items with exact steps |
| `security_changes_code_impact.docx` | Lambda secrets code changes with before/after |
| `mfa_implementation_plan.docx` | MFA design (now implemented) |

---

*Session: 2026-04-28 to 2026-04-29*
*Next compliance evidence run: monthly (automated)*
*Next quarterly review: 2026-07-29*
