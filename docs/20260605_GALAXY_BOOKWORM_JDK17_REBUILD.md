# Galaxy image rebuilt on bookworm + JDK 17 — the actual fix

**Date:** 2026-06-05
**Branch:** integration/next-phase @ e2065bd02
**Status:** ✅ Image built + container swapped on dev. Validation in flight.

## What changed

`backend/Dockerfile`:

```diff
-FROM python:3.9-slim
+FROM python:3.9-slim-bookworm
```

One line. Pins the base to Debian 12 bookworm (was implicitly resolving to Debian 13 trixie).

Cascading effects:

| Component | Before (broken) | After (fixed) |
|---|---|---|
| Debian | 13 trixie | **12 bookworm** |
| glibc | 2.41 | **2.36** |
| OpenJDK | 21.0.11 (default-jre-headless resolved to 21) | **17.0.19** (openjdk-17-jre-headless still in apt) |
| Image size | 5.5 GB | 1.83 GB |

## Why this is the real fix

The "publishDir / FileTransfer JVM SIGSEGV" crashes have been the dominant infrastructure failure for weeks. Six independent mitigations applied previously (per-run CRT cache, `-Xss2m`, `-Daws.crt.disable.crt.in.client=true`, FD-decouple, NXF_VER pin, LD_BIND_NOW=1) reduced the crash rate but didn't eliminate it. Empirical: 14/16 parallel-fired workflows crashed within 60s on the trixie+JDK21 image; 1/12 with serial-fire.

The crash signature was always:
```
SIGSEGV (0xb) at pc=..., in ld-linux-x86-64.so.2+0x2475a
software.amazon.awssdk.crt.CRT.extractAndLoadLibrary
```

This is a glibc 2.41 + JDK 21 dlopen race triggered by AWS CRT's native lib extraction. Neither glibc nor JDK 21 is doing anything wrong individually; the combination is the bug.

Bookworm has glibc 2.36 (the prior stable LTS); OpenJDK 17 has a different threading model that doesn't trigger the race. **Either change alone would likely fix it; we got both.**

## Build path

Per `docs/20260513_DEV_INFRASTRUCTURE_REBUILD.md`:

```bash
# Local (laptop)
tar --exclude='database' --exclude='client' --exclude='.venv' \
    --exclude='*.bak*' --exclude='biomni_workflows' ... \
    -czf /tmp/galaxy_build_ctx.tar.gz -C backend .
aws s3 cp /tmp/galaxy_build_ctx.tar.gz \
    s3://biomate-nextflow-work/dev-sync/galaxy_build_ctx.tar.gz

# On dev EC2
sudo aws s3 cp s3://biomate-nextflow-work/dev-sync/galaxy_build_ctx.tar.gz /tmp/
sudo tar -xzf /tmp/galaxy_build_ctx.tar.gz -C /opt/biomate/galaxy_build/
cd /opt/biomate/galaxy_build
sudo docker build -t biomate-galaxy-backend:latest -f Dockerfile .

# Save rollback image
sudo docker commit biomate-galaxy-dev biomate-galaxy-backend:rollback-pre-bookworm

# Container swap
sudo docker stop biomate-galaxy-dev && sudo docker rm biomate-galaxy-dev
sudo docker run -d --name biomate-galaxy-dev \
    --network biomate-dev-net \
    --env-file /opt/biomate/.env \
    -p 8081:8080 \
    --restart unless-stopped \
    biomate-galaxy-backend:latest
```

