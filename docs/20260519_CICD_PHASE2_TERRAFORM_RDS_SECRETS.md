# CI/CD Rebuild — Phase 2 Session Report

**Date:** 2026-05-19
**Scope:** P2.1 (Terraform skeleton + imports), P2.2 (RDS Postgres + connection wiring), P2.3 (Secrets Manager integration)
**Plan:** [`docs/20260514_CICD_REBUILD_PLAN.md`](20260514_CICD_REBUILD_PLAN.md)
**Branch:** `integration/next-phase`
**Status:** All CI/CD infrastructure for P2 complete. Remaining blocker for "fully booted Galaxy on Postgres" is a Galaxy-fork-internal alembic migration issue (task #19), NOT a CI/CD scope.

---

## 1. P2.1 — Terraform skeleton + imports

**State backend** (bootstrapped via aws-cli, idempotent):
- `s3://biomate-terraform-state` — versioning + SSE-AES256 + public-access blocked
- `dynamodb biomate-terraform-lock` — PAY_PER_REQUEST

**Directory structure**:

```
infra/terraform/
├── modules/
│   └── ec2_app/main.tf            reusable app-host module (SG + EC2 + idle alarm)
├── envs/
│   ├── dev/                       imports EC2 i-06696b0d91f4346e0 + dev-public DNS + creates idle alarm
│   ├── test/                      imports EC2 i-0482a6fa98c6f301a + stage-public DNS + SNS + alarm; provisions RDS + secret
│   ├── stage/                     empty for P2.4
│   └── prod/                      empty for P4.1
└── README.md
```

**Imports** — both env stacks return `terraform plan` no-op after one apply cycle, meaning state authoritatively matches reality:

| Env | Resource | TF resource | Action |
|---|---|---|---|
| test | EC2 `i-0482a6fa98c6f301a` | `aws_instance.test_app` | imported |
| test | SG `sg-0a70bb26e47332c55` | `aws_security_group.test_app` | imported |
| test | Route53 A `stage-public.biomate.ai` | `aws_route53_record.test_alias` | imported |
| test | SNS `biomate-deploy-events` | `aws_sns_topic.deploy_events` | imported |
| test | CW alarm `biomate-deploy-test-idle` | `aws_cloudwatch_metric_alarm.test_idle` | imported |
| dev | EC2 `i-06696b0d91f4346e0` | `aws_instance.dev_app` | imported (SG kept untouched via data source — has cross-system rules with billing/Lambda/RDS) |
| dev | Route53 A `dev-public.biomate.ai` | `aws_route53_record.dev_alias` | imported |
| dev | CW idle alarm | `aws_cloudwatch_metric_alarm.dev_idle` | **created new** — closes the L14 gap that caused the $1,400 g6.12xlarge orphan |

Defensive `lifecycle.ignore_changes` on the dev EC2 covers `ami`, `user_data`, `instance_type`, `root_block_device`, `vpc_security_group_ids` — so TF can't accidentally replace a live host.

---

## 2. P2.2 — RDS Postgres

**Provisioned** (test env first; stage/prod replicate the pattern):

| Resource | Identifier | Notes |
|---|---|---|
| `aws_db_instance` | `biomate-test-galaxy` | Postgres 17.6, db.t3.micro, 20GB gp3, encrypted, single-AZ, `backup_retention_period=0`, `skip_final_snapshot=true` |
| `aws_db_subnet_group` | `biomate-test-db-subnet-group` | default-VPC subnets (RDS requires ≥2 AZs even for single-AZ) |
| `aws_security_group` | `biomate-test-rds-galaxy-sg` | 5432 ingress from the test EC2 SG **only** — tightest possible scope |
| `aws_secretsmanager_secret` | `test/biomate/rds-galaxy` | holds username/password/host/port/dbname + a ready-to-use `postgresql://` URL |
| `random_password` | 32 chars, no specials (avoids URL-encoding pain) | regen on TF state loss; secret rotation belongs in a later phase |

**Cost**: ~$13/mo (db.t3.micro) + ~$2/mo (20GB gp3 + minimal storage I/O). Idle-alarm-armed.

### 2a. The OVERRIDE_ env-var trap

First test deploys silently went to SQLite even though the env was set. Root cause was in `lib/galaxy/util/properties.py:116-124`:

```python
override_prefix = f"{config_prefix}OVERRIDE_"
for key in os.environ:
    if key.startswith(override_prefix):
        config_key = key[len(override_prefix):].lower()
        properties[config_key] = os.environ[key]               # overrides file
    elif key.startswith(config_prefix):
        config_key = key[len(config_prefix):].lower()
        if config_key not in properties:                       # only fills if missing
            properties[config_key] = os.environ[key]
```

So `GALAXY_CONFIG_DATABASE_CONNECTION=postgresql://…` is **ignored** if `database_connection:` is already set in `galaxy.yml` (which `galaxy.yml.template` provides as `sqlite://…`). The correct variable is `GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION`. Fixed in `deploy/docker-compose.deploy.yml` and in deploy.sh's secret-fetch block.

### 2b. The `docker compose up` idempotency trap

`docker compose up -d --wait` won't recreate a container whose image digest + env signature match the running one. That means a freshly-rotated secret in `/opt/biomate/.env` doesn't take effect on the second deploy of the same image tag. Added `docker compose down --remove-orphans --volumes` then `up --force-recreate` to guarantee fresh containers + fresh env every deploy.

---

## 3. P2.3 — Secrets Manager wiring

Pattern proven end-to-end:

```
Terraform               IAM                          deploy.sh on operator           target EC2 (via SSM)
─────────────           ─────────                    ──────────────────              ──────────────────────
secret value generated  inline policy on             aws ssm send-command            aws secretsmanager get-secret-value
in random_password +    BioMateEc2DeployRole         (base64-encoded shell)          (using instance-profile creds)
stored encrypted in     scoped to THIS                                                → parse JSON → write
secretsmanager          secret ARN only                                                /opt/biomate/.env
                                                                                       docker compose up
                                                                                       (compose reads .env)
```

Inline IAM policy is **env-scoped** — `test/biomate/rds-galaxy` only. Stage and prod will add their own policies for their own secret ARNs, never a wildcard. Confirmed working:

```
[ssm:stage] OVERRIDE_DATABASE_CONNECTION sourced from test/biomate/rds-galaxy
```

L9 (`(API_KEY|SECRET|TOKEN)=<value>` grep guard) and the rotation of the existing leaked keys (LAGO, BILLING_INTERNAL, JWT) remain to be done in the dev/stage cutover sessions when the operator-set `.env` files on dev EC2 get retired.

---

## 4. Galaxy app boot — the remaining hard stop

This session's deploy.sh deliveries everything an app expects: a connection URL via Secrets Manager, a clean Postgres database, network reachability, container env, force-recreated containers. But the actual Galaxy app fails to boot through. The error chain:

1. `manage_db.sh init` → `alembic.util.exc.CommandError: Multiple heads are present` — this Galaxy fork has multiple alembic heads.
2. `manage_db.sh upgrade` (which implies `gxy@head`) → `Multiple head revisions are present for given argument 'gxy@head'`.
3. `manage_db.sh upgrade heads` (plural, the literal hint from the error message) → progresses further, then `sqlalchemy.exc.ProgrammingError: relation "workflow" does not exist [SQL: ALTER TABLE workflow ADD COLUMN source_metadata BYTEA]` — a migration ALTERs a table that hasn't been CREATEd by an earlier migration in the same revision graph.

This is a Galaxy fork migration-file hygiene issue, not infrastructure work. Tracked as **task #19**. The CI/CD pipeline does not need to wait on it — `sync_to_dev.sh` remains the production path until it's fixed (per P4.3 exit criteria).

---

## 5. What's now ready for P3 (CD pipeline) regardless

- **`deploy.sh <env> <release-tag>`** — every primitive proven (SSM, ECR pull via VPC endpoint SG path, compose force-recreate, healthcheck, auto-rollback, SNS notify, env-scoped Secrets Manager fetch, idle alarm coverage).
- **Terraform** — single source of truth for dev + test envs. Stage and prod are empty skeletons ready to be filled in P2.4 / P4.1.
- **GHA image build** — green on every push.
- **Idle alarms** — every EC2 covered (closes the $1,400-orphan L14 gap).

P3.1 can wrap `deploy.sh` in a workflow as soon as task #19 is resolved (or sooner if we choose to deploy a stub app for pipeline validation).

---

## 6. Files touched / created

```
infra/terraform/                                                  (new)
├── modules/ec2_app/main.tf
├── envs/dev/{main.tf, .terraform.lock.hcl}
├── envs/test/{main.tf, rds.tf, secrets_access.tf, .terraform.lock.hcl}
├── envs/{stage,prod}/                                            (empty placeholders)
├── README.md
└── .gitignore

scripts/deploy.sh                                                 (+ RDS_SECRET_NAME, force-recreate, .env sync)
deploy/docker-compose.deploy.yml                                  (OVERRIDE_ env var)
docs/20260519_CICD_PHASE2_TERRAFORM_RDS_SECRETS.md                (this file)
```

AWS new resources:
```
s3://biomate-terraform-state                                      (versioned, SSE-AES256, public blocked)
dynamodb biomate-terraform-lock                                   (state lock)
rds biomate-test-galaxy                                           (Postgres 17.6, db.t3.micro)
secretsmanager test/biomate/rds-galaxy                            (creds + URL)
sg biomate-test-rds-galaxy-sg                                     (5432 from test EC2 SG only)
db-subnet-group biomate-test-db-subnet-group                      (default VPC across AZs)
iam role-policy BioMateEc2DeployRole / test-biomate-secrets-read  (env-scoped)
cw alarm biomate-deploy-dev-idle                                  (closes L14 on dev EC2)
```
