# On-Prem Deployment Readiness — Harness Gap Audit + DB Localization

**Date:** 2026-10-02
**Question (user):** all our work targets on-prem deployment; the harness must self-adapt. Examine the
current system for gaps. Should we prepare all DBs locally — what do we have, what don't we?
**Method:** grounded in a code audit of cloud couplings (not memory). Companion: [[20261001_TWO_LLM_ARCH]].

## ⚠️ CORRECTION (2026-10-02) — next-phase already BUILT most of this
A colleague has shipped a near-complete on-prem deployment on `integration/next-phase` (~100 numbered
on-prem bug fixes, Chinese-commented). My gap list below over-claimed: **the harness plumbing is DONE.**
What exists on next-phase:
- `.env.onprem.example` + `docker-compose.onprem.yml` — full self-contained stack: **Postgres, Redis,
  MinIO (replaces S3), optional Ollama, local registry, db-init (pulls the catalog DB), backend, frontend.**
- **LLM → local**: `LLM_API_URL` / `GALAXY_AI_LLM_PROVIDER=openai_compatible` / `LLM_MODEL` / `OLLAMA_BASE_URL`.
- **Execution → local**: `NEXTFLOW_USE_AWS=false` + `NEXTFLOW_WORK_DIR` (local Nextflow, no Batch).
- **Storage → MinIO**, **registry → `BIOMATE_LOCAL_REGISTRY`**, **billing disabled**, **catalog DB
  air-gap pre-download** (`BIOMATE_DB_URL` + a no-network pre-download note).
So the layer table below is the *architecture*, but nearly every row is **already implemented** on
next-phase. The honest lesson: I audited my worktree, not next-phase — check the colleague's branch first.

### What's actually LEFT (my complementary, non-duplicating contribution)
1. **The on-prem LLM MODEL.** next-phase defaults to a **generic** `LLM_MODEL=qwen2.5-32b-instruct`
   (examples: deepseek-r1-32b, llama-3.3-70b). Our **domain-pro** (CPT on the BioMate knowledge/background
   corpus) is the BioMate-specific brain that slots straight into their `openai_compatible` endpoint —
   a better on-prem model than stock Qwen. **This is my workstream and it plugs in with zero new plumbing.**
2. **Air-gap external-resolver mirrors** — the ~120 external calls (ebi/ncbi/ensembl/pubchem/uniprot/rcsb)
   appear **unhandled** for fully air-gapped (fine for VPC-with-egress). Needs ChEMBL-subset + resolver
   mirrors if air-gap is a target. ← genuine open gap.
3. **Verify** the deploy ships **embeddings + a literature-RAG index** (catalog DB carries workflow
   embeddings; knowledge_recall RAG may need a shipped literature index). ← quick check with the colleague.

**Coordination:** harness/deploy = colleague (done); **model + air-gap knowledge-data = me.** Don't rebuild the stack.

---

## The decisive scoping question (sets the whole scope)
There are two very different "on-prem" targets:
- **A. VPC-with-egress** (realistic first target): customer runs compute + storage + LLM in their VPC,
  but outbound internet is allowed. Only the LLM, execution, and object-store need to move in-VPC;
  external resolvers/reference-data still work via egress. **Much smaller lift.**
- **B. Fully air-gapped** (regulated/classified): no outbound internet. EVERYTHING must be local —
  resolvers, reference genomes, container images, literature. **Large lift; some data inherently big.**
Recommend targeting **A first**, then hardening to B. Most gaps below are HIGH only for B.

## What's ALREADY on-prem-capable (don't rebuild)
- **DL inference self-host** — `bionemo_client.py` has a `self_host_url` path (80 `self_host` refs);
  BioNeMo NIMs (Boltz, docking, etc.) can run self-hosted. ✓
- **Local/docker executor fallback** — `nextflow_executor.py` (lines ~1320/1347) already has a
  'docker'/local work-dir path (dev-grade, not yet production-hardened for on-prem). ◑
- **Per-request LLM BYOK client** — `galaxy-assistant.ts` has an OpenRouter/custom OpenAI client set
  per request (`openrouterKey`/`selectedModel`); repointing it at a local **vLLM** (OpenAI-compatible)
  endpoint is the on-prem LLM path. ◑ (hook exists; make it the default on-prem)
- **Workflow catalog DB present locally** — `backend/database/galaxy_ai_tools.db` = **322 MB** full
  enriched (not a stub in this tree): catalog + tool scientific_context + embeddings. ✓ shippable
