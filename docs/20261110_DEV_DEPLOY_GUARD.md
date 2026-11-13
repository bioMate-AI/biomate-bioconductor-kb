# Dev deploy guard — nobody can silently remove deployed work (2026-11-10)

## What went wrong

Fixes the founder had verified kept "disappearing" from dev. Cause: dev was deployed from
different lines that did not contain each other —

- `scripts/sync_to_dev.sh` from the `cursor/tutorial-…` line (and from integration branches);
- `.github/workflows/deploy-dev.yml` (GitHub Action) with its default tag
  `integration-next-phase-latest`, which on 2026-11-10 was an image **built 2026-11-06**
  (`sha-a90eb23ae58e`). The Action stops and recreates both containers — it had **no lock and
  no ancestry check**. Deploying that image over today's dev would have removed **253 commits**.
- old checkouts of `sync_to_dev.sh` from before the ancestry check existed (added 2026-11-07).

## The rules (enforced on every official path)

1. **Commit ancestry** — The commit being deployed must **contain** the commit live on dev
   (`https://dev-public.biomate.ai/build-info.json`) and the last ledger deploy when it differs.

2. **Content preservation** (added 2026-11-13) — Containing the live commit is not enough.
   `git merge -s ours <live>` records ancestry while keeping the *other* branch's tree, which
   used to pass the gate and silently clobber dev (skills UI / short descriptions). For every
   protected product path (`frontend/`, `backend/lib/`, `backend/biomni_workflows/`,
   `backend/config/`, `scripts/`) whose blob would change vs the live tip, HEAD must include a
   **non-merge** commit after that tip that touches the path. Otherwise the deploy is refused
   with `Content clobber` and the path list.

If ancestry fails, the refusal **lists the live commits it would remove**. If content
preservation fails, do a real merge that keeps the live blobs (or commit an explicit intentional
override on those paths) — never a bare `-s ours` sync.

## Mechanisms

| Path | Lock (`/opt/biomate/.dev-deploy.lock`) | Ancestry gate | Ledger entry |
|---|---|---|---|
| `scripts/sync_to_dev.sh` | yes (existing) | yes — `scripts/dev_deploy_ancestry.py` | **new** |
| `deploy-dev.yml` (Action) | **new** | **new** — resolves the image's commit from its `sha-<commit>` ECR tag, runs the same checker with `--head <image commit>` | **new** |
| old script copies / raw docker | — | — | not recorded → **detected**: next sync prints a drift warning |

**Deploy ledger** — `/opt/biomate/.deploy-ledger.jsonl` on the dev host, one JSON line per deploy:
`{"at", "commit", "branch", "by", "via", "override"}`. Each `sync_to_dev.sh` run prints the last 5
entries and warns if the live commit is not the last recorded one (someone bypassed the gate).

**Emergency override** (knowingly replace newer live code, e.g. a rollback): `BIOMATE_EMERGENCY_DEPLOY_REASON="…"`
for the script, `emergency_reason` input for the Action. Requires ≥12 chars; recorded in the ledger.

## For everyone who deploys dev

1. Deploy from an up-to-date checkout (`git pull`) — old copies of `sync_to_dev.sh` have no gate.
2. If refused: `git merge <live commit>` (or merge its branch), re-run tests, deploy again.
3. To see who deployed what: `ssh … tail /opt/biomate/.deploy-ledger.jsonl` (also printed by every sync).

## Verification

- `scripts/tests/test_dev_deploy_ancestry.py` — 10 passed (new: refusal names the removed work; `--head` checks a given commit).
- Simulated the Action's default image against live dev: refused, "would REMOVE 253 commit(s)", exit 2.
- `bash -n scripts/sync_to_dev.sh` OK; `deploy-dev.yml` parses.

Remaining gap: a copy of the script from before 2026-11-07, or a hand-run `docker` command on the
host, is not blocked — only detected at the next sync. Closing it fully needs the container swap
itself to run through a host-side gate.

## Cross-session claim (added 2026-11-13)

Cursor and Claude Code do **not** share chat history. Concurrent agents in different
worktrees only meet on dig. After a successful sync the script writes
`/opt/biomate/.deploy-claim.json` (worktree + session + branch, default TTL 4h).
Another worktree must set `BIOMATE_DEPLOY_TAKEOVER_REASON` (≥12 chars) to deploy
while that claim is active. Same worktree may redeploy freely. Ledger lines now
also record `worktree` and `session`.

Together with **content preservation**, this closes: (1) silent `-s ours` clobber,
(2) blind cross-session takeover without acknowledging the other agent.
