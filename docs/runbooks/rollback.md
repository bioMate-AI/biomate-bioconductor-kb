# Runbook: Rollback

How to revert a deployed change. Two paths: automatic (already in flight)
and manual (operator-triggered).

---

## Automatic rollback

If a deploy fails its external HTTP healthcheck AND a prior healthy tag
exists in `/opt/biomate/last_deployed_tag` on the target, `scripts/deploy.sh`
re-execs itself with that prior tag. SNS publishes a failure event noting
the rollback target. You don't need to do anything.

The prior tag is only written AFTER a deploy reaches healthy, so it's a
safe rollback target by construction.

---

## Manual rollback

Use this when:
- A green deploy turned out to have a functional regression caught later
  (e.g. by user reports, follow-up E2E, or a stage-only smoke test).
- You need to revert past the most-recent failure (which auto-rollback
  already addressed).

```bash
# Find the tag to redeploy. `sha-*` and `release-*` tags persist in ECR
# per the lifecycle policy (last 10 of each per repo).
aws ecr describe-images --repository-name biomate/dev-backend --region us-west-2 \
  --query 'sort_by(imageDetails[?imageTags!=null],&imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' \
  --output text

# Trigger the rollback workflow (dedicated for audit-trail visibility):
gh workflow run rollback.yml --ref integration/next-phase \
  -f env=test \
  -f tag=sha-27999805f8e3 \
  -f reason="health check passed deploy but workflow_X regression confirmed"
```

The rollback workflow:
1. Publishes an SNS event with subject `[rollback] <env> → <tag>` first
   (so on-call sees the action before the deploy starts).
2. Runs the same `scripts/deploy.sh` as a normal deploy — same SSM mechanism,
   same healthcheck gate. If the rollback target is _also_ unhealthy, the
   workflow exits 1 and SNS publishes another failure event.

---

## What rollback does NOT cover

Rollback redeploys a prior container image. It does NOT:

- **Revert RDS schema changes.** If the failed deploy ran an Alembic
  migration that altered tables, redeploying the prior image will hit
  schema-mismatch errors. For migration-touching changes, the major-track
  gate (plan §3.1.1) requires an RDS manual snapshot before deploy —
  recovery is `aws rds restore-db-instance-to-point-in-time` or restore
  from snapshot, NOT a tag rollback. Use:
  ```bash
  aws rds describe-db-snapshots --db-instance-identifier biomate-test-galaxy \
    --query 'DBSnapshots[?starts_with(DBSnapshotIdentifier,`pre-`)].[DBSnapshotIdentifier,SnapshotCreateTime]' \
    --output text
  ```
- **Revert S3 object changes.** S3 PutObject from a workflow run is not
  rolled back. If a deploy wrote bad data to S3, restore is per-prefix.
- **Restore old secrets.** Secrets Manager versions are preserved (default
  retention 7 days for our test secret). Roll back via:
  ```bash
  aws secretsmanager update-secret-version-stage \
    --secret-id test/biomate/rds-galaxy \
    --version-stage AWSCURRENT \
    --move-to-version-id <prior-version-id>
  ```

---

## Time budget

| Phase | Typical | Worst case |
|---|---|---|
| `gh workflow run rollback.yml` → workflow starts | <30s | 2 min |
| ECR pull on target | 30s (cached layers) | 3 min (fresh image) |
| compose down + up | 30s | 90s |
| External healthcheck | 90s budget | 90s (then exit 1) |
| **Total wall time** | **~3 min** | **~7 min** |

If the rollback workflow itself stalls past 10 min, the job-level timeout
fires (set in deploy.yml + rollback.yml).

---

## After a rollback

1. **Tag the bad release**: add a comment to the original PR / commit
   identifying it as the regression source.
2. **Investigate**: don't redeploy until the root cause is identified —
   see [incident.md](incident.md) for the post-mortem template.
3. **Snapshot the working state if not already**: if the rollback target
   is currently the only known-good build, consider re-tagging it as the
   current `<branch>-latest` to prevent the next auto-deploy from
   re-applying the broken tag.
