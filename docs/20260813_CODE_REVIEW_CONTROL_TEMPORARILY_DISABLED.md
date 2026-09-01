# Code-Review Control Temporarily Disabled (integration/next-phase)

**Date:** 2026-08-13
**Decision owner:** yaoyun.zhang@biomate.ai (compliance owner)
**Executed by:** renyuankai (zheganjue519)
**Status:** TEMPORARY — to be remediated later.

## What changed

On the default/production branch `integration/next-phase`:

1. **Required pull-request review REMOVED.** `required_pull_request_reviews`
   was `{ required_approving_review_count: 1, dismiss_stale_reviews: true }`
   → now `null`. Anyone with write access can now commit and merge directly,
   no approval needed.
2. **Auto-assign-reviewers workflow DISABLED** (`disabled_manually`). It no
   longer requests reviewers on new PRs (this also stops the review-request
   emails / thread subscriptions that were flooding the team).

## What was intentionally KEPT (safety guards, not "review")

- `allow_force_pushes: false` — force-push still blocked.
- `allow_deletions: false` — branch deletion still blocked.
- `enforce_admins: true` — the remaining guards apply to admins too.

## Compliance impact (accepted, honest red — NOT faked green)

This is a deliberate, documented risk acceptance. The SOC2 change-management
posture in Vanta will truthfully reflect the disabled control:

- **`code-review-application-config` ("Application changes reviewed") → will FAIL.**
  This test checks that ≥1 approval is required to merge to the default branch.
  With required reviews removed, it flips OK → FAIL. This is expected.
- `github-ensure-branch-protection-enforced` — a protection rule with
  `enforce_admins: true` still exists (force-push/deletion guards), so this
  one likely stays green.
- `github-author-is-different-from-reviewer` — GitHub-enforced; no self-approval
  can occur, so no change.

We did NOT use a bot/shared-account workaround to keep the test green while
removing the substance. The control is genuinely off and Vanta shows it.

## Remediation plan (later)

Re-enable when ready by restoring the required review. Reference payload:

```bash
gh api --method PUT repos/bioMate-AI/biomate/branches/integration/next-phase/protection --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 1, "dismiss_stale_reviews": true },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

# and re-enable the reviewer bot:
gh workflow enable "Auto-assign reviewers" --repo bioMate-AI/biomate
```

The auto-assign workflow file remains in the repo
(`.github/workflows/auto-assign-reviewers.yml`); it is only disabled, not
deleted, so re-enabling is one command.
