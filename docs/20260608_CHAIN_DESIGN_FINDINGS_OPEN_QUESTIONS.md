# Chain Generation — Findings & Open Questions for Later Review

**Captured**: 2026-06-08 during pattern library drafting.
**Status**: parked for discussion. No action expected until reviewed.

**Companion docs**:
- `docs/20260608_CHAIN_GENERATION_DESIGN.md` — three-layer architecture
- `docs/20260608_CHAIN_PATTERN_LIBRARY_DRAFT.md` — 12 patterns drafted v1

---

## A. Catalog data-quality findings (audited 2026-06-07/08)

These shape what L1/L2/L3 can actually rely on. All numbers from current `backend/database/galaxy_ai_tools.db`.

### A1. Bioconductor output types are stub-collapsed
2,506 of 3,050 Bioconductor workflows have **identical** `output_types = ["table/csv", "plot/pdf", "object/rds"]`. The indexer (`extract_bioc_input_output` at `backend/scripts/index_all_workflows.py:252`) emits a uniform stub regardless of the package's actual biology. Every DESeq2, Seurat, clusterProfiler, methylKit looks identical at the typed-port layer.

**Implication**: typed-port graph search across Bioconductor is impossible from current indexed data — every Bioc workflow is indistinguishable from every other. The pattern library + prose retrieval path is the only viable composer for Bioc.

### A2. Bioconductor input types are freeform narrative strings
Examples: `"counts.tsv (matrix of raw integer counts)"`, `"ExpressionSet (microarray expression data and phenotypic metadata)"`. Useful as LLM context, useless as type-match keys.

**Implication**: planner-style strict matching does not work on Bioc. The proposed L3 tool-use loop is the right shape because the LLM can read the prose and decide compatibility heuristically.

### A3. biomni_nextflow input types are parameter names, not data types
The same indexer file at line 309 (`extract_biomni_input_output`) stores `params.*` declarations as `input_types`. Drug-discovery workflows therefore have `input_types = ["max_routes", "max_depth", "smiles_file", "n_cpus", "gpu", "use_aws", ...]`.

**Implication**: indexer bug, scope-able as a separate fix. The C2 prototype's `_is_meaningful_input_types` filter already skips these at planning time. Real fix requires re-extracting `input_types` from process input blocks (not params blocks) — see `extract_bioc_input_output` for the correct pattern.

### A4. Cross-source coverage today is hand-authored only
17/29 curated chains span multiple sources (nfcore + nextflow + biomate). Zero of the cross-source joins were auto-discovered — all hand-encoded in `CURATED_CHAINS` at `backend/scripts/index_all_workflows.py`.

**Implication**: the 29 curated chains are the entirety of automated cross-source chaining today. Scaling cross-source coverage requires either (a) L2 pattern library + LLM compose, or (b) hand-curating more chains. Probably both.

---

## B. Pattern library — candidates deferred from v1

Three patterns were excluded from the v1 draft pending review. All three are plausibly distinct shapes that warrant inclusion if you agree.

### B1. `time_series_longitudinal`
Same subjects measured at multiple timepoints. Distinct from `cross_cohort_replication` because of **within-subject correlation** — analyses must use mixed-effect models (lme4, limma `duplicateCorrelation`) or time-aware methods (`maSigPro`, `splineTimeR`). Single-subject perturbation time-courses (drug treatment over 0/6/24/72 h) and developmental atlases both instantiate this.

**Likely include.** Shape: per-timepoint pipeline branches → time-aware joint model → temporal pattern report. Common in pharmacodynamics, single-cell developmental atlases, and circadian transcriptomics.

### B2. `case_control_matched`
Paired/matched design — tumor + adjacent-normal, before + after treatment, twin studies. Distinct from generic `sequential_omics_pipeline` because the paired structure carries information (paired Wilcoxon, McNemar, paired DE) and must propagate through every step.

**Likely include but lower priority.** Could conceivably be absorbed as a *parameterization* of `sequential_omics_pipeline` ("with `paired: true`"). The honest question: is the paired structure a *shape* or a *flag*? If the chain DAG itself doesn't change, it's a flag. Argues for **not** making it a top-level pattern.

### B3. `dose_response_curve`
Distinct shape in pharmacology / toxicology / receptor binding: N doses → N independent measurements → curve fit (Hill / 4PL / Emax) → derived endpoints (IC50, EC50, MTD). Each dose is a parallel branch but they don't merge into a typed result — they merge into a *fitted model* whose parameters are the deliverable.

**Likely include.** Pharma-heavy use cases are core to BioMate's drug-discovery surface. Shape resembles `multi_method_consensus` but the "aggregator" is fitting a parametric model, not voting.

---

## C. Patterns in v1 to reconsider

### C1. `comparative_benchmarking` (entry 10) — RESOLVED: move out of main library
**User decision (2026-06-08)**: the comparison view that matters to users is the before/after parameter diff already implemented inside `iterative_refinement` (auto-loop remediation card shows `was→now` param changes). Method-vs-method bake-offs are a developer-tier concern, not a user-facing pattern.

**Action**: remove `comparative_benchmarking` from the main library; either drop it entirely or relocate to a developer-mode catalog. Note the connection to `iterative_refinement` explicitly so the LLM knows where "comparison" lives.

