# Drug-Dev Sweep on 25.10.5 — CRT JVM Crash Fixed, cyp_ddi rdkit Fixed

**Date:** 2026-05-26 (afternoon session, continued from 25.10.5 morning)
**Branch:** `integration/next-phase`
**Key commits:** `5708f3d1a` (cyp_ddi rdkit), `e4910e566` (real CRT-disable properties)

## TL;DR

After the 25.10.0 → 25.10.5 bump fixed the meta-finalize bug, a drug-dev sweep surfaced two more layered defects. Both fixed this session:

1. **JVM SIGSEGV in AWS SDK CRT native lib loader** — the prior mitigation flag `-Daws.crt.disable.crt.in.client=true` was a fabricated property name with no effect. Replaced with the real AWS SDK Java v2 properties (`software.amazon.awssdk.http.async.service.impl=...NettySdkAsyncHttpService` + sync equivalent). Confirmed via `useCrtClient:false` in Nextflow's runtime config dump.
2. **cyp_ddi `rdkit-pypi` shadowing modern rdkit** — workflow pip-installed an old PyPI fork (2022.9.5) that overrode the modern rdkit already in `biomni-tools:x86`, breaking `rdMolStandardize.Standardizer`. Swapped to `pip install rdkit` (4 sites).

End-state on dev: AWS Batch jobs run to SUCCEEDED with real outputs in S3. A residual fragility (Nextflow JVM dies when Galaxy container restarts → publishDir never runs → outputs stranded in `work/`) is filed as Task #16 for defense-in-depth.

## Sequence of investigation

The morning's 25.10.5 bump cleared `No such property: meta for class: ProcessDslV1` in finalize. Re-running 5 drug-dev workflows showed a different pattern:

| Workflow | Reported status | Real outputs |
|---|---|---|
| `transporter_ddi_prediction` | ✓ succeeded (223s) | yes (worked from morning) |
| `predict_admet_properties` | ✓ succeeded (221s) | yes (worked from morning) |
| `ivive_hepatic_clearance` | ✓ succeeded (170s) | **0** |
| `pocket_detection_druggability` | ✓ succeeded (32s) | only auto-reports |
| `pharmacophore_filtering` | ✓ succeeded (26s) | **0** |
| `pbpk_simulation` | ✓ succeeded (206s) | **0** |
| `cyp_ddi_panel` | ✗ failed (102s) | 0 (rdkit error) |

Reading the run logs showed three distinct root causes:

```
# A fatal error has been detected by the Java Runtime Environment:
#  SIGSEGV (0xb) at pc=0x00007631a166275a, pid=617
#  Problematic frame: C  [ld-linux-x86-64.so.2+0x2475a]
#  Frame: software.amazon.awssdk.crt.CRT.extractAndLoadLibrary
```

(ivive, pharma, pbpk → JVM CRT race)

```
AttributeError: module 'rdkit.Chem.MolStandardize.rdMolStandardize'
has no attribute 'Standardizer'
```

(cyp_ddi → old rdkit-pypi shadowing)

```
params.pdb_input is required — local path, s3:// URI, or 4-letter PDB ID
```

(pocket → test invocation typo: sent `pdb_id`, workflow wants `pdb_input`)

## Fix 1 — Bogus CRT property replaced (`e4910e566`)

### What was wrong

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` had been setting:

```python
crt_opts = (
    f"-Daws.crt.lib.dir={nxf_crt_cache} "
    f"-Daws.crt.disable.crt.in.client=true "   # ← invented property
    f"-Xss2m"
)
```

The middle flag `aws.crt.disable.crt.in.client` is not documented anywhere in the AWS SDK Java v2 codebase or docs. It was a no-op. The CRT native lib was still being extracted and loaded on every run, and the loader race in `ld-linux-x86-64.so.2` on Debian trixie / glibc 2.41 kept SIGSEGV'ing the JVM under concurrent process startup.

### The real properties

From [AWS SDK for Java 2.x — HTTP CRT configuration docs](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/http-configuration-crt.html):

> To use the AWS CRT-based HTTP clients as the default HTTP for your application, you can set the Java system property `software.amazon.awssdk.http.async.service.impl` to a value of `software.amazon.awssdk.http.crt.AwsCrtSdkHttpService`.

Inverting that — to force *non-CRT* clients, set the same property to the Netty implementation (and the sync equivalent for the blocking client):

```python
crt_opts = (
    f"-Daws.crt.lib.dir={nxf_crt_cache} "
    f"-Dsoftware.amazon.awssdk.http.async.service.impl=software.amazon.awssdk.http.nio.netty.NettySdkAsyncHttpService "
    f"-Dsoftware.amazon.awssdk.http.service.impl=software.amazon.awssdk.http.apache.ApacheSdkHttpService "
    f"-Xss2m"
)
```

`-Daws.crt.lib.dir` (real property) retained as defense-in-depth for anything that still instantiates `S3CrtAsyncClient` directly. `-Xss2m` retained for stack-size safety on the native loader thread.

### Validation

Fired `pbpk_simulation` on dev with the new flags. The Nextflow detail log (`work/.nextflow.log`) showed:

```
nextflow.file.FileHelper - Creating a file system instance for provider:
  S3FileSystemProvider; config=[..., client:[uploadChunkSize:104857600,
  s3:[useCrtClient:false], maxConnections:20]]
