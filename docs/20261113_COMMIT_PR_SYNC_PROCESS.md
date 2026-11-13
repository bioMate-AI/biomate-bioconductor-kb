# Commit, PR, and sync-to-dev process (2026-11-13)

Operator playbook driven by real failures on **2026-11-13**: multi-worktree races (panelfix / nextphase-ci-fix / review / coldstart), catalog clobber via `_self_heal_input_kinds`, FTS-broken / wrong-worktree DB uploads, Cursor `HTTP_PROXY` → SSM failure, emergency overrides without recovery, and ledger tip ≠ live code after hot-patches.

**Related:** `docs/PRE_SYNC_CHECKLIST.md` (tests before sync), `docs/20261107_DEPLOYMENT_ANCESTRY_GUARD.md`, `docs/20261113_INPUT_KINDS_ENRICHMENT_DIAGNOSIS.md`.

---

## 1. One-writer rule for DEV

There is **one** shared DEV (`https://dev-public.biomate.ai`, instance `i-06696b0d91f4346e0`).

| Rule | Detail |
|------|--------|
| **One designated writer** | Only **one** worktree / agent may run `scripts/sync_to_dev.sh` at a time. |
| **Announce before sync** | In the coordinating chat/thread: worktree path, branch, commit SHA, layers (frontend / backend / workflows / db). |
| **Lease** | Sync acquires `/opt/biomate/.dev-deploy.lock` on the host. Another sync waits or refuses. |
| **Local lock** | `/tmp/biomate_sync_to_dev.lock` on the laptop — same machine, many worktrees still collide. |
| **No parallel “just DB” / “just backend”** | Parallel writers caused ancestry fights and catalog clobber on 2026-11-13. |

**Who may sync:** the person (or single agent) that owns the **merge commit you intend to leave on DEV**, from the **one designated worktree** that contains that commit *and* (if uploading DB) the **designated catalog** `galaxy_ai_tools.db`.

---

## 2. Pre-sync checklist (ops gates)

Run `docs/PRE_SYNC_CHECKLIST.md` tests first. Then:

### 2.1 Ancestry

```bash
# What public frontend reports
curl -fsS https://dev-public.biomate.ai/build-info.json

# Local HEAD must contain BOTH build-info commit AND last ledger commit
# (sync script runs scripts/dev_deploy_ancestry.py under the remote lease)
```

If refused: **merge the named commit(s) into what you deploy**, then retry.  
Message means: “merge `abc123…` (or its branch) into *this* worktree’s HEAD — not into an unrelated long-lived branch.”

### 2.2 Locks

```bash
# Local
test -f /tmp/biomate_sync_to_dev.lock && ps -p "$(cat /tmp/biomate_sync_to_dev.lock)" || echo "local lock free"

# Do not clear a live remote lease. Stale (>30 min) is broken automatically by the next sync.
```

### 2.3 Proxy (AWS / SSM)

Cursor sandbox often sets `HTTP_PROXY=http://127.0.0.1:…`. That **breaks SSM**.

- Sync script **auto-unsets** loopback proxies (warns).  
- Or manually: `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy`  
- Strict: `BIOMATE_STRICT_PROXY=1` → refuse instead of unset.

### 2.4 DB md5 decision matrix

| Situation | Action |
|-----------|--------|
| Code only; local DB wrong / stub / other worktree | `BIOMATE_SYNC_DB=0 bash scripts/sync_to_dev.sh` |
| Intentional catalog upload from **designated** DB worktree | Default sync; local FTS OK, workflow count ≥ 3500, not shrinking DEV |
| Local FTS integrity fails on a **full** DB that differs from DEV | **Refuse** — rebuild FTS or `BIOMATE_SYNC_DB=0`; never soft-skip and pretend |
| Local workflow count &lt; DEV (full DB) | **Refuse** — wrong lineage (e.g. biomate vs review). Override only with `BIOMATE_SYNC_DB_ALLOW_SHRINK=1` + incident reason |
| Stub / tiny local DB | Skip upload; continue code layers |
| Need DEV catalog unchanged while shipping heal/backend fix | `BIOMATE_SYNC_DB=0` (do **not** hot-patch) |

**Never** sync catalog from a random worktree “because it has a db file.” On 2026-11-13, review vs biomate lineages differed; wrong tree + heal rewrote `input_kinds`.

---

## 3. PR flow → sync from ONE worktree

```
feature branch ──► PR ──► review / CI ──► merge (or sync/onto-dev branch)
                                              │
                                              ▼
                         ONE designated worktree at that merge tip
                                              │
                                              ▼
                                    bash scripts/sync_to_dev.sh
```

1. **Branch** — one concern; conventional commits (below).  
2. **PR** — `gh pr create` from a machine with a valid `gh` auth (keyring token may be stale: `gh auth login` / `GH_TOKEN`).  
3. **Sync** — only from the worktree whose `HEAD` **is** (or contains) what you want on DEV.  
   - Examples that confused operators: `sync/pr398-onto-dev`, `deploy/models-abc-*`, coldstart tips.  
   - Ancestry “merge X into what you deploy” = merge into **this sync worktree’s HEAD**, not “into main somewhere else.”  
