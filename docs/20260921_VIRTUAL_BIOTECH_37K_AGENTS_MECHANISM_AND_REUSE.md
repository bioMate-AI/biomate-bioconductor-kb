# The Virtual Biotech (Stanford/Zou) — 37k-agent mechanism & what BioMate reuses

**Date:** 2026-09-21 · **Scope:** how the ~37,000-agent system actually works, and the concrete patterns
we adopt onto BioMate's execution substrate. Companion to `20260921_COMPETITIVE_INTEL_AI_DRUG_DISCOVERY.md`
(landscape) and `research/guangzhou_all_atom/docs/20260921_LEVERAGE_AND_INSPIRATION.md` (need N8).

**Sources:** *Science* 17 Sep 2026 DOI 10.1126/science.aeg6779 (paywalled — headline numbers via Stanford Med
press); bioRxiv 10.64898/2026.02.23.707551; **public re-implementation `github.com/gliaropoulos/virtualbiotech`
(primary mechanism source — read directly).**

> **Sourcing caveat (important):** the deep mechanism (Semaphore concurrency, schema-checkpoint, cascade,
> Reviewer internals) comes from the **public re-impl**, an explicitly *faithful re-build* citing the preprint —
> so it reflects the paper's **intended** design, corroborated against press for headline numbers, but is not
> guaranteed byte-identical to Stanford's private code. Effect sizes + B7-H3-convergence are HIGH (press-confirmed).

---

## 1. The ~37,000-agent ephemeral fan-out (the "37k")

- **One agent : one clinical trial.** Each ephemeral agent gets **one NCT ID + its full context window** and emits
  **one schema-validated JSON record** of that trial's outcome. That is the whole job — structured extraction of
  one trial. Run size: **37,075 trials in ~6 h**. *(Press cites a ~50k/55,984 corpus; re-impl cites 37,075 —
  likely full-corpus vs analyzed Phase II/III subset. MED.)*
- **Spawn/schedule/bound:** async `asyncio.gather` over all NCT IDs, bounded by a **`Semaphore(32)`** (default) +
  optional rate limit. Not a fancy scheduler — a bounded map.
- **Model tiering:** per-trial extractors = **Sonnet 4.5** (scientist tier); **Haiku 4.5** reserved for Chief of
  Staff + Reviewer, *not* the fan-out. Per-case-study cost small ($46–54); the 37k run is "expensive, rate-limited."
- **Bounding = checkpoint/resume, not orchestration:** a trial is "done" iff `{NCT}.json` exists **AND re-validates
  against the Pydantic schema**; done trials skipped on resume; failures isolated per-trial (`try/except` records
  the error and continues — one trial never aborts the run).
- **Reduce = classical stats, not an LLM.** Fan-out is a pure map to flat JSON files; a **separate deterministic
  layer** (statsmodels: logistic/beta regression, permutation tests, GLMM confounder adjustment, BH-FDR) computes
  the population correlations. **The LLMs extract; deterministic stats conclude.**
- **Headline result:** cell-type-specific ("switch-like") targets → **+40 % Phase I→II, +48 % reach-market,
  −32 % adverse-event rate** (Stanford Med).

## 2. Standing architecture — 11 agents, 4 divisions + Office of the CSO

- **CSO orchestrator** (Sonnet) — pure coordinator, **owns no tools, runs no analysis**: clarify → decompose →
  route (parallel/sequential) → synthesize.
- **Chief of Staff** (Haiku) — MCP-tool-inventory + web landscape brief, parallel with clarification.
- **Scientific Reviewer** (Haiku) — independent QA loop (§3).
- **8 scientists** (Sonnet), each with a **restricted MCP permission set** (separation of duties):
  Target-ID (Statistical Genetics, Functional Genomics, Single-Cell Atlas) · Target-Safety (Bio-Pathways/PPI,
  FDA Safety Officer, Single-Cell) · Modality (Target Biologist, Pharmacologist) · Clinical (Clinical Trialist,
  FDA Safety Officer).
- **Tools = one FastMCP server per data source** (typed fn, docstring→schema, returns `{summary, data, preview}`),
  bridged in-process into the Agent SDK. ~11 servers: Open Targets (GraphQL backbone), ClinicalTrials.gov, PubMed,
  CELLxGENE, Tabula Sapiens, Tahoe-100M, cBioPortal, OpenFDA, DailyMed, gnomAD/ClinVar, DepMap.

## 3. Verification / QA — the anti-hallucination core (the most reusable part)

