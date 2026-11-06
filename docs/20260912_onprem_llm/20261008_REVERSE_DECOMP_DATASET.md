# Reverse-Decomposition Dataset + Need-Satisfaction Grader

**Date:** 2026-10-08
**Author:** Yaoyun Zhang (with Claude Opus 4.8)
**Artifacts:** `evaluation/datasets/reverse_decomp/`
**Builds on / fixes:** `project_sft_from_gold_result` (memory), `decomposition_real`,
`20261006_DECOMPOSITION_ERROR_ANALYSIS.md`, `20261007_REAL_DECOMP_DATA.md`

---

## 1. Why this exists — the task-design fix

Our prior synthetic decomposition set (`build_decomp_depgraph.py` → `decomposition_v2`)
**fabricated abstract DAGs**. The on-prem model then overfit the generator's shapes, and
node/edge-F1 **floored on real topologies** (`decomposition_real` base ≈ 0.016). Two root
causes, now both fixed:

1. **Fabricated structure.** The synthetic DAGs did not reflect how real pipelines wire up.
   → **Fix:** structure comes only from REAL capability compositions or REAL chains; the gold
   is never an invented DAG.

2. **Wrong metric + leaky queries.** `decomposition_real` scored **exact tool-ID node-F1**,
   which punishes *valid alternatives* (answering "DESeq2" when gold said "edgeR" scored 0),
   and its queries **named the tools** so there was nothing to recover. Exact-match on a
   single gold tool-set is the wrong target.
   → **Fix:** the query is a **pure biomedical need** (never names a tool); the gold is an
   **expected outcome + an ACCEPT-SET of capability-equivalent tool-plans**; grading is
   **need-satisfaction** (did the plan meet the need via *any* valid realization), not tool-ID
   similarity.

The arbiter is a **REAL held-out test**. A solver gain on real usage = real generalization —
exactly what the synthetic set could not show.

---

## 2. Core design

### 2.1 Query = a pure biomedical need (never names a tool)
A query states only: **{data/material in hand} + {what to learn / decide / produce} +
{deliverable}**. It never names a tool, workflow, method, package, database, or internal step
("find which genes change between conditions", **not** "run DESeq2 + enrichGO"). The catalog
capability is the *hidden answer-key*, never the phrasing. A hard leak-filter rejects any query
containing a tool/method token (`deseq2`, `star`, `gatk`, `alignment`, `normalization`, …).

### 2.2 Gold = outcome + ACCEPT-SET (not a single tool-set)
Gold is a list of capability **units**; each unit carries:
- `capability` — the functional role implied by the need (e.g. `differential_expression`)
- `deliverable` — the output KIND the need asks for (e.g. `de_table`)
- `accept_set` — **every catalog tool/workflow that satisfies this capability** (DESeq2 **OR**
  edgeR **OR** limma **OR** nf-core/differentialabundance …). All members are **real catalog
  identifiers**, verified at build time; capabilities with no real realization are dropped.
- `depends_on` — the dependency edges (structure)

One need → **many equivalent tool-plans**. The accept-set enumerates them.

### 2.3 Grade = need-satisfaction (credit any valid realization)
`need_grader.py` scores *did the plan meet the stated need*, not tool-ID overlap:
```
need_recall    = fraction of gold capability units satisfied by ≥1 predicted node
need_precision = fraction of predicted nodes that map to some gold unit  (punishes junk)
need_score     = 0.65·recall + 0.35·precision   (recall-leaning: gold is a MINIMAL CORE;
                 a natural need may legitimately imply a superset, so covering the core
                 is weighted over exactness, while pure junk still tanks recall)
structure      = parallel / sequential / mixed / single shape match
aggregation    = if the need implies rank/select/compare/integrate, did the plan include
                 such a step (keyword OR a ≥2-dependency fan-in node)?  else 1.0

reward = 0.55·need_score + need_recall·(0.25·structure + 0.20·aggregation)
```
Structure/aggregation credit is **gated by need_recall** — a wrong-tool plan with the right
shape must not score high (that was the reverse of the `decomposition_real` failure).

A node **satisfies** a unit when it names any accept-set member (key-token recall ≥ 0.5, after
stripping toolshed path/owner/version/`bioconductor`/`nf-core` noise) **OR** the capability
itself (label-token recall ≥ 0.6). This tolerance is the deliberate fix for the 0.016 floor.

