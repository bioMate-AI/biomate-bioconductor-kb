# Interactive Tools — production runtime (k8s / ECS job destination)

**Audience:** infra/platform engineer implementing a production-safe runtime for
Galaxy Interactive Tools (Jupyter, RStudio, CellxGene).
**Status:** design + implementation guide. The app side is ready; this doc is the
infra side.
**Author handoff:** written 2026-11-10.

---

## 1. Problem (why ITs don't work today)

Galaxy Interactive Tools (ITs) are launched as **containers**: an IT "job" starts a
long-running Jupyter/RStudio/CellxGene container that exposes an HTTP entry point,
and `gx-it-proxy` routes the user's browser to it.

On the current stack the IT job destination is **`docker_local`** — it runs the IT
container by calling `docker` **from inside the Galaxy container**
(`backend/config/job_conf.yml`: `interactive_tool_.* → docker_interactive_root`,
`docker_enabled: true`). But the `biomate-galaxy-dev` container has **no docker CLI
and no docker socket**, so every IT job fails at launch. The user sees:

> "The notebook job stopped before the session became available."

This hits **both** launch surfaces identically (dataset panel
`/api/projects/:id/files/:fileId/open-in` → routes.ts; Outputs tab / CellxGene →
`/api/interactive/launch`), because both do
`launchInteractiveTool → waitForInteractiveSession`, which reports `reason: 'failed'`
when the Galaxy job terminates before the session is ready.

### Why not just mount the docker socket
`scripts/sync_to_dev.sh:enable_interactive_tools()` can mount the host
`/var/run/docker.sock` into the Galaxy container (triple-gated:
`BIOMATE_IT_APPLY=1` + `BIOMATE_IT_SOCKET_APPROVED=1` + a reviewed plan SHA). That
makes ITs work **immediately** but gives the Galaxy container **effective root on the
host**, and it runs arbitrary user IT images with that access. The script's own
comment says it is **"acceptable on DEV only; production needs a real IT job
destination (k8s/ECS), not this."** This box is tagged **BioMate-Production**, so the
socket is only an interim/dev measure. **This doc is the production fix.**

---

## 2. How a Galaxy IT works end-to-end (what any runtime must preserve)

1. User clicks "Open in Jupyter/RStudio/CellxGene". The Node frontend calls Galaxy to
   launch the IT tool (`interactive_tool_jupyter_notebook` / `_rstudio` / `_cellxgene`,
   registered via `backend/config/interactivetools_conf.xml`).
2. Galaxy submits the IT as a **job** to the configured destination. The job starts a
   **container** that runs the notebook server and declares an **entry point** (host-
   relative URL + internal port) via Galaxy's IT entry-point API.
3. Galaxy writes the mapping (`<token>` → `host:port` of the IT container) into the
   **proxy session map**. Today that map is a sqlite file
   (`/gxdata/interactivetools_map.sqlite`) read by the **`gx-it-proxy`** container
   (`@galaxyproject/gx-it-proxy --port 4002 --sessions …`).
4. `gx-it-proxy` routes `https://<token>-<port>.interactivetool.<domain>/…` to the IT
   container. Galaxy config already has `interactivetools_enable: true` and
   `interactivetools_upstream_proxy: true`.
5. The Node layer polls `waitForInteractiveSession(job_id)` until the entry point is
   ready, then returns the URL to the browser.

**Invariant:** whatever runtime launches the IT container, it must (a) run the
container, (b) make its `host:port` reachable by `gx-it-proxy`, and (c) let Galaxy
write the entry point into the proxy map. Steps 1, 3, 4, 5 and the tool defs do **not
change** — only the **job destination** (step 2) and the **container networking** do.

---

## 3. Recommended: Kubernetes IT destination (Galaxy-native, lowest risk)

Galaxy ships first-class support for ITs on Kubernetes; this is the documented
production pattern and avoids a custom runner.

### 3.1 Components
- A **Kubernetes cluster** (EKS fits this AWS account). Galaxy submits IT jobs as
  **Pods**; each IT Pod runs the Jupyter/RStudio/CellxGene image.
- Galaxy's **Kubernetes job runner** (`galaxy.jobs.runners.kubernetes`, needs `pykube-ng`
  in the Galaxy image) for the IT destination.
- `gx-it-proxy` deployed **in-cluster** as a Deployment + Service + Ingress, reading
  the proxy map from a shared store (see 3.3).
- An **Ingress / ALB** with a **wildcard host** `*.interactivetool.<domain>` and a TLS
  cert, forwarding to `gx-it-proxy`.

### 3.2 Galaxy job_conf — add a k8s destination for ITs
In `backend/config/job_conf.yml`, add a runner + destination and route
`interactive_tool_.*` to it (replacing `docker_interactive_root`):
```yaml
runners:
  k8s:
    load: galaxy.jobs.runners.kubernetes:KubernetesJobRunner
    k8s_config_path: /path/to/kubeconfig        # or in-cluster service account
    k8s_namespace: galaxy-its
    k8s_galaxy_instance_id: biomate
execution:
  environments:
    k8s_interactive:
      runner: k8s
      docker_enabled: true                      # k8s pulls the image; no host docker
      k8s_run_as_user_id: 1000
      k8s_supplemental_group_id: 1000
      k8s_pull_policy: IfNotPresent
tools:
  - id: interactive_tool_.*
    environment: k8s_interactive
```
(Keep the AWS Batch destination for regular Nextflow workflows unchanged — this is
only the IT path.)

