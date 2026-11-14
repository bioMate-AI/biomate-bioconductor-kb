# 2026-11-14 — reinvent4-nf:x86 ECR rebuild

## Result

| Field | Value |
|-------|-------|
| **Push** | **success** |
| **URI** | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/reinvent4-nf:x86` |
| **Also tagged** | `:latest`, `build-i-08232195bc858e990` |
| **Digest** | `sha256:0c798092f9c8591d3bf9abdd50b6875be3c503e9c733731de694d62117f036af` |
| **Pushed at** | 2026-11-14T11:29:17-06:00 |
| **Size** | ~1.47 GiB (was ~422 MiB on Nov-10 `sha256:443e2e6e…`) |
| **Builder** | on-demand `c6i.2xlarge` `i-08232195bc858e990` (`biomate-reinvent4-nf-builder`), terminated after push |

## Verified on deploy-test pull (Batch shape)

```
PATH includes /opt/conda/bin
env -i PATH=/opt/conda/bin:/usr/local/bin:/usr/bin:/bin reinvent --help → BATCH_CLI_OK
/opt/reinvent4/priors/reinvent.prior          23M
/opt/reinvent4/priors/reinvent_pubchem.prior  23M
/opt/reinvent4/priors/libinvent.prior         91M
/opt/biomate/reinvent_runner.py present
/opt/biomate/drug_discovery/reinvent4_runtime.py present
```

Image also retains `/opt/REINVENT4` (git tree on `PYTHONPATH`) so the synced Galaxy `main.nf` runtime bridge remains compatible.

## Process notes

- Proxies/SOCKS cleared; `NO_PROXY='*'`.
- Local Docker Desktop absent / disk ~4 GiB free → used EC2 builder (same pattern as `scripts/build_mlip_md_image.sh`).
- Build context uploaded to `s3://biomate-nextflow-work/reinvent4-nf/`.
- Script added for repeats: `scripts/build_reinvent4_nf_image.sh` (`BUILD_MODE=ondemand|spot|host`).
- Stashes/WIP left intact; `reinvent4_runtime.py` was read from `stash@{17}` into the build context only (stash not popped).

## Remaining verify (live re-measure **still needed**)

ECR fix removes Batch dependence on missing CLI / empty priors. Confirm end-to-end:

1. Re-run coldstart / design harness case `design-generate-sm-0` (or equivalent REINVENT4 lead-design) on AWS Batch.
2. Expect `GENERATE_REINVENT4` past exit 3; molecules written (not `CLI/package not found` / `HONEST_FAIL`).
3. Optional: confirm task no longer needs runtime Zenodo fetch (priors already under `$REINVENT4_PRIORS`).

Galaxy `main.nf` bridge from ledger `9fb3c6f302` remains a safety net until that live run is green.