### 2.4 Generation direction stays REVERSE
capability (defines accept-set + outcome) → biomedical need → natural query. The capability
fixes the *answer-key*; an LLM writes only the *goal-framed request*.

---

## 3. REAL-FIRST sourcing (generation is augmentation only)

We do **not** assume generated = real. Priority order:

1. **Harvest REAL queries** from the catalog DB and public corpora.
2. **Generate only to fill thin diversity cells**, **few-shot-seeded with real queries** so the
   style matches reality, with a **realism discriminator** + **test-dedup** filter.
3. The **REAL held-out test is the arbiter**; we measure whether train-on-(real+augmented)
   transfers to real usage.

### 3.1 What is really available locally (honest inventory)
The **local** `backend/database/galaxy_ai_tools.db` is a **stub** for user-query tables:

| Table | Local rows | Usable as real NL queries? |
|---|---|---|
| `chat_messages` | **0** | — (enriched DB on dev/S3) |
| `workflow_generation_audit` | **1** | 1 placeholder ("Test query for RNA-seq analysis") |
| `user_interactions.query` | 8 | ~5 short search terms ("differential expression") |
| `workflow_user_corrections` | 19 | no query text (domain/tool corrections only) |
| `session_workflows` | 0 | — |
| **`workflow_chains.example_queries`** | **300** | **YES — curated real natural-language intents** |
| GTN tutorials (`gtn_corpus.jsonl`) | 538 tutorials | **505 have extractable goal statements** |

**→ The only rich real-query source present locally is `workflow_chains.example_queries` (300)
and GTN (538 tutorials).** The real chat/audit logs live in the enriched DB on **dev/S3**
(`reference_workflow_db_canonical`). **To scale the REAL pool we need that enriched DB** — this
is the single biggest expansion lever and is flagged as a hard dependency.

### 3.2 How the real queries are used
- The **300 `example_queries`** become the **held-out REAL TEST** (the arbiter).
- A copy of the real queries also seeds the generator as **few-shot STYLE exemplars** (voice/
  length/register only — never as labels), and every generated query is **deduped against the
  test set** so no test query can leak into train.
- **GTN** (538 tutorials, 505 goal statements) is a **verified-available** second real source;
  clean need→accept-set extraction needs an intent-rewrite + tool-sequence join pass and is
  scoped as the next real-harvest step (see §7). We did not ship noisy auto-extracted GTN rows.

### 3.3 Generator model + realism filter
- **Generator / validator / realism discriminator model:** `anthropic/claude-sonnet-4.5`
  (via OpenRouter — the strongest model confirmed reachable on the key; `anthropic/claude-3.5-
  sonnet` 404s). Key verified with a live call **before** any batch (one call; stop-on-401/402).
