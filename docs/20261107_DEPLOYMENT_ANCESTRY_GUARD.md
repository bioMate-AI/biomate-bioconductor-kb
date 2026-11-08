# Cross-worktree deployment ancestry guard

A deployment mutex prevents concurrent writes but cannot stop a stale checkout from replacing newer dev code later. `scripts/dev_deploy_ancestry.py` reads public `https://dev-public.biomate.ai/build-info.json` over normal verified HTTPS, refuses redirects, non-JSON/HTML/oversized responses and incomplete identities, then uses Git commit objects and merge-base ancestry locally. Same commit or a local descendant is allowed. Older/divergent local HEAD and unknown deployed commits are refused. It never fetches, resets, rewrites or deploys anything.

Eight tests use real temporary Git repositories and cover same/descendant, stale checkout, divergent history, unknown commit, explicit emergency handling and invalid transport/identity. These are local checks, not a deployed acceptance claim.

The sync hook is now present in the working copy of `scripts/sync_to_dev.sh` in `/private/tmp/biomate-zh-en-parity`, under the remote deployment lease and before code/DB mutation. This is a local source observation, not evidence that other worktrees have acquired the hook. Health and rollback gates are unchanged.

The patch adds only the fail-closed ancestry preflight under the existing remote lease, before the IT-only branch and any code/DB mutation. Existing CHANGED/local-marker layer selection is preserved exactly; the guard does not force backend/workflow reconciliation or broaden a UI sync. A public frontend identity does not establish backend/workflow identity, and worktree-private diff markers remain an acknowledged gap pending trusted per-layer deployment identities. Database synchronization remains separately governed by existing logic and is not authorized by an ancestry result.

The same ancestry guard covers IT recovery: its additive helper must come from the current deployed commit or a descendant, even though it does not ship frontend source. A stale recovery checkout must be reconciled before use. The ancestry check grants no socket capability and does not bypass the separate recovery approval/digest checks.

Emergency rollback requires `BIOMATE_EMERGENCY_DEPLOY_REASON` containing a meaningful incident reason (at least 12 characters). This permits a known non-ancestor only; unavailable/invalid identity or a deployed commit absent locally still fails. Operators must preserve the reason in the incident record. This is an explicit exceptional operation; normal deploys must reconcile Git history instead. No automatic fetch or silent bypass exists.


## Read-only local worktree inventory (2026-11-07)

Compared all 16 registered worktrees with known deployed commit `8e42b494641382ba173a25b88b61840f2c3c3e61` using local Git ancestry only; no fetch, remote read, deployment, reset, stash, or other-checkout edits. Guard presence below refers to the actual working-copy sync script, including uncommitted edits.

Only the current repair checkout contains both guards. Thirteen other checkouts contain a sync script with neither guard; two have no sync script. An updated script cannot protect dev from an old script copy that never invokes either guard. In particular, the lease is cooperative, not a remote enforcement barrier. These stale scripts must not be used to deploy; reconcile the intended checkout with the deployed history and use the reviewed guarded entry point. This inventory does not itself establish a global deployment restriction.

Dirty counts are aggregate Git status entries (tracked / untracked), not proof that each entry is an intentional source edit or lost work. No unrelated filenames or file contents were collected into this report.

| Checkout path | Branch | HEAD | Relative to deployed | Dirty tracked / untracked | Remote lease | Public ancestry guard |
| --- | --- | --- | --- | --- | --- | --- |
| `/Users/kky/biomate` | `fix/resolver-real-nfcore` | `d539811d1722` | divergent | 4 / 10 | no | no |
| `/private/tmp/biomate-zh-en-parity` | `codex/zh-en-ui-parity` | `8e42b4946413` | same | 7 / 3 | yes | yes |
| `/Users/kky/biomate-audit-fix` | `audit-fix-immune-llm` | `4b6692e3213f` | divergent | 4 / 10 | no | no |
| `/Users/kky/biomate-corpusfs` | `feat/corpus-fs-20261008` | `5740c2f365ee` | divergent | 0 / 0 | no script | no script |
| `/Users/kky/biomate-ihlm` | `ihlm/integration-20261031` | `d075b67d2b14` | divergent | 5 / 12 | no | no |
| `/Users/kky/biomate-orch` | `feat/orch-retrieval-s2-20261008` | `6f4da7a04a7e` | divergent | 0 / 0 | no script | no script |
| `/Users/kky/biomate-pr-product` | `fix/sysucc-assay-bo-benchling` | `60eade9f79b1` | divergent | 0 / 0 | no | no |
| `/Users/kky/biomate-review` | `cursor/tutorial-live-recording-and-report-editing-4ea7` | `20f159a1cb79` | older ancestor | 1614 / 564 | no | no |
| `/Users/kky/biomate-review/.claude/worktrees/grounded-harness2` | `grounded-harness2` | `d0f46d6652cb` | older ancestor | 0 / 0 | no | no |
| `/Users/kky/biomate/.claude/worktrees/agent-a048dd27c2924735b` | `worktree-agent-a048dd27c2924735b` | `928b80f1558e` | divergent | 0 / 1 | no | no |
| `/Users/kky/biomate/.claude/worktrees/agent-a16ada558a0974020` | `worktree-agent-a16ada558a0974020` | `6b5cbb2264f8` | divergent | 0 / 0 | no | no |
| `/Users/kky/biomate/.claude/worktrees/agent-a547e59a6315c8224` | `worktree-agent-a547e59a6315c8224` | `f7e857dda77c` | divergent | 0 / 0 | no | no |
| `/Users/kky/biomate/.claude/worktrees/agent-a8ab7e3a23d6085f0` | `worktree-agent-a8ab7e3a23d6085f0` | `63a4f2b8f30b` | divergent | 0 / 0 | no | no |
| `/Users/kky/biomate/.claude/worktrees/agent-aa1ad953bef5f8662` | `worktree-agent-aa1ad953bef5f8662` | `ab39e67cb007` | divergent | 0 / 0 | no | no |
| `/Users/kky/biomate/.claude/worktrees/agent-aef0cfd1a945553e9` | `worktree-agent-aef0cfd1a945553e9` | `108efb91d0dd` | divergent | 0 / 0 | no | no |
| `/Users/kky/biomate/.claude/worktrees/grounded-land-20261020` | `grounded-land-20261020` | `7e9ef58044cc` | divergent | 0 / 0 | no | no |
