# Isolation · Private Deployment · Scheduler — Implementation Roadmap

**Date:** 2026-08-13
**Branch:** `feat/compute-platform-v2` (cut from `integration/next-phase`)
**Author:** engineering (session-authored)
**Status:** Phase 0 skeleton in progress

---

## Motivation — three verified capability gaps

A code-grounded review (2026-08-13) confirmed three real gaps. File:line
references are against `integration/next-phase` at the time of writing.

### ① Sandbox isolation — weakest link
- Production workflows (`NEXTFLOW_USE_AWS=true`) route to AWS Batch and get
  container/ECS-task isolation — OK.
- **Local execution + user-uploaded `.nf`** run as a bare
  `subprocess.Popen()` under the backend process identity — no container,
  no seccomp/gVisor, no egress limits.
  See `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — user
  `.nf` written to `/tmp/biomate_user_nf/{user_tag}/` (~L4664) then launched
  via `subprocess.Popen(...)`.
- Upload handler `POST /api/workflows/upload-file`
  (`frontend/server/routes.ts`) stores raw `file_content` with **no
  validation**.
- Multi-tenancy is only per-user S3 prefixes
  (`outputs/{user_id}/{run_id}`). Local filesystem is shared; interactive
  tools (Jupyter/RStudio) have no session-level isolation or resource caps.
- **Verdict:** safe only for trusted enterprise / single-tenant. Not safe
  for multi-tenant public SaaS with arbitrary-code execution.

### ② Private deployment — "private within AWS" yes, "off-AWS / air-gap" no
- Terraform (`infra/terraform/`), `docker-compose`, external env
  (`/opt/biomate/.env` + Secrets Manager) → private deploy inside a
  customer's own AWS VPC is feasible.
- **AWS is a hard dependency:** 9× `import boto3` in the executor; S3 +
  Batch + RDS + Redis are load-bearing; Nextflow fetches the `nf-amazon`
  plugin online (executor unsets `NXF_OFFLINE`). Full air-gap does not run
  today.
- No Helm/K8s — EC2 + docker-compose only.
- **Verdict:** can deliver private in-customer-AWS; cannot deliver pure
  on-prem / 信创 / offline yet.

### ③ Local↔remote dispatch — a switch, not a scheduler
- Single global flag `NEXTFLOW_USE_AWS`: true → all Batch, false → all
  local. No per-job selection.
  See `nextflow_executor.py` routing block ~L4783–4872.
- Memory tiers exist (`process_low/medium/high/high_memory` =
  12/36/72/200 GB, `process_gpu` = 8 vCPU/32 GB + GPU) but are hardcoded by
  Nextflow process label, not chosen from measured demand
  (~L2407 in `_generate_executor_config`).
- No local↔remote failure fallback, no cost/speed optimizer, no hybrid
  scheduling.
- **Verdict:** "automatic dispatch" does not exist — only a manual flag.

---

## Architectural spine — the key decision

All three features are changes to **which backend executes and how**.
Rather than rewrite the routing logic three times, we introduce one shared
abstraction and hang all three features off it:

```
Phase 0  Compute/Storage backend abstraction
         (ComputeBackend / StorageBackend / RunSpec / Scheduler skeleton)
   │  ——— common prerequisite; behind feature flag; default behavior unchanged
   ├──────────────┬───────────────────┬────────────────────┐
   ▼              ▼                    ▼                    ▼
 ① Sandbox     ② Private (AWS)      ② Private (air-gap)   ③ Scheduler
 SandboxedLocal Terraform param     MinIO/Slurm/K8s        Scheduler policy
 Backend        + Batch in TF       + offline plugins      + cost model
                                    + install kit          + fallback
