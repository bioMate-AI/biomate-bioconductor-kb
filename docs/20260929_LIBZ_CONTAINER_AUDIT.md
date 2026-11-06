# Raw quay.io/biocontainers → libz Batch-Staging Failure — Scope Audit

**Date:** 2026-09-29
**Type:** READ-ONLY audit + scoped fix proposal. **No code changed, no commits, no sync.**
**Repo:** `/Users/kky/biomate-review` (canonical 320 MB `galaxy_ai_tools.db` present locally)

## TL;DR

- The prior claim **"688 files, all fail"** is **both over- and under-stated**.
  - **True at-risk count is 699** `.nf` files that set an **active** process `container`
    directive to a raw `quay.io/biocontainers/*` image (688 of them under `bioconductor/`,
    which is where the "688" came from — it was the bioconductor subset, not the total).
  - **"All fail" is false.** Only **one** workflow (`dropletutils`) was ever *observed* to
    hit the libz S3-staging failure on Batch. The DB records **zero** other aws-cli
    `libz.so.1` staging failures, and **1,092** bioconductor workflows have `ok`/`ok_warnings`
    real-exec status. The rest is **projection, not observation**.
- The failure is real and correctly root-caused, but the fleet of "both" files
  (2,165) are **not** at risk — their raw-quay line is a `//` comment; their active
  `container` directive is already a Batch-ready `biomate/bioc-domain-*` ECR image.
- **Recommended fix: option (a)** — a single executor change that extends the Batch
  `volumes` libz mount to all container paths. It is viable **and** the safest, but with
  one important correction to the plan (see §4): the effective Batch mount is the
  `aws.batch.volumes` directive, **not** the `containerOptions -v` branch (Batch ignores
  `-v`), so the fix must be applied to the right line.

---

## 1. Real count + breakdown (exact)

Scope: `backend/biomni_workflows/nextflow_nfcore/**` + `backend/nf-core-modules/**`, `*.nf`.

| Category | Count | At risk? |
|---|---|---|
| **Total `.nf` files** | **3,787** | — |
| Reference `quay.io/biocontainers` anywhere (comment or directive) | 2,874 | mostly no |
| Reference `biomate/bioc-domain-*` (ECR) | 2,679 | no |
| **quay ONLY** (no bioc-domain in file) | **709** | candidate |
| — of which set an **ACTIVE** `container "quay.io/biocontainers…"` directive | **699** | **YES — the true at-risk set** |
| — quay in comment only / no active directive | 10 | no |
| **quay + bioc-domain BOTH** in the file | **2,165** | **NO** |
| **bioc-domain ONLY** | 514 | no |
| files reading `params.container` | 1 | n/a |

**Key structural fact (verified on samples across all three categories):**
In every "both" file, the raw-quay string is a **documentation comment**
(`// Container: quay.io/biocontainers/...`) recording the upstream biocontainer, while
the **active** `container "…"` directive points at
`399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-<domain>:3.20-slim`.
Zero "both" files have an active raw-quay directive. So the **only** files that will
actually run against a raw quay image on Batch are the **699** with an active raw-quay
`container` directive.

**Directory breakdown of the 699 at-risk files:**

| Directory | Count |
|---|---|
| `nextflow_nfcore/subworkflows/bioconductor` | **688** |
| `nextflow_nfcore/subworkflows/transcriptomics` | 3 |
| `nextflow_nfcore/subworkflows/genomics` | 3 |
| `nextflow_nfcore/subworkflows/epigenomics` | 3 |
| `nf-core-modules/**` | 3 |
| `nextflow_nfcore/subworkflows/rare_disease` | 1 |
| `nextflow_nfcore/subworkflows/proteomics` | 1 |

→ **The prior "688" was the `bioconductor/` subset**, not the class total. The true
class total of active-raw-quay files is **699** (688 bioconductor + 11 elsewhere).

`params.container` is a non-factor: exactly **1** file references it. There is no
executor-override-via-params escape hatch in play here.

---

## 2. The actual failure mechanism + who is exempt

**Root cause (verbatim, CloudWatch, from `docs/20260928_DOMAIN_VALIDATION_UNTESTED.md`):**
```
/opt/aws-cli/bin/aws: error while loading shared libraries:
  libz.so.1: cannot open shared object file: No such file or directory
```
Nextflow injects the host AMI's `/opt/aws-cli/bin/aws` (via `aws.batch.cliPath`) into
each Batch task to stage inputs/outputs from S3. That aws binary is dynamically linked
against `libz.so.1`. Raw quay biocontainers keep their `libz.so.1` in `/usr/local/lib`,
which the executor **deliberately excludes** from the injected `LD_LIBRARY_PATH`
(to avoid a bad `/usr/local/lib/libtinfo.so.6` that breaks pyFlow tools like
Strelka/Manta). So the host `aws` binary can't resolve libz and exits **before the R/tool
body runs** — S3 staging fails, work dir contains only `.command.run`/`.command.sh`.

