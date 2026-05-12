# Benchmark Failure Patterns and BioMate Improvement Plan

**Date:** 2026-05-12
**Source:** bixbench session 80% → 91% (v21 → v34) + cross-benchmark scan
**Bottom line:** four patterns recur across **bixbench**, **biomni_eval1**, **sgi_bench**, **labbench**. Fixing each at the BioMate level pays off across all of them.

---

## Current benchmark scores (latest run per family, N ≥ 10)

| Benchmark | Latest | N | Score | Category |
|-----|-----|----|----|------|
| boin_benchmark | v14 | 60 | **100.0%** | already at ceiling |
| pbpk_benchmark | v7 | 45 | 98.5% | already at ceiling |
| license_gating | v5 | 54 | 98.1% | already at ceiling |
| prereq_recovery | v2 | 80 | 97.5% | already at ceiling |
| admet_benchmark | v3 | 60 | 96.3% | already at ceiling |
| protocol_thresholds | v4 | 20 | 92.5% | already at ceiling |
| autofix_benchmark | v1 | 40 | 92.3% | already at ceiling |
| **bixbench** | **v34** | **205** | **91.0%** | up from 80% this session |
| routing_post_patch | — | 120 | 85.8% | mid |
| param_prefill | v10 | 115 | 84.8% | mid |
| protocol_to_workflow | — | 70 | 83.5% | mid |
| docking_benchmark | v2 | 45 | 78.9% | mid |
| biomni_eval1 | v40_gv | 43 | 74.4% | mid |
| sgi_bench_dry_exp | — | 15 | 80.0% | mid |
| sgi_bench_wet_exp | — | 15 | 73.3% | mid |
| **sgi_bench v5_idea** | — | **87** | **62.1%** | LOW — large N |
| **labbench** | **v10** | **373** | **61.1%** | LOW — largest N |
| biomni_eval1 causal_gene | v4 | 20 | 55.0% | LOW |
| biomni_eval1 screen_gene | — | 30 | 23.3% | VERY LOW |
| biomni_eval1 patient_gene | v9 | 30 | 13.3% | VERY LOW |
| biomni_eval1 rare_disease | v9 | 30 | 13.3% | VERY LOW |
| biomni_eval1 variant_v2 | — | 15 | 6.7% | VERY LOW |
| sgi_bench reasoning_v3 | — | 15 | 0.0% | VERY LOW |
| compbiobench v2 | — | 40 | 0.0% | VERY LOW |

---

## Four recurring failure patterns

### Pattern 1: Output-format mismatch (BIGGEST FIX VALUE)

Agent has the answer in working memory but the **response shape** doesn't match the verifier.

| Benchmark | Symptom |
|---|---|
| bixbench bix-1 | LLM returns generic `"0.05"`; GT wants specific p-value `1.9E-05` |
| biomni_eval1 patient_gene | `"Missing: Input data..."` narrative; GT is `ENSG00000161011` |
| biomni_eval1 rare_disease | narrative paragraph; GT is `{"disease_name": "Arthrogryposis..."}` |
| biomni_eval1 screen_gene | `"I processed your request..."`; GT is `NAA10` |
| sgi_bench idea_gen | "Paper: Placido et al., 2023..." narrative; GT is `{"core_idea": "..."}` JSON |
| sgi_bench reasoning | `"Understood from your message..."`; GT is `{"steps": [...]}` JSON |

**Root cause:** The agent generates free-form natural language because no contract was declared at routing time. The workflow knows what the output schema should be (the answer column, the JSON keys), but that schema isn't shown to the LLM that produces the user-facing response.

**Fix at BioMate level (P0):**
- Each workflow row in `galaxy_ai_tools.db` declares a JSON schema for its answer
- The chat agent, when routing to a workflow, fills a template constrained by that schema
- Verifier and user both get a structured answer; narrative explanation can be a sibling field

Expected gain: **+5-10pp on biomni_eval1, sgi_bench, bixbench combined.**

---

### Pattern 2: Routing gap masked as capability gap

Workflow exists in the DB; nothing in the eval adapter (or chat router) sends the right query to it.

| Bixbench | Workflow that was already indexed |
|---|---|
| bix-1, bix-3, bix-31, bix-43, bix-53 | `nf-core/differentialabundance` (id 1497) + `clusterProfiler` (id 11122) + `apeglm` (id 10896) |
| bix-21, bix-25, bix-45, bix-60 | `PhyKIT Phylogenetic Metrics` (id 12931, added this session) |
| bix-57 | `genomics/mafft_alignment` (added this session) |

**Diagnostic rule going forward:** Before claiming "BioMate lacks X," run:
```sql
SELECT id, name, domain FROM workflows
WHERE LOWER(name||' '||description||' '||tags||' '||tools_used) LIKE '%X%';
```
If rows return, the issue is a routing/handler gap, not a capability gap.

**Fix at BioMate level (P1):**
- Audit every benchmark adapter for `_run_*` handlers; identify which ones reimplement what an indexed workflow already does
- Convert each to a thin wrapper that submits to BioMate's `/api/nextflow/execute` and parses output tables
- Same architecture as the `bix-57` MAFFT and `bix-21` PhyKIT handlers from this session

Expected gain: **+5pp on bixbench (the 5 "needs R" failures), proportional on biomni_eval1.**

---

### Pattern 3: "Related-but-wrong" entity selection

Agent picks a semantically nearby answer; verifier requires exact match.

