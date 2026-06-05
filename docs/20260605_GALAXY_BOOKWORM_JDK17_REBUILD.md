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