Build took ~3 minutes (was faster than the doc's ~15 min estimate because most layers cached).

## What needed fixing along the way

| Issue | Fix | Commit |
|---|---|---|
| `python:3.9-slim` resolved to trixie (glibc 2.41) | Pin to `python:3.9-slim-bookworm` | `e2065bd02` |
| `openjdk-17-jre-headless` not in trixie apt | Bookworm has it — solved by #1 | (same) |
| `pdfplumber>=0.11.9` transitively needs `pdfminer.six==20251230` (not on PyPI) → ResolutionImpossible | Downgrade pin to `pdfplumber==0.11.8` | `e2065bd02` |
| cipa_cardiac_safety_ode `\'O\'Hara\'` inside single-quoted Python string → SyntaxError when groovy unescapes | Switch 3 lines to double-quoted strings | `e2065bd02` |

## Rollback path (if anything breaks)

```bash
ssh dev '
  sudo docker stop biomate-galaxy-dev && sudo docker rm biomate-galaxy-dev
  sudo docker run -d --name biomate-galaxy-dev \
    --network biomate-dev-net \
    --env-file /opt/biomate/.env -p 8081:8080 --restart unless-stopped \
    biomate-galaxy-backend:rollback-pre-bookworm
'
```

The `:rollback-pre-bookworm` tag captures the running container's state at the moment before swap (including any database changes since image build 3 weeks ago).

## What's pending

- Validating the JVM doesn't crash any more on real Nextflow runs (monitor `bzcg8igb2` is firing `physicell_tumor_tgi` as the litmus test — that one always crashed on the old image).
- Re-running the 19-workflow sweep to compare pre/post crash rates.
- After confirmation, the 6 CRT mitigation flags in `nextflow_executor.py` become safely removable (defense in depth they were never proven to be).
- The 8 unreached failures from the prior serial sweep need re-triage with the new image — their rc=1 may have been JVM-related too.

## Files / commits

- `backend/Dockerfile` (this commit)
- `backend/lib/galaxy/dependencies/pinned-requirements.txt` (symlink target of `backend/requirements.txt`)
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/cipa_cardiac_safety_ode/main.nf`
- `docs/20260605_SERIAL_FIRE_BREAKTHROUGH.md` — empirical data that prompted this fix
- `docs/20260605_19_WORKFLOW_SWEEP_RESULT.md` — parallel-fire 0/19 result

---

## Update 2026-06-06 — JDK17 + bookworm did NOT fix the AWS CRT crash

Post-rebuild empirical test: `physicell_tumor_tgi` single-fire on bookworm + JDK 17.0.19 still crashes the JVM at publishDir.

```
SIGSEGV (0xb) at pc=..., in C [ld-linux-x86-64.so.2+0x224ba]
JRE version: OpenJDK Runtime Environment (17.0.19+10)
Java VM: OpenJDK 64-Bit Server VM (17.0.19+10-1-deb12u2-Debian)
Host: Debian GNU/Linux 12 (bookworm), glibc 2.36
Current thread: JavaThread "PublishDir-3"
Java stack: software.amazon.awssdk.crt.CRT.extractAndLoadLibrary
```

The crash hits at slightly different `ld-linux` offset (`+0x224ba` vs trixie's `+0x2475a`), but the same library, same Java stack, same code path: `S3CrtAsyncClient.<init>` → `CRT.<clinit>` → `extractAndLoadLibrary()` → `System.load()` → glibc dlopen → SIGSEGV.

**The bug is in AWS CRT native lib's extract+load sequence, not in glibc.** Multiple glibc versions (2.36 bookworm, 2.41 trixie) and multiple JDK versions (17.0.19, 21.0.11) all crash the same way.

This means:
- Tier 3 item #10 (eliminate publishDir + replace S3 transfer client) is the ONLY actual fix.
- The JDK + base-image changes are still worthwhile (Galaxy boots in 60s vs 5-15 min, image is 1.83GB vs 5.5GB, smaller attack surface) but do NOT address the JVM SIGABRT class.
- The 6 mitigation flags (Xss2m, LD_BIND_NOW, aws.crt.lib.dir, aws.crt.disable.crt.in.client, NXF_VER, FD-decouple) reduce frequency but cannot eliminate it.
- Serial-fire (concurrency ≤ 1) is the only operational mitigation today.

## What now actually has to happen

Re-prioritise Tier 3 #10 from `docs/20260604_BATCH_ROBUSTNESS_TEAM_DISCUSSION.md` to be **the next sprint** item, not strategic-quarter:

1. Disable `publishDir` in the generated `nextflow.config` for AWS Batch runs.
2. Implement a Galaxy-side post-task sweep: when `workflow-trace.txt` shows COMPLETED, use boto3 (or `aws s3 sync` subprocess — no CRT) to copy from `s3://.../work/<hash>/` to `s3://.../outputs/<run_id>/`.
3. Galaxy's existing `run:<runId>:datasets` URI handler already lists from S3 directly via boto3 — that's the proven non-CRT path.
4. For input staging (the FileTransfer crash class), use `aws.batch.cliPath` (already configured) to pull inputs on the Batch host via AWS CLI; have Nextflow's local FS executor not touch S3 at all.

These changes are scoped in `docs/20260604_BATCH_ROBUSTNESS_TEAM_DISCUSSION.md` Tier 3 #10. ~365 LOC, ~3 days.

## What we DID gain from the rebuild

Not zero — just not the JVM crash fix:

- Galaxy cold-boot 60s on bookworm (vs 5-15 min on trixie). Useful.
- Image 1.83GB vs 5.5GB. Useful.
- Pre-cached NF jar at `/opt/nextflow/framework/25.10.5/`. Useful as plugin pre-bake foundation.
- `ENV NXF_VER=25.10.5` baked into the image. Defense in depth against drift to NF 26.04.
- Test guards (`backend/tests/test_nextflow_version_pin.py`) added.

The rebuild itself was the right call — it just doesn't end the JVM crash story.
