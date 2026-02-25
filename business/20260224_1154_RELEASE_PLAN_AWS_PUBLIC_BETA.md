# BioMate — AWS Public Beta Release Plan
**Created**: 2026-02-24
**Last updated**: 2026-02-24
**Target**: Invite-only closed beta → open registration
**Owner**: Alice (UI/Research), Bob (AWS/Workflows), Carol (Backend/Billing)

**Implementation log**: `business/20260224_1232_CLOSED_BETA_SECURITY_BILLING_IMPL.md`

---

## Part 1 — Pre-Release Security Fixes

### P0 — Critical Blockers

| Item | Description | Status |
|------|-------------|--------|
| P0-A | Add `authenticateToken` / `optionalAuth` to all unprotected API endpoints | ✅ Done |
| P0-B | CSP `unsafe-inline` / `unsafe-eval` dev-only; remove localhost from prod CORS | ✅ Done |
| P0-C | JWT / SESSION_SECRET / BILLING_INTERNAL_KEY → `process.exit(1)` if missing in prod | ✅ Done |
| P0-D | `BILLING_DEV_MODE=true` must be `false` in production (startup assertion in billing service) | ✅ Done |
| P0-E | `dangerouslySetInnerHTML` wrapped with `DOMPurify.sanitize()` | ✅ Done |

**P0-D detail**: `billing_router.py` needs a startup guard:
```python
if os.getenv("BILLING_DEV_MODE", "").lower() == "true":
    log.warning("BILLING_DEV_MODE is enabled — internal key auth is disabled")
    if os.getenv("ENV", "development") == "production":
        raise RuntimeError("BILLING_DEV_MODE must not be enabled in production")
```

---

### P1 — High Priority

| Item | Description | Status |
|------|-------------|--------|
| P1-A | JWT stored in localStorage → migrate to httpOnly cookie | ✅ Done |
| P1-B | Rate limiting on AI generation + URL import tied to billing tier | ✅ Done — see billing quota middleware below |
| P1-C | Lago billing configuration (real API keys, plan codes created in Lago dashboard) | ❌ Pending |

**P1-A detail** (done): `auth-context.tsx` now relies entirely on the httpOnly `biomate_token`
cookie (auto-sent with `credentials: 'include'`). All `localStorage.setItem/getItem('auth_token')`
calls removed. Stale keys are cleared on mount to migrate existing browser sessions.

**P1-B implementation**: `server/quota-middleware.ts` — `checkBillingQuota(resourceName)` replaces
the old IP-based `aiGenerateLimiter` (20/hr) and `urlImportLimiter` (10/hr). Instead of flat IP counters it checks the Redis quota from the billing service.

**P1-C detail**: Before billing is live, create these plan codes in the Lago dashboard:

| Lago plan code | Tier | Monthly cap |
|---|---|---|
| `free` | trial / academic | $5 |
| `basic` | professional | $50 |
| `pro` | enterprise | $500 |
| `enterprise` | admin | unlimited |

These must exist before `register_user` + `ensure_quota_set` work against live Lago.

---

### P2 — Medium Priority (Week 2–3, or before open registration)

- [ ] `sameSite: 'lax'` → `'strict'` for the session cookie
- [ ] JWT expiry: change `JWT_EXPIRES_IN` from `7d` to `24h` with refresh token flow
- [ ] Audit log persistence: `AuditLogger.log()` currently console-only → wire to CloudWatch Logs or audit table
- [ ] Global rate limiter: add Redis store so it works across multiple instances (`express-rate-limit` + `rate-limit-redis`)
- [x] `workflowLimiter` replaced with `checkBillingQuota` on `/api/workflows/execute`

---

## Part 2 — AWS Production Infrastructure

### Architecture Overview