**The four conditions a file must meet to actually fail this way:**
1. Runs on **AWS Batch** (`compute.executor="awsbatch"`; dev has `NEXTFLOW_USE_AWS=true`). ✔ default on dev
2. Stages from S3 via the **host-mounted aws** (`aws.batch.cliPath=/opt/aws-cli/bin/aws`). ✔ always
3. Its **libz is in `/usr/local/lib`** (raw quay biocontainer layout), not resolvable via the injected `LD_LIBRARY_PATH`. ✔ true for raw-quay bioc images
4. The executor **does not mount host libz** into a path its dynamic loader searches. ✔ true for `bioconductor/` (see below)

**Who is exempt (the mount gating — the load-bearing detail):**

There are **two** libz-mount mechanisms in `nextflow_executor.py`, and only one works on Batch:

- **`containerOptions -v` branch** (lines ~2877–2892): gated on
  `_needs_host_libz = "/nf-core-workflows/" in nf_path or "/nf-core-modules/" in nf_path`.
  Commit `2f0d9a8ac` extended this to `/nf-core-modules/` for the DDA fix.
  **BUT** the executor's own comment at line ~3020 states: *"Batch ignores `-v` flags in
  containerOptions; only the `volumes` directive (Batch mountPoints) has effect."*
  → **This branch is a no-op on Batch.** It only matters for a local-docker executor.

- **`aws.batch.volumes` directive** (lines ~3030–3034): this is the **only** mount that
  Batch honors. It emits
  `volumes = ['/usr/lib64/libz.so.1:/usr/lib64/libz.so.1:ro']` and is gated on
  **`is_nfcore = "/nf-core-workflows/" in nf_path`** — i.e. downloaded nf-core *pipelines* only.

