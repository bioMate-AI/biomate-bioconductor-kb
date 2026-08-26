# RStudio Interactive Tool — Working on dev (2026-08-22)

**Status:** ✅ WORKING end-to-end. Launch → per-session routing → RStudio Server **IDE loads
straight in** (no sign-in) on `https://dev-public.biomate.ai/interactive/<token>/`.
**Image:** the **stock** `quay.io/galaxy/docker-rstudio-notebook:23.1` — no custom image needed.
**Continues:** `docs/20260817_MULTISESSION_INTERACTIVE_TOOLS.md`, `docs/20260615_RSTUDIO_IT_DISABLED_ON_DEV.md`.

## TL;DR — it was three basic Galaxy-config mistakes, not the image

RStudio had "never worked" on dev. It turned out Galaxy essentially ships RStudio; the stock image is
fine. The container kept dying ~15 s after launch. Root causes, in order of discovery:

1. **Wrong destination (the big one).** Galaxy's `job_conf` `tools:` **tool-id matching is EXACT,
   not regex.** The rule `interactive_tool_.*` never matched anything, so every interactive tool fell
   through to the default `docker_local` destination — which sets `--user $UID`. Jupyter tolerates
   `--user 1000:1000` (its image default *is* jovyan/1000); RStudio does not.
2. **`--user` breaks RStudio.** The stock image uses **s6-overlay v2**, which requires **root**. Under
   `--user 1000:1000` the job stderr shows `s6-supervise (child): fatal: unable to exec run:
   Permission denied` in a loop, the tool script exits 1, and Galaxy fails+kills the container (~15 s).
3. **`docker_set_user` must be explicitly empty.** *Absence* of `docker_set_user` **defaults to
   `$UID`** — it does not mean "no user". Only `docker_set_user: ''` disables `--user`.

## The fix (all in `backend/config/job_conf.yml`)

```yaml
    # runs interactive containers as their image default user (root for rocker/rstudio)
    docker_interactive_root:
      runner: local
      docker_enabled: true
      docker_auto_rm: true
      docker_set_user: ''        # empty string REQUIRED to disable --user (absence => $UID)
      docker_volumes: $job_directory:rw,$working_directory:rw,$default_file_path:rw
      docker_run_extra_arguments: -e MPLCONFIGDIR=/tmp -e HOME=/tmp -e DISABLE_AUTH=true
tools:
  # EXACT ids — job_conf tool matching here is not regex
  - id: interactive_tool_rstudio
    environment: docker_interactive_root
  - id: interactive_tool_rstudio_bioc_3.20
    environment: docker_interactive_root
```

`DISABLE_AUTH=true` (honored by the image → writes `auth-none=1` into `rserver.conf`) makes RStudio
open straight into the IDE; the session is already gated by BioMate auth + the per-token proxy.

## Proxy piece (`frontend/server/routes.ts`, the `/interactive` proxy)

RStudio's tool XML declares `requires_path_in_header_named="X-RStudio-Root-Path"`, so the proxy sends
that header per request → RStudio emits per-session URLs. It also now sends `X-Forwarded-Host` /
`X-Forwarded-Proto: https` and **rewrites RStudio's absolute internal-host redirects**
(`https://172.19.0.1:<port>/…`) back to the public host, so the browser stays on
`dev-public.biomate.ai` instead of being bounced to the internal gateway address.

## Verified

```
launch interactive_tool_rstudio → /interactive/<token>/
GET /interactive/<token>/            → 302 → …/auth-sign-in (auth-none auto-passes)
final page                            → <meta name="gwt…"> + rstudio.nocache.js 200  (the GWT IDE)
/interactive/<token>/rpc/client_init  → 200  (live RStudio session RPC)
redirect Location host                → https://dev-public.biomate.ai/…  (not 172.19.0.1)
```

## What was NOT needed (removed)

A custom `biomate/rstudio-biomate` image (rocker + Bioconductor) was built and pushed to ECR, then
transported to the dev host via S3 (the dev host can't reach the ECR API endpoint — connect timeout to
`api.ecr.us-west-2.amazonaws.com`, a VPC egress limitation) and `docker load`ed. **None of this was
necessary** — the stock image works once routed to root. The ECR/S3 repoint has been removed from
`sync_to_dev.sh :: enable_interactive_tools`. The custom image remains in ECR
(`biomate/rstudio-biomate:latest`) as a *future enhancement* if we want DESeq2/edgeR/clusterProfiler
preinstalled — but it needs the same job_conf root routing, and to be pullable the dev host needs ECR
network reachability (NAT/VPC endpoints) or the S3 side-load.

## Gotchas for next time
- `docker_set_user: ''` (empty) to disable `--user`; absence ≠ disabled.
- `job_conf` `tools:` id match is exact — list exact tool ids, not `.*`.
- A gunicorn HUP does **not** reliably reload job-destination config; use `galaxyctl restart` (full).
- s6-overlay v2 images (rocker/rstudio) require root.
- Every normal sync replaces `universe.sqlite` + restarts galaxy (wipes IT sessions); host `/app`,
  the docker socket, nginx WS config, and loaded images persist.

## CellxGene — also working (2026-08-23)

CellxGene works end-to-end too: launch → per-token proxy → **`<title>CELL×GENE | Annotate</title>`**,
HTTP 200, single-cell viz UI serving the dataset. Fixes:
1. **Port 80** added to the proxy's container-port probe (`targetForToken`) — cellxgene serves on 80.
2. **`infile` mapping** (`/api/interactive/launch`): map the first selected `dataset_ids` entry to the
   tool's `infile` param (`{src:'hda', id}`); 400 if none selected (cellxgene visualizes a *specific*
   dataset and Galaxy rejects the launch without it).
3. **Root routing** — port 80 is privileged, so `interactive_tool_cellxgene` → `docker_interactive_root`.

**⚠️ anndata version wall (real-user issue).** cellxgene `1.1.1` (`quay.io/biocontainers/cellxgene:
1.1.1--pyhdfd78af_0`) bundles **anndata 0.8.0**. h5ads written by modern anndata (0.10+) use the
`nullable-string-array` encoding, which 0.8.0 has no reader for → cellxgene reports the generic
`"File must be an .h5ad object"` (real error: `KeyError(..., IOSpec(encoding_type=
'nullable-string-array', ...))`). Verified by writing a test h5ad with cellxgene's *own* anndata 0.8.0 →
loads + renders fine. **For real scanpy-produced h5ads, bump the cellxgene image to a newer tag
(newer anndata) or convert/downgrade the h5ad on ingest.** The plumbing (launch, routing, port,
proxy, infile) is done and durable in `job_conf.yml` + `routes.ts`.
