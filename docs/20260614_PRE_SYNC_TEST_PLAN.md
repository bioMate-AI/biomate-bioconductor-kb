# Pre-sync test plan — `integration/next-phase` (2026-06-14)

## Why

`integration/next-phase` has absorbed ~30 merges in the last several
days from at least six work streams (chat / project framework /
auth / embeddings / Bioc retrieval / composer + NER / schema-grounded
extraction / CI-CD env). Per the new sync rule
(`CLAUDE.md` § "Sync Rule"), this is the only branch that goes to
dev. **Before that sync, every load-bearing user scenario should be
exercised, on the workstation OR against a dry-run container, in a
single pass.**

The plan below is organized as **use cases first** (real user flows
that exercise many features in combination) rather than feature
checklists. Each use case has a specific assertion + a P-rating.
P0 must be green before sync.

## P-ratings

| Rating | Meaning |
|---|---|
| P0 | Hard gate. Sync if and only if every P0 use case passes. |
| P1 | Should pass. A single P1 failure is a release-note item; multiple P1 failures argue for delaying sync. |
| P2 | Nice to verify. Useful for confidence but not a gate. |

---

## Part 1 — Pre-sync workstation checks (deterministic, fast)

Run these before scenarios. They take < 5 minutes total and protect
against catastrophic regressions that would brick dev on first request.

### W1 — Type check (P0)

```bash
cd frontend && npx tsc --noEmit -p .
```

Expected: clean, OR the only errors are the long-standing
`server/routes.ts(6686 + 13558)` parse errors from a parallel session
(see commit log for `regulatory-training-routes`). Anything new is
a P0 fail.

### W2 — Unit + integration tests (P0)

```bash
cd frontend && npx vitest run
```

Expected: > 780 passing, 0 failing. The two long-standing
`DATABASE_URL` env failures
(`server/galaxy-assistant-history-block.test.ts`,
`server/galaxy-assistant-history-edge-cases.test.ts`) are skipped
not failed.

### W3 — Embeddings staleness round-trip (P0)

The 2026-06-13 patch added auto-rebuild on DB drift. Confirm both
sides still rebuild on a forced staleness event:

```bash
cd /home/yzhang/biomate
PYTHONPATH="$PWD/backend/lib:$PWD/backend" python3 -c "
from pathlib import Path
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch
s = UnifiedWorkflowSearch(db_path=Path('backend/database/galaxy_ai_tools.db'))
print('workflow init:', s._ensure_workflow_embeddings())
"
```

Expected: returns `True` in < 1 s on a warm `.npz` (no rebuild).

### W4 — Local boot smoke (P0)

`scripts/smoke_boot.sh` runs the backend boot path inside a clean
container image and asserts `/api/version` returns 200.

```bash
bash scripts/smoke_boot.sh
```

Expected: HTTP 200, no `ImportError`, no Galaxy migration error.

---

## Part 2 — Use-case scenarios

Each scenario exercises **multiple features in combination** —
they're how a real user would meet the platform, not how a single
patch behaves in isolation.

For each, the column headed *Touches* lists which recent merges the
scenario validates. Use it to figure out who to ping if it fails.

### UC-1 — New user, first chat, no project (P0)

| Step | Expected | Touches |
|---|---|---|
| Register a new email + password | 201; response includes `verificationToken` (dev / no-SMTP path) | auth fix |
| Click the dev-mode `/verify-email?token=…` link | Page loads, email marked verified | auth fix |
| Open chat, send "hello" | Chat returns a reply; chat-stream HTTP 200 | core chat |
| DB: `chat_sessions.project_id` for that session | `NULL` (project-less) | project framework |
| DB: `ltm_users` table | New row inserted matching the new auth user id | LTM bridge |
| Logs: `gate=skip reason=no_datasets_attached` | Present | injection gate |

### UC-2 — Returning user with active workspace runs DEG (P0)

| Step | Expected | Touches |
|---|---|---|
| Login fixture (`lifeifei163361@163.com`) | Token returned | auth |
| `POST /api/projects {name:"DEG-2026-06"}` | 201 + project id | project CRUD |
| `localStorage.setItem('biomate-active-project-id', <id>)` | Set | client wiring |
| Attach `gse22055_expression.csv` (Galaxy reference) | `chat_sessions.datasets` gains 1 entry | dataset cap |
| Chat input shows "1 / 32" muted indicator | Indicator renders | UI |
| Send "Run DEG on this microarray with limma" | Workflow card emitted with `nf-core/differentialabundance` (limma-aware) | routing fixes |
| DB: `project_episodes` for project id | 1 row appears with `user_query` containing "Run DEG" | LTM bridge |
| Logs: `[MemoryIntegration] Recorded episode N` | Present | LTM episode write |
| Logs: `gate=inject reason=…` for that turn | Present (not skip) | injection gate |
| DB: `chat_sessions.project_id` for that session | The project id (not NULL) | project framework |

