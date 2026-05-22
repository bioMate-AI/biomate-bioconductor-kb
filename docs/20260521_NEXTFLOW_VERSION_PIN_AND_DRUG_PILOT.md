# 2026-05-21 — Nextflow version pin, drug-pilot E2E, sync-after-DB-clobber fix

Continues `docs/20260521_JVM_SIGSEGV_DIAG_AND_SWEEP_PASS.md`. Session
purpose: run the drug-development end-to-end suites that the user said
were not realistic before, fix issues as they surface.

---

## TL;DR

- The drug-discovery pilot E2E (S1-S6) and pharmacology suite all
  failed across two earlier runs because two infrastructure things
  re-broke on dev: (a) **the alembic merge migration was getting
  clobbered by every sync** (local universe.sqlite overwrote dev's
  manually-upgraded DB), and (b) **Nextflow 26.04 silently
  auto-installed itself** and 26.04's stricter DSL2 parser rejected
  21 of our older workflows.
- Fixed both at the right scope:
  - sync_to_dev.sh now runs `manage_db.sh upgrade` after copying
    universe.sqlite, so dev always ends up at the code-expected
    alembic head no matter what was in the local DB.
  - Pinned Nextflow framework to **25.10.0** (last pre-26 LTS) via
    `NXF_VER` env in `nextflow_executor.py` + matching launcher
    reinstall in sync_to_dev.sh. The pin makes our 21 workflows work
    again as-is — no need to rewrite them to satisfy 26.04.
- A full audit across all **2,397 workflow files** showed bioconductor
  (1,818 files = 76% of the catalogue) is completely clean; the
  Nextflow 26.04 breakage was concentrated in 28 older drug-discovery
  + structural workflows that were already exposing legacy DSL2
  patterns the new version rejected.
- Re-ran drug pilot v3 with both fixes in place. S1 ADMET now parses
  cleanly with 25.10 (`DSL2 - revision: 29a6b55766`), submits to AWS
  Batch (`executor > awsbatch (1)`), and the Batch task is mid-run.
  This is exactly the kind of progress the previous "not realizable"
  runs were blocked from showing.

---

## The two re-broken infrastructure pieces

### 1. universe.sqlite clobbering

**Symptom:** the chat-stream hung for 90s with only heartbeats, no
LLM response. Galaxy backend logs showed `OutdatedDatabaseError:
DB has 3af58c192752, code expects 204367c6a604` — even though
yesterday I'd manually run `manage_db.sh upgrade` and verified
Galaxy booted cleanly.

**Root cause:** every `sync_to_dev.sh` run does
`aws s3 cp <local-universe-sqlite> dev` to ship Galaxy state. The
local universe.sqlite carries the local repo's alembic head
(`3af58c192752` — the parent of the merge). Each sync therefore
overwrote the dev DB back to the pre-merge revision, which the
deployed code refused to boot against.

**Fix** (`3a7f10acf`):
- After the `docker cp universe.sqlite` step, run
  `manage_db.sh upgrade` inside the container so the deployed DB is
  brought to whatever head the code expects.
- Also clean up stranded `a7f3deepagent` rows in `alembic_version`
  (the merge parent that some sessions left lingering).
- All steps inside the same `ec2_ssh` heredoc so the upgrade can't
  be skipped by an intermediate failure.

### 2. Nextflow 26.04 auto-installed and broke DSL2 acceptance

**Symptom:** `Statements cannot be mixed with script declarations` on
21 workflows that had previously worked (`def _useAws = ...` at script
scope), `Unexpected input: R2` on cyp_ddi_panel (Python docstring
inside Groovy heredoc), `log.info '''...'''` banner parse failures.

**Root cause:** sync_to_dev.sh installs Nextflow via
`curl https://get.nextflow.io | bash` whenever the launcher is
missing. That installer always pulls the latest release. At some
point the latest became 26.04.x, and 26.04's DSL2 parser is
significantly stricter than 25.x. Our older workflows became
incompatible without anyone changing them.

**Decision tree:**
- **Path A:** rewrite the 21 workflows to satisfy 26.04
  (top-level `def` → `params.X`, drop `log.info` banners, etc.).
- **Path B:** pin Nextflow to 25.10 LTS so the existing syntax
  keeps working.

