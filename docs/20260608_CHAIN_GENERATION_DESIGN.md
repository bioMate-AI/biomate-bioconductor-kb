# Chain Generation Design — Balanced Layered Approach

**Status**: design proposal. Supersedes the planner-centric approach in `docs/20260607_PARALLELISM_AND_CROSS_DOMAIN_CHAINING_PROPOSAL.md`.

**Companion docs**:
- `docs/20260607_PARALLELISM_AND_CROSS_DOMAIN_CHAINING_PROPOSAL.md` — original proposal (C2 BFS planner now deprecated; C1 typed-port backfill scoped down; C7 already shipped)
- `docs/20260607_PARALLELISM_CHAINING_IMPLEMENTATION_NOTES.md` — what's in the worktree today
- `docs/20260509_BIOMATE_MULTI_WORKFLOW_PLANNING_ARCHITECTURE.md` — tier-1/2/3 routing today

## 1. The core tension and the resolution

Two failure modes at the extremes:

| Approach | Failure mode |
|---|---|
| **Strict taxonomy** ("chain_type ∈ {linear, multi_omics, consensus, …}") | Real queries fall between the boxes. LLM stops thinking and starts force-fitting. Ossifies. |
| **Pure free composition** (LLM picks any workflow, any edges, verified only at submit) | Wrong by default. User tunes too often. Not a smart product. |

**Resolution: knowledge-rich, verification-light, user-corrigible composition with three confidence-ranked layers.** Patterns are codified as *knowledge the LLM reads*, not as schema values it picks.

## 2. The three composition layers (ordered by confidence)

### Layer 1 — Curated chains (pre-connected)
The 29 hand-authored chains today (`workflow_chains` table). Exact-match retrieval via `unified_workflow_search.search_chains`. No LLM in the loop when a curated chain scores ≥ threshold. Fast, deterministic, the **floor** for high-frequency requests. Grows deliberately as we observe demand.

### Layer 2 — Pattern library (typical chain shapes) — NEW
A small catalog (~10–15 entries) of canonical chain shapes the LLM is *taught about*, not *picks from*. Each entry is a knowledge document, retrieved by similarity to the query and injected into the LLM's context at composition time. The LLM uses patterns as scaffolding; it can still emit off-pattern when the question warrants.

**Initial pattern set** (seed; literature survey will refine):

| Pattern | Shape | When |
|---|---|---|
| Sequential omics pipeline | linear A→B→C | raw data → result, single modality |
| Multi-omics integration | N parallel single-omics → fan-in | ≥2 modalities (MOFA / DIABLO / Signac) |
| Multi-method consensus | shared input → N parallel methods → intersect | DE with DESeq2+edgeR+limma; variant calling with HC+Strelka+Mutect2 |
| Ensemble annotation | gene/variant list → N annotators in parallel → consolidated | enrichment (GO+KEGG+Reactome), variant annotation (VEP+SnpEff+ClinVar) |
| Iterative refinement | step → QC gate → adjust params → re-run | already implemented as auto-loop |
| Cross-cohort replication | same DAG on N datasets → meta-analysis | validation, biomarker replication |
| Discovery → validation | exploratory on cohort A → confirmatory on cohort B | biomarker discovery, classifier training |
| Branching by QC outcome | step → IF X go to A, ELSE go to B | conditional QC paths |
| Hierarchical re-evaluation | cluster → annotate → sub-cluster → re-annotate | single-cell atlasing |
| Comparative benchmarking | same data, N tool variants, compare | method evaluation studies |

Each entry: name, when-to-use signals, shape diagram, 2 real instantiations from current catalog, common pitfall to avoid.

### Layer 3 — Free composition (tool-use loop)
When L1+L2 still uncertain, LLM composes with three tools:
- `search_workflows(query, domain?)` — semantic search
- `inspect_workflow(name)` — full annotation + I/O + neighbors
- `propose_chain_step(workflow, role, depends_on, rationale)` — incrementally builds the chain

LLM iterates: search → inspect → propose → revise. Same shape as Claude Code's coding loop. Scales to 50k workflows because no workflow list lives in the prompt.

## 3. Surfacing mode (orthogonal to layer)

**Whether and how a chain is shown is a separate decision from whether a chain exists**, driven by a single confidence score.

| Mode | When | UX |
|---|---|---|
| **Upfront** | High confidence — query fully specifies the downstream OR matches a curated chain strongly | Render full chain card; phase cards visible immediately; auto-queue next phase as each completes |
| **Stepwise** | Medium confidence — chain shape is clear but user may want to inspect results between steps | Render full chain card BUT each downstream step gates on a "Run when ready" button. The split-step mode. |
| **Reactive** | Low confidence — downstream depends on what step 1 actually produces | Run step 1. When it lands, a post-completion analyzer reads outputs and surfaces 1–3 contextual "what next" suggestions in chat. Existing `bioc_reactive` pattern, generalized. |

### Confidence signals (explicit, debuggable)

A scalar `confidence ∈ [0,1]` computed from:

| Signal | Weight | Source |
|---|---|---|
| Curated chain match score | high | `search_chains` similarity (BGE + FTS) |
| Pattern library match | medium | retrieval similarity to top pattern |
| Query specificity | medium | named-entity density (organism, modality, contrast, etc.) |
| Downstream determinism | high | does the chain have ≥2 plausible "what next" candidates, or essentially one? |
| User signal | direct override | explicit "do the whole analysis" → +0.3; "let's start with…" → -0.3 |
| User profile | mild | from memory: beginner → bias stepwise; PI → bias upfront |