**Consequence for the 699 at-risk files:**
- `bioconductor/` paths → `is_nfcore = False` **and** not `/nf-core-modules/` **and**
  not `/nf-core-workflows/` → **neither** mount fires → **condition 4 is met** → they will
  hit the libz failure on Batch. (`is_nfcore_or_bioc=True` only suppresses the *default
  container injection*, so the `.nf`'s own raw-quay directive stands verbatim.)
- The 3 `nf-core-modules/` at-risk files get the `containerOptions -v` branch — **but that
  branch is ignored by Batch**, so they are *also* not actually mounted on the Batch path
  (see §3 — the DDA "fix" was never verified on a live Batch dispatch).

**So: all 699 active-raw-quay files meet conditions 1–4 on the dev Batch path.** The
mechanism is real. What is *not* real is the claim that they've been shown to fail.

---

## 3. Evidence: observed failures vs projection

**Runs on Batch / real-exec coverage (canonical 320 MB DB, `workflows` table):**

| `real_exec_status` | count |
|---|---|
| (null / never run) | 989 (bioconductor) / 1,869 (all) |
| `ok` | 690 (bioconductor of 4,201-row table: 690) |
| `ok_warnings` | 402 |
| `exec_error` | 797 |
| `fixture_failed` | 277 |
| `runnable_assumed` | 109 |
| `timeout` | 18 |
| `ran_empty_output` | 3 |

- **2,332 bioconductor workflows have a real-exec record** (only 989 are null), and
  **1,092 are `ok`/`ok_warnings`.** That alone refutes "all fail."
- **Zero** rows have an aws-cli libz S3-staging failure signature
  (`real_exec_err LIKE '%libz%'` AND aws/staging/127): **0 matches.**
- The 14 rows matching `exit 127` / `.command.run` are a **different** bug
  (`... unbound variable` — shell templating), not libz.
- The many `unable to load shared object` errors are **R DLL / `DLLpath` package-load**
  failures **inside** the R body (a dependency-completeness issue), also **not** the
  aws-cli libz-staging failure.
- **`dropletutils` is the ONLY observed libz-staging failure** (run
  `56851a75-…`, Nextflow `becd7879-…`), and it has since been **fixed and re-validated**
  (`real_exec_status='ok'`; emptyDrops detected 2,876 cells on real PBMC3k on Batch) by a
  **per-workflow container swap** to `bioc-domain-transcriptomics:3.20-slim`
  (commits `9641ed6e2`, `6fb4b084e`; see `docs/20260928_DOMAIN_VALIDATION_UNTESTED.md`).

**Critical caveat on the 1,092 "successes":** the bioconductor real-exec harness
(`docs/verification/BIOC_EXECUTABLE_VERIFICATION_GUIDE.md`) runs `nextflow run` (no `-stub`)
in a **dependency-complete image on an EC2 worker with a local executor** — it builds a
fixture input locally and does **not** stage from S3 through the host-mounted aws binary.
So those successes prove the **R science is valid**; they **do not** exercise the
Batch+S3-staging path where the libz failure lives. The libz risk for
`bioconductor`-on-Batch is therefore **projected for 698 of the 699**, and **observed for
exactly 1** (`dropletutils`, now fixed).

**The DDA "fix" was also never verified on Batch.** `docs/20260928_PROTEOMICS_DDA_VALIDATION.md`
states the DDA run was **"BLOCKED before any Batch dispatch"**, **"Batch job id: none
submitted"**, **"Total Batch spend: \$0.00"** — it failed at Nextflow compile time. The
executor comment claiming *"Verified live 2026-09-28 on proteomics_dda_search"* (line ~2876)
is **inaccurate**; and because it patched the `containerOptions -v` branch (ignored by
Batch), it would not have mounted libz on a real Batch dispatch anyway.

---

## 4. Scoped, SAFE fix proposal

### Recommendation: **Option (a) — one executor change, applied to the `volumes` directive.**

Extend the Batch libz mount to all container paths by changing the gate on the
**`aws.batch.volumes`** directive (lines ~3030–3034), from:

```
*( ["        volumes = ['/usr/lib64/libz.so.1:/usr/lib64/libz.so.1:ro']"]
   if is_nfcore else [] )
```
to apply the same `volumes` mount **unconditionally** (or gated on
`compute.executor == 'awsbatch'`), so bioconductor + nf-core-modules + BioMate custom
containers all get the host `libz.so.1`.

**Why (a) is correct and safe:**
- **Touches one file, zero workflows.** Fixes the whole 699-file class without editing a
  single `.nf` (vs. option (b)'s ~699 edits).
- **Precisely the mount already proven safe.** The `volumes = ['/usr/lib64/libz.so.1:…']`
  single-file mount is the exact form already shipped and validated for nf-core
  (comment at lines 3024–3029: verified 2026-06-08 on nfcore/chipseq — libz-only mount
  fixes GTF2BED with no glibc/tinfo regression; the full `/usr/lib64` mount was the thing
  that broke, and we are **not** proposing that). Broadening the *gate* on an
  already-safe single-file mount is low-risk.
- **Cannot regress the "both"/bioc-domain images.** ECR `bioc-domain-*` images already
  have their own working libz; a read-only bind of a compatible host `libz.so.1` over the
  same path is inert for them (already proven: nf-core pipelines that use their own
  containers already receive this mount today without issue).

**One required correction to the naive plan:** do **not** implement (a) by broadening the
`_needs_host_libz` / `containerOptions -v` branch — **Batch ignores `-v`**, so that would
be a silent no-op (the same trap the DDA fix fell into). The change must be on the
`aws.batch.volumes` directive.

**Residual to check before implementing (not done here — audit only):**
- Confirm the mount is inert for **GPU / non-biocontainer** images (gromacs, rocker,
  BioNeMo) — a read-only single-file bind over an existing compatible libz should be safe,
  but a live smoke test on one such run is warranted, since the mount would now apply to
  them too.
- The `bioconductor` path currently suppresses default `container` injection
  (`is_nfcore_or_bioc`), so the `.nf`'s own image is used — the mount must be validated to
  land for that no-injected-container case as well.

### Why not the alternatives

- **(b) per-workflow container swaps** (raw quay → `bioc-domain-*`, the dropletutils
  pattern): **rejected as the class fix.** It's ~699 file edits, each needs the correct
  domain image + a verified deps manifest match (dropletutils also needed a `versions.yml`
  case-fix), and every edited `.nf` is executed by Nextflow so a wrong image silently
  breaks that workflow. High blast radius, high toil. Fine as a *targeted* remedy for a
  specific workflow being validated **now**, but not for closing the class.
- **(c) leave as-is + fix on demand:** acceptable *only* because 698/699 are untested on
  Batch, so there is no active user-facing breakage today. But it leaves a latent class
  trap that re-surfaces every time a bioconductor workflow is first dispatched to Batch
  (exactly what happened with dropletutils and nearly with DDA). Option (a) retires the
  class for roughly the same effort as one more (b) swap.

**Bottom line:** Option (a) is **viable and the safest** — provided it is implemented on
the Batch-effective `aws.batch.volumes` directive, not the Batch-ignored
`containerOptions -v` branch. Recommend (a) for the class fix; keep (b) only as a
per-workflow remedy when a specific workflow is being validated and a container swap is
independently justified.

---

## Appendix — commands used (all read-only)

- Counts: `comm -12/-23/-13` on sorted `grep -rl` sets for `quay.io/biocontainers` vs
  `biomate/bioc-domain`; active-directive test `grep -qE '^\s*container\s+["'\'']quay\.io/biocontainers'`.
- DB: `sqlite3 backend/database/galaxy_ai_tools.db` (320 MB canonical) — status
  histogram + `real_exec_err` signature searches (libz / exit 127 / `.command.run`).
- Executor: read `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
  (`_needs_host_libz` ~2877, `aws.batch.volumes` ~3030, `is_nfcore` ~2974,
  `is_nfcore_or_bioc` ~2831).
- Git: `git show 2f0d9a8ac` (DDA fix diff) — confirmed it patched the `containerOptions -v`
  branch only.
- Docs: `20260928_DOMAIN_VALIDATION_UNTESTED.md` (dropletutils root cause + fix),
  `20260928_PROTEOMICS_DDA_VALIDATION.md` (DDA never dispatched to Batch, \$0 spend),
  `verification/BIOC_EXECUTABLE_VERIFICATION_GUIDE.md` (local-executor fixture harness,
  not S3-staging).