```
Internet
   │
   ▼
Route 53 (biomate.ai)
   │
   ▼
CloudFront (CDN + WAF)
   │
   ├──► S3 (static assets)
   │
   ▼
ALB (Application Load Balancer)
   │
   ├──► Frontend ECS (Node/Express, port 5000)
   │       └── Fargate tasks, 2 min / 4 max
   │
   └──► Backend ECS (Galaxy/Python, port 8081)
           └── Fargate tasks, 1 min / 3 max
               │
               ├──► RDS PostgreSQL (users, billing, workflows)
               ├──► ElastiCache Redis (billing quotas, rate limiting, sessions)
               │       biomate-billing-redis.xzhevl.0001.usw2.cache.amazonaws.com:6379
               ├──► S3 (nextflow work + production data, us-east-1)
               └──► AWS Batch (Nextflow workflow execution)
```

### Step-by-Step Deployment

#### Phase 1 — Containerization (Bob, Week 1–2)

**Frontend Dockerfile** (`frontend/Dockerfile`):
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server ./server
ENV NODE_ENV=production
EXPOSE 5000
CMD ["node", "dist/index.js"]
```

**Backend Dockerfile** (`backend/Dockerfile`):
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PYTHONPATH=/app/lib
EXPOSE 8081
CMD [".venv/bin/gunicorn", "-w", "4", "-b", "0:8081", "galaxy.webapps.galaxy.fast_app:app"]
```

Push both to **ECR** (one repo per service).

#### Phase 2 — Database (Carol, Week 1)

**RDS PostgreSQL** (recommended: `db.t4g.medium` → `db.r7g.large` at scale):
- Enable Multi-AZ from day one
- Enable automated backups (7-day retention)
- Run `npm run db:migrate` as part of the CI/CD pipeline — never manually
  - Migration `0000_add_auth_system` — users, sessions, all auth tables
  - Migration `0001_invite_codes` — invite_codes, invite_code_uses, users.invite_code_id

**ElastiCache Redis** — already provisioned (`biomate-billing-redis`, us-west-2). Verify:
- `REDIS_URL` is set on both frontend and backend ECS task definitions
- Connection over private subnet only (no public access)
- SG `sg-096a3c0fcd3e4504c` allows port 6379 from backend + billing Lambda SG

#### Phase 3 — Secrets Management (Carol, Week 1)

Move ALL secrets to **AWS Secrets Manager** or **SSM Parameter Store**. Inject into ECS tasks as environment variables. Never bake into Docker images.

Required secrets:
```
/biomate/prod/JWT_SECRET                 — 64+ byte random hex
/biomate/prod/SESSION_SECRET             — 32+ byte random hex
/biomate/prod/BILLING_INTERNAL_KEY       — 32+ byte random hex (w498JF1dufdEd9O8AInfhS4VyJXi7CKiBz_0qzNVGOE in staging)
/biomate/prod/REDIS_URL
/biomate/prod/DATABASE_URL
/biomate/prod/ANTHROPIC_API_KEY
/biomate/prod/LAGO_API_KEY
/biomate/prod/LAGO_WEBHOOK_SECRET
/biomate/prod/GALAXY_API_KEY
/biomate/prod/REQUIRE_INVITE_CODE        — "true" for closed beta, "false" for open
```

ECS task definition references secrets by ARN — no plaintext in task defs.

#### Phase 4 — ECS / Fargate Services (Bob, Week 2–3)

Create two ECS services in a private VPC:

**Frontend service** (`biomate-frontend`):
- Task: 1 vCPU, 2 GB RAM
- Min 2, max 10 (scale on CPU > 60%)
- Health check: `GET /api/health` → 200

**Backend service** (`biomate-backend`):
- Task: 2 vCPU, 4 GB RAM
- Min 1, max 5 (scale on CPU > 70%)
- Health check: `GET /api/version` → 200

Both behind a single **ALB** with path-based routing:
- `/api/billing/*` and `/internal/billing/*` → backend target group (billing proxy passes through)
- `/api/galaxy/*` → backend target group
- `/*` → frontend target group

#### Phase 5 — CDN + WAF (Bob, Week 2)