- **(a) Independent Reviewer loop, *different model*.** A separate Haiku Reviewer scores each output on
  relevance / evidence-strength / thoroughness, emits `APPROVE | CONDITIONAL | REVISE-AND-RESUBMIT` with
  prioritized must-fix/should-fix; on gaps the **CSO re-delegates** before synthesis. Explicitly checks effect
  sizes / stats / uncertainty are reported and STRONG/MODERATE/WEAK ratings are justified.
- **(b) Schema-validated extraction w/ self-correction.** Pydantic model with **status-conditional required
  fields** (COMPLETED ⇒ endpoint results required; TERMINATED ⇒ stop reason + category from a fixed 16-term
  vocabulary); on failure the agent re-consults sources until it passes; `UNKNOWN` only after exhausting evidence.
- **(c) 3-level evidence cascade w/ source verification.** ClinicalTrials.gov → PubMed → web, escalating only when
  fields still missing; **PubMed/web hits are NCT-ID-verified before trusted**; per-field provenance recorded.
- **(d) Deterministic stats outside the LLM** (see §1 reduce).
- **Reproducible workspace:** `sessions/<id>/` with append-only **`trace.jsonl`** (every brief/clarify/decompose/
  dispatch/review/synthesize event) + generated code/figures/data → "a human can re-run any result."

## 4. Honest limits

- **In-silico only** — no wet-lab validation in the paper. **CONFIRMED.**
- **B7-H3 = external convergence, NOT validation.** The system independently proposed a B7-H3 (CD276) ADC for
  B7-H3⁺ fibroblasts in lung cancer from pre-Jan-2025 info; months later an established pharma reached the same
  strategy (Merck/Daiichi ifinatamab deruxtecan, Breakthrough). Third-party strategic agreement ⇒ plausible
  hypothesis — **not** proof the molecule works, and no wet-lab readout. **CONFIRMED (press).**
- **Info-leakage risk** — authors deliberately used post-cutoff readouts to avoid pretraining contamination;
  where impossible, results may be biased. Reproducibility drifts as public DBs update.

## 5. What BioMate reuses (concrete)

The pattern is strikingly close to what we already have — reuse the **orchestration + verification**, keep our
**execution** moat:

1. **Ephemeral per-item fan-out harness (we lack this).** Their `ExtractionHarness` (~150 lines: Semaphore-bounded
   async + schema-validated checkpoint-resume + per-item error isolation + flat-JSON reduce) maps directly onto
   **one agent per accession** (RealBio accession→modality→method / our 28-accession provenance) and **one agent
   per candidate peptide** in the generate→verify→learn loop. Adopt the checkpoint idiom = *"output exists AND
   re-validates against schema"* — cheaper/more robust than current run-state tracking.
2. **Reviewer loop for *reasoning*, not just metrics.** Our auto-loop QC is already verifiable-reward for numeric
   thresholds (hERG, coverage); a different-model Reviewer with an explicit rubric + APPROVE/REVISE generalizes it
   to **AI-findings text + workflow recommendations** — directly targets the `research_query` confabulation gap.
   Wire a Haiku reviewer between findings-generation and report-render.
3. **CSO as a pure coordinator + per-agent MCP permission matrix.** Cleaner than current chat↔galaxy-assistant
   coupling; the permission matrix scopes servers per role and helps the "chat sees only 20 of 60+ sources"
   fragmentation.
4. **FastMCP-server-per-source** — we already expose `mcp__biomate__*` (search_literature, resolve_accession,
   query_database, fetch_public_data, search_workflow, run_workflow). Copy their `{summary,data,preview}` +
   per-server smoke discipline; their public-DB servers (Open Targets, gnomAD, DepMap, cBioPortal, DailyMed,
   Tahoe-100M) are **new sources to wrap** for target-confidence / stratification.
5. **`trace.jsonl` per-session workspace = the data-centric provenance layer** already scoped in
   enterprise-agent-modernization notes. Their format is the concrete spec; cheap to add to the Nextflow executor.

**Where it does NOT map — our moat:** they have **no execution engine** (read-only reasoning over public DBs).
BioMate's AWS-Batch workflow *execution* + the closed generate→verify→**wet-lab**→learn loop is exactly what the
Virtual Biotech lacks and explicitly calls out. **Reuse their brain patterns; our hands are the differentiator.**

## Change log
- 2026-09-21 — created from a mechanism deep-dive (public re-impl code + Stanford Med press). Confidence-flagged;
  re-impl-vs-private-code caveat stated.