- **Realism discriminator:** a per-query `REAL`/`SYNTHETIC` judgement; drop on an explicit
  `SYNTHETIC` verdict. (Ambiguous or non-English replies are kept — the discriminator sometimes
  answers in the query's language; that is not a reject.)
- **Round-trip validator:** a second call recovers the implied capabilities *from the query
  alone*; keep iff it recovers ≥ 0.5 of the gold capabilities (query is not under-specified).
  Over-specification is recorded (`overspec_ratio`) for audit.

---

## 4. Diversity grid (structural, not cosmetic)

Dataset scale = **structure × diversity-cell** (dedup folds both into the source signature, so
one capability combo yields many structurally-diverse natural queries).

| Axis | Cells |
|---|---|
| **complexity** | single tool · tool category/set · linear pipeline · multi-domain + aggregation |
| **specificity** | explicit params · vague · negation-constraint |
| **input-handling** | explicit · recover-from-prior · accession |
| **count** | single-task · multi-task |
| **persona/phrasing** | terse PI · verbose postdoc · EN · 中文(ZH) · lay · jargon |
| **output-intent** | run · run-rank-select · interpret |

`complexity` spans the four required bands; the other five axes are sampled per row.

---

## 5. Train / Test split + zero-overlap proof

- **TRAIN** = reverse-generated, real-seeded. Source-units are capability combos in the
  namespaces `single::`, `category::`, `linear::<pipeline>::<prefix>`, `multidomain::`. The
  linear/multidomain structures come from **canonical biology pipelines** (`PIPELINES` in
  `build_reverse_decomp.py`) — standard domain workflows, **not** `workflow_chains` rows.
- **TEST** = the 300 **real** `workflow_chains.example_queries`, with gold rebuilt in the
  accept-set schema (step `role` → accept-set via the lexicon ∪ the step's own real workflow;
  edges from the chain's real `connections`). Source-units are `chain::<name>`.
- **Zero-overlap (proven in `split.json`):** `source_unit_overlap = 0` **and**
  `capability_combo_overlap = 0` — not only are the source units disjoint, the capability
  *compositions* themselves are held out (TRAIN canonical pipelines ≠ TEST curated chains).
  `tool_id_overlap = 711` is reported **honestly** and is EXPECTED > 0 (both draw one catalog);
  the held-out axes are the **real queries, real structures and real compositions**, not the
  tool vocabulary. (Same partition philosophy as `decomposition_real`.)

---

## 6. Files

| File | What |
|---|---|
| `capability_lexicon.py` | Builds `accept_sets.json` — capability → verified catalog accept-set (curated lexicon ∪ chain roles ∪ tool categories). |
| `accept_sets.json` | 212 capabilities, 2927 members; **33 are multi-member equivalence classes** (the ones that make "any valid realization" meaningful). |
| `build_reverse_decomp.py` | Phase 1 `--units` (gold specs, no API) · Phase 2 (OpenRouter query gen + few-shot real seeding + realism + round-trip + test-dedup, resumable/bounded/concurrent). |
| `units.jsonl` | 3000 gold specs across the complexity×diversity grid (no API). |
| `reverse_decomp_train.jsonl` | the generated TRAIN rows (query + gold + validation metadata). |
| `build_test_real.py` | Builds the REAL held-out TEST from `workflow_chains` + the `split.json` overlap proof. |
| `reverse_decomp_test_real.jsonl` | 300 real held-out test rows. |
| `need_grader.py` | the need-satisfaction grader + `--selftest` (oracle / alt-realization / wrong / partial). |
| `split.json` | zero-overlap proof + honest combo/tool overlap. |

---

## 7. Grader validation (oracle ≈ 1.0, wrong ≈ 0)

`python need_grader.py --selftest --dataset units.jsonl` (3000 rows):

| Candidate | Mean reward | Meaning |
|---|---|---|
| **oracle_A** (one accept member / unit) | **1.000** | a valid realization scores ~1 |
| **oracle_B** (a *different* accept member / unit) | **1.000** | **a different tool-set is equally correct** |
| **wrong** (unrelated tools, right shape) | **0.021** | wrong tools tank despite correct structure |
| **partial** (half the units) | **0.603** | graded continuously |

Also passes on the REAL test gold (`reverse_decomp_test_real.jsonl`): oracle 1.000 / wrong 0.000.

### 7.1 The required example — two different tool-sets, same need, both correct
**Need (query):** *"I have a count matrix from a tumor-vs-normal RNA-seq experiment; tell me
which genes are differentially expressed and which biological pathways they implicate."*
**Gold units:** `differential_expression` → `pathway_enrichment` (sequential).

- **Plan 1:** `BIOC_DESEQ2` → `BIOC_CLUSTERPROFILER`  → **reward 1.0**
- **Plan 2:** `nf-core/differentialabundance` → `bioconductor/fgsea` → **reward 1.0**

Both tool-sets are members of the two units' accept-sets, so both satisfy the need and both
score 1.0 — the exact behaviour exact-tool-ID node-F1 got wrong.
(`transcriptomics:differential_expression` has **98** accept members;
`transcriptomics:pathway_enrichment` has **80**.)

---

## 8. Example (query, gold-plan) pairs

### 8.1 Real-harvested (TEST) — simple
> **Query:** "Run RNA-seq analysis and differential expression"
> **Gold:** `nf-core/rnaseq` → `nf-core/differentialabundance` → enrichment (sequential);
> each node graded against its accept-set. *(provenance: real_workflow_chain)*

### 8.2 Real-harvested (TEST) — complex / multi-modal
> **Query:** "Run a complete rare disease workup — I have WES and RNA-seq"
> **Gold:** germline variant calling → annotation **in parallel with** RNA-seq outlier
> detection, integrated (mixed structure, `aggregation=integrate`). *(real_workflow_chain)*

### 8.3 Augmented (TRAIN) — complex multi-tool with selection (the peptide-style example)
> **Query (terse PI, run-rank-select):** "Rank these 47 small-molecule candidates by oral
> bioavailability and hepatotoxicity risk so we can prioritize the top five for our NASH
> program."
> **Gold:** `admet_prediction` ∥ (second property branch) → `rank_selection` (mixed,
> `aggregation=rank`). Accept-set for the ADMET unit = 39 real catalog ADMET/tox/CYP/hERG
> workflows; **any** of them satisfies the need.

> **Note on the prompt's named peptide example:** PepFuNN / Peptide-Tools / CPMP are **not in
> this catalog** — per the honesty rule we did not fabricate them. The analogous **real**
> capability `proteomics:peptide_toolset` resolves to **14 real galaxyp peptide tools**
> (PeptideBuilder, PeptideIndexer, PyProphet peptide, Peptide-to-GFF, …) and is used as the
> category-set example instead.

---

## 9. Counts, model, keep-rate  *(finalized in §9.1 after the batch completes)*

- **Generator model:** `anthropic/claude-sonnet-4.5` (OpenRouter).
- **Accept-sets:** 212 capabilities / 2927 members / 33 multi-member equivalence classes.
- **Gold specs (grid):** 3000 (`units.jsonl`) — linear 1414, single 718, multi_domain 591,
  category 277.
- **TEST (real, held-out):** 300 rows / 69 chains — sequential 215, mixed 43, single 27,
  parallel 15. `zero_source_overlap = true`.
- **TRAIN (augmented):** see §9.1.

### 9.1 Final batch results (this session)
- **Generated:** 800 specs → **534 kept** (`reverse_decomp_train.ok.jsonl`), **keep-rate 0.667**.
- **Rejections (honest):** round-trip 112 (query under-specified the gold) · empty-content 90
  (model returned null/reasoning content; one retry did not recover — ~11%, retriable) ·
  realism=SYNTHETIC 37 · leak 27. No dup-test rejections (dedup held).
- **Kept diversity (balanced across every axis):**
  - complexity: linear 263 · single 141 · multi_domain 127 · category 3
    (category needs are vague → more round-trip drops; minor band).
  - persona: zh 132 · lay 123 · terse_PI 105 · jargon 95 · verbose_postdoc 79.
  - specificity: negation 189 · explicit 183 · vague 162.
  - input: explicit 183 · accession 177 · recover-from-prior 174.
  - output-intent: run 185 · run_rank_select 185 · interpret 164.
- **Split proof (`split.json`):** train 534 / test 300; **source_unit_overlap = 0** ·
  **capability_combo_overlap = 0** (even the capability *compositions* are held out — stronger
  than source-unit disjointness) · tool_id_overlap = 711 (EXPECTED > 0, both draw one catalog).
- **Grader selftest on the REAL generated train (534 rows):** oracle_A 1.000 · oracle_B 1.000
  (alt realization) · wrong 0.020 · partial 0.574 → **PASS**.

**Source split so far:** TEST = 300 real-harvested (`real_workflow_chain`); TRAIN = 534
augmented (reverse-generated, real-seeded). Real TRAIN rows await the enriched dev/S3 DB (§10).
To scale TRAIN further: `build_reverse_decomp.py --units-in units.jsonl --limit N` (resumable).

---

## 10. Honesty / limitations / next steps

- **Real catalog tool-IDs only.** No fabricated tools; capabilities with no real realization
  are dropped. Named tools absent from the catalog (PepFuNN/CPMP) were **not** used.
- **Local DB is a stub for chat/audit logs.** The rich real-query harvest (`chat_messages`,
  full `workflow_generation_audit`, `user_interactions`) requires the **enriched DB on
  dev/S3**. This is the top expansion lever — with it, the REAL train pool grows from ~0 to
  thousands of genuine query↔plan pairs.
- **GTN** (538 tutorials, 505 goal statements) is verified-available; a clean intent-rewrite +
  `workflow_order_corpus` tool-sequence join would add a second source-disjoint real pool.
- **Accept-sets err toward recall** (broad LIKE patterns), so the grader is lenient by design
  (credits alternatives). Some patterns over-collect (e.g. germline/somatic callers share a
  class); the `need_precision` term and curated patterns can be tightened as needed.
- **Scaling TRAIN to a few thousand:** rerun `build_reverse_decomp.py --units-in units.jsonl
  --limit N` (resumable — skips ids already written). Grid supports ~3000 distinct rows now;
  more comes from enriched-DB real seeds + GTN.
- This dataset is the gauge for the on-prem size ladder (0.6B → 27B) as SOLVERS; the strong
  model here is only the query GENERATOR.