**CloudFront** in front of ALB:
- Cache static assets (JS/CSS/images) at edge
- Pass API calls through (`/api/*` cache behavior: TTL=0)
- Enable **AWS WAF** with:
  - AWS Managed Rules (Core Rule Set + Known Bad Inputs)
  - Rate-based rule: 2000 req/5min per IP (blocks volumetric attacks before app)
  - Geo-block if there are export control concerns

#### Phase 6 — CI/CD Pipeline (Alice + Bob, Week 2–3)

**GitHub Actions** workflow:
1. `test` — run frontend/backend test suites (`npm test` + pytest)
2. `build` — build Docker images, push to ECR with SHA tag
3. `deploy-staging` — update ECS task definition, deploy to staging
4. `integration-test` — run e2e tests against staging
5. `deploy-prod` — manual approval gate → deploy to prod with blue/green via CodeDeploy

#### Phase 7 — Observability (All, Week 3)

- **CloudWatch Container Insights** — CPU, memory, network per task
- **CloudWatch Logs** — structured JSON logs, 90-day retention
- **CloudWatch Alarms**:
  - P95 API latency > 2s → PagerDuty
  - Error rate > 1% → PagerDuty
  - Redis connection failures → PagerDuty
  - Billing Lambda DLQ depth > 0 → alert
  - Quota-exceeded (402) rate spike → alert (unusual user activity)
- **X-Ray** tracing for the Nextflow execution path

---

## Part 3 — Invite Code System

### Status: FULLY IMPLEMENTED ✅

All components are built and live on `connection_formal` branch.
Full implementation details: `business/20260224_1232_CLOSED_BETA_SECURITY_BILLING_IMPL.md`

### Quick Reference

**Create beta codes**:
```bash
DATABASE_URL=postgres://... npm run admin:invite -- \
  --prefix BETA --count 100 --trial-days 14 --quota 10.00 \
  --description "Closed beta wave 1"
```

**Promote yourself to admin** (required first):
```bash
DATABASE_URL=postgres://... npm run admin:set -- your@email.com
```

**List codes**:
```bash
DATABASE_URL=postgres://... npm run admin:invite -- --list
```

**Shareable registration link**:
```
https://biomate.ai/register?invite=BETA-A1B2-C3D4
```
The code pre-fills in the registration form automatically.

**Gate toggle** (single env var, no code change):
```bash
REQUIRE_INVITE_CODE=true   # closed beta
REQUIRE_INVITE_CODE=false  # open registration
```

---

## Part 4 — Billing Integration (New)

### Status: Infrastructure deployed, Lago config pending

**What's live**:
- Redis quota store (`biomate-billing-redis`) provisioned and wired
- Billing Lambda (batch job cost tracking) deployed
- Billing API endpoints (32/32 e2e tests passing)
- `syncUserToBilling()` in `auth-service.ts` seeds quota at registration
- `checkBillingQuota` middleware gates AI generation + URL import

**What's pending (P1-C)**:
- Create plan codes in Lago dashboard (`free`, `basic`, `pro`, `enterprise`)
- Set real `LAGO_API_KEY` and `LAGO_WEBHOOK_SECRET` in prod
- Without Lago, `ensure_quota_set` falls back to `DEFAULT_PLAN_LIMITS` in `quota_enforcer.py` ($5/$50/$500) — this is acceptable for closed beta but usage won't be tracked in Lago until configured

**Plan configuration** (`server/plan-config.ts`):

| Tier | Billing plan | Monthly quota |
|---|---|---|
| `trial` / `academic` | `free` | $5 |
| `professional` | `basic` | $50 |
| `enterprise` | `pro` | $500 |
| `admin` | `enterprise` | unlimited |

---

## Part 5 — Release Timeline

```
           WEEK 1         WEEK 2         WEEK 3         WEEK 4         WEEK 5+
Status:    ✅ DONE        In progress    Pending        Pending        Pending

Security:  P0-A,B,C,E    P0-D           P2 items
           + P1-B done    P1-A (JWT
           Invite codes   cookies)
           schema +       P1-C (Lago)
           billing sync   Containers
                          + CI/CD
                          + Secrets
                          + RDS

Infra:                    ECR + ECS      CDN + WAF
                          RDS + Secrets  E2E tests
                          ALB routing    Observability

Beta:                                                   Closed beta    Open beta
                                                        50 users       REQUIRE_
                                                        REQUIRE_       INVITE_CODE
                                                        INVITE_CODE    =false
                                                        =true
```

