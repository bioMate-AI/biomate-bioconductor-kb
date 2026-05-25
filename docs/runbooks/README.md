# BioMate Runbooks

Operational guides for the CI/CD pipeline built in the rebuild project.
Plan and rationale: [`../20260514_CICD_REBUILD_PLAN.md`](../20260514_CICD_REBUILD_PLAN.md).

| When you need to… | Read |
|---|---|
| Ship a normal change (or trigger a manual deploy / debug a deploy failure) | [deploy.md](deploy.md) |
| Revert a deployed change | [rollback.md](rollback.md) |
| Ship an emergency fix on the fast path | [hotfix.md](hotfix.md) |
| Respond to an active incident | [incident.md](incident.md) |

## Known operational constraints

- **Branch protection on `integration/next-phase` is not enforced** — the
  `bioMate-AI/biomate` repo is on the free GitHub plan, which doesn't
  support branch protection rules on private repos. Enforcement would
  require upgrading to GitHub Pro or making the repo public. Until then,
  protection is honor-system: don't force-push the default branch, don't
  delete it, don't bypass CI checks.

- **SNS deploy-event subscription is `PendingConfirmation`** for
  `xiaoni5122@gmail.com`. Notifications silently drop until you click the
  AWS confirmation email. Verify with:
  ```bash
  aws sns list-subscriptions-by-topic --region us-west-2 \
    --topic-arn arn:aws:sns:us-west-2:399683337364:biomate-deploy-events \
    --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' --output text
  ```

- **`sync_to_dev.sh` remains the supported fallback** for the dev EC2
  (`i-06696b0d91f4346e0` → `dev-public.biomate.ai`) until the GHA pipeline
  has the track record described in plan §P4.3 exit criteria: ≥2 weeks of
  green deploys, ≥1 successful auto-rollback drill, ≥1 successful
  major-track DB-migration deploy. The CD pipeline is currently
  exercised against the **test** env only.

- **Task #19 (Galaxy fork alembic)** still blocks Galaxy app boot on
  Postgres — so every deploy currently ends in the failure path. The CD
  primitive itself works correctly; the app it deploys does not.
