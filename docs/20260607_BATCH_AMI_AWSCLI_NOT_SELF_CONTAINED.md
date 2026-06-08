# Batch AMI: aws-cli must be installed self-contained at /opt/aws-cli/

**Date:** 2026-06-07
**Status:** Diagnosis only — no AMI/LT rebuild attempted

## TL;DR

The Batch worker AMI installs aws-cli **system-style**: the binary lives at
`/usr/local/bin/aws` and `/opt/aws-cli/bin/aws` is a *symlink* to it
(per the executor.py header for `ami-08fe495be97a3dbf4`).

When Nextflow auto-mounts `cliPath`'s parent dir (`/opt/aws-cli/`) into a
task container, the symlink resolves to `/usr/local/bin/aws` — which is
*not* mounted. Even when the binary is reachable, it is dynamically
linked against the *host's* `/usr/lib/x86_64-linux-gnu/libz.so.1`,
which is also not mounted, so it fails:

```
/opt/aws-cli/bin/aws: error while loading shared libraries: libz.so.1:
cannot open shared object file: No such file or directory
```

This breaks **any nf-core pipeline** whose process containers are
minimal biocontainers (e.g. `quay.io/biocontainers/perl`,
`quay.io/biocontainers/gtf2bed`) that lack libz. Reproduced
2026-06-07 on `nfcore/chipseq` with `-profile test,aws`.

## Why band-aids keep regressing

This is the **third** time the team has hit this class of bug:

| Date | Doc | Band-aid | Why it didn't fix the root cause |
|---|---|---|---|
| 2026-04-17 | `20260417_DRUG_DISCOVERY_7_WORKFLOW_FIXES.md` | Added `volumes = ['/opt/aws-cli']` | Launch Template v9 was *deleting* and re-downloading `/opt/aws-cli/` |
| 2026-04-17 | `20260417_CS10_CRYOSPARC_EXECUTION_FIXES.md` | Removed `volumes` (cliPath auto-mounts) | Auto-mount works, but mounted symlink target is unreachable |
| 2026-06-07 | (would have been) | Mount host `/lib` and `/usr/lib` into container | Risks glibc symbol mismatch; doesn't fix the next minimal container |

Each band-aid in the executor created the next failure mode. The real
issue is upstream: **the AMI's `/opt/aws-cli/` is not a self-contained
install directory**.

## The right fix

The backend Dockerfile already installs aws-cli correctly
(`backend/Dockerfile` ~line "AWS CLI v2 in /opt/aws-cli (self-contained …)"):

```bash
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -i /opt/aws-cli -b /opt/aws-cli/bin \
    && /opt/aws-cli/bin/aws --version
```

That produces `/opt/aws-cli/v2/current/dist/` containing the binary +
*all* bundled libs (including libz). The binary's RPATH is `$ORIGIN`,
so when Nextflow auto-mounts `/opt/aws-cli/` into a task container,
the dynamic loader finds every dep inside the mount itself — no host
libs required.

**Action:** apply the same install pattern to the Batch worker AMI's
build script / Launch Template user-data. Remove any
`rm -rf /opt/aws-cli` step and replace any `apt-get install awscli` or
`pip install awscli` calls with the self-contained installer above.

## What's blocked until then

- `nf-core` test runs that exercise minimal biocontainers
  (verified: chipseq, atacseq, rnaseq, airrflow, cutandrun all fail
   at the first PREPARE_GENOME-style task)
- BioMate's own workflows are **unaffected** — they ship
  `biomate-nextflow-base` which has aws-cli baked into the container,
  so cliPath is unused.

## Files / commits referenced

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
  (containerOptions LD_LIBRARY_PATH lines) — *no change needed there*
- AMI build (out of repo? — find and update)
- Launch Template user-data (out of repo? — find and update)