### 3.3 Proxy map on k8s
`gx-it-proxy` must read the SAME map Galaxy writes. Options, in order of preference:
- **Database-backed proxy map** (`interactivetools_map` in Galaxy's Postgres) +
  `gx-it-proxy` pointed at it — survives Pod restarts, no shared filesystem. Preferred.
- A shared **PVC** (EFS) holding the sqlite map, mounted into both Galaxy and the
  proxy Pod.
Set in galaxy.yml: `interactivetools_map`, `interactivetools_proxy_host`,
`interactivetools_base_path`, and keep `interactivetools_upstream_proxy: true`.

### 3.4 Networking + TLS
- Wildcard DNS `*.interactivetool.<domain>` → the Ingress/ALB → `gx-it-proxy` (4002).
- TLS cert covering the wildcard (ACM on the ALB).
- NetworkPolicy: IT Pods egress **denied by default** (they run arbitrary user code);
  allow only what a notebook legitimately needs. No access to cluster metadata/IRSA
  beyond a minimal scoped ServiceAccount.

### 3.5 Security (must-haves — IT Pods run arbitrary user code)
- IT Pods: `runAsNonRoot`, drop all capabilities, read-only root FS where possible,
  a **minimal ServiceAccount** (no cluster-admin, no node access), resource limits.
- **IMDS blocked** from Pods (EKS: set the node IMDS hop limit to 1 / use IRSA with a
  least-privilege role; never expose the node role to Pods).
- Reuse the existing **upload source pre-check** (already mandatory + fail-closed in
  `nextflow_executor.py`) — it blocks obvious metadata/exfil patterns before any user
  artifact runs. The Pod sandbox is the real boundary; the pre-check is defense in depth.
- Per-user namespace or Pod isolation so one user's IT can't reach another's.

---

## 4. Alternative: AWS ECS/Fargate IT destination (AWS-native, more custom)

Fits the AWS-only footprint (no cluster to run), but Galaxy has **no built-in ECS
runner**, so it needs either **Pulsar** (as the IT job runner submitting ECS tasks) or
a small custom runner. Higher build cost than k8s; choose it only if standing up EKS
is undesirable.
- Each IT = an **ECS Fargate task** (the Jupyter/RStudio/CellxGene image from ECR),
  with a **scoped task role** (no host role; mirror the least-privilege
  `biomate-nextflow-task-role` pattern already created for Batch).
- An **ALB** with host rule `*.interactivetool.<domain>` → a target group that
  `gx-it-proxy` fronts (the proxy still does token→task routing; it needs the task's
  private IP/port, written to the proxy map by the runner).
- Fargate gives container isolation without host-root; set the task's IMDS off and
  egress via a locked-down security group.
- This reuses the ECR images and AWS IAM model already in place, at the cost of a
  custom/Pulsar IT runner. **k8s (§3) is the lower-effort supported path.**

---

## 5. App side — already done; one flip to go live

The frontend was made **honest** (commit `462d9e66`): `/api/interactive/available` now
reports a tool available **only** when `INTERACTIVE_TOOLS_ENABLED` is set, so until the
runtime exists the UI **hides** the IT buttons instead of showing dead ones. Nothing
else in the app needs to change.

**To turn ITs on once the runtime (k8s or ECS) is live:**
1. Set `INTERACTIVE_TOOLS_ENABLED=1` on the **Node frontend** container.
2. Point `gx-it-proxy` at the shared proxy map and the wildcard Ingress/ALB.
3. Set the IT job destination in `job_conf.yml` (§3.2) and restart Galaxy.
No frontend code change — the buttons reappear and now **launch for real**.

---

## 6. Acceptance test (done = all green)
1. `GET /api/interactive/available` → `{available:true, tools:{jupyter,rstudio,cellxgene:true}}`.
2. Open a `.rds` output → RStudio launches, the session URL loads, the R object is in
   the environment. (`.csv` → Jupyter; `.h5ad` → CellxGene.)
3. From inside an IT Pod/task: `curl -s -m2 http://169.254.169.254/…` **fails** (no
   metadata creds), S3 read of the staged input **works** (scoped role only).
4. Kill the IT Pod/task → the proxy map entry is cleaned up; relaunch works.
5. Two users launching simultaneously get isolated sessions.

---

## 7. References (this repo)
- Current IT config: `backend/config/job_conf.yml` (docker_interactive_root),
  `backend/config/interactivetools_conf.xml`, galaxy.yml `interactivetools_*`.
- Proxy: `gx-it-proxy` container (`@galaxyproject/gx-it-proxy --port 4002`).
- App launch path: `frontend/server/routes.ts` `/api/projects/:id/files/:fileId/open-in`
  and `/api/interactive/launch`; readiness `waitForInteractiveSession`;
  availability probe `/api/interactive/available` (gated on `INTERACTIVE_TOOLS_ENABLED`).
- Interim dev-only socket path (NOT for prod): `scripts/sync_to_dev.sh`
  `enable_interactive_tools()` + `scripts/interactive_runtime_recovery.py`.
- Least-privilege task-role precedent to mirror for ECS: `biomate-nextflow-task-role`
  (see `docs/20261110_BATCH_JOBROLE_IMDS_HARDENING_PLAN.md`).
