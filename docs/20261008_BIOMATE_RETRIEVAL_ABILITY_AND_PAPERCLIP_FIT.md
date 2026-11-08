# BioMate Retrieval/Literature Ability & Resources — and where Paperclip actually fits

**Date:** 2026-10-08
**Purpose:** Ground the Paperclip question in what BioMate *already has* (ability + resources),
then answer integrate-vs-compete from evidence, not assumption.
**Method:** direct code audit; every claim has a file:line.

---

## 1. What BioMate already has (verified)

### 1.1 Literature / multi-source retrieval — substantial
| Capability | Where | What it is |
|---|---|---|
| **Parallel federated fan-out** | `backend/lib/galaxy/ai/federated_query.py:88-97` | entity-type → source list, hits many DBs in parallel and merges. Literature set = `pubmed, europepmc, semantic_scholar, openalex`. |
| **Canonical source registry** | `backend/lib/galaxy/ai/data_sources.py:1-20` | single source of truth unifying what were 4 drifting lists; **60+ sources** (EuropePMC 4M OA full-text, OpenAlex 250M works, Semantic Scholar, PubChem, ChEMBL, UniProt, …). |
| **PaperQA2 synthesis** | `webapps/galaxy/api/ai_assistant.py:6113-6203`; tool `synthesize_papers` (`frontend/server/orchestrator.ts:135,266`) | grounded multi-paper RAG → cited answer over uploaded PDFs. |
| **ResearchAgent** | `backend/lib/galaxy/ai/agents/research_agent.py` | literature-backed Q&A (PubMed/arXiv/S2) + citation/methods writing. |
| **Curated local full-text index** | `backend/lib/galaxy/ai/local_literature.py` | **FTS5** over **PMC open-access** docs (pmcid/title/year/licence); a *small, reviewed* index ("never replace an existing reviewed index"), **not** a bulk corpus. |
| **Semantic/vector search** | `backend/lib/galaxy/ai/vector_search.py` | sentence-transformers embeddings over the tool/workflow catalogue. |
| **Dataset RAG** | `backend/lib/galaxy/ai/biomni_dataset_rag.py` | dataset recommendations. |

Known weak path: **`research_query` confabulates real-but-unrelated PMIDs**
(`[[project_research_confabulation]]`) — that is a *recall-based* path, distinct from the grounded
PaperQA/FTS5 paths.

### 1.2 Execution & orchestration substrate — already present
| Capability | Where |
|---|---|
| **`run_code` sandboxed code execution** (python/R/bash over files, container `biomate-biotools:1`) | `frontend/server/routes.ts:16882` (`POST /api/code/run`), `code-runner.ts:221`, `galaxy-assistant.ts:_toolRunCode:2902` |
| **Sandboxed head launcher** (locked-down docker/podman) | `backend/lib/galaxy/ai/compute/sandbox/launcher.py` |
| **Inference-time consensus/verify** | `backend/lib/galaxy/ai/verification_layer.py` |
| **Dormant router→parallel-specialists→assembler orchestrator** | `backend/lib/galaxy/ai/agents/agent_orchestrator.py` |
| **Durable cross-worker parallel run-tracking + completion** | `backend/lib/galaxy/ai/runs/run_state_store.py`, `completion_poller.py` |

### 1.3 Resources (verified)
- **S3 buckets:** `biomate-data`, `biomate-ai-tools`, `biomate-ml-training`, `biomate-regulatory-llm`,
  `biomate-nextflow-sandbox`, `annotation-cache`, GPU/CPU/spot Batch queues, … (grep of `ai/`).
- **Compute:** AWS Batch (cpu/gpu/spot), EC2, the `run_code` sandbox image, the Nextflow sandbox.
- **Workflow DB:** `backend/database/galaxy_ai_tools.db` (4,210 workflows / 12k tools) + vector index.

---

## 2. The one thing BioMate's literature stack does NOT have

BioMate accesses literature-at-scale through **live APIs** (EuropePMC/OpenAlex/S2/PubMed fan-out)
plus a **small curated FTS5 index**. It has **no bulk, downloaded, agent-navigable corpus** — i.e.
nothing an agent can `grep`/`cat`/`find` over as a filesystem, and no **map-reduce fan-out of
cheap sub-agents over a local corpus**.

That — *corpus-as-filesystem + agentic grep + map-reduce extraction* — **is exactly Paperclip's
technique**, and it is precisely the axis BioMate is missing. Paperclip is **not** a competitor to
PaperQA2 (synthesis), federated_query (multi-source fan-out), or vector_search (semantic match);
it sits at a **different layer — the grounded retrieval/navigation substrate** that *feeds* them.

---

## 3. Why integrate, not compete (the corrected answer)

The layers stack; they don't overlap:

```
            ┌─────────────────────────────────────────────┐
  SYNTHESIS │ PaperQA2 (cited answer)  · ResearchAgent      │  ← BioMate has
            ├─────────────────────────────────────────────┤
  RETRIEVAL │ federated_query fan-out (live APIs, 60+ src) │  ← BioMate has
            │ vector_search (semantic) · FTS5 (curated)    │  ← BioMate has
            ├─────────────────────────────────────────────┤
  SUBSTRATE │ ❖ corpus-as-filesystem + grep + map-reduce   │  ← MISSING = Paperclip
            └─────────────────────────────────────────────┘
```