### Gate Criteria for Closed Beta (Week 4)

- [x] All P0 security fixes merged and passing (A, B, C, D, E — all done)
- [x] P1-A: JWT in httpOnly cookie (localStorage fully removed from client)
- [x] Invite code schema migrated and API endpoints live
- [x] `syncUserToBilling()` wired at registration
- [x] Billing quota middleware on AI generation + URL import
- [ ] Frontend + backend running on ECS Fargate
- [ ] Secrets in SSM Parameter Store (no env files on EC2)
- [ ] CloudWatch alarms active
- [ ] `REQUIRE_INVITE_CODE=true` confirmed in prod env
- [ ] `BILLING_DEV_MODE=false` confirmed in prod env
- [ ] Lago plan codes created (`free`, `basic`, `pro`, `enterprise`)
- [ ] First batch of invite codes generated

### Gate Criteria for Open Registration (Week 5+)

- [ ] Closed beta ran for ≥2 weeks with no P0 incidents
- [ ] Cost-per-user within acceptable range (validated by billing audit)
- [ ] Email verification flow tested end-to-end
- [ ] `REQUIRE_INVITE_CODE=false`
- [ ] Rate limits tuned based on beta usage patterns
- [ ] JWT → httpOnly cookie migration complete (P1-A)

---

## Part 6 — Cost Estimate (AWS, Monthly at Beta Scale ~50 users)

| Service | Config | Est. Cost/month |
|---|---|---|
| ECS Fargate (frontend) | 2 tasks × 1vCPU/2GB, ~720h | ~$60 |
| ECS Fargate (backend) | 1 task × 2vCPU/4GB, ~720h | ~$60 |
| ALB | 1 LB + ~5GB processed | ~$20 |
| RDS PostgreSQL | db.t4g.medium, Multi-AZ | ~$70 |
| ElastiCache Redis | cache.t4g.small (existing) | ~$25 |
| CloudFront | ~50GB transfer | ~$5 |
| Route 53 | 1 hosted zone | ~$1 |
| CloudWatch | Logs + metrics | ~$15 |
| WAF | 1 WebACL + rules | ~$10 |
| AWS Batch (Nextflow) | Pay per workflow run | Variable |
| **Total (fixed)** | | **~$266/month** |

Nextflow compute (AWS Batch) is billed per run — monitored via billing Lambda.

---

## Appendix A — Secrets Rotation Checklist

Before every deploy, verify these are rotated and not defaults:
- [ ] `JWT_SECRET` — 64+ byte random hex
- [ ] `SESSION_SECRET` — 32+ byte random hex
- [ ] `BILLING_INTERNAL_KEY` — 32+ byte random hex
- [ ] `ENCRYPTION_KEY` — 32 bytes (AES-256 key)
- [ ] `LAGO_API_KEY` — from Lago dashboard
- [ ] `LAGO_WEBHOOK_SECRET` — from Lago dashboard
- [ ] Galaxy admin API key — rotated from Galaxy admin panel
- [ ] AWS credentials — use IAM roles, never static keys in env

## Appendix B — One-Time Deployment Commands

```bash
# 1. Run DB migrations (both must succeed before starting services)
DATABASE_URL=postgres://... npm run db:migrate

# 2. Promote first admin user
DATABASE_URL=postgres://... npm run admin:set -- founder@biomate.ai

# 3. Create closed-beta wave 1 invite codes
DATABASE_URL=postgres://... npm run admin:invite -- \
  --prefix BETA1 --count 100 --trial-days 14 --quota 10.00 \
  --description "Closed beta wave 1 — Feb 2026"

# 4. Verify billing dev mode is OFF
curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://backend:8081/internal/billing/admin/health | jq .
```
