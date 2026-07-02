# BioMate backend scaling — vertical (bigger instance) & horizontal (autoscaling)

Context: the search/connector concurrency ceiling is CPU + single gunicorn worker.
Current test = **1× t3.medium (2 vCPU / 3.7 GiB)**, `workers:1`, `preload:false`,
single-EC2 docker-compose (`deploy/docker-compose.deploy.yml`) behind a standalone
Caddy. Each worker holds ~2 GiB (Galaxy app + 2 embedding models + catalog handle),
`~1 GiB free, no swap` → **can't add workers without OOM** (that's why `workers:1`).

The good news for scaling: most state is ALREADY external, so the backend is close
to stateless:
- Run state → Redis (`RUN_STATE_STORE=redis`).
- Billing → Redis + Lago (external EC2).
- Galaxy DB → RDS Postgres (`GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION`).
- Workflow execution → AWS Batch.
- Embedding models → baked into the image; catalog + `.npz` → host bind-mount.

---

## Track A — Vertical (bigger instance + more workers)  ★ do this first

Simplest, biggest immediate win, **no architecture change** — just `deploy.sh` to a
bigger instance + a config bump.

### A1. Pick the instance
Embedding inference is **CPU-bound and sustained**, so a **non-burstable compute**
instance beats t3 (t3 is burstable — under sustained load it throttles to ~20-40%
of a vCPU once CPU credits drain, which is exactly the concurrency case).

| Option | vCPU/RAM | Notes |
|---|---|---|
| t3.large | 2/8 | RAM for 2-3 workers but still 2 (burstable) vCPU — modest |
| **c6i.xlarge** | **4/8** | recommended floor: 4 real cores, non-burstable |
| **c6i.2xlarge** | **8/16** | headroom for ~4-6 workers + real concurrency |

### A2. Worker count + the memory lever (preload/COW)
Per-worker memory is the constraint. Two ways to fit more workers:
- **`preload:true`** — the master loads the app + models ONCE, workers fork
  copy-on-write → models/catalog shared read-only → **per-worker memory drops a
  lot**, so far more workers fit. This is the key economical lever.
  ⚠️ Galaxy had a past `preload` rollback (see `galaxy.yml.docker` comment: workers
  bind-port failure) — validate on test before prod. Also: my per-worker startup
  warmup (`WORKFLOW_SEARCH_WARMUP`) + `_EMBED_INIT_LOCK` already handle the
  fork/warm race; under preload the warm happens in the master pre-fork (COW
  inherit), which is even better.
- Rule of thumb without preload: `workers ≤ RAM_GiB / 2.5`. With preload: much higher.
- Start `workers = 2` on c6i.xlarge (preload off) or `workers = 4` (preload on),
  measure RSS + `/api/version` + search concurrency, then tune.

Set in `backend/config/galaxy.yml.template` (the deployed image copies it):
```yaml
  gunicorn:
    workers: 4          # was 1
    preload: true       # validate first — enables COW model sharing
    max_requests: 3000  # already raised (#81)
    max_requests_jitter: 300
```

### A3. Also raise the AnyIO threadpool if needed
Sync endpoints run in a threadpool; default (40) is fine for now, but if you add
many workers on many cores, confirm it isn't the new ceiling.

**Effort:** ~1-2h (change instance tag/size in the deploy, bump galaxy.yml, deploy,
verify RSS + concurrency). **Cost:** ongoing (bigger instance, test + prod).

---

## Track B — Horizontal autoscaling  ★ medium-term, for real user load

Move from 1 EC2 to N backend instances behind a load balancer that scales on load.

### B1. Orchestration
- **ECS (Fargate or EC2) + Application Load Balancer + Service Auto Scaling**
  (target-tracking on CPU 60-70% or ALB `RequestCountPerTarget`). Cleanest fit —
  the app is already containerized (`dev-backend`/`dev-frontend` images).
- Alternative: EC2 **Auto Scaling Group** behind an ALB (each instance runs the
  compose stack). Less clean than ECS but closer to today's setup.
- EKS/HPA only if you're already on k8s (heavier).

### B2. What must change to be horizontal-safe
1. **Redis must be shared** — today test uses a LOCAL `biomate-redis` container.
   Point every instance at **ElastiCache** (prod already has one for billing).
   Run state + sessions + billing all need the shared endpoint, else instances
   don't see each other's runs.
2. **Catalog + `.npz` + models per task.** Models are baked (✓). The catalog
   (279 MB) + `.npz` (3.7 MB) are host bind-mounts today. For N tasks, either:
   - **EFS** mounted into every task (shared, simplest, auto-consistent), or
   - pull from S3 on container start (an init step; `s3://biomate-nextflow-work/dev-sync/`
     already holds the catalog), or
   - bake the catalog into the image (biggest image, but fully self-contained).
   EFS is the least-effort for keeping catalog/.npz consistent across tasks.
3. **SSE / session affinity — the main gotcha.** Chat/agent SSE streams and the
   backend→frontend `/internal/sse-inject` assume one process pair. With N
   instances behind an ALB you need EITHER:
   - **ALB sticky sessions** (cookie-based) so a client stays on one instance for
     its SSE stream, OR
   - **Redis pub/sub-backed SSE fan-out** so any instance can deliver an event for
     a run regardless of which instance is streaming (more work, more robust).
   Start with sticky sessions; move to redis pub/sub if cross-instance delivery is
   needed (e.g. a Batch-completion event arrives on a different instance than the
   one holding the SSE).
4. **TLS/ingress**: replace the standalone Caddy with the ALB (ACM cert) →
   target group → backend tasks. Frontend can be its own service/target group.

### B3. Scaling policy
- Metric: ALB `RequestCountPerTarget` (search/chat are request-bound) or CPU 65%.
- Min 2 (HA) / desired 2 / max N per budget; scale-out cooldown short, scale-in
  long (avoid flapping — each new task pays the ~10-20s warmup).
- Warmup: the per-worker warmup + baked models mean a new task is ready in ~10-20s;
  keep min≥2 so a scale event never drops to zero capacity.

**Effort:** meaningful (ECS/ALB stack, EFS or S3-sync, SSE affinity, IaC). **Cost:**
scales with traffic; min-2 baseline.

---

## Recommendation

1. **Now:** Track A on a **c6i.xlarge** (4 vCPU) with `workers:2` (preload off) or
   `workers:4` (preload on, after validating preload on test). Removes the CPU
   concurrency ceiling for a small, predictable cost. No app changes.
2. **When real concurrent user load grows:** Track B (ECS + ALB + autoscaling),
   whose main work is: shared ElastiCache, catalog/.npz on EFS (or S3-sync), and
   SSE session affinity. The rest (stateless backend, external DB/Batch/billing,
   baked models) is already in place.

Do NOT bump `workers` on the current t3.medium — it OOMs (verified: ~2 GiB/worker,
~1 GiB free, no swap). Vertical must upsize the instance first.