```

`useCrtClient:false` is the confirmation — Nextflow's nf-amazon plugin is no longer instantiating `S3CrtAsyncClient`. AWS Batch job `b87a2a46-0e35-4d33-b4b6-02b2f1de3dda` then ran to:

```
status=SUCCEEDED  exitCode=0
```

with 6 real output files in S3:

| File | Size |
|---|---|
| `pbpk_results.json` | 224 B |
| `pbpk_output.txt` | 334 B |
| `pk_profile.csv` | 6832 B (actual PK curve data) |
| `ddi_fold_change.json` | 165 B |
| `nca_parameters.json` | 186 B |
| `versions.yml` | 90 B |

Zero SIGSEGV anywhere in the log.

## Fix 2 — cyp_ddi rdkit modernized (`5708f3d1a`)

### What was wrong

`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/cyp_ddi_panel/main.nf` had four process scripts beginning with:

```bash
pip install rdkit-pypi 2>/dev/null || true
```

The container `biomni-tools:x86` already has a modern rdkit. But `rdkit-pypi==2022.9.5` is an older PyPI fork; when pip re-installs it, it *shadows* the modern rdkit in `site-packages`. The 2022.9.5 fork's `rdkit.Chem.MolStandardize.rdMolStandardize` does not export `Standardizer`, so:

```python
from rdkit.Chem.MolStandardize import rdMolStandardize
standardizer = rdMolStandardize.Standardizer()   # AttributeError
```

### Fix

Swap all four sites: `pip install rdkit-pypi` → `pip install rdkit`. The container has modern rdkit so the install becomes a no-op; if it ran elsewhere without rdkit, the modern PyPI `rdkit` (which has `Standardizer`) would install instead.

## Residual issue (filed as Task #16)

In one resweep run, the Nextflow JVM died at ~T+8s (right after submitting to AWS Batch) because the Galaxy container was restarted by `sync_to_dev.sh` (lines 343/347/388 stop+start the container). AWS Batch ran on without it, completed cleanly, and wrote outputs to `work/<hash>/` — but Nextflow wasn't alive to run publishDir, so files never reached `outputs/<runId>/`. `/api/runs/:id/outputs` reads only the `outputs/` prefix and returned `[]`.

This is **fragility, not the bug we fixed**. The CRT fix and rdkit fix both held — the workflow's actual compute succeeded. The recovery path (when Nextflow dies mid-run, pull outputs from `work/` either by `aws s3 cp` or by extending the outputs endpoint to read `work/<runId>/`) is Task #16. Not blocking for the drug-dev release because the typical cause (CRT crash) is now fixed.

## File touch list

```
backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/cyp_ddi_panel/main.nf
  (4 sites: rdkit-pypi → rdkit)

backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py
  (crt_opts block: bogus property → real Netty/Apache service-impl properties)
```

No workflow grammar / publishDir patterns touched — the fixes are at the SDK and image layer.

## Open follow-ups

1. **Task #16** — reconcile outputs from `work/` when Nextflow dies before publishDir runs (defense-in-depth)
2. **Full drug-dev resweep** on the 5 same workflows + cyp_ddi (rdkit fix) — fired post-CRT-fix as of this session; results pending
3. **Stashed UI work** — `app-sidebar.tsx` + `register.tsx` (BUG-10b billing widget + minor) are in `git stash`; user is taking these via another agent

## Lessons captured

- **Verify property names against vendor docs**, especially for "disable" flags. The bogus `-Daws.crt.disable.crt.in.client=true` had been in our tree since 2026-05-21 and never did anything.
- **`pip install rdkit-pypi` is an anti-pattern** in any workflow whose container already has modern rdkit. The shadowing breaks Standardizer and other modern APIs silently.
- **Status reporting is fragile when subprocesses die**. A "succeeded" with `0 outputs` is worse than a clear failure. Reconcile-from-Batch + work/ fallback (Task #16) closes the worst class of silent success.
