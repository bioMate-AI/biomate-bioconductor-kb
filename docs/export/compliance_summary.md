# BioMate — Security & Compliance Summary

**Date:** 2026-04-29
**Evidence score: 13/14 controls passing**
**Sources:** SOC2/HIPAA Audit Framework, live AWS evidence run 2026-04-29

---

## 1. Applicable Standards

| Standard | Scope | Status |
|---|---|---|
| SOC2 Type II | Security, Availability, Processing Integrity, Confidentiality, Privacy | In progress — evidence framework and automation in place |
| HIPAA | Administrative, Physical, and Technical Safeguards (45 CFR §§ 164.302–318) | Controls implemented; PHI stripping live; AWS BAA covers Bedrock |

---

## 2. Evidence Scorecard (last run: 2026-04-29)

| # | Control | Status | Notes |
|---|---------|--------|-------|
| 1 | CloudTrail enabled | ✅ | `biomate-audit-trail`, multi-region, log validation |
| 2 | S3 public access blocked | ✅ | 15 buckets, all four block flags enabled |
| 3 | S3 evidence versioning | ✅ | Compliance bucket versioned |
| 4 | KMS key rotation | ✅ | All 3 CMKs have annual rotation |
| 5 | Root access keys absent | ✅ | Root key deactivated 2026-04-29 |
| 6 | Root MFA enabled | ✅ | Console MFA active |
| 7 | ElastiCache encrypted | ✅ | `biomate-redis-enc` — at-rest + in-transit (mode=required) |
| 8 | EC2 IMDSv2 required | ✅ | `HttpTokens=required` on BioMate-Production |
| 9 | SG no public dangerous ports | ❌ | Port 22 on 5 builder SGs — **accepted risk** (ephemeral build nodes; VPN planned Q3 2026) |
| 10 | S3 default encryption | ✅ | All 11 biomate buckets encrypted |
| 11 | Lambda no plaintext secrets | ✅ | Secrets moved to Secrets Manager 2026-04-29 |
| 12 | RDS backup retention ≥ 7 days | ✅ | `biomate-postgres` — 7-day automated backup |
| 13 | CloudWatch auth alarm | ✅ | `biomate-auth-failures-alarm` → SNS → email |
| 14 | IAM password policy | ✅ | MinLen=14, complexity, MaxAge=90, reuse-prevention=12 |

---

## 3. Data Security Controls

### 3.1 Encryption

| Layer | Specification | Status |
|---|---|---|
| In-transit (external) | TLS 1.2+ via AWS ALB | ✅ |
| In-transit (Redis) | TLS required (`rediss://`, mode=required) | ✅ Fixed 2026-04-28 |
| At-rest (PostgreSQL RDS) | AES-256, AWS KMS | ✅ |
| At-rest (S3 uploads) | SSE-KMS | ✅ |
| At-rest (Redis) | AES-256 | ✅ Fixed 2026-04-28 |
| At-rest (Galaxy API keys) | AES-256-GCM, application-layer | ✅ Added 2026-04-28 |
| KMS key rotation | Annual rotation on all 3 CMKs | ✅ |

### 3.2 Authentication & Access Control

| Control | Implementation | Status |
|---|---|---|
| Password hashing | bcrypt 12 rounds | ✅ |
| JWT tokens | HS256, 15-min production expiry, `httpOnly` + `sameSite:strict` | ✅ |
| IAM — admin user | `biomate-admin` with `AdministratorAccess` | ✅ Active 2026-04-29 |
| IAM — root key | Deactivated (Inactive) | ✅ 2026-04-29 |
| IAM — service accounts | `galaxy-dev` (workflow automation), `biomate-ses-smtp` (email) | ✅ |
| GitHub Actions credentials | Updated to `biomate-admin` key | ✅ 2026-04-29 |
| MFA (product) | TOTP prototype — 70/70 tests passing | ⏳ Integration next sprint |

### 3.3 PHI Controls

- Automatic stripping of 6 PHI types before any LLM call (`safety-guardrails.ts`)
- SHA-256 message hash logged to `audit_logs` — no plaintext PHI stored
- LLM via AWS Bedrock — AWS BAA covers PHI processing (no separate Anthropic BAA needed)

---

## 4. Infrastructure

### 4.1 Database — migrated to RDS 2026-04-29

