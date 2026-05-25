# Runbook: Hotfix

When a production-affecting bug needs a fix RIGHT NOW.

---

## Decision: hotfix or normal deploy?

Use hotfix flow when ALL of:
- Live users are blocked or losing data.
- The fix is < ~20 lines and well understood.
- Waiting for the normal deploy queue (image build ~8 min + healthcheck)
  is too slow OR the queue is jammed.

Use normal deploy flow otherwise. Hotfix bypasses some safety gates and
should be rare.

---

## Hotfix flow (under 15 minutes total)

```bash
# 1. Cut a branch from the broken commit, apply the smallest possible fix.
git checkout -b hotfix/<short-desc> integration/next-phase
# edit the file
git commit -am "hotfix: <one-line description>"

# 2. Push and tag immediately — the image build fires on the tag too.
git push origin hotfix/<short-desc>
git tag release-0.0.<next>
git push origin release-0.0.<next>

# 3. Wait for the release-tagged image to land in ECR (~8 min).
gh run watch $(gh api repos/bioMate-AI/biomate/actions/runs --jq '.workflow_runs[0].id') --exit-status

# 4. Manual deploy of the release tag (don't wait for workflow_run auto-trigger).
gh workflow run deploy.yml --ref integration/next-phase \
  -f env=test \
  -f tag=release-0.0.<next>

# 5. Watch the deploy. If healthcheck fails, auto-rollback fires.
gh run watch ...

# 6. Open a follow-up PR merging hotfix → integration/next-phase so the
# fix is in the main line, not orphaned on the hotfix branch.
gh pr create --base integration/next-phase --head hotfix/<short-desc> \
  --title "hotfix: <description>" \
  --body "Released as release-0.0.<next>. Merging back into main line."
```

---

## What hotfix BYPASSES

| Normal path includes | Hotfix path skips |
|---|---|
| PR review | (yes — emergency only) |
| Full CI (lint, tests, image build via push trigger) | Image build still runs (via tag push) |
| `concurrency: cancel-in-progress: false` | Same — rollback still serializes |
| Auto-rollback on healthcheck failure | **No — still active.** Don't disable this. |

If the hotfix itself fails healthcheck, **let auto-rollback run**. Don't
override it. If the only known-good build is also broken, you have a
bigger problem than a hotfix — escalate to [incident.md](incident.md).

---

## When hotfix is the wrong tool

- **Multi-line refactor**: too risky without review. Take the queue time.
- **DB migration**: never hotfix a migration. Always go through the
  major-track gate (plan §3.1.1, requires RDS snapshot + extra approval).
- **Config-only change**: if it's just an env var or Secrets Manager
  value, no code change needed — rotate the secret and `gh workflow run
  deploy.yml` to pick it up (force-recreate happens every deploy).
- **Network / infra**: route this through Terraform, not a code hotfix.