### UC-3 — Cross-project isolation, second user (P0)

| Step | Expected | Touches |
|---|---|---|
| Register a second fixture | OK | auth |
| `GET /api/projects` as second fixture | The first fixture's project is **not in the list** | isolation |
| `GET /api/projects/<first-fixture-id>` as second | 404 (not 403) | isolation |
| `DELETE /api/projects/<first-fixture-id>` as second | 404 | isolation |
| Chat as second with NO active project | `chat_sessions.project_id` = NULL; project-less | policy |
| Chat as second, then look at `project_episodes` for the first fixture's project | Zero rows added | episode isolation |

### UC-4 — Datasets cap + indicator (P1)

| Step | Expected | Touches |
|---|---|---|
| Attach datasets 1–24 | Indicator shows muted tone, "N / 32" | UI |
| Attach datasets 25–31 | Tone switches to amber | UI |
| Attach dataset 32 | Tone red, tinted box, tooltip "At the 32-attachment cap…" | UI |
| Attach dataset 33 | First-attached drops; `chat_sessions.datasets.length` stays 32 | server cap |
| Look at `chat_sessions.datasets[0]` after overflow | Refers to dataset 2 (oldest dropped) | drop-oldest |

### UC-5 — Compression preserves dataset UUIDs (P1)

| Step | Expected | Touches |
|---|---|---|
| Build a synthetic 30-message chat that contains `[Galaxy dataset: …]` UUID blocks | Compression triggers at 70-80% token | compression-dialog |
| Click "Compress Now" → POST `/api/compress-session` | Summary row created; all `[Galaxy dataset: …]` UUIDs survive verbatim in the summary header | compression-block fix |
| Continue chat after compression | Bot can still reference the dataset by id | wjunlin@HKU regression |

### UC-6 — Cold-refresh dataset recovery within a project (P1)

| Step | Expected | Touches |
|---|---|---|
| In project A, attach a dataset to session S1 and send a chat | OK | core |
| Open a **new** session S2 in project A, send "do the same again" | Logs show `[chat-stream] recovered N project-scoped dataset(s)`; prompt block labels the recovered datasets distinctly | cold-refresh |
| In project B (different), open session S3 | NO recovery log (cross-project bleed prevented) | isolation |
| Project-less session S4 | NO recovery log | policy |

### UC-7 — Pure-knowledge question SKIPS dataset injection (P1)

| Step | Expected | Touches |
|---|---|---|
| Session with datasets attached but no recent run, no last-assistant data reference | Send "What is BH FDR correction?" | injection gate |
| Logs | `[sessionDatasetsBlock] gate=skip reason=pure_abstract_intent_no_signals` | gate |
| Bot reply | Doesn't tangentially reference the attached dataset | LLM behavior |
| Send "How long will this take?" while a run is active | `gate=inject reason=run_state_relevant` | gate |

### UC-8 — Trial-expired user lands on free tier, not 404 (P0)

| Step | Expected | Touches |
|---|---|---|
| Set a test user's `trial_ends_at` to 8 days ago + `subscription_tier = 'trial'` | DB updated | setup |
| Login that user | Login succeeds; response shows `subscriptionTier: 'free'` | auth fix |
| DB after login | Row demoted: `tier='free'`, `status='inactive'` | demotion |
| Open chat | Chat works (free-tier quota) | no 404 |

### UC-9 — Sync-rule self-check (P0)

| Step | Expected | Touches |
|---|---|---|
| `git branch --show-current` in the worktree about to sync | `integration/next-phase` | CLAUDE.md sync rule |
| Anything else | STOP. Do not sync. | rule |

### UC-10 — Bioc retrieval — routing improvements (P1)

| Step | Expected | Touches |
|---|---|---|
| "I have proteomics MS spectra → DE analysis" | Routes to a Bioc proteomics chain (not generic nf-core) | Bioc citations + workflow_id pinning |
| "phyloseq differential abundance microbiome" | Routes to a phyloprofile-class chain, NOT collapsed into one ambiguous result | catalog differentiation |
| "GPCR cryo-EM density map" | Hard-fail or specific cryo-EM workflow (not generic SPA) | retrieval fix |
| Composer telemetry log appears | `[ComposedChain]` events emit in shadow mode | composer telemetry |

### UC-11 — Workflow chain ↔ chat coupling (P1)

| Step | Expected | Touches |
|---|---|---|
| Run a 3-step pipeline (FastQC → STAR → DESeq2) | Each step completes; `chat_progress` SSE narrator emits friendly progress messages back to chat | chain plumbing |
| After step 3 completes, `AfterRunReport` Findings tab loads | Findings prose rendered; outputs listed in Outputs tab | `useFetchFindings` |
| Click "Continue analysis" on the FindingsCard | A suggested next-step text is injected into the chat input | `onContinueAnalysis` |

### UC-12 — Schema-grounded extraction smoke (P2)

