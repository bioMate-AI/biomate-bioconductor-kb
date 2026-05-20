# Runbook: Deploy

How to ship a change to an environment via the CI/CD pipeline.

---

## Normal deploy (automatic)

Push to `integration/next-phase` (the default branch) → image-build workflow
fires → on success, `Deploy to environment` fires → SSM applies the new tag
to the target EC2 → external HTTP healthcheck gates promotion → SNS notify.

You don't need to do anything. Watch progress at:

- [Actions tab](https://github.com/bioMate-AI/biomate/actions)
- SNS email (once you confirm the subscription on `biomate-deploy-events`)
- The env URL (e.g. `http://stage-public.biomate.ai`)

If a deploy fails, the workflow exits 1 and (if a prior healthy tag exists)
auto-rollback fires inside the same job. SNS gets a failure event including
the rollback target.

---

## Manual deploy

Trigger the deploy workflow yourself for a specific tag:

```bash
gh workflow run deploy.yml --ref integration/next-phase \
  -f env=test \
  -f tag=sha-c30d962bd694    # or release-0.0.1, or integration-next-phase-latest
```

Find available tags:

```bash
aws ecr describe-images --repository-name biomate/dev-backend --region us-west-2 \
  --query 'sort_by(imageDetails[?imageTags!=null],&imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' \
  --output text
```

ECR lifecycle keeps the last 10 `sha-*` tags + the last 10 `release-*` tags
per repo (set in P1.2 commit `9b41d87bd`).

---

## What gets deployed

The deploy targets are env-tagged EC2 hosts running docker-compose. The
deploy.yml workflow:

1. Resolves the EC2 by `Name=biomate-deploy-<env>` tag.
2. Sends a base64-encoded shell script via AWS SSM to that host.
3. Inside the script: pre-flight (disk, docker, orphan sync_to_dev.sh),
   ECR login, fetch RDS connection URL from Secrets Manager (env-scoped),
   `docker compose pull && down && up -d --wait --force-recreate`.
4. From the GHA runner: external HTTP healthcheck loop (90s budget, 5s
   interval) against `<env-public-url>/api/health`.
5. On success: record the new tag in `/opt/biomate/last_deployed_tag`,
   prune old stopped containers (last 3 kept), SNS success notify.
6. On failure: SNS failure notify, optional auto-rollback to prior tag.

No SSH. No long-lived AWS keys. Every step is audited in CloudTrail (SSM)
and in the GHA workflow log.

---

## If the deploy fails

1. Open the workflow run. The failed step output names which guard tripped
   (pre-flight / pull / compose-up / healthcheck).
2. SSH-equivalent: any state inspection on the target host should also use
   SSM (no SSH key needed):
   ```bash
   aws ssm start-session --target i-0482a6fa98c6f301a
   # then on the host:
   docker ps -a --format '{{.Names}}: {{.Status}}'
   docker logs --tail 100 biomate-galaxy-deploy
   cat /opt/biomate/last_deployed_tag
   ```
3. If the failure is recoverable (e.g. transient ECR pull), just re-run
   the workflow. If it's a code issue, fix it and push.
4. If you need to revert immediately, see [rollback.md](rollback.md).

---

## Past incidents this pipeline guards against

See `docs/20260514_CICD_REBUILD_PLAN.md` §6.3 for the full lessons register
(L1–L22). Highlights enforced in the deploy path:

- **L3**: never `docker prune -af` — only `--filter=until=24h`.
- **L7**: `pkill -f sync_to_dev.sh` on target before deploying so legacy
  sync loops can't fight with the new container set.
- **L17**: auto-rollback on healthcheck failure to the last tag recorded
  in `/opt/biomate/last_deployed_tag` (only written after a healthy boot).
- **L20**: SSM Run Command, not EC2 Instance Connect (which has a 60s key
  TTL and a history of mid-transfer race failures).
- **L21**: external HTTP healthcheck is the gate — container `(healthy)`
  alone is insufficient.

---

## Known limitations / out of scope (this rebuild)

- **Galaxy fork alembic** (Task #19): first-boot DB stamping on Postgres
  fails due to multi-head migrations. Until fixed, every deploy ends in
  the failure path even when the deploy mechanism itself worked perfectly.
- **Stage env** (P2.4) and **prod env** (P4.1) not yet provisioned.
- **Major-track gate** (DB-migration auto-snapshot + extra approval per
  plan §3.1.1) — not yet implemented; P2.2 RDS snapshot can be done
  manually before a migration-touching deploy: `aws rds create-db-snapshot`.
