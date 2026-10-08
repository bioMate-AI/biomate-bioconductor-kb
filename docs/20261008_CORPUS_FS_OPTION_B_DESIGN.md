# Option B — Corpus-as-Filesystem on BioMate's OWN corpus (on-prem/private)

**Date:** 2026-10-08
**Decision:** user chose **Option B** (re-implement Paperclip's *technique* on BioMate's own
resources) over Option A (consume the hosted service). Rationale: BioMate's differentiated value is
private/regulated/on-prem drug discovery (CRO/IND, customer data) — exactly the regime where the
hosted Paperclip service **cannot** be used because queries leave the perimeter.
**Parent context:** `docs/20261008_BIOMATE_RETRIEVAL_ABILITY_AND_PAPERCLIP_FIT.md`.

## 1. Goal (the technique, not the product)
Give BioMate agents a **grounded corpus-as-filesystem**: navigate a corpus with `ls`/`cat`/`grep`/
`find`, and fan out a lightweight sub-agent per document (map) → synthesize (reduce). Grounded **by
construction** — an agent can only cite text that physically exists in the store, which structurally
kills the `research_query` PMID-confabulation failure (`[[project_research_confabulation]]`). All
in-perimeter: no external service, usable on private/regulated/on-prem data.

## 2. Build on REAL BioMate infra (verified — no new services)
- **No Elasticsearch/PG-search in BioMate** (grep: only a test references ES). → **Do NOT introduce
  ES.** Use what BioMate already runs:
  - **SQLite FTS5** — `local_literature.py` already defines `documents(pmcid,pmid,title,year,
    licence,url)` + FTS5 `chunks`. **Extend this**, don't invent a new store.
  - **sentence-transformers vector** — `vector_search.py` (sqlite + numpy), for optional semantic
    block ranking.
- **Execution** — the existing `run_code` sandbox (`biomate-biotools:1`, `POST /api/code/run`).
- **Map-reduce fan-out + aggregation** — the dormant `agent_orchestrator.py` +
  `RunStateStore`/`CompletionPoller` (shared with the Pattern-Router work).
- **Synthesis** — existing PaperQA2 / `ResearchAgent`.
- **Corpus bytes** — `biomate-data` S3 (private corpora stay in our buckets).

## 3. Architecture (layers)
```
 reduce/synthesis   PaperQA2 / ResearchAgent              (exists)
 map (fan-out)      orchestrator + RunStateStore           (exists, dormant)
 navigation         virtual-FS: ls/cat/grep/find  ──►  SQL/FTS5(+vector) query   (NEW, small)
 store              documents + blocks (FTS5 [+ vec])  extends local_literature   (NEW, small)
 bytes              scoped corpus in biomate-data S3 / disk                       (ingest)
```
**Key Paperclip insight reused:** the "filesystem" is a **virtual translation** — bash paths
(`/papers/<id>/sections/Results.lines`) map to index queries; we do *not* materialize millions of
files. A block = paragraph/table/figure-caption with `(doc_id, section, kind, text, line_start,
line_end)`, so `grep` returns grounded ~200-token snippets with provenance, not whole papers.

## 4. Slices (incremental, disciplined — mirrors the portfolio-scheduler cadence)
- **S1 (this build): the store + virtual-FS query primitives + ingest, with hermetic tests.**
  A `corpus_fs` module: schema (documents + blocks FTS5), `ingest(jsonl)` (extends
  `local_literature.build` to block granularity + section/line metadata), and grounded query
  primitives `ls(doc)`, `cat(doc, path)`, `grep(pattern, path_glob)`, `find(...)` that translate
  virtual paths → FTS5/SQL. Grounded-by-construction (returns only stored text). Pure stdlib +
  sqlite, Python-3.9-safe, no network, inert/additive.
- **S2: map-reduce fan-out + synthesis wiring.** A `corpus_map(question, doc_set)` that dispatches a
  per-doc sub-agent (grep its blocks) via the orchestrator/run-tracking, then reduces via PaperQA2.
  Add a `corpus_fs` fetcher to `federated_query` so grounded local retrieval joins the fan-out.
- **S3: real ingestion + scale.** Ingest a scoped private/on-prem corpus into `biomate-data` S3;
  optional per-block vectors via `vector_search`; refresh pipeline. Gated, opt-in.

## 5. Guardrails
- Grounded-by-construction + provenance on every returned block (doc id, section, line range).
- Inert/additive until wired; S1 touches no live path.
- Private corpora never leave the perimeter (the whole reason for Option B vs A).
- Tests are hermetic (synthetic docs); no real corpus needed to test the primitives.

Build location: `integration/next-phase` (forward tier), module
`backend/lib/galaxy/ai/corpus_fs/`.