| Step | Expected | Touches |
|---|---|---|
| Submit a workflow request where a numeric param is implied ("use 8 threads, MAF cutoff 0.05") | Param values extracted into the param panel | schema-grounded PR |
| Look at backend log for `schemaGroundedExtractor` events | Wrapper smoke green | worktree-schema-grounded |

### UC-13 — Memory/interactions try/catch (P2)

| Step | Expected | Touches |
|---|---|---|
| Force a memory write to fail (e.g. simulate LTM DB outage) | Chat-stream still returns 200; error is logged; chat doesn't 500 | memory/interactions try/catch |

---

## Part 3 — Sync

Once Parts 1 and 2 are green:

```bash
cd /home/yzhang/biomate
# Confirm: we ARE on integration/next-phase (per CLAUDE.md rule)
git branch --show-current   # must print: integration/next-phase
git status                  # clean
git pull --ff-only origin integration/next-phase

bash scripts/sync_to_dev.sh 2>&1 | tee /tmp/sync_$(date +%s).log
```

If the script reports an uncommitted source file, abort and resolve
before syncing. **Do NOT auto-stash and sync** — the canonical branch
must be in a fully-committed state.

---

## Part 4 — Post-sync verification on dev

Run within 10 minutes of sync. These are the same scenarios as Part
2 but executed against `https://dev-public.biomate.ai`.

### S1 — Health (P0)

```bash
curl -sS -o /dev/null -w "HTTP %{http_code}  %{time_total}s\n" https://dev-public.biomate.ai/
curl -sS -o /dev/null -w "HTTP %{http_code}  %{time_total}s\n" https://dev-public.biomate.ai/galaxy/api/version
```

Both must return 200 in < 5 s. Anything else → investigate
immediately.

### S2 — Live audit script (P0)

```bash
bash scripts/audit_project_framework.sh
```

This driver runs S1–S5 of the project framework audit
(`docs/20260613_PROJECT_FRAMEWORK_AUDIT_RESULTS.md`). Expected output:
`PASS=24 FAIL=0`.

### S3 — Container log scan (P0)

```bash
ssh -i "$KEY_FILE" "${EC2_USER}@${EC2_HOST}" \
  'sudo docker logs biomate-dev-frontend --since 10m 2>&1 | grep -iE "TypeError|crashed|relation.*does not exist|ENOENT|fatal" | head -20'
```

Expected: empty. If you see new types of errors, file an issue and
revert the sync.

### S4 — Embedding alignment on dev (P0)

Confirm the dev container's `.npz` matches the dev DB's content
signature. If `signature stamped: False`, the `.npz` predates the
2026-06-13 patch — schedule a rebuild via §7 of
`docs/20260613_DENSE_EMBEDDINGS_PATHS.md`.

### S5 — Pick 2 random P1 scenarios from Part 2 and run them by hand (P1)

The fastest "did anything break the UX" check: open the dev UI, do
UC-2 (project + chat + episode write) and UC-7 (skip injection on
abstract question). If both feel normal, the platform is up.

---

## Part 5 — Rollback plan

If S1–S4 fail or if a real user reports a regression within an hour:

1. Identify the sync's commit: `tail -2 /tmp/sync_<timestamp>.log` →
   "`=== Sync OK at <hash> ===`".
2. Find the prior known-good commit on the same branch:
   `git log --before='1 hour ago' origin/integration/next-phase -1`.
3. Re-sync to that commit:
   ```bash
   git checkout <known-good-hash>
   bash scripts/sync_to_dev.sh
   ```
4. Open an incident issue with: which UC failed, dev container log
   excerpts, and the sync log.

After rollback, the offending commit goes back to its topic branch
for investigation. **Do not push a hotfix directly to next-phase
without merging it through the same workflow** (per the sync rule).

---

## Appendix — Mapping recent merges to scenarios

| Merge area | Covered by |
|---|---|
| chat + project framework | UC-1, UC-2, UC-3, UC-6 |
| dataset cap + indicator | UC-4 |
| compression block preservation | UC-5 |
| injection gate | UC-7 |
| auth fixes (verification, trial-expiry) | UC-1, UC-8 |
| sync rule | UC-9, Part 3 |
| Bioc retrieval / catalog | UC-10 |
| chain ↔ chat coupling | UC-11 |
| schema-grounded | UC-12 |
| memory try/catch | UC-13 |
| embeddings staleness | W3, S4 |

---

## Definition of "ready to sync"

Every one of these must be true:

- [ ] W1–W4 green
- [ ] UC-1, UC-2, UC-3, UC-8, UC-9 green (the P0 set)
- [ ] No new P1 regressions vs the last sync
- [ ] Working tree on `integration/next-phase` is clean and pushed
- [ ] `git branch --show-current` prints `integration/next-phase`
- [ ] You can name a single owner for any P0 failure (so the rollback
      path has a human in the loop)