```

- **Sandbox** = a new `SandboxedLocalBackend` (container/microVM wrapper).
- **Private deploy** = swappable backends (`AWSBatch`→`Slurm`/`K8s`,
  `S3`→`MinIO`).
- **Scheduler** = `Scheduler.select_backend()` upgraded from boolean switch
  to capability/cost scoring + fallback.

---

## Phase 0 — Compute/Storage abstraction spine (2–3 weeks) — PREREQUISITE

**Deliverables**
1. `RunSpec` — normalized resource/routing descriptor (cpus, mem, gpu,
   est_data_gb, data_locality, needs_network, trust_level + the current
   routing inputs).
2. `ComputeBackend` Protocol — `submit / poll / cancel / collect_outputs`.
   Wrap the existing two paths as `LocalSubprocessBackend` and
   `AWSBatchBackend` with **identical behavior**.
3. `StorageBackend` Protocol — `S3Backend` today, `endpoint_url` parameter
   reserved for MinIO.
4. `Scheduler.select_backend(spec)` — v1 is **logic-equivalent** to today's
   `NEXTFLOW_USE_AWS` + personal-workflow + S3-autodetect decision.
5. Feature flag `COMPUTE_BACKEND_V2` (default off). **Shadow mode**: when
   on, compute the new scheduler's decision alongside the legacy decision
   and log agreement — never act on it. Zero behavior change either way.

**Acceptance:** the 4 domain real runs (ADMET / RNA-seq / WGS / CryoEM)
produce identical routing under shadow mode; scheduler decision matches
legacy on every case. This is the only high-risk refactor — lock down
zero-regression here before anything is switched over.

---

## Feature ① Sandbox (3–5 weeks) — keep arbitrary code + real sandbox

**Tiered threat model (configurable strength):**

| Tier | Isolation | Use |
|---|---|---|
| **1 (default)** | rootless Podman/Docker per run: userns remap, `--cap-drop ALL`, `no-new-privileges`, default seccomp, read-only rootfs + tmpfs workdir, cgroups v2 cpu/mem/pids caps (from RunSpec tier) | trusted enterprise |
| **2** | Tier 1 + egress default-deny, allowlist via proxy (package mirrors + reference data), netns + iptables | multi-tenant SaaS default |
| **3** | gVisor (`runsc`) runtime or Firecracker microVM/run (kernel-level) | untrusted code |

**Work**
1. `SandboxedLocalBackend` (on Phase 0): launch head + tasks inside a
   sandbox container instead of bare subprocess. Nextflow native
   `-with-podman`/`-with-docker` for task layer; head wrapped too.
2. Per-run ephemeral workdir + per-run UID — remove the shared
   `/tmp/biomate_user_nf` cross-run surface. Mount only that run's inputs.
3. Upload static pre-check (defense in depth, not the boundary): AST/lint
   the `.nf`, reject obvious escapes (`--privileged`, mount `/`, curl|bash
   to internal IPs, absolute host paths). Add at upload handler + pre-exec.
4. Interactive tools: cgroup cpu/mem caps, egress policy, idle-timeout
   reaping, per-session netns.
5. `run_code` tool routed through the sandbox backend.
6. Config `SANDBOX_TIER=1|2|3`, defaulted by deployment mode.

**Acceptance:** an escape test-suite (read host `/etc/shadow`, reach
`169.254.169.254`, fork bomb, write host FS) is fully blocked; the 4
domains are unaffected.

---

## Feature ② Private deployment — two sub-targets

### ②-A Private inside customer AWS (2–3 weeks) — ship first

**Work**
1. Terraform refactor: promote hardcoded `envs/test` values into a reusable
   root module + per-customer `.tfvars`; drop hardcoded VPC/instance IDs;
   provision RDS/Redis/S3/Batch/IAM inside the customer's VPC.
2. Bring AWS Batch compute environments + queues (incl. GPU spot) into
   Terraform (currently manual/implicit).
3. Package a customer bootstrap: one `.tfvars` + one `deploy.sh` stands up
   the full stack; data never leaves the customer VPC.

### ②-B Air-gap / on-prem / 信创 (4–6 weeks)

**Work (all on Phase 0 abstraction)**
1. `MinIOStorageBackend` (S3-compatible via `endpoint_url`; verify Galaxy
   objectstore + every executor S3 call honors the override).
2. `SlurmBackend` / `K8sBackend` (Nextflow native slurm/k8s executors).
3. Offline Nextflow plugins: bake `nf-amazon`/`nf-minio`/local into the
   image `NXF_HOME` plugin cache; set `NXF_OFFLINE=true`; stop unsetting it.
4. Secrets provider abstraction in `deploy.sh` (Secrets Manager →
   env-file/Vault).
5. Offline image + data kit: mirror ECR to customer registry; provide
   `docker save/load` bundle + workflow DB + embeddings `.npz` + reference
   data bundle.
6. Delivery form: Helm chart + air-gap install guide.

**Acceptance:** on a network-isolated host with MinIO + local Postgres +
local Redis + Slurm/K8s, RNA-seq (deseq2) runs green with real DE results.

---

## Feature ③ Full scheduler (3–4 weeks) — cost/speed + hybrid

**Work (on Phase 0 Scheduler skeleton, upgraded incrementally)**
1. Resource estimator: derive `RunSpec` from the workflow (process labels →
   cpu/mem/gpu; input sizes → est runtime/data; data location → local vs S3
   vs on-prem). Replaces the global flag.
2. Backend registry + capability/cost model: each backend registers
   `has_gpu / max_mem / $-per-vCPU-hr / queue depth / data locality`
   (local, Batch spot/on-demand, Slurm, K8s); wire spot pricing.
3. Policy engine: weighted score per job (cost × speed × locality); respect
   user/plan constraints (free tier → local only; data-residency → on-prem
   only).
4. Capacity awareness: query Batch queue depth + local semaphore
   utilization; prefer idle.
5. Failure fallback: on backend failure / queue timeout, re-dispatch to the
   next-best backend (with `-resume` where possible); per-backend circuit
   breaker. Fills the missing local↔remote fallback.
6. Hybrid scheduling: split a workflow — light preprocessing local, heavy /
   GPU steps remote — via Nextflow per-process executor mapping (config
   already supports it; the scheduler generates the process→executor table).
7. Observability: per-run "why this backend" decision log; est-vs-actual
   cost into existing Lago billing.

**Acceptance:** with no manual flag, GPU jobs auto-route to the GPU queue,
small jobs stay local, jobs fall back when the Batch queue is saturated,
and the cost-decision log is explainable.

---

## Sequencing & timeline

| Milestone | Content | Duration | Unlocks |
|---|---|---|---|
| **M0** | Phase 0 spine (zero-regression refactor) | 2–3w | everything |
| **M1** | ① Sandbox Tier 1+2 + ②-A private-in-AWS | 3–4w (parallel) | multi-tenant + first private pharma customer |
| **M2** | ③ Scheduler (rules→scoring→fallback→hybrid) | 3–4w | real local/remote auto-dispatch |
| **M3** | ① Sandbox Tier 3 + ②-B air-gap/K8s | 4–6w | 信创 / on-prem / medical hard requirements |

Total ≈ 3–4 months single-threaded; M1 items parallelizable.

---

## Discipline (per CLAUDE.md)

- Every step behind a feature flag, default = old behavior. Phase 0 must
  prove zero regression on all 4 domains before anything switches over.
- No production workflow-file edits for scheduling/benchmark reasons.
- Sandbox escape cases are real attack tests, never mocked.
- Each milestone appends a dated `docs/*.md` progress note.

---

## Progress log

- **2026-08-13** — Roadmap authored. Branch `feat/compute-platform-v2` cut
  from `integration/next-phase`. Phase 0 skeleton started:
  `backend/lib/galaxy/ai/compute/` (`run_spec`, `backends/`, `storage/`,
  `scheduler`), flag `COMPUTE_BACKEND_V2` (default off, shadow-mode only).
  Committed `b1b8de6d6`, pushed.

- **2026-08-13 (M0.1)** — Head-launch primitive extracted.
  `nextflow_executor._launch_nextflow_head` is now the single, named,
  overridable launch seam (semaphore → FD-decoupled Popen → set_pid →
  slot-release reaper); the legacy path calls it (byte-identical extraction,
  plus a latent `_slot_acquired` NameError hardened). Defined the head-launch
  seam in the compute package (`launcher.py`: `LaunchRequest`,
  `HeadLauncher` Protocol, `CallableHeadLauncher`, default-launcher
  registry) and a `HeadLaunchMixin` so `Local`/`AWSBatch` backends share one
  launch path; the executor registers `_launch_nextflow_head` as the default
  launcher (guarded). Self-tests: scheduler parity 7/7, launcher wiring 7/7,
  py3.9 imports clean. **Not yet verified end-to-end** — full-module import
  needs `a2wsgi` (absent here) and this sandbox can't sync to dev; E2E on the
  4 domains is required before trusting the extraction in production.

  **M0.2 (next, E2E-gated):** extract the executor-config / command
  generation into `LocalSubprocessBackend.submit()` /
  `AWSBatchBackend.submit()` (the part where local/awsbatch/slurm/k8s
  actually diverge), then add a `COMPUTE_BACKEND_V2=active` mode that routes
  through `Scheduler.select_backend` + `backend.submit()`. This touches the
  launch monolith's config path and MUST be done in a session with dev sync
  + E2E on ADMET / RNA-seq / WGS / CryoEM (no speculative deploys — see
  CLAUDE.md).

- **2026-08-14 (Feature ① sandbox — core shipped)** — Built the sandbox on
  the M0.1 seam: `backend/lib/galaxy/ai/compute/sandbox/`.
  - `config.py` — `SandboxTier` (1/2/3) + `SandboxConfig.from_env` (all
    `SANDBOX_*` env; per-run non-root UID derived from run_id; cgroup caps
    sized from the RunSpec tier); secret-env markers + safe allowlist.
  - `command.py` — `build_sandbox_command` wraps the **whole head** in
    `docker/podman run` with `--cap-drop ALL`, `--security-opt
    no-new-privileges`, `--read-only` + bounded tmpfs, `--user` non-root,
    `--cpus/--memory/--pids-limit`, `--network` (tier2 none/egress-net),
    `--runtime runsc` (tier3 gVisor), bind-mount ONLY the run's workdir (rw)
    + the .nf (ro). `filter_container_env` strips AWS/LLM/DB/billing/token
    creds so they never reach untrusted code.
  - `validator.py` — static `.nf` pre-check (block: privileged, host-root/
    docker-sock mount, docker-in-docker, metadata-IP SSRF, /etc/shadow &
    ~/.aws creds read, curl|bash, Groovy Runtime.exec/ProcessBuilder).
    Defense in depth — NOT the boundary.
  - `launcher.py` — `SandboxedHeadLauncher` *decorates* the base launcher
    (rewrites cmd → sandboxed argv, delegates), reusing all M0.1 concurrency/
    log/pid/orphan machinery.
  - Wired flag-gated into `nextflow_executor` (default `SANDBOX_ENABLED`
    off → zero change): upload static pre-check + `_maybe_sandboxed_launch`
    at the launch site, **fail-closed** (sandbox error never falls back to a
    naked subprocess). Self-tests: 53/53 sandbox + 7/7 parity + 7/7 launcher,
    py3.9 imports clean.

  **Feature ① remaining (not in this commit):**
  1. ~~Build the `biomate-nextflow-sandbox` image~~ — DONE (2026-08-14, below).
  2. **Real E2E** — the 4 domains under `SANDBOX_ENABLED=true` (full workflow
     paths), + gVisor tier3 (test host has no runsc). Sandbox *mechanism* is
     now validated (below); the 4-domain workflow runs still need dev-sync.
  3. **`run_code` tool** — route its Python/R exec through the same sandbox
     (separate code path from nextflow_executor).
  4. **Interactive tools** (Jupyter/RStudio GIE) — add cgroup caps, egress
     policy, idle-timeout reaping, per-session netns.
  5. Author a **custom seccomp profile** + optional Firecracker tier-3b.

- **2026-08-14 (Feature ① — sandbox image built + validated on TEST)** —
  `docker/sandbox/Dockerfile`: FROM `biomate-nextflow-base` (Debian 13,
  python3+awscli+rdkit) + openjdk-21-jre-headless + Nextflow 25.10.5. Under a
  read-only rootfs Nextflow needs a writable NXF_HOME, so the framework is
  baked into a read-only `/opt/nxf_seed` and an entrypoint seeds a writable
  NXF_HOME on tmpfs at start (offline, no runtime download). Built ON THE
  TEST box (i-0482a6fa98c6f301a) via SSM — never dev/prod
  (i-06696b0d…, customer-facing) — and pushed to ECR
  `biomate-nextflow-sandbox:latest` (577 MB; nothing pulls it without
  `SANDBOX_ENABLED`). SandboxConfig default image updated to the ECR URI.

  **Validated on test with the exact flags command.py emits**
  (`--rm --cap-drop ALL --security-opt no-new-privileges --read-only
  --tmpfs /tmp --user 20001:20001 --cpus 2 --memory 12g --pids-limit 512
  --network none`):
  - nextflow -version → 25.10.5 ✓
  - local `hello.nf` run → **NF_EXIT=0**, task executed, output produced ✓
  - read-only rootfs enforced (touch /root denied) ✓
  - `--network none` → 169.254.169.254 unreachable ✓
  - non-root uid=20001 ✓
  - cap-drop → mknod "Operation not permitted" ✓
  - test host has NO gVisor (`runsc`) → tier 3 not exercisable there.

- **2026-08-14 (Feature ① — tier 3 gVisor validated on TEST)** — Installed
  gVisor (`runsc release-20260810.0`) on the test box (i-0482a6fa98c6f301a)
  via SSM and registered it as a Docker runtime with `runsc install` +
  `systemctl reload docker` (reload, NOT restart — existing test containers
  untouched). `docker info` Runtimes now lists `runsc`. Validated tier 3:
  - `docker run --runtime=runsc … uname -r` → `4.19.0-gvisor`; `dmesg` →
    "Starting gVisor..." (kernel interception confirmed).
  - `hello.nf` under `--runtime=runsc` + the full tier flags + `--network
    none` → **NF_EXIT=0**, task executed, output produced.

  All three tiers are now proven on real infra: tier 1 (container isolation),
  tier 2 (+ egress none), tier 3 (+ gVisor).

- **2026-08-14 (integration proof + two real bugs fixed)** — Ran the ACTUAL
  `build_sandbox_command` output (not hand-typed flags) for all 3 tiers on
  test. Caught two bugs the self-tests couldn't:
  1. `filter_container_env` forwarded host `PATH` → clobbered the image PATH →
     `nextflow` not found → exit 127. Fixed with `IMAGE_OWNED_ENV` (PATH/HOME/
     NXF_HOME/JAVA_HOME/CAPSULE_CACHE_DIR/NXF_OFFLINE dropped; image owns them).
  2. `run_uid` used builtin `hash()` (PYTHONHASHSEED-salted, non-deterministic
     across processes) → switched to `hashlib.sha256`. Re-ran all 3 tiers with
     the fixed shipped-code argv → NF_EXIT=0 each. (commit 75d1c4f6f)

- **2026-08-14 (Feature ① — run_code hardened to parity)** — `run_code`
  (frontend/server/code-runner.ts) already sandboxed (docker `--network=none`
  `--memory` `--cpus` `--user` non-root, minimal env — no cred leak). Added
  the missing hardening to parity with the Nextflow sandbox: `--cap-drop ALL`,
  `--security-opt no-new-privileges`, `--pids-limit` (default ON — safe for
  compute); `--read-only`+tmpfs (`RUN_CODE_READONLY`) and gVisor
  (`RUN_CODE_RUNTIME` / `SANDBOX_TIER>=3`) opt-in. Mirrored into the sidecar
  contract. Validated on test: default + strict(gVisor+read-only) → EXIT=0,
  output written. tsc clean.

- **2026-08-14 (Feature ① — LIVE on test: complete BioMate in sandbox mode)** —
  Deployed the sandbox into the running test backend and ran a real workflow
  through the live API, fully sandboxed. Method (all on test i-0482, never
  dev/prod):
  - Test backend code is baked in the image (`dev-backend:sha-c7f5ee5eb806`,
    a divergent lineage — 9279 lines vs my branch's 9911) and NOT bind-mounted.
    So: pulled test's exact executor, confirmed the patched regions are
    byte-identical to my branch base, and applied my executor diff with
    `git apply` (clean). Built a **thin overlay image**
    `dev-backend:sandbox-test` = FROM the current test image + docker CLI
    (static 27.3.1) + `galaxy` added to the docker-socket group (gid 988) +
    the patched executor + the compute package. Real module import verified
    inside the image (`IMPORT_OK`+`COMPUTE_OK`, full galaxy deps, py3.9).
  - Solved two docker-out-of-docker issues: **volume-path alignment**
    (identity-mount `/tmp/nextflow_runs` + `/tmp/biomate_user_nf` so host and
    backend see the same paths) and **uid alignment** (`SANDBOX_RUN_UID=1000`
    so the sandbox writes the backend-owned work dir).
  - Deployed via a compose **override** (`docker-compose.sandbox.yml`):
    sandbox image + docker.sock + identity mounts + `SANDBOX_ENABLED=true
    SANDBOX_TIER=2 SANDBOX_RUN_UID=1000 SANDBOX_IMAGE=<ecr>`. Backend healthy;
    `BACKEND_CAN_DOCKER` confirmed. Config backed up.
  - **E2E through the live API**: `POST /api/nextflow/execute` with a personal
    `.nf` → `[sandbox] run … → tier-2 container (net=none, cpus=2, mem=12g)` →
    status **succeeded, returncode 0**, task output `sandboxed-on-test-1000`
    (ran as uid 1000 inside the sandbox, output read back by the backend).
  - Batch workflows unaffected (NEXTFLOW_USE_AWS=true unchanged;
    `_maybe_sandboxed_launch` returns None for awsbatch → identical path).

  **Rollback (one step):** `cd /opt/biomate && rm docker-compose.sandbox.yml &&
  BACKEND_IMAGE=…/dev-backend:sha-c7f5ee5eb806 docker compose -f
  docker-compose.deploy.yml up -d galaxy-backend-deploy`. Backups:
  `.env.bak.sandbox.*`, `docker-compose.deploy.yml.bak.sandbox.*`.

- **2026-08-14 (Feature ① — heavy R/bioc sandbox image LIVE on test)** —
  Built `biomate-nextflow-sandbox:heavy` (`docker/sandbox/Dockerfile.heavy`,
  FROM `bioc-domain-general:3.20-mofa2` = R+Bioconductor+python+java + the
  same Nextflow-runner hardening). Validated under real isolation flags: R
  workflow tier-2 (network none) NF_EXIT=0 (`mean=0.03`) and tier-3 (gVisor)
  NF_EXIT=0. Pushed to ECR; switched test `SANDBOX_IMAGE` → heavy; backend
  recreated healthy. **Live-API E2E**: `POST /api/nextflow/execute` with an R
  personal `.nf` → `[sandbox] run … → sandbox:heavy` → succeeded, output
  `R-sandboxed-ok mean=-0.022 uid=1000`. Local user workflows needing R/bioc
  now run fully sandboxed on test.

- **2026-08-14 (Feature ① — run_code hardening LIVE on test)** — First
  attempt (rebuilding the server bundle from my branch source) crash-looped
  the frontend — the deployed frontend is an OLDER commit
  (`dev-frontend:sha-2c42bc9e6c0b`) than my branch, so a from-source bundle
  diverged. Reverted immediately (site restored). Correct approach: patch the
  **deployed bundle in place** — `docker cp` its `dist/index.js`, inject the
  hardening tokens into the run_code `dockerArgs` array (after `"--rm"`:
  `--cap-drop ALL`, `--security-opt no-new-privileges`, `--pids-limit 512`) —
  exactly one match, `node --check` passes → zero divergence. Built
  `dev-frontend:sandbox-test2` (FROM the deployed image + patched bundle),
  deployed with docker.sock + identity-mount `/tmp/biomate_code` +
  `RUN_CODE_IMAGE=heavy`. Frontend healthy, site HTTP 200.
  **E2E via the PUBLIC domain** (`POST /api/code/run`):
  - python → `uid:0`, **`NET:blocked-by-sandbox`** (network none proven),
    exit 0, output file written.
  - R → `mean=-0.036`, exit 0, output file written (heavy image has R).
  - running bundle confirms `cap-drop` + `no-new-privileges` present.
  (run_code runs as uid 0 inside the container but de-capped + network-none;
  a non-root uid is a later refinement.)

- **2026-08-14 (Feature ① — gVisor default on BOTH surfaces)** — Upgraded
  test to maximum isolation on both user-code paths:
  - Backend `SANDBOX_TIER=2 → 3` (gVisor). Verified: R personal `.nf` via the
    live API → `[sandbox] run … → tier-3 container` → succeeded,
    `R-sandboxed-ok mean=-0.016`.
  - run_code: injected `--runtime runsc` into the deployed bundle's dockerArgs
    (frontend `dev-frontend:sandbox-test3`). Verified via public
    `/api/code/run`: python → `kernel: 4.19.0-gvisor`, `NET:blocked`, exit 0.
  Both `.nf` workflows and run_code now run under gVisor + cap-drop ALL +
  no-new-privileges + network-none (+ read-only for `.nf`).

  **Feature ① remaining (each with the reason it's not done yet):**
  - **Interactive tools (Jupyter/RStudio/GIE)** — launched by Galaxy's native
    InteractiveTool manager (container from the tool XML, run by Galaxy's job
    runner), so hardening = a Galaxy `job_conf` change
    (`docker_run_extra_arguments`: --cpus/--memory/--network/--cap-drop +
    interactive GC for idle reaping), NOT the compute sandbox package. Also
    not E2E-verifiable on test (in-browser session proxy is missing). Left as
    a documented, separate Galaxy-config task rather than an unverifiable edit
    to the live backend.
  - **run_code non-root uid** — runs as uid 0 (frontend is root; the code uses
    `process.getuid()`). De-capped + gVisor + network-none, but a fixed
    non-root uid needs the baseDir made writable to it (chmod). Minor
    refinement.
  - **docker-socket-proxy** — would limit the backend/frontend docker.sock
    blast radius to a create/run API subset. Real improvement but reconfigures
    the working docker access; deferred to avoid destabilizing a verified
    setup without a careful test pass.
  - **custom seccomp**; **Firecracker tier-3b** (gVisor already covers
    kernel-level isolation); **durable images + overlays into CI** (currently
    live only on the test host: `dev-backend:sandbox-test`,
    `dev-frontend:sandbox-test3`, `biomate-nextflow-sandbox:latest`+`:heavy`).
</content>
</invoke>
