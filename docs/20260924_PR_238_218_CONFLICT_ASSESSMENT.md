# PR #238 / #218 conflict assessment

**Date:** 2026-09-24
**Question (original):** do the conflicts on PRs #238 / #218 need resolving, and do they affect dev?

## Finding: these are NOT mechanical conflicts — they are massive integration-branch divergences

| PR | head → base | changed files | additions / deletions | state |
|---|---|---|---|---|
| **#238** | `feat/drugdev-reinvent4-realgen` → `integration/next-phase` | **8,501** | **+1,704,833 / −191,551** | OPEN, mergeable=UNKNOWN |
| **#218** | `integration/dev-test` → `integration/next-phase` | **8,341** | **+1,684,969 / −189,948** | OPEN, mergeable=UNKNOWN |

Both PRs diff ~8,400 files / ~1.7M lines against `integration/next-phase`. A test-merge of either into next-phase produces a **100+-file staged blob** (verified twice — two separate agents each left a `MERGE_HEAD` worktree with 137 staged files and *no* conflict markers). This is not a "resolve a few `<<<<<<<` markers" task; the integration branches have diverged enormously.

**#238 is this session's own working branch** (`feat/drugdev-reinvent4-realgen`) — i.e. the branch carrying all the recent private-DB/MCP, run-finalization, UI-hide, and manual work. It is far *ahead* of `integration/next-phase`, not in a small-conflict state.

## Does it affect dev? NO.

`scripts/sync_to_dev.sh` deploys by **tarring the local working tree and pushing it directly** to the dev EC2 (frontend Docker rebuild + backend file cp + health-gated) — there is **no PR-merge / review gate** in the deploy path (confirmed in the script; matches the standing "sync direct from the local working tree, no merge/PR gate" directive). So the state of PRs #238/#218 on GitHub has **zero effect on what is running on dev**. Dev tracks whatever was last `sync_to_dev`'d from the local `feat/drugdev-reinvent4-realgen` worktree.

## Recommendation

This is a **human branch-management / release decision**, not an automated conflict-resolution task:
- Decide which integration branch is canonical going forward (`next-phase` is badly behind both `feat/drugdev-reinvent4-realgen` and `integration/dev-test`).
- Likely the right move is to **fast-forward / reset `integration/next-phase`** to the current canonical branch (or land the work as a fresh squashed PR), rather than merge an 8,500-file diff.
- Do NOT auto-commit a giant merge — it would be unreviewable and could reintroduce reverted work (e.g. the gpt-6-luna swap that was explicitly reverted this session).

**Attempting an automated merge is actively harmful here** (unreviewable blob, risk of resurrecting reverted commits) and buys nothing, since dev is unaffected. Left for a human release decision.

## Cleanup done
- Removed two abandoned half-merge worktrees (`agent-a19f…` and `scratchpad/wt-238`) that were consuming disk (the repo host was out of disk space).