- **Trained on-prem LLM** — domain-pro/base CPT in progress ([[20261002...CPT]]). ◑

## GAPS (cloud couplings to self-adapt), by layer
| Layer | Current (cloud) | On-prem need | A (egress) | B (air-gap) |
|-------|-----------------|--------------|:----------:|:-----------:|
| LLM default backend | OpenRouter/Anthropic API | default to local **vLLM** (hook exists) | **MED** | MED |
| Execution | **AWS Batch** + S3 workdir + ECR | production-grade **local Nextflow** executor + local scheduler | **HIGH** | HIGH |
| Object storage | **S3** (`biomate-nextflow-work`, models) — 25 files use boto3 | **MinIO**/filesystem behind one storage shim | **HIGH** | HIGH |
| Container images | ECR / quay biocontainers / biomni-tools | local registry + **pre-pulled** images (note libz-mount, [[reference_executor_container_resolution]]) | MED | HIGH |
| External resolvers | ebi.ac.uk (52), eutils.ncbi (23), ncbi (12), ensembl (9), semanticscholar (7), uniprot (6), rcsb (5), pubchem (5) ≈ **120 call sites** | local mirrors/caches | low (egress ok) | **HIGH** |
| Literature RAG | PubMed / Semantic Scholar | **local literature index** (we HAVE the PMC/lit corpus) | low | MED |
| State DBs | Postgres + Redis (ElastiCache) — 38+ Redis refs | local Postgres + Redis (standard) | **LOW** | LOW |
| Billing | Stripe / (Lago dropped) | offline licensing / flat-tier | LOW | MED |

**"Self-adapted harness" = the missing abstraction:** today these are chosen by scattered env/hardcoded
cloud defaults. The clean fix is one **deployment-profile layer** (`DEPLOY_MODE=cloud|vpc|airgap`) with
pluggable backends for {LLM, executor, storage, resolver, literature} — each already has a seam
(BYOK client, docker executor, boto3 wrapper, resolver fns) but no unifying switch. Build that switch.

## DB / data localization — what we HAVE vs DON'T
**HAVE locally or trivially shippable:**
- `galaxy_ai_tools.db` (322 MB) — workflow+tool catalog, scientific_context, **embeddings** (vector search) ✓
- Nextflow/nf-core workflow files (in repo) ✓
- Literature/PMC concept corpus + ontology corpora (GO/HPO/ChEBI/EDAM) — on S3, ship as the local RAG index ✓
- Trained domain-pro/base LLM — in progress ◑
- BioNeMo NIM weights (self-host) ◑

**DON'T have locally (external; mirror for air-gap, or rely on egress for VPC):**
- **Compound resolvers**: PubChem/ChEMBL/ChEBI/KEGG live DBs (name→SMILES, properties). ChEMBL is a
  downloadable ~4 GB SQLite (shippable); PubChem is huge → ship a drug-like subset.
- **Reference genomes** (GRCh38/GRCm39/… iGenomes) — large (GBs each); stage the ones customers need.
- **Protein structures** (RCSB PDB, UniProt, AlphaFold DB) — subset or customer-provided.
- **Accession→data** (GEO/SRA/ENA via fetchngs) — *inherently external*; the sequencing DATA is PB-scale.
  Air-gapped customers stage their OWN data; public-accession fetch is a cloud-only convenience.
- **Container images** (biocontainers, biomni-tools, nf-core modules) — pre-pull into a local registry.
- **Fresh literature** — the local PMC index is a snapshot; it goes stale (acceptable; refresh on update).

## Recommended sequence
1. **Deployment-profile switch** (`DEPLOY_MODE`) + make **vLLM the default LLM backend** on-prem (small; hook exists).
2. **Storage shim** (S3↔MinIO/filesystem) behind one interface (unblocks the 25 boto3 sites).
3. **Production-grade local Nextflow executor** (promote the docker fallback; local scheduler; local workdir) — the biggest lift.
4. **Local registry + pre-pulled images.**
5. **Ship the catalog DB + embeddings + LLM + literature index** (all HAVE).
6. For air-gap (B): add **ChEMBL-subset + reference-genome staging + resolver mirrors**; for VPC (A), skip — use egress.

**Honest bottom line:** the *knowledge* side (catalog DB, embeddings, LLM, literature, DL self-host) is
largely in hand. The *execution + storage + external-resolver* side is where the real on-prem work is —
and its size depends entirely on VPC-with-egress (moderate) vs fully air-gapped (large). That scoping
decision should be made before building.
