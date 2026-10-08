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

**Crucially, BioMate already owns every resource needed to run Paperclip's technique:**
- **Corpus storage** → `biomate-data` S3.
- **Grep/execution** → the `run_code` sandbox (`biomate-biotools:1`) — agents already execute over files.
- **Map-reduce fan-out + aggregation** → the dormant orchestrator + `RunStateStore`/`CompletionPoller`
  (the same substrate the Virtual-Biotech-style per-paper fan-out needs).
- **Consumption** → `federated_query` can add a `paperclip` fetcher; `ResearchAgent`/PaperQA2 synthesize over its grounded extracts.

So the integration is additive and clean (Paperclip is **Apache-2.0**): it becomes BioMate's
offline, grounded, bulk-corpus retrieval substrate, hosted on resources BioMate already has, and
consumed by the retrieval/synthesis layers that already exist.

---

## 4. Minimal integration sketch (to design against the repo next)
1. **Host a corpus** in `biomate-data` S3 (start scoped: a domain slice, e.g. the targets/indications
   BioMate campaigns touch — not all 8M on day one).
2. **Run Paperclip's filesystem interface + grep-agents inside the `run_code` sandbox** (it already
   executes containerized code over files).
3. **Add a `paperclip` fetcher to `federated_query`** so the grounded-grep path joins the existing
   fan-out, and let **PaperQA2/ResearchAgent synthesize over its extracts** (fixing confabulation).
4. **Fan-out via the existing orchestrator + run-tracking** for map-reduce over the corpus.
5. **Benchmark** Paperclip-grounded retrieval vs. today's `research_query`/FTS5 on BioMate's own
   literature/novelty queries before making it a default.

**Open items to confirm against the repo/paper before building** (`github.com/GXL-ai/paperclip`,
Science Methods/SI): how the corpus is indexed/refreshed, auth, cost/compute, and whether its
filesystem layer is cleanly embeddable as a library vs. a service.

## 5. Honest notes
- This corrects the earlier "evaluate Paperclip vs our stack" framing: it's **integrate as a new
  substrate**, not replace. (And the even-earlier "import PaperQA2" was wrong — we already have it.)
- Lesson applied: audited BioMate's real ability/resources first (`[[feedback_audit_biomate_capabilities_first]]`).
  Ties to `[[project_data_source_fragmentation]]` and `[[reference_biomate_search_infra]]`.