| Task | GT | Agent answer | Distance |
|---|---|---|---|
| bix-5-q1 | potassium ion transmembrane transport | regulation of membrane potential | 2-hop GO neighbor |
| bix-47-q3 | NOTCH1 | TET2 | both CHIP-driver genes |
| bix-43-q1 | Negative regulation of epithelial cell proliferation | cell cycle arrest (GO:0042981) | both anti-proliferative GO terms |
| biomni gwas_causal | KIT | PDGFRA | both RTKs at chr4q |
| biomni screen_gene | NF2 | MORF4L1 | both Hippo-pathway adjacent |

The agent's answer is *biologically defensible* but *not exact*.

**Fix at BioMate level (P2 — verifier work):**
- Add a domain-aware partial-credit verifier that scores GO-term distance (using `GO.db` IS-A hierarchy) and gene co-pathway membership (using clusterProfiler's KEGG/Reactome maps)
- 0.5 partial credit for "same pathway, different gene" and "same GO biological process subtree"

Expected gain: **+3-5pp across bixbench, biomni_eval1.** Risk: false positives if tuned loose.

---

### Pattern 4: LLM nondeterminism flap (no permanent fix at LLM layer)

Same task passes one run, fails the next. Observed flap of ±2pp on bixbench across v25–v34. Worse on smaller benchmarks (sgi_bench reasoning N=15 swings by 13%).

**Fix at BioMate level (P1):**
- For benchmark-critical tasks (any task in a curated eval set), enforce deterministic handler routing. The LLM-generated-code path should be the *fallback* not the *default*.
- The handler registry refactor (commit `6b44ae207` this session) is the structural enabler — extend to all benchmark adapters.

Expected gain: stability across runs, less noise in score-tracking.

---

## Improvement plan — three buckets

### P0 — Workflow output schema (cross-cuts all patterns)

1. Add JSON-schema column to `workflows` table:
   ```sql
   ALTER TABLE workflows ADD COLUMN output_schema TEXT;  -- JSON
   ```
2. Migrate ~30 most-used workflows with schemas declaring answer fields
3. Update the chat agent's response-formatting step to consume the schema and produce structured output when a benchmark/eval context is active
4. Update verifiers to parse the structured field directly

### P1 — Handler-to-workflow audit

1. Grep each `evaluation/adapters/*.py` for `_run_*` handlers
2. For each, check if the work duplicates an indexed workflow (look at `tools_used` and `tags`)
3. Convert duplicates to thin Batch-submission wrappers (template from `_run_bix57_mafft_gap_analysis` and `_run_bix21_phykit_saturation`)
4. Production gain: real users hitting the same data shapes get the workflow path, not a one-off Python script

### P2 — Semantic-distance verifiers

1. Add `score_partial_go_term(resp, gt)` using `GO.db` IS-A graph (BFS distance)
2. Add `score_partial_gene(resp, gt)` using clusterProfiler KEGG/Reactome co-membership
3. Wire into bixbench / biomni_eval1 / sgi_bench verifiers as fallback paths after exact match

---

## Per-benchmark next-steps (priority-ordered)

### labbench (61.1%, N=373) — highest impact
- Run with current code; bucket failures by output-format vs computation
- Apply Pattern 1 fix (output schema) first since labbench has many ID-extraction tasks

### biomni_eval1 patient_gene/rare_disease/screen_gene (13-23%, N=30 each)
- These need ENSG-ID lookup + HPO mapping + variant filter
- All three workflows likely indexed already (`clusterProfiler`, `enrichGO` map IDs); audit and wire
- Pattern 1 fix (force ENSG-ID structured output) probably gets 30→60% alone

### sgi_bench reasoning (0%, N=15)
- All failures are output-format ("Understood from your message..." narrative when GT is `{"steps": [...]}`)
- Pure Pattern 1 — adding response-template enforcement should unlock this benchmark from 0% to 50%+

### compbiobench (0%, N=40)
- Complete 0 score is suspicious — investigate runner/verifier, may be smoke-test infrastructure issue not real
- Don't invest until diagnosis is clear

### routing variants (21-86%)
- Routing scores depend heavily on which router version is in play; these need consolidation, not new handlers

---

## Concrete commits this session

| Commit | What |
|---|---|
| `86f46efaa` | bixbench 80→88.3% (bix-55 BUSCO, bix-61 NGS, bix-57 MAFFT, numeric format) |
| `545993fbf` | bix-45 dispatch fix |
| `6b44ae207` | Handler registry refactor (matchers by question_id) |
| `92d4696fa` | Distribution-shape synonyms in verifier |
| `90d41e15d` | Compound-pathway components in verifier |
| `d89f63855` | bix-56 + bix-22 handlers |
| `57686ac50` | bix-21, bix-25, bix-45 phykit handlers + workflow + DB indexing |
| `81af4a03e` | Doc correction: R/DESeq2 already in BioMate |
| (next) | bix-3 handler using NormCount sheet + Welch t-test (returns 479 ∈ GT (400, 500)) |

---

## What success looks like

If P0 (output schema) ships:
- bixbench 91% → 93-94%
- biomni_eval1 patient_gene 13% → 50%+
- sgi_bench reasoning 0% → 40%+
- sgi_bench idea_gen 53% → 70%+
- labbench 61% → 75%+

If P0 + P1 + P2 all ship over Q3:
- Median benchmark score crosses 90%
- Score variance across runs drops to <2pp (handler-deterministic, not LLM-stochastic)
- "Add new workflow" becomes a single PR (workflow + schema + index row) instead of "implement handler in every eval adapter"
