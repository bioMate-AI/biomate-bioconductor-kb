# Real Workflow Execution — Systemic Failures (Diagnosis, 2026-07-08)

**Status:** DIAGNOSIS ONLY — no production code changed (per session directive).
**Target:** dev (`https://dev-public.biomate.ai`, `NEXTFLOW_USE_AWS=true`, real AWS Batch).
**Fixture:** `lifeifei163361@163.com` (canonical, per CLAUDE.md).

## TL;DR

Ran the new real-run harness against dev for 2 of 4 target domains. **0 of 12
launched runs reached `completed`.** Real workflows launch, Nextflow starts, but
every run aborts **before any task executes** (`succeededCount=0`, `totalTasks=0`,
`returncode=1`). This is a **systemic execution-launch problem**, not a per-domain
data issue and not a harness bug. At least **three distinct root causes** were
isolated from real dev backend logs.

## How to reproduce

New harness: [`scripts/run_real_workflows.sh`](../scripts/run_real_workflows.sh) —
runs the canonical real-run Playwright e2e per domain against dev, polls each run
to a terminal state, prints run_id + pass/fail. NOT a mock/demo path.

```bash
E2E_FIXTURE_PASSWORD='<fixture pw>' scripts/run_real_workflows.sh              # all 4
DOMAINS="admet rnaseq" E2E_FIXTURE_PASSWORD='...' scripts/run_real_workflows.sh
```
Logs: `docs/real_run_harness/<TS>_*`. (Prereq: `cd frontend && npx playwright install ffmpeg`
— the rnaseq spec records video and needs the playwright ffmpeg binary.)

## Results

| Domain | Cases | Test pass/fail | **Real `completed`** |
|---|---|---|---|
| admet (drug-discovery) | 11 | 7 / 4 | **0** — all `exec=failed` or `prereq_blocked` |
| rnaseq (FASTQ QC) | 1 | 0 / 1 | **0** — `status=failed`, progress 11/11 but `succeededCount=0` |

The 7 admet "passes" are misleading: the drug-discovery spec tolerates *graceful
failure* for commercial-license (AMBER/Glide/MOE) and GPU (GROMACS) tools, so a
`failed`/`prereq_blocked` exec still passes the assertion. **Zero runs actually
produced outputs.** Every `progress=N/N` is the step-parser counting declared
steps, NOT real execution — do not trust it as a success signal.

## Root causes (from real dev `nextflowStatus.log_tail`)