| | Before | After |
|---|---|---|
| Host | Docker container on EC2 | AWS RDS `biomate-postgres` |
| Version | PostgreSQL 15.17 (Docker) | PostgreSQL 15.17 (RDS) |
| Encryption | None | AES-256 KMS |
| Backup | Manual cron (had never run) | Automated 7-day retention, hourly |
| HA | None | Single-AZ (Multi-AZ upgrade: Q4 2026) |
| Migration | — | 418,913 rows migrated, row count verified |

### 4.2 Backup Schedule

| Resource | Mechanism | Frequency | Retention |
|---|---|---|---|
| PostgreSQL (RDS) | AWS automated | Continuous | 7 days |
| EC2 EBS volumes | DLM policy `policy-0f50e1cdeec6242c4` | Daily 03:00 UTC | 7 snapshots |
| Audit logs | `export_audit_logs.py` → S3 Glacier IR | Daily 02:00 UTC | 6 years |

### 4.3 Secrets Location

| Secret | Location |
|---|---|
| `JWT_SECRET`, `FIELD_ENCRYPTION_SECRET`, `MFA_ENCRYPTION_SECRET` | `/opt/biomate/.env` on EC2 |
| `biomate/billing/api-key`, `biomate/lago/api-key` | AWS Secrets Manager |
| `biomate/rds/master-password` | AWS Secrets Manager |
| Lambda env vars | URLs only — no secrets |
| GitHub Actions | GitHub Secrets (uses `biomate-admin` key) |

---

## 5. Network Security

| Control | Status |
|---|---|
| Production SSH (`biomate-sg`) | Restricted to `104.63.31.236/32` (team IP) |
| PostgreSQL 5432 | Removed from public access; RDS only accessible from EC2 private IP |
| Redis 6379 | Private VPC only (no public endpoint) |
| S3 buckets | All public access blocked |
| EC2 IMDSv2 | `HttpTokens=required` on production |

---

## 6. Audit & Monitoring

| Component | Status |
|---|---|
| CloudTrail | `biomate-audit-trail` — multi-region, log file validation enabled |
| AWS Config | 7 managed rules, recorder active — SNS alert on any regression |
| CloudWatch alarm | `biomate-auth-failures-alarm` → `biomate-compliance-alerts` SNS → email |
| Evidence collector | Monthly run → `s3://biomate-compliance-evidence-399683337364/` |
| Audit log export | Daily → S3 Glacier IR (HIPAA 6-year retention) |

---

## 7. Business Associate Agreements

| Party | Status |
|---|---|
| AWS | ✅ Executed — covers RDS, S3, Bedrock, ElastiCache, Lambda, CloudTrail |
| Anthropic | N/A — using AWS Bedrock |

---

## 8. Open Items

| # | Item | Risk | Plan |
|---|------|------|------|
| 1 | Port 22 on 5 builder SGs | Low | Accepted — ephemeral nodes. VPN Q3 2026 |
| 2 | Root key Inactive, not deleted | Low | Delete after 30-day `biomate-admin` observation period |
| 3 | MFA not yet in main app | High | Prototype done (70/70 tests) — integrate next sprint |
| 4 | SiLA2 gRPC `insecure=True` | Medium | Lab-only — TLS certs pending device manufacturer |
| 5 | Secrets Manager full migration | Low | Remaining `.env` secrets → SM, Q3 2026 |
| 6 | RDS Single-AZ | Medium | Upgrade to Multi-AZ at production scale, Q4 2026 |
| 7 | VPN infrastructure | Medium | Replace SSH IP whitelist, Q3 2026 |

---

## 9. Key Contacts & Resources

| Purpose | Contact / Resource |
|---|---|
| Privacy inquiries | privacy@biomate.ai |
| Legal / Terms | legal@biomate.ai |
| Enterprise / HIPAA / BAA | Sales team |
| Compliance alerts | `yaoyun.zhang@biomate.ai` (SNS subscription pending confirmation) |
| Evidence bucket | `s3://biomate-compliance-evidence-399683337364/` |
| Audit framework | `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` |
| Remediation brief | `docs/20260428_SECURITY_REMEDIATION_TEAM_BRIEF.md` |
| Code changes guide | `docs/20260428_SECURITY_CHANGES_CODE_IMPACT.md` |

---

*This summary reflects controls verified and implemented 2026-04-28 to 2026-04-29.*
*Next quarterly review: 2026-07-29.*