Paperclip slots in at the bottom as a new **grounded substrate** that the existing retrieval +
synthesis layers consume. It is grounded-by-construction (an agent can only cite what it `grep`'d
from a real file), which is the structural fix for the `research_query` PMID-confabulation failure.

### CORRECTION (firsthand read of repo + blog, 2026-10-08)
Reading the actual repo/blog overturns the "self-hostable substrate" assumption:
- **Paperclip is a HOSTED third-party service**, not a local corpus. The corpus (PostgreSQL per-block
  JSONB + Elasticsearch BM25+dense, ~70M blocks from **~450K bioRxiv/medRxiv preprints** + some
  PMC/FDA/trials; "8M" is aspirational across sources) lives **server-side at `paperclip.gxl.ai`**.
- The "filesystem" is a **virtual abstraction** the client presents (paths like
  `/papers/<id>/sections/Results.lines`); shell commands are **translated into remote corpus
  queries** — it is NOT a FUSE mount or local files. `map_()` dispatches lightweight subagents
  *server-side* across a result set.
- The **Apache-2.0 repo is a CLIENT** — MCP endpoint (`paperclip.gxl.ai/mcp`), CLI (`paperclip`,
  OAuth login), Python SDK (`gxl_paperclip.PaperclipClient`, API key `pk_...`). **No self-hosting
  documented.** Per-task cost ≈ **$0.21–0.53**. Python 3.8+.
- Benchmark (bioRxiv-Bench, 140 Qs) is **vs. a bioRxiv MCP connector and FutureHouse Edison** — i.e.
  it's a better *retrieval service/interface*, measured against other services.

**Consequence:** you cannot "run Paperclip's technique on `biomate-data` S3 + the sandbox." Paperclip
is consumable only **as an external hosted source**. BioMate's own S3 + `run_code` sandbox +
orchestrator are what you'd need to **re-implement the technique on your own corpus** (a real build,
inspired by the Apache-2.0 client — not an import). The §4 design below reflects this.

---

## 4. Corrected integration design — two distinct options

### Option A — consume Paperclip as a hosted external source (fast, cheap, public data only)
Paperclip is just a (very good) external biomedical-retrieval service, and **BioMate's
`federated_query` is already built to fan out to external sources.** So:
1. **Add a `paperclip` fetcher** to `federated_query` (literature entity type) and/or register its
   MCP endpoint (`paperclip.gxl.ai/mcp`) as a BioMate connector; call via the `gxl_paperclip` SDK
   with an API key held in BioMate secrets.
2. Route **grounded bioRxiv/medRxiv retrieval, novelty checks, and multi-paper synthesis** through
   it; let **PaperQA2/ResearchAgent synthesize over its grounded extracts**. Its novelty-check
   result (80% vs 28% MCP) is directly useful to the **drug novelty/FTO gate**
   (`[[project_drug_novelty_fto_gate]]`).
3. **Benchmark** it against today's `research_query`/FTS5/federated paths on BioMate's own queries
   before defaulting to it.
- **Caveats (decisive):** it is an **external hosted dependency** (OAuth/API key, per-task $),
  queries **leave BioMate's perimeter** → **gate OFF for private/regulated/on-prem data** (CRO/IND,
  customer corpora); corpus is **preprint-heavy (~450K)**, not a general 8M-paper or private corpus;
  availability/latency depend on gxl.ai.

### Option B — re-implement the filesystem+map-reduce *technique* on BioMate's own corpus
Justified only where Option A can't be used — **on-prem, private/customer data, regulated queries,
or non-bioRxiv corpora** (incl. BioMate's fragmented 60+ sources, `[[project_data_source_fragmentation]]`).
This is a genuine build *inspired by* Paperclip's open client, using resources BioMate already owns:
- **Corpus** (scoped: the targets/indications/private docs we need) in `biomate-data` S3, parsed to
  per-block records in Elasticsearch/Postgres (the Paperclip ingestion shape).
- **Filesystem + grep-agents** inside the existing `run_code` sandbox (`biomate-biotools:1`).
- **Map-reduce fan-out + aggregation** via the dormant orchestrator + `RunStateStore`/`CompletionPoller`.
- **Synthesis** by the existing PaperQA2/ResearchAgent.
This is the same substrate the Virtual-Biotech-style per-paper fan-out needs, so Option B and the
§5.1 Pattern-Router work share infrastructure.

### Recommendation
**Start with Option A as a scoped PoC** (public bioRxiv/medRxiv novelty + synthesis via
`federated_query`), measure vs. existing paths, and **gate it to non-private data**. Treat **Option B
as the on-prem/private-data path** — a larger, separately-scoped build to decide later, not now.

## 5. Honest notes
- This corrects the earlier "evaluate Paperclip vs our stack" framing: it's **integrate as a new
  substrate**, not replace. (And the even-earlier "import PaperQA2" was wrong — we already have it.)
- Lesson applied: audited BioMate's real ability/resources first (`[[feedback_audit_biomate_capabilities_first]]`).
  Ties to `[[project_data_source_fragmentation]]` and `[[reference_biomate_search_infra]]`.