Mapped to mode via two tunable thresholds (default `>0.75` upfront, `>0.45` stepwise, else reactive). Thresholds are operational settings, not part of the data model.

### Why one score, not two
Tempting to split into "chain quality" and "user readiness" but produces 4 quadrants that collapse to 3 modes. One score keeps it debuggable — dev mode shows `confidence 0.62 → stepwise` with signal breakdown, A/B testable.

### Why mode is orthogonal to layer
A curated chain (L1) might still surface reactively for a low-specificity query. A pattern-library chain (L2) might surface upfront for a tightly-specified query. The LLM/retrieval generates the *plan*; confidence decides *how much of it to show right now*. Separation lets us tune surfacing without re-prompting the LLM.

## 4. How knowledge guardrails the LLM

The LLM stays smart by reading rich knowledge, not by choosing from a closed enum:

- **Pattern docs are retrieved into context, not enumerated as options.** Same as RAG.
- **Curated chains act as "neighbor exemplars."** When composing, show the 3 most-similar curated chains inline. Strong gravity toward shapes that have worked.
- **Common pitfalls are surfaced as "things to avoid."** Each pattern doc has a "Don't do X — leads to Y" section. The LLM otherwise hallucinates these.
- **Workflow descriptions stay rich prose**, not lossy types. Bioconductor's 3,050 packages each have one-paragraph annotations — the LLM reads "DESeq2 takes count matrix + design formula; canonical downstream is clusterProfiler" and reasons. This is essential because the typed-port indexer (`extract_bioc_input_output`) produces near-identical `output_types=["table/csv","plot/pdf","object/rds"]` for 2,506/3,050 Bioc workflows; the prose is the only signal.

## 5. User-in-the-loop

Refinement, not rescue. The chain card is **editable nodes/edges**: swap a step, add a parallel branch, delete a step, run-up-to-here. If the LLM is consistently wrong such that users tune every chain, that's a failure signal, not a feature — drives pattern-library / curated-chain growth.

## 6. What this changes in code

| Component | Change |
|---|---|
| `backend/lib/galaxy/ai/chain_planner.py` (worktree only) | **Deprecate.** BFS over flat types was the wrong abstraction. Keep the file as a reference for the alias-blocklist and junk-type filter logic, which are still useful for verification. |
| `workflow_chains` table | Keep schema. Add a `typical_surfacing_mode` *hint* column (advisory, not enforced). |
| **NEW**: `docs/chain_patterns/*.md` OR `chain_patterns` table | 10–15 pattern knowledge docs. Markdown is easier to author and review; table is easier to query. Decide based on retrieval pattern needs. |
| `unified_workflow_search` | Add `search_patterns(query)` alongside `search_chains`. |
| `ai_assistant.py` chain routing tier | Restructured to: L1 lookup → L2 pattern-retrieval + LLM compose → L3 tool-use loop. |
| Routing return shape | Add `surfacing_mode` and `confidence` fields alongside existing chain payload. |
| Chat UI chain card | Render variants for the three surfacing modes (upfront / stepwise / reactive). Stepwise needs per-step run buttons; reactive needs the post-completion suggestion path generalized. |
| `bioc_chain_templates.py` | Generalize post-completion analyzer beyond Bioc — feeds reactive mode for any chain. |
| Confidence scoring | New module `chain_confidence.py` computing the scalar from signals. Pure function, easy to unit-test. |

## 7. What gets thrown away from the prior plan

- The C2 BFS planner abstraction (planner module file kept for its verification helpers).
- The closed "chain_type" enum I was about to draft.
- The v3 demo page as planner-preview (replace with v3 = pattern-library + editable chain UI demo).
- The C1 typed-port backfill — **partially**. Still useful for fast retrieval pre-filter, but the LLM reads prose. Lower priority.

## 8. Order of operations

1. **Draft the pattern library** (~10–15 markdown entries, with literature-supported shapes). This is the foundational artifact. Review with user before any code.
2. **Confidence scoring module** + unit tests. Pure function, no infra.
3. **L2 retrieval + LLM compose** in `ai_assistant.py`. Tool-use loop for L3 in parallel.
4. **Routing return shape** update (`surfacing_mode`, `confidence`).
5. **Chat UI chain-card variants** for the three modes.
6. **Generalize post-completion analyzer** for reactive mode.
7. **Editable chain UI** for user refinement.
8. **v3 gate** wraps all the above so it can be tested in isolation before promoting to default.

## 9. Open questions

- **Pattern library format**: markdown docs vs SQL table? Markdown is easier to author/review; table is easier to embed + query at scale. Likely: markdown source-of-truth + indexed at build time.
- **Confidence thresholds**: defaults need calibration on real queries. Plan to instrument signal breakdown for a week before locking values.
- **Reactive analyzer scope**: the current `bioc_chain_templates.py` is Bioc-specific. Generalizing to read arbitrary step outputs requires either (a) a typed manifest contract per workflow (C3 from prior proposal) or (b) an LLM "inspect this run's outputs and suggest next" pass. (b) is cheaper to ship, (a) is more reliable long-term. Probably both eventually.
- **L1↔L2 promotion path**: when L2 produces a chain that the user accepts and runs successfully, should it auto-promote into L1? Probably yes with a `source='learned'` tag, but needs a confidence/usage threshold to avoid catalog bloat.

## 10. Honest scope check

This is multi-week work in total. The session-1 deliverable is **the pattern library draft** (item 1), reviewed and approved, before any code lands. That doc is the *test* against which downstream design gets judged — if the patterns are wrong, all downstream code is wrong.