4. **Do not** sync from panelfix while nextphase holds the lease (or vice versa).

---

## 4. Layer selection: DB-only vs backend-only vs full

| Intent | How |
|--------|-----|
| Full (default) | `bash scripts/sync_to_dev.sh` — diffs since `.last_dev_sync_commit` |
| Frontend only | `BIOMATE_ONLY_FRONTEND=1` (does **not** advance full sync marker) |
| Force layers | `BIOMATE_SYNC_FORCE=frontend,backend,workflows` |
| Code without catalog | `BIOMATE_SYNC_DB=0` |
| Force replace live Galaxy `universe.sqlite` | `BIOMATE_REPLACE_GALAXY_DB=1` (rare; backs up first) |

### Hot-patch policy (forbidden unless ledger-corrected)

**Do not** `docker cp` / S3-drop / SSM-edit production paths on DEV to “unblock” sandbox SSM failures.

If you ever must emergency-patch:

1. Record incident + files touched.  
2. **Immediately** run a normal `scripts/sync_to_dev.sh` from a clean ancestry-ok worktree so `/opt/biomate/.deploy-ledger.jsonl` and `.last_dev_sync_commit` match reality.  
3. Until then, treat ledger tip as **untrusted**.

This script will **not** grow more hot-patch tooling.

---

## 5. Emergency overrides — use rarely, recover always

| Override | When | Recovery |
|----------|------|----------|
| `BIOMATE_EMERGENCY_DEPLOY_REASON="…"` (≥12 chars) | Knowingly deploy a tip that does **not** contain live/ledger commits (rollback) | After DEV is stable, merge/reconcile git so the **next** sync does not need override; document reason in `docs/` |
| Pinning `.last_dev_sync_commit` to HEAD | Only to unstick a marker after a documented partial ship | Next full sync must still ship every needed layer; prefer fixing marker by syncing missing layers with `BIOMATE_SYNC_FORCE=…` |
| `BIOMATE_SYNC_DB_ALLOW_SHRINK=1` | Intentionally replace DEV catalog with fewer workflows | Backup on host first (sync does); verify md5 + counts in DEV receipt |

Overrides without a written recovery step are how stacked “emergency” commits and lying ledgers accumulate.

---

## 6. Post-sync verification

After a healthy sync the script prints a **DEV receipt** (commit, layers, db md5, workflow count, `input_kinds` non-null).

Also verify:

```bash
curl -fsS https://dev-public.biomate.ai/build-info.json
# commit should match the tip you synced (frontend layer); backend-only leaves this stale — trust ledger + receipt

# Smoke: app up
curl -fsS -o /dev/null -w '%{http_code}\n' https://dev-public.biomate.ai/

# Catalog (via sync receipt or SSM): md5, workflow count, input_kinds non-null
```

Ledger: last line of `/opt/biomate/.deploy-ledger.jsonl` must be this sync’s commit when `result=healthy`.

---

## 7. Commit / PR hygiene

- **Conventional commits:** `fix:`, `feat:`, `chore:`, `docs:`, `test:` — subject focuses on **why**.  
- **One concern per commit** — do not stack “emergency sync”, docs-only, and unrelated code in one commit.  
- **Docs-only** vs **code** — say so in the subject (`docs:`); operators need to know what reached DEV.  
- **Never commit secrets** — no `.env`, API keys, `E2E_FIXTURE_PASSWORD`, fixture passwords.  
- **Never amend pushed commits** on shared branches; no force-push to `main`/`master`.  
- **Dirty tree:** sync refuses uncommitted source under frontend/backend paths — commit or stash first (no auto-commit).  
- **`gh` auth:** if `gh` keyring token is invalid, re-auth before PR/CI commands; do not fall back to manual GitHub HTML as a deploy path.

---

## 8. Operator cheat sheet (going forward)

1. Pick **one** writer + **one** worktree at the deploy tip.  
2. Run pre-sync tests (`docs/PRE_SYNC_CHECKLIST.md`).  
3. Unset loopback proxies (or let the script clear them).  
4. Decide DB: designated catalog upload **or** `BIOMATE_SYNC_DB=0`.  
5. `bash scripts/sync_to_dev.sh` — wait for lease; no parallel syncs.  
6. Read the **DEV receipt**; confirm build-info / md5 / smoke.  
7. No hot-patches; no emergency override without a recovery note.

---

## 9. Still manual / unfixed

- Choosing the **designated catalog worktree** (review vs biomate vs panelfix) remains a human decision — gates refuse shrink/FTS but cannot know “which enrichment is intended.”  
- Cross-laptop coordination is social (remote lease helps; chat announce still required).  
- Frontend-only `build-info.json` can lag backend-only deploys — ledger + receipt are ground truth until a full frontend rebuild.  
- Valid `gh` authentication is operator-local.  
- Healing / classifier backfills for `input_kinds` are separate from sync; see `docs/20261113_INPUT_KINDS_ENRICHMENT_DIAGNOSIS.md`.