### C2. `iterative_refinement` (entry 5) — pattern or step-level property?
Already implemented as `auto_loop` infrastructure. Including it as a pattern teaches the LLM it can be **invoked as a macro** rather than just a setting — favors keeping it. But the boundary between "step with QC retry" and "chain pattern" is fuzzy.

**Proposal**: keep, but explicitly note in the doc that the *implementation* is the existing auto-loop infrastructure — the pattern entry is for awareness, not for instructing the LLM to design a new loop mechanism.

---

## D. Architectural decisions parked

### D1. Pattern library storage format
Options:
- (a) Markdown files (`docs/chain_patterns/*.md`) indexed at build time into a retrieval table. Authors edit prose; system retrieves embeddings.
- (b) SQL `chain_patterns` table with structured columns + a `body` markdown blob.
- (c) Hybrid: markdown source-of-truth; SQL is the build artifact; ETL is part of `index_all_workflows.py`.

**Lean: (c).** Markdown is the right format for human-edited knowledge prose. SQL is the right format for retrieval at query time. Pick the hybrid; don't dual-source.

### D2. Confidence threshold calibration
Default-proposed: `>0.75` upfront, `>0.45` stepwise, else reactive. These are guesses. Need real-query telemetry before locking values.

**Plan**: instrument the confidence scorer to log `{query, signals, score, chosen_mode, user_outcome}` for one week post-ship. Tune from data.

### D3. L1 ↔ L2 promotion
When L2 (pattern + LLM compose) produces a chain that the user accepts and runs successfully, should it auto-promote into `workflow_chains` with `source='learned'`? Probably yes, gated on a usage threshold (e.g., same shape accepted 3× by independent users) to avoid catalog bloat.

**Parked**: requires a metrics/telemetry layer that's currently absent. Designing the gate is its own session.

### D4. Reactive-mode analyzer generalization
`bioc_chain_templates.py` produces post-run suggestions for Bioconductor only. Generalizing to any source needs either:
- (a) A typed output manifest contract per workflow (`outputs.json` — C3 from `20260607_PARALLELISM_AND_CROSS_DOMAIN_CHAINING_PROPOSAL.md`).
- (b) An LLM "inspect this run's outputs and suggest next" pass.

**Lean: (b) first, (a) eventually.** (b) ships in days; (a) requires touching every Nextflow workflow.

### D5. Editable chain UI
Required for "user-in-the-loop refinement" to be real. Spec: per-step swap/insert/delete/run-to-here. Existing chain card is read-only.

**Parked**: needs a UX design pass. Big enough to be its own work item; small enough that the v1 chain card already has 80% of the structure.

---

## E. What the v1 pattern library doc does NOT yet cover

Items called out in the draft's open-questions section, restated here for tracking:

1. Whether the pattern library should include patterns for **agent-driven discovery** (LLM tries hypothesis 1, on fail tries hypothesis 2) — could be a meta-pattern wrapping any of the 12.
2. **Negative patterns** — shapes the LLM should explicitly NOT propose. E.g., "don't run DESeq2 on TPM values." Useful as anti-pattern guardrails. None drafted yet.
3. **Domain-specific pattern variants** — cryoEM has its own pipeline grammar (motion correction → CTF → particle pick → 2D class → 3D class → refine); structural biology, microbiome, and clinical trials each have idiomatic shapes. The 12 patterns are biomolecular-data-flavored; whether they generalize across BioMate's full domain spread is untested.
4. **Pattern composition rules** — when patterns combine (e.g., `multi_omics_integration` + `iterative_refinement`), are there gotchas? The cross-reference table in the v1 draft shows combinations exist; it doesn't capture combination *constraints*.

---

## F. Summary table for review

| # | Item | Type | Recommendation |
|---|---|---|---|
| A1 | Bioc output stubs (2,506 identical) | Data | Accept — drives L2/L3 design |
| A2 | Bioc inputs as prose | Data | Accept — feeds LLM context |
| A3 | biomni_nextflow params-as-types | Bug | Fix in separate session |
| A4 | Cross-source = hand-authored | Data | Drives need for L2 |
| B1 | `time_series_longitudinal` | Pattern | **Add to library** |
| B2 | `case_control_matched` | Pattern | **Likely flag, not pattern** |
| B3 | `dose_response_curve` | Pattern | **Add to library** |
| C1 | `comparative_benchmarking` | Pattern | **Resolved 2026-06-08: remove from main library — user-facing comparison is the before/after param diff in `iterative_refinement` (auto-loop UI), already shipped** |
| C2 | `iterative_refinement` | Pattern | **Keep + clarify implementation** |
| D1 | Storage format | Architecture | **Hybrid markdown + indexed** |
| D2 | Confidence thresholds | Tuning | **Instrument + tune from data** |
| D3 | L1↔L2 learned promotion | Architecture | **Park until telemetry exists** |
| D4 | Reactive analyzer generalization | Architecture | **LLM-inspect first; manifest later** |
| D5 | Editable chain UI | UX | **Park for design pass** |

---

## What to do with this doc

This is a *parked items log* — not a plan. When you have time to review the chain design work, this is the agenda. Each row maps to a decision; once decided, the row drops out and the relevant doc (design, pattern library, or code) gets updated.

If the row count grows past ~20, that's a sign we have accumulated too many open architecture questions and should hold a focused decision session before any more code lands.
