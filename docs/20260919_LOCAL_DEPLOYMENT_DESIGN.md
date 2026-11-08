# Local / on-prem deployment — design & open questions (4B + 27B)

**2026-09-19.** Synthesis of colleague's next-phase work (survey) + the two-LLM serving specs + the
open questions to resolve. Four topics: databases, LLM rate-limit/concurrency, hardware, tool-docker scope.

---

## 1. Databases
**Done (colleague):** catalog `galaxy_ai_tools.db` (~279 MB) bind-mounted (`docker-compose.deploy.yml`),
seeded once from S3; nextflow defs + BGE embeddings `.npz` (3.7 MB) bind-mounted; Postgres = **cloud RDS**
(users/plans, `quota_enforcer.py`); Redis = **ElastiCache** (run-state + plan cache, graceful in-mem fallback).
**Recommendation (air-gap):** the catalog/embeddings/defs are small → **bundle them in the install kit**
(already the pattern). Replace RDS→**bundled Postgres container** + first-boot migrations/seed; ElastiCache→
**local Redis container**; ship the BGE `.npz` (tiny) rather than recompute. Credentials via a local sealed
`.env`/Vault, not AWS Secrets Manager. Workflow **outputs** → local disk or **MinIO** (S3-compatible).
Package as one `docker-compose.onprem.yml` profile (postgres + redis + backend + vLLM + minio).
**Open:** repeatable offline Postgres migration/seed flow; credential injection method; MinIO sizing (see §3).

## 2. LLM rate-limit & concurrency (4B + 27B)
**Done:** cost-based quota (`quota_enforcer.py`, USD/mo tiers) — but that's for **cloud Batch cost, not local
LLM throughput**; scheduler skeleton (`compute/scheduler.py`, Phase-0 shadow); `infra/vllm/start-vllm.sh`
serves **ONE base model + LoRAs** (Qwen3-8B default, MAX_LORAS=6) — **no size-routing, no token-rate limit,
no overflow queue.**
**Recommendation:**
- **Serve both** as two vLLM instances (separate ports): 4B fp16 + 27B AWQ-4bit, co-resident on one
  48–80 GB GPU (~30 GB combined weights).
- **Route via the cascade** (our two-model design): gateway → 4B; escalate to 27B on low confidence / hard
  task type. This *is* the size-routing answer, and it keeps 27B traffic (hence concurrency) low.
- **Add throughput limits** the current quota lacks: token-bucket per user (**req/min + tokens/min**),
  separate buckets per model (27B stricter). Overflow → bounded queue → 429 + `Retry-After`.
- **Per-model concurrency** = vLLM `max_num_seqs` (4B ~32–64; 27B ~4–8, matching KV-cache room).
**Open:** escalation policy (confidence threshold / task types) — decide from the v3 removal-eval + routing
confidence; per-model `max_num_seqs` tuning; queue depth & backpressure to the UI.

## 3. Hardware
**Done:** vLLM 8B 4-bit ≈ 12–14 GB VRAM (`start-vllm.sh`); Nextflow resource tiers (`run_spec.py`:
LOW 2c/12G · MED 6c/36G · HIGH 12c/72G · HIGH_MEM 12c/200G · GPU 8c/32G+1GPU); control plane t3.medium.
**Recommendation (team of ~5):**
- **LLM node:** 1× **L40S 48 GB** (27B AWQ + 4B fp16 co-resident) *or* 1× A100/H100 80 GB; 16 vCPU, 128 GB
  RAM, ~200 GB SSD (weights + KV).
- **Compute node:** 32–64 vCPU, 256 GB RAM, 1 GPU (for GPU-tier workflows) + large working disk.
- **Disk (the big variable):** outputs by domain — RNA-seq 50–500 GB/run, CryoEM 0.5–2 TB/run, drug-disc
  10–100 GB/run. A mixed team → **2–4 TB** working; CryoEM-heavy → **10 TB+**.
**Open:** disk budget by the deployment's domain mix; multi-GPU serving (LB/proxy); CPU-only workflow perf.

## 4. Tool-docker scope per deployment
**Done (concept only, 🔴 not built):** nf-core auto-pulls biocontainers on first run; base image ships
stub-tool deps; roadmap mentions offline image+data kit / `docker save/load` bundle + `NXF_OFFLINE=true`
— but **no per-customer allow-list / subset selection exists.**
**Recommendation (buildable NOW from the catalog — this is the concrete lever):**
- **Derive the required container set from the ENABLED workflows**: `workflows.tools_used` → `tools`
  (container_info) → the transitive closure of biocontainers. A deployment enabling domains {X,Y} →
  compute exactly the images to **mirror** to the customer registry + the **allow-list** to enforce at run.
- **Enforce** at launch: refuse workflows/tools not in the deployment manifest (clear error, not a hang).
- **Air-gap:** `NXF_OFFLINE=true` + pre-seed only the manifest's images; tool-not-in-scope → explicit error.
- **License-gated** tools (AMBER/Schrödinger): manifest flags them; gate per deployment/user.
→ `export_deployment_manifest.py` produces this manifest (built below).
**Open:** manifest schema/versioning; license-enforcement layer; customer's own custom containers.

---

## Most important open question per topic
1. **DB:** offline Postgres migration/seed flow, or "bring-your-own-Postgres"?
2. **LLM:** the 4B→27B escalation policy + per-model queue/backpressure.
3. **HW:** disk budget for the deployment's actual domain mix.
4. **Tools:** ship all 2,600 workflows+containers, or a curated per-deployment subset (manifest) with add-on packs?

## Buildable now
`export_deployment_manifest.py` — given enabled domains/workflows, emits the required container mirror-list +
tool allow-list from `tools_used`/`container_info` (grounds topic #4). Everything else needs a
product/infra decision (the open questions above) or the trained models (escalation policy).
