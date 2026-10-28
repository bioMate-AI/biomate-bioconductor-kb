# Branch reconciliation + PR #238/#218 status refresh

**Date:** 2026-09-28
**Mode:** read-only assessment + plan. NOTHING here has been executed. No commits, no cherry-picks, no sync.
**Scope:** (1) reconcile this session's work off the churned `docs/peptide-pharma-loop-work-20260926` branch; (2) refresh the PR #238/#218 finding.

---

## TL;DR recommendation

1. **Dev is already correct** — `sync_to_dev.sh` deploys the local working tree with no PR gate. This session's fixes are live on dev regardless of branch state. Nothing below is deploy-blocking.
2. **This session's code is cleanly separable** from the concurrent peptide/onprem session. It is a small, disjoint set of files (proteomics, metabolomics/domain-image Dockerfile, sync script, register script, `.fcs` fixture). None of it overlaps the peptide/onprem commits.
3. **Recommended low-risk action:** cherry-pick this session's ~14 separable commits onto `feat/drugdev-reinvent4-realgen` (the PR #238 head, the canonical drug-dev branch) as durable history — **OR** simply leave as-is since dev already has them via sync and origin has the branch. Do NOT attempt to merge the whole 74-commit peptide branch.
4. **The private-DB/MCP, run-finalization, and UI-hide fixes are ALREADY on `feat/drugdev-reinvent4-realgen`** (below the merge-base) — they need no action.
5. **PRs #238/#218 unchanged** from the 2026-09-24 finding: 8,501 / 8,341-file integration-branch divergences, both OPEN, `mergeable=UNKNOWN`. This is a human release decision, dev unaffected.

---

## Branch topology (verified 2026-09-28)

```
merge-base(peptide, feat/drugdev)   = 79d95e7df
merge-base(peptide, next-phase)     = 2b11dbc4e
merge-base(feat/drugdev, next-phase)= 2b11dbc4e

feat/drugdev-reinvent4-realgen ..  peptide  = 74 commits ahead   (peptide = feat/drugdev + 74)
peptide .. feat/drugdev-reinvent4-realgen  = 0 commits           (feat/drugdev fully contained in peptide)
next-phase .. feat/drugdev                 = 689 commits ahead
```

Meaning: `feat/drugdev-reinvent4-realgen` is entirely an ancestor of the peptide branch. The peptide branch = `feat/drugdev` **plus 74 commits** that stack this session's fixes interleaved with the concurrent peptide/onprem session's work.

### ACTIVE CHURN WARNING (observed live this session)

The **local** branch tip has already moved past origin during this assessment:

| ref | sha |
|---|---|
| local `docs/peptide-pharma-loop-work-20260926` / HEAD | `e115933772` |
| origin `docs/peptide-pharma-loop-work-20260926` | `cde8e52b09` |

The local branch is **32 commits ahead of origin**, and 3 of those (`e11593377`, `1f702185c`, `192ab8646` — all peptide/onprem) appeared *during* this session. This is exactly the churn pattern in memory (`project_teamwork_worktree`, `feedback_commit_immediately`): a concurrent session is actively rewriting/advancing this branch. **Treat the branch as a moving target. Do any reconciliation from fixed SHAs, not from the branch name.**

---

## DELIVERABLE 1 — commit reconciliation

### 1a. This session's work is in TWO layers

**Layer A — already on `feat/drugdev-reinvent4-realgen` (below merge-base `79d95e7df`) — NO ACTION NEEDED.**
These are the private-DB/MCP, run-finalization, and UI-hide fixes the task lists. They are already captured on the canonical branch:

| sha | subject |
|---|---|
| `364e337c9` | fix(runs): finalize stuck runs via AWS Batch describe-jobs (282-stuck-run bug) |
| `577c29950` | docs(private-db/mcp): RESOLVED — full CRUD verified end-to-end on dev |
| `6728256a4` | fix(private-db): Vault->preferences fallback so create/list persist |
| `029b694a3` | docs(private-db/mcp): root cause = userProxy hits Galaxy as BootstrapAdminUser |
| `eacb3f36c` | fix(private-db/mcp): move routes off /api/users/* to /api/biomate/* (route collision) |
| `aa07892db` | fix(ui): hide CRO Library route (/drug-discovery-cro) for now |
| `35713d24c` | fix(ui): hide IND Report from sidebar |
| `4540064e7` | fix(mcp/private-db): return 401 (not 500) on unauthenticated proxy routes |
| `58d25fdb5` | test(private-db): live-Postgres integration test |
| `b79141bb9` | feat(mcp): wire external-MCP end-to-end (API + routes + LLM tool exposure) |
| `a7eab26da` | fix(ui): redirect dead /dashboard links to home |
| `3d5872ef7` | fix(ui): hide Billing nav+route |
| `325c6694a` | feat(connectors): 'Your connections' tab — private DB + MCP server forms |
| `61d39bd30` | feat(private-db): connect + read-only query a user's private Postgres (MVP) |
| `e4b058256` | feat(mcp): external MCP client MVP (SSRF-guarded) |

Since `feat/drugdev-reinvent4-realgen` = PR #238 head, this work is already in a PR. **Leave it.**

**Layer B — on peptide branch, ABOVE merge-base, NOT yet on `feat/drugdev` — candidate to cherry-pick.**
These are this session's remaining separable fixes (proteomics/#217, metabolomics/domain-image, sync, register, `.fcs`). Full list in 1b.

### 1b. This session's separable commits above the merge-base (cherry-pick candidates)

All touch a **disjoint file set** from the peptide/onprem commits (proteomics workflows, `Dockerfile.tmpl`, `deps/metabolomics.txt`, metaboanalystr subworkflow, `sync_to_dev.sh`, register script, flow-cytometry sample data). Cleanly separable.

**Proteomics / PR #217 chain** (a merge commit `12cb94fbc` brought PR #217 in; the underlying commits, in order):
| sha | subject |
|---|---|
| `7e200a784` | docs+bench(proteomics): DB-search optimization survey + Phase-0 benchmark scaffold |
| `db9245c6b` | docs(proteomics): DIA-NN cohort-scale diagnosis + BioMate status |
| `57b7a8616` | feat(proteomics): license-clean DDA search capability (Comet+OpenMS) — Option C |
| `f81fc6602` | feat(proteomics): vendor EncyclopeDIA (nf-encyclopedia) — license-clean DIA — Option B |
| `a6594a4fa` | chore(proteomics): register DDA + EncyclopeDIA workflows for the DB |
| `12cb94fbc` | merge: proteomics DB-search + license-clean DDA/DIA (PR #217) into current branch |

**Register-script + sync-pipeline fixes** (the task's "register-script fix + sync nf-core-modules fix"):
| sha | subject |
|---|---|
| `77e0206ec` | fix(register): find nf-core-modules workflows (proteomics DDA/DIA would never register) |
| `409164aa9` | fix(sync): deploy backend/nf-core-modules/ (executor resolves it; was never synced) — touches only `scripts/sync_to_dev.sh` |

**Metabolomics / MetaboAnalystR + domain-image Dockerfile chain** (all touch only `Dockerfile.tmpl`, `deps/metabolomics.txt`, and the metaboanalystr subworkflow):
| sha | subject |
|---|---|
| `02906f82f` | feat(metabolomics): add MetaboAnalystR as a first-class bioconductor subworkflow |
| `1df4ab7ea` | fix(domain-image): install Bioc deps as binaries (xcms R_NO_REMAP source fail) |
| `c8c9f9e56` | fix(domain-image): patch xcms for R_NO_REMAP |
| `7e770d26b` | fix(domain-image): xcms R_NO_REMAP via forced-include |
| `0ba8d60d1` | fix(domain-image): global R_NO_REMAP undef + loud MetaboAnalystR install |
| `14edf48e1` | perf(domain-image): use all 16 cores (Ncpus=16 + MAKEFLAGS=-j16) |
| `61de4eaec` | fix(domain-image): bump xfun>=0.52 for metabolomics (CAMERA needs it) |
| `a31807d49` | fix(domain-image): move xfun>=0.52 bump to Step 5 (CAMERA installs there) |
| `779ab301d` | diag(domain-image): un-mask OptiLCMS/MetaboAnalystR install (quiet=FALSE) |
| `086fe190c` | fix(domain-image): patch OptiLCMS mzClust.cpp (missing <array>) + add fgsea |
| `2cece3936` | fix(domain-image): OptiLCMS patch via R file-IO (system+sed quoting broke R parse) |
| `3599af2b9` | fix(domain-image): MetaboAnalystR install as a FILE (inline Rscript -e corrupts in transit) |

**Workflow compile-bug + fixture fixes:**
| sha | subject |
|---|---|
| `4a499bb05` | fix(workflows): metabolomics + single-cell compile/entry-point bugs |
| `ca8e3b3d7` | feat(flow-cytometry): real default .fcs sample so the workflow is one-click runnable |

> Note: the domain-image chain is a *sequence of iterative fixes to the same file*
> (`Dockerfile.tmpl`). If cherry-picking, take the whole chain in order (or squash it)
> — cherry-picking a subset will conflict, and only the final state matters.

### 1c. The concurrent session's commits (peptide/onprem) — DO NOT touch

The remaining ~30 commits in the 74 are the concurrent session's peptide-model + on-prem-LLM work (subjects prefixed `feat(peptide…)`, `feat(onprem…)`, `docs(peptide…)`, `docs(onprem…)`, `IP:`, plus the routing-data/corpus JSON artifacts in the untracked `docs/20260912_onprem_llm/…`). Examples: `50a518d11`, `0b5823485`, `48e10bcf9`, `85424f45c`, `8a414e0ac`, `cded33ee8`, `e11593377`, etc. These are that session's to land. They do not overlap this session's files.

### 1d. Recommended reconciliation (low-risk, pick ONE)

**Option 1 — LEAVE AS-IS (lowest risk, default).**
- Dev already has all of it (synced from the working tree).
- The Layer-A private-DB/MCP/run-final/UI work is already on `feat/drugdev` = PR #238.
- The Layer-B fixes are on origin `docs/peptide-pharma-loop-work-20260926` (pushed) — recoverable.
- Cost: Layer-B fixes are only in a doc-named branch, not in the drug-dev PR history. Acceptable if the peptide branch is expected to land wholesale later.

**Option 2 — CHERRY-PICK Layer B onto `feat/drugdev-reinvent4-realgen` (recommended for durable history).**
Puts this session's proteomics/metabolomics/sync/register/`.fcs` fixes into the canonical PR #238 branch, decoupled from the churning peptide branch. Because the file sets are disjoint, this is low-conflict. Suggested groups (cherry-pick in commit order within each group):
- Proteomics: `7e200a784 db9245c6b 57b7a8616 f81fc6602 a6594a4fa` (skip the merge commit `12cb94fbc`; cherry-pick the underlying commits linearly).
- Register + sync: `77e0206ec 409164aa9`.
- Metabolomics/domain-image chain (in order): `02906f82f 1df4ab7ea c8c9f9e56 7e770d26b 0ba8d60d1 14edf48e1 61de4eaec a31807d49 779ab301d 086fe190c 2cece3936 3599af2b9` (or squash into one).
- Workflow/fixture: `4a499bb05 ca8e3b3d7`.
- Do this from a fresh worktree off `feat/drugdev-reinvent4-realgen` to avoid the active churn on the peptide branch.

**Do NOT** merge or rebase the whole peptide branch into `feat/drugdev` — it would drag in the concurrent session's in-flight peptide/onprem work (some of which its own docs mark NO-GO / reverted, e.g. `192ab8646` "27B mid-train NO-GO", `5a4d0398b` "drop broken teacher judge"). Same unreviewable-blob hazard as PR #238.

**Risk callout (from memory):** this branch is churned by a concurrent session (32 commits ahead of origin, 3 new during this session). Any cherry-pick must reference the fixed SHAs above and run in an **isolated worktree** — do not check out or reset the shared peptide branch.

---

## DELIVERABLE 2 — PR #238 / #218 status refresh (verified 2026-09-28)

| PR | head → base | state | changed files | additions / deletions | commits | mergeable | mergeStateStatus |
|---|---|---|---|---|---|---|---|
| **#238** | `feat/drugdev-reinvent4-realgen` → `integration/next-phase` | OPEN | **8,501** | +1,704,833 / −191,551 | 100 | UNKNOWN | UNKNOWN |
| **#218** | `integration/dev-test` → `integration/next-phase` | OPEN | **8,341** | +1,684,969 / −189,948 | 100 | UNKNOWN | UNKNOWN |

**No material change from the 2026-09-24 assessment** (`docs/20260924_PR_238_218_CONFLICT_ASSESSMENT.md`). File counts moved by a handful (8,501 vs the prior 8,501 for #238; #218 unchanged at 8,341). Both remain massive integration-branch divergences, not mechanical conflicts. `mergeable=UNKNOWN` persists (GitHub cannot compute a mergeability verdict at this diff size).

**Confirmed unchanged findings:**
- These are branch-divergence, not `<<<<<<<` conflicts. A test-merge yields a 100+-file staged blob with no conflict markers.
- **Dev is unaffected.** `sync_to_dev.sh` deploys the local working tree directly (no PR-merge gate). Latest dev tag: `dev-v0.onprem-fixes-20260928`. PR state on GitHub has zero effect on dev.
- This is a **human release / branch-management decision** — decide the canonical branch and land as a fresh squashed PR or a controlled fast-forward of `next-phase`; do NOT auto-merge an 8,500-file diff (unreviewable; risks resurrecting reverted work).

---

## Recommended action list for a human

1. **(No-op / verify)** Confirm dev is healthy on `dev-v0.onprem-fixes-20260928`. Nothing below blocks deploy.
2. **(Optional, recommended)** In an isolated worktree off `feat/drugdev-reinvent4-realgen`, cherry-pick this session's Layer-B SHAs (Option 2 groups above) to give the proteomics/metabolomics/sync/register/`.fcs` fixes durable history inside PR #238's branch. Use fixed SHAs; do not touch the churning peptide branch.
3. **(No action)** Layer-A private-DB/MCP/run-finalization/UI-hide fixes are already on `feat/drugdev` — leave them.
4. **(No action from an agent)** Let the concurrent peptide/onprem session land its own commits on `docs/peptide-pharma-loop-work-20260926`.
5. **(Human release decision)** Resolve PRs #238/#218 by picking a canonical integration branch and landing via a fresh squashed PR / controlled reset — NOT an 8,500-file auto-merge. Dev is unaffected either way.

_All items above are recommendations. None were executed in this session._