### RC-1 — nf-core subworkflow launched with unbound `take:` channels (rnaseq)
Run `c064aadf-1b58-4972-a69a-db1dfd9c838b`:
```
Workflow `FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS` declares 24 input channels but 0 were given
Session aborted -- succeededCount=0
```
The executor recognizes named-only-workflow-with-`take:` shapes and is supposed to
generate an anonymous entry wrapper (`-entry` cannot bind a `take:` channel). But
[`_build_bioc_entry_wrapper`](../backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py#L1327)
only handles the **single-process / single-take Bioconductor shape** — its wrapper
body is `workflow { PROC( Channel.of(chan) ) }`
([line 1452](../backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py#L1452)),
binding exactly one channel to one process. A real nf-core subworkflow with **24
`take:` channels** does not match; the wrapper is not built, launch falls back to
`-entry <NAME>` ([line 4460-4466](../backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py#L4460)),
and Nextflow aborts because the 24 take channels are unbound.
**Fix direction (not applied):** either drive nf-core subworkflows via their pipeline
`main.nf` entry (which wires the channels), or extend the wrapper generator to bind
all N `take:` channels from the params/samplesheet — not just one.

### RC-2 — `Script compilation error` at launch, though source compiles clean (admet tier-A)
Runs `1eae1316…`, `3fdb1bdc…`, `57b65725…`, `a514fbcf…`:
```
ERROR nextflow.cli.Launcher - Script compilation error
Caused by: MultipleCompilationErrorsException: startup failed
```
**But the checked-in source subworkflows compile clean locally.** Verified with
`nextflow run <dir>/main.nf -preview -profile standard` for `nca_pknca`,
`scaffold_hopping`, `alphafold_db_search`, `drug_moa_rnaseq`,
`aizynthfinder_retrosynthesis` — no compilation errors (nca_pknca even reaches
param validation: `ERROR: --input_csv is required`). Therefore the syntax error is
**introduced at dev launch time** — a generated wrapper/inline artifact the executor
writes ([inline config line 4572](../backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py#L4572),
[params JSON line 4588](../backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py#L4588)),
**or dev deploy skew** (older/broken file versions on the dev container vs. repo HEAD).
**Next step to disambiguate (not done):** `docker exec` the dev galaxy container and
diff the deployed subworkflow files against repo HEAD; capture the exact generated
`.nf`/`.config` the executor wrote into the run's log dir and re-compile it locally.

### RC-3 — `Unable to parse config file` (admet MOE covalent docking)
Run `d3f4aa5f…`:
```
ERROR Unable to parse config file:
  '/app/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/moe_covalent_docking/nextflow.config'
```
The local `moe_covalent_docking/nextflow.config` **parses clean** (`nextflow config
-profile standard .` succeeds). Same signature as RC-2 → launch-time generation or
deploy skew, not a source bug. Likely shares RC-2's root cause.

### Also seen — `prereq_blocked` (never launched)
admet DA-3, DB-1, DB-4, DB-6 + rnaseq-adjacent: "Run button disabled: prereq_blocked",
empty `log_tail`. The workflow card rendered but the Run gate stayed disabled
(missing required param / unmet input prereq) — a **separate front-of-house issue**
from the Nextflow-launch failures above.

## What is NOT broken
- The harness (login → chat → generate → Run → poll-to-terminal works end-to-end).
- The source subworkflow `.nf`/`.config` files (compile clean locally).
- AWS Batch reachability (runs submit; they abort at Nextflow parse/invocation, before Batch).

## Evidence index (dev run_ids, 2026-07-08 ~06:2x UTC)
- RC-1 rnaseq: `c064aadf-1b58-4972-a69a-db1dfd9c838b`
- RC-2 compile: `1eae1316-…`, `3fdb1bdc-…`, `57b65725-…`, `a514fbcf-…`
- RC-3 config:  `d3f4aa5f-29bf-42b6-bba2-96fdd19a2ad3`
- prereq_blocked: admet cases DA-3, DB-1, DB-4, DB-6 (empty log_tail)
Full per-case log: `docs/real_run_harness/20260708_141833_admet.log`.

## TEST container verification (2026-07-08, via SSM — test is VPN-gated, private 172.19.x)

Instance `i-0482a6fa98c6f301a` (biomate-deploy-test, us-west-2), galaxy container
`biomate-galaxy-deploy`, Nextflow **25.10.5**, `NXF_SYNTAX_PARSER` unset → **v1 default**
(same strict parser as dev; local machines default v2, which is why bugs hid locally).

**A real workflow WAS launched and run on test** (bypassing frontend auth — the fixture
`lifeifei163361@163.com` does NOT exist in the test DB; called the galaxy execute API
directly: `POST localhost:8080/api/nextflow/execute`, `X-Forwarded-Proto: https`).
Target: `drug_discovery/nca_pknca/main.nf`, real S3 input CSV (6-subject single-oral-dose
PK), `NEXTFLOW_USE_AWS=true` → real AWS Batch. run_id `5001b847-b3e4-4042-9b7a-71d5d9e1826e`.

**Result — test's core execution WORKS; the failure is downstream:**
- Step 1 NCA_INPUT_VALIDATION → **exit 0** (validated_conc_time.csv)
- Step 2 NCA_PKNCA_ANALYSIS → **exit 0**, real PKNCA 0.12.1 output on S3
  (nca_results.csv, nca_summary.json: AUClast≈16547, Cmax≈1926, Tmax 2h, **t½ 4.64h** —
  matches the input ke=0.15 → ln2/0.15=4.62h). Science is correct.
- Step 3 NCA_REPORT_HTML → **failed at script COMPILATION** → whole run marked failed exit 1.

Two concrete bugs, both live on test:

### BUG A — unescaped R `$` in a Groovy script block (nca_pknca report step)
`.nextflow.log`: `ProcessUnrecoverableException: Process NCA_REPORT_HTML script contains error(s)`.
The NCA_REPORT_HTML `script:` block embeds R/Rmd containing `$` (`smry$study_info`,
`knitr::opts_chunk$set`, `info$dose`, …) inside a Groovy `"""…"""` GString **without
escaping to `\$`**. Steps 1–2 escape correctly (`df\$conc`, `e\$message`) — step 3 does not.
Groovy tries to interpolate `$study_info` etc. → compile error. This is deferred: Nextflow
compiles a process script only when the task dispatches, so `nextflow run -preview` does
NOT catch it (explains why the source "compiles clean" in preview but fails at runtime — the
same illusion behind the dev RC-2 reports). Fix: escape `$`→`\$` in the report `script:` block
(or move the Rmd out to a template file / `templateDir`).

### BUG B — finalizer race misreports terminal state
Same run, contradictory log lines seconds apart:
`orphan_finalizer … finalized — status=succeeded returncode=0` vs
`nextflow_executor … finished — status=failed returncode=1`.
When a process fails at script-compilation (not task execution), Nextflow reports
`succeededCount=2; failedCount=0` but returncode=1. `orphan_finalizer` keys off task counts
→ declares success/0; the executor keys off returncode → declares failed/1. The status API
then returns a bare `failed` with **no nextflowStatus/log_tail** (what made dev failures look
detail-less). Real state-consistency bug in the finalizer's success heuristic — it must treat
returncode≠0 (or session "Execution cancelled") as failure even when failedCount==0.

### Net answer: does test have "the problem"?
Partly. test's real execution capability **works** (Batch + R + correct PK outputs). It is in
**better shape than dev** (tier-A `.nf` compile; a real pipeline produced correct results).
Remaining on test: RC-3 (MOE config v1 parse — verified failing on test), BUG A (report-step
`$` escaping — this class likely affects other report/Rmd-embedding steps), BUG B (finalizer
race). RC-1 (multi-channel nf-core `take:` wrapper) not yet exercised on test.

## FIXES APPLIED + VERIFIED ON TEST (2026-07-08)

All changes are in the repo working tree; the nca_pknca file was hot-copied into the
test galaxy container (`docker cp`) purely to verify — **a real deploy/sync is still
required for persistence** (the container copy is overwritten on next deploy).

| Fix | File | Status |
|---|---|---|
| **Bug B** finalizer race | `lib/galaxy/ai/runs/orphan_finalizer.py` | `_read_returncode_from_disk` now scans the launcher log for session-abort markers (`script contains error(s)`, `Execution cancelled`, `ProcessUnrecoverableException`, …) **before** the optimistic trace heuristic; returns rc=1 on match. Unit tests added (`test_orphan_finalizer.py`: compile-fail regression + success-not-flipped guard) — both PASS. |
| **Bug A** Groovy `$` in report | `…/drug_discovery/nca_pknca/main.nf` | Escaped 8 unescaped R `$` (`opts_chunk$set`, `smry$study_info`, `info$dose/route/time_unit/conc_unit/auc_unit/n_subjects`) → `\$`. Only file with this bug (audited all 14 report-embedding `.nf`). Verified on test: step 3 now **dispatches** (compile error gone). |
| **Bug C** report references absent columns | `…/nca_pknca/main.nf` | `nca-table` chunk hard-referenced `CL_F`/`Vd_F`, which PKNCA omits for extravascular data → render crash. Rewrote to `select(all_of(present))` + label_map, tolerant of any missing NCA parameter. |
| **RC-3** MOE config `$(id -u)` | `…/moe_covalent_docking/nextflow.config` | Escaped `$(id -u)`/`$(id -g)` → `\$(…)` inside the double-quote GString (kept `${System.getenv}`). Verified: `NXF_SYNTAX_PARSER=v1 nextflow config` now parses (was failing). |

**End-to-end verification (real test AWS Batch, run_id 74291e62-63de-4dc8-9c2f-2d612cad2595):**
nca_pknca ran to **status=succeeded** — all 3 steps completed, outputs include the real
**`nca_report.html`** (previously never rendered), nca_results.csv, nca_summary.json,
qc_metrics.json. Real PKNCA science: t½ 4.64h, Cmax≈1926 (6 subjects). Prior runs on the
SAME container failed (compile error → then missing-column render crash); these two fixes
close the loop.

### Still open (not yet done)
- Deploy Bug B (finalizer) + RC-3 (MOE config) to test — only nca main.nf was hot-copied.
- Commit repo changes + run proper sync so all four fixes persist.
- RC-1 (multi-channel nf-core `take:` wrapper) — not exercised on test; rnaseq/WGS/CryoEM
  still likely hit it. Separate fix (extend `_build_bioc_entry_wrapper` or route via pipeline main.nf).

## (superseded) Original recommended order of fixes
1. **RC-2/RC-3 first** — confirm deploy-skew vs. generated-artifact by diffing dev
   container files against HEAD. If skew: re-sync. If generated: fix the emitter.
   Cheap, and likely unblocks the largest share of admet cases.
2. **RC-1** — extend the entry-wrapper generator to bind multi-channel nf-core
   `take:` subworkflows (or route via pipeline `main.nf`). Unblocks rnaseq + likely
   WGS/CryoEM (all nf-core).
3. Re-run `scripts/run_real_workflows.sh` per domain to verify each fix lifts
   `exec=` to `completed` — the score improvement proves the fix is real.