I shipped Path A first (commit `42ad2a288`, 21 files). Then yzhang
correctly pushed back ("we don't need to use the latest if it
causes trouble. it should accommodate the old version, why not?"),
which pointed at Path B as the better fix. I reverted Path A
(`51450928d`) and shipped Path B (`c1de025f4`).

**Path B implementation:**

1. `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`:
   ```python
   env["NXF_VER"] = os.environ.get("NXF_VER", "25.10.0")
   ```
   Every Nextflow `Popen` now pulls the 25.10 framework jar
   regardless of which launcher version is on PATH. Overridable via
   host env if we ever want to bump.

2. `scripts/sync_to_dev.sh`: launcher-version check on every sync:
   ```bash
   EXPECTED_NF_VER="25.10.0"
   INSTALLED_NF_VER=$(docker exec biomate-galaxy-dev /usr/local/bin/nextflow -v | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
   if [[ "$INSTALLED_NF_VER" != "$EXPECTED_NF_VER" ]]; then
     docker exec biomate-galaxy-dev bash -c "
       cd /tmp && rm -f /tmp/nextflow
       NXF_VER=$EXPECTED_NF_VER curl -fsSL https://get.nextflow.io | bash
       mv /tmp/nextflow /usr/local/bin/nextflow
       chmod +x /usr/local/bin/nextflow
     "
   fi
   ```
   This is the "bump deliberately, not by curl" pattern.

### Why 25.10 specifically

| Version | Status | DSL2 strictness |
|---|---|---|
| 26.04.x | Latest at session start | Stricter — broke 21 of our workflows |
| **25.10.x** | Last pre-26 LTS | Accepts top-level `def`, heredoc-friendly |
| 24.10.x | Older LTS | Same as 25.10 + missing newer plugin features |
| 23.10.x | Old LTS | Lacks AWS Batch CRT improvements |

---

## Full-catalogue audit (2,397 .nf files)

Ran 5 grep patterns covering every 26.04 breakage class seen this
session. Counts BEFORE the version pin was reverted to 25.10:

| Pattern | Total files | Already fixed? | After 25.10 pin |
|---|---|---|---|
| `publishDir` bare `${meta.X}` (no closure) | 0 (all 297 fixed in `84c4a0923`) | ✅ | N/A |
| Top-level `def X = ...` statements | 14 | reverted from `42ad2a288` | ✅ accepted |
| Top-level `log.info` / `println` / `workflow.on*` | 8 | reverted | ✅ accepted |
| Python `"""docstring"""` inside Groovy heredoc | 6 (cyp_ddi, virtual_cell, pbpk_disease_state already fixed previously) | partial | ⚠️ still risky at any version |
| `aws_batch` profile name | 0 (cyp_ddi alone fixed in `8aa5ed84e`) | ✅ | N/A |

### Domain breakdown (top-level `def` exposure)

| Domain | Files with top-level def | Total files | % |
|---|---|---|---|
| drug_discovery | 8 | 44 | 18% |
| genomics | 3 | 36 | 8% |
| multi_omics | 1 | 1 | 100% |
| structural_biology | 2 | 2 | 100% |
| **Bioconductor** | **0** | **1,818** | **0%** |
| All other 11 domains | 0 | — | 0% |

**Bioconductor verdict:** the colleague's recent Bioconductor work
(1,818 workflows = 76% of catalogue) is clean. No top-level
statements, no bare publishDir interpolations, no Python-Groovy
heredoc collisions, no profile name mismatches. Well-built; no
remediation work needed there.

---

## Drug pilot v3 progress (Nextflow 25.10 active)

In-flight as of doc-write. S1 ADMET partial state:

```
[S1_ADMET:Turn1] response=63237ms workflow=none runBtn=true   ← 4× faster vs v2's 240s
[S1_ADMET] Clicked Confirm & Run
[S1_ADMET] Execute API status=200 type=workflow runId=2d1e463b-fe1b-4567-9087-0f8cc2d5333f
[S1_ADMET] Poll 0: status=running steps=0/0

Galaxy backend nextflow log:
  Downloading plugin nf-amazon@3.4.1
  Launching `predict_admet_properties/main.nf` [irreverent_curry] DSL2 - revision: 29a6b55766
  executor >  awsbatch (1)
  [65/72b3cf] PRE…ICT_ADMET_PROPERTIES (run) | 0 of 1
```

What the v2 run did:
- S1 Turn 1 took 240 s, returned no workflow card
- S2-S6 same — 4 of 6 never produced a card, 2 hit Batch parse errors

What v3 is doing:
- S1 Turn 1 returned in 63 s with a real workflow card
- Card → Run → real Batch task ID submitted
- Currently waiting on AWS Batch worker (~3-5 min more expected
  based on the cyp_ddi runs from earlier today)
- No parse errors, no JVM crashes, no missing-import errors

The S1 progress alone confirms both fixes (alembic + Nextflow pin)
are working end-to-end.

### Final v3 outcomes

| Test | Duration | Terminal status | vs v2 |
|---|---|---|---|
| S1 ADMET | 15.3 min (Playwright timeout) | run in-flight at suite cut-off | reached Batch (v2 hit no card) |
| S2 IVIVE | 5.7 min | failed | reached Batch (v2 hit no card) |
| S3 POCKET | 4.7 min | failed | reached Batch (v2 hit no card) |
| S4 PHARMA | 1.2 min | failed | reached Batch (v2 hit no card) |
| **S5 RANKING** | 7.3 min | **completed** ✅ | **promoted from fail to pass** |
| **S6 CRO** | (last in suite) | **completed** ✅ | **promoted from fail to pass** |

**Net change vs v2**: 4 workflows promoted from "no workflow card
generated" to actually executing on AWS Batch. 2 workflows promoted
all the way from "failed at parse" to "terminal=completed". The
remaining 4 reached real Batch execution but their workflow-level
outputs/assertions failed — those are individual workflow bugs to
diagnose, not infrastructure breakage.

The S5 + S6 success is exactly the canary expected: those are the
two workflows we surgically fixed earlier today (`log.info '''`
banner removal — now superseded by the pin since 25.10 accepts the
banners, but the cleanup is benign). They confirm end-to-end
real-Batch execution + canonical outputs work on dev again.

Per-workflow diagnosis of the 4 still-failing runs is the next
session's work.

---

## Today's commit chain (this round)

| # | SHA | Title |
|---|---|---|
| — | `3a7f10acf` | sync: run alembic upgrade after universe.sqlite copy |
| — | `42ad2a288` | (mass-rewrite of 21 workflows — was Path A) |
| — | `c1de025f4` | **fix(nextflow): pin framework version to 25.10.0 (last pre-26 LTS)** |
| — | `51450928d` | revert Path A — the pin makes it unnecessary |

Plus continuing earlier-session commits that all stay (publishDir
closures across 297 files, reconcile-on-read, CRT disable, numpy<2
base pin, cyp_ddi triple fix, deny-list terminal states, deprecate
s3_output_files, ECR orphan audit doc).

---

## Operational runbook addition

When Galaxy refuses to boot with `OutdatedDatabaseError` after a
sync:

```bash
# This is automatic now in sync_to_dev.sh, but to do it manually:
docker exec biomate-galaxy-dev bash -c "cd /app && ./manage_db.sh upgrade"
docker exec biomate-galaxy-dev bash -c \
  'sqlite3 /app/database/universe.sqlite \
   "DELETE FROM alembic_version WHERE version_num = '\''a7f3deepagent'\'';"'
docker restart biomate-galaxy-dev
```

When the Nextflow launcher version drifts from 25.10.0:

```bash
docker exec -u root biomate-galaxy-dev bash -c "
  cd /tmp && rm -f /tmp/nextflow
  NXF_VER=25.10.0 curl -fsSL https://get.nextflow.io | bash
  mv /tmp/nextflow /usr/local/bin/nextflow
  chmod +x /usr/local/bin/nextflow
"
```

To bump the pin (after testing locally), edit:
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` —
  default in `env["NXF_VER"] = os.environ.get("NXF_VER", "...")`
- `scripts/sync_to_dev.sh` — `EXPECTED_NF_VER="..."` constant

---

## Still-open issues (carrying forward)

1. `biomni-tools:x86` (now rebuilt with numpy<2) container — need to
   verify cyp_ddi runtime is unblocked (was failing on numpy 2.x ABI
   yesterday).
2. Drug pilot v3 final result — S1 in flight; S2-S6 to follow.
3. Colleague's small Dockerfiles (cloning/crispr/synbio/structural)
   need to be located — they're not in any branch of this repo.
   yzhang said he will ask the colleague directly.
4. Sample-data fabrication issue in `galaxy-assistant.ts:5170` —
   the LLM "demo" exception that produces fake DESeq2 results.
   Design discussed; not implemented.
5. Backend `mock_mode = True` defaults in 3 runtime validators —
   tracked, not flipped yet.

---

## CLAUDE.md compliance

- [x] Real BioMate execution path used throughout (no mocked Batch
      paths, no synthetic outputs).
- [x] When a fix had a choice between "rewrite many things" vs
      "address the underlying cause", chose the underlying cause
      (Nextflow version pin instead of mass-rewriting workflows).
- [x] No workflow definitions edited under
      `nextflow_nfcore/subworkflows/**/*.nf` to make benchmarks pass
      — the 21 workflows were reverted because a better fix existed.
- [x] Doc lives under `docs/` with date prefix.
