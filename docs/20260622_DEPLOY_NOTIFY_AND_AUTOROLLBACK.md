# Deploy: failure notification + auto-rollback (root-cause fix)

Date: 2026-06-22
Branch: feat/mobile-responsive-layout
File touched: `scripts/deploy.sh`

## Problem reported

"CICD 启动失败时没有邮件提醒，也没有自动回滚。"

## Root cause

`.github/workflows/deploy.yml` (header L16/L23) and the rollback.yml comment
claimed `scripts/deploy.sh` enforced **L17 auto-rollback to previous tag** and a
**deploy notification**. Neither was actually implemented — the comments were
aspirational.

Concretely, before this change:

1. **No notification anywhere in `deploy.sh`.** `aws sns publish` appeared only
   in `rollback.yml`'s manual "Announce rollback" step (a `workflow_dispatch`
   action, not a failure trigger). On health-check failure `deploy.sh` just
   `exit 1` and told no one.
2. **No rollback.** Step 6 ran `docker compose up -d` (new image already live),
   then Step 7's health check `exit 1` on failure — leaving the **broken new
   containers running**. No prior-tag capture, no revert.
3. **SNS topic had 0 subscribers.** `biomate-deploy-events`
   (`arn:aws:sns:us-west-2:399683337364:biomate-deploy-events`) existed but
   `SubscriptionsConfirmed=0, Pending=0` — so even a publish would reach no one.

`sync_to_dev.sh` (the path actually used per the deploy-topology memory) likewise
had no failure-notify / rollback gate. Both paths shared the gap.

## Fix (in `scripts/deploy.sh`)

- **A. Auto-rollback (host-side, atomic).** Step 6 is now a single host script:
  capture the images currently in service (`docker inspect ... .Config.Image`),
  bring up the new images, run a ~90s health gate, and on failure `compose up`
  the **previous** images and re-check. The host prints a terminal marker:
  `DEPLOY_RESULT=healthy|rolled_back|rollback_failed|failed_no_prev`
  with exit codes `0 / 2 / 3 / 1`. Prior images are still local (we never prune —
  past-incident L3), so the revert needs no pull.
- **B. SNS notify on every exit.** An `EXIT` trap (`on_exit` → `notify`) publishes
  exactly one message to `biomate-deploy-events` with env / tag / instance /
  state / GHA run URL. Subjects are ASCII (SNS subject requirement). **Publish
  failure is non-fatal** (logged as `::warning::`) so a missing IAM perm can never
  block a deploy. Early failures (no instance, env-load failure) now notify too.
- `ssm_run` now captures host stdout/stderr into `SSM_OUT`/`SSM_ERR` globals
  (even on a failed invocation) so Step 6 can parse the `DEPLOY_RESULT` marker.

## Still required (C — operator action)

The notification only reaches a human once the topic has a **confirmed email
subscription**. Pending the address from the operator:

```bash
aws sns subscribe --region us-west-2 \
  --topic-arn arn:aws:sns:us-west-2:399683337364:biomate-deploy-events \
  --protocol email --notification-endpoint <email>
```

## Live test on `test` (i-0482a6fa98c6f301a) — 2026-06-23

Ran end-to-end against the real test box. Email subscription
(zheganjue519@gmail.com) confirmed first.

- **Test 1 — happy path** (`deploy.sh test sha-71729b1e1a09`): prev captured,
  new image healthy, `DEPLOY_RESULT=healthy`, exit 0, `SNS notified (healthy)`.
  ✅ as predicted.
- **Test 2 — rollback** (deployed a deliberately-broken busybox image pushed to
  both repos at `sha-broken-test`): **first run FOUND TWO REAL BUGS in the
  initial Step 6:**
  1. `docker compose up -d` **hung forever** on a broken image — the compose
     file has `frontend depends_on backend (condition: service_healthy)`, so a
     backend whose healthcheck never goes green blocks `up` indefinitely; the
     script never reached the rollback branch and left the box broken.
  2. Even without the hang, `broken-health (90s) + rollback + Galaxy cold start`
     exceeded `ssm_run`'s hard-coded 300s poll → false "failed" notification
     while the host kept working.
- **Fix applied** (this is what's in the committed deploy.sh):
  - `bring_up` now uses `docker compose up -d --wait --wait-timeout <N>` (bounded
    wait — returns non-zero instead of hanging) wrapped in `timeout` as a hard
    kill. New image budget 180s, rollback 240s.
  - `ssm_run` gained an optional timeout arg; Step 6 uses 600s.
  - Host persists the terminal `DEPLOY_RESULT` to `/tmp/biomate_deploy_result`;
    deploy.sh reads it back if the marker isn't in the stream.
  - Exported `BACKEND_IMAGE/FRONTEND_IMAGE` before the pre-`up` `down` to avoid
    a benign "invalid compose project" warning.
- **Test 2 re-run — PASSED**: broken image `up --wait` returned `timeout waiting
  for dependencies` (no hang), rollback to `sha-71729b1e1a09` went Healthy,
  `DEPLOY_RESULT=rolled_back`, exit 2, `SNS notified (rolled_back)`. Box left
  healthy. Broken ECR tags + host artifacts cleaned up afterward.

Net: both **notification** and **auto-rollback** are now verified working on the
real test environment.

## Verify before relying on it

1. `bash -n scripts/deploy.sh` — done, passes.
2. Confirm the deploy role can publish: the GHA OIDC role
   `arn:aws:iam::399683337364:role/GitHubActionsDeploy` (or whatever principal
   runs `deploy.sh`) needs `sns:Publish` on the topic. `rollback.yml` already
   assumes this; if its publish has been silently failing, fix the policy.
3. After the email subscription is confirmed, trigger a deploy that fails health
   (e.g. a bad tag) on `test` and confirm: (a) prior image restored & healthy,
   (b) one `[deploy ROLLED BACK]` email arrives.

## sync_to_dev.sh (the real dev deploy path)

Per the deploy-topology memory, dev deploys actually run through
`scripts/sync_to_dev.sh` (an in-place file sync + gunicorn HUP), not the
image-tag `deploy.sh`. Changes made there:

- **B. SNS notification — added.** A consolidated `on_exit` EXIT trap publishes
  one `[dev-sync ok|FAILED]` message to `biomate-deploy-events` with commit /
  instance / exit code. Gated by `SYNC_STARTED` so pre-flight refusals
  (dirty tree, not-a-repo, lock contention) stay silent — only real deploy
  attempts notify. SNS failure is non-fatal (warning), and the trap preserves
  the script's original exit code (verified under bash 3.2 with all three
  outcomes).
- **Bug fixed in passing:** `resync_galaxy_env` did `trap "rm -f $LIVE_ENV" EXIT`,
  which *replaced* the lock-file-removal trap (bash traps don't stack) — so any
  run through that path leaked `/tmp/biomate_sync_to_dev.lock`. Both cleanups
  now live in the single `on_exit` handler; temp files register via
  `CLEANUP_FILES` instead of re-trapping.

- **A. Auto-rollback — deliberately NOT added here.** sync_to_dev is an in-place
  file sync, so there is no "previous image" to revert to. A real rollback needs
  a snapshot-before-sync design (e.g. capture the prior synced artifacts / git
  ref and restore on failure). Bolting on a partial revert would be a workaround
  (forbidden by CLAUDE.md), so the notification instead instructs the operator to
  re-sync a known-good commit. **Open design item.**
