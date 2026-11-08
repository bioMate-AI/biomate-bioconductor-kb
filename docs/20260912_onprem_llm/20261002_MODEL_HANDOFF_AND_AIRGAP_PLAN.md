# Domain-Pro Model Hand-off (→ next-phase serve) + Air-Gap Knowledge-Data Plan

**Date:** 2026-10-02
**Correction verified 2026-10-03:** The single-base adapter handoff proposed below is not valid
for the current training pipeline. `spot_train.sh` merges CPT into `base_domain`, then trains
the SFT adapter on **that modified checkpoint**. Even matching the original model ID and
dimensions is insufficient: the SFT adapter requires the exact CPT-merged weights. Deliver
`base_domain` plus its SFT adapter, or merge both stages into a standalone domain-pro model.
Keep the general model as a separate model/endpoint. Do not retrain on 8B just to match an old
serve default. Also, the inspected `origin/integration/next-phase` launcher discovers only
`regulatory_llm_*`, not arbitrary BioMate adapters; the auto-discovery claim below is superseded.
See `20261003_CPT_RECOVERY_AND_TAKEOVER.md` for current evidence and recovery work.

**Context:** next-phase has a complete on-prem harness ([[20261002_ONPREM_READINESS_AUDIT]]). My two
remaining pieces: (a) hand the domain-pro MODEL into the colleague's vLLM serve; (b) air-gap knowledge data.

## (a) Model hand-off — how our model plugs into next-phase's serve
Colleague's `backend/deploy/vllm/run-vllm.sh` (verified):
- `BASE_MODEL=Qwen/Qwen3-8B` (default, env-overridable)
- serves **multiple LoRA adapters** (`MAX_LORAS=6`, `MAX_LORA_RANK=16`) discovered at
  `models/<name>/lora_adapter`, served as `name=path` (current convention: `regulatory_llm_*`).
- OpenAI-compatible endpoint; harness points at it via `LLM_API_URL` + `GALAXY_AI_LLM_PROVIDER=openai_compatible`.

**This fits the two-LLM architecture cleanly:** one base (Qwen3-8B) served directly + several LoRA
adapters on it; `resolve_model(role)` routes each role to the right adapter name. So:
- **base LLM** = Qwen3-8B (served directly) → the 🟢 harness-carried / general roles.
- **domain-pro** = our CPT+SFT delivered as a **LoRA adapter** at `models/biomate_domainpro_vN/lora_adapter`,
  served alongside; `resolve_model` routes 🔴 judgment/knowledge roles to it.
- `regulatory_llm_*` (the colleague's existing adapter) coexists — vLLM already multiplexes up to 6.

### ⚠️ Coordination item #1 — align the BASE MODEL
The deploy serves **Qwen3-8B**; my CPT has been on **Qwen3-4B** (feasibility) with 9B/27B queued. A LoRA
trained on 4B/9B **will not load** on an 8B base. **Action:** agree one base with the colleague and train
the domain-pro LoRA on *that* base (rank ≤16 to match `MAX_LORA_RANK`). Recommend standardizing on
**Qwen3-8B** (their default) unless we deliberately raise `BASE_MODEL`. This also settles my
4B-vs-9B-vs-27B question: match the deploy.

### Hand-off checklist (when the model is trained on the agreed base)
1. Train domain-pro LoRA on `BASE_MODEL` (agreed), rank ≤16.
2. Place adapter at `models/biomate_domainpro_vN/lora_adapter` (+ `adapter_config.json`).
3. Wire `resolve_model` role→adapter map (judgment/knowledge → `biomate_domainpro_vN`; general → base).
4. Confirm it serves via their `run-vllm.sh` (adapter auto-discovered) and the harness reaches it
   through `LLM_API_URL`. No new plumbing.

## (b) Air-gap knowledge-data plan
**Key refinement from the resolver audit:** most of the ~120 external calls are **offline DB-BUILD**,
not runtime — `comprehensive_tool_knowledge_agent`, `tool_knowledge_collector`, `migrate_tool_availability`,
`citation_enricher` run at *our* build time to enrich the shipped `galaxy_ai_tools.db`. They do **not**
run on the customer box, so they are **not** an air-gap runtime problem.

**The genuine runtime air-gap needs (what breaks at a no-egress customer):**
| Need | Source today (external) | Local mirror to ship | Size |
|------|-------------------------|----------------------|------|
| Compound resolve (name→SMILES, props) — `federated_query`, drug-dev | pubchem (29), chembl (25) | **ChEMBL SQLite** (downloadable) + drug-like PubChem subset | ~4 GB + subset |
| Gene/protein/pathway lookup — `federated_query` | uniprot (55), ensembl (25), ebi (14) | UniProt/Ensembl **subset** tables (human + key organisms) | GBs (subset) |
| Literature RAG — knowledge_recall / scientific_qa | eutils/ncbi (13), semanticscholar | **local literature index** from our PMC/concept corpus (already on S3, 540M tok) | ~2 GB |
| Structures — docking/structure tasks | rcsb (5) | PDB subset or customer-provides | varies |

**First concrete builds (tractable, high-value):**
1. **Literature-RAG index** — we already have the corpus (`pmc_concept` + background, on S3). Build a
   local embedding index (reuse the harness's MiniLM/BGE) so knowledge_recall/scientific_qa work offline.
2. **ChEMBL-subset resolver** — ship the ChEMBL SQLite (or a name→SMILES+props subset) behind
   `federated_query`'s compound path, gated by an `OFFLINE_MODE`/`RESOLVER_LOCAL` switch (to add to
   the deploy profile). This is the flagship drug-dev path.
3. Gene/protein subset + PDB subset — later, per customer need.

For **VPC-with-egress** customers, none of (b) is needed (egress covers resolvers); it's an
**air-gap-only** deliverable. Confirm the target before building the heavier mirrors.

## Division of labor (confirmed)
- **Harness + deploy stack + MinIO + local-exec + serve infra** → colleague (done).
- **Domain-pro model (on the agreed base) + air-gap knowledge-data (literature index, ChEMBL-subset)** → me.
