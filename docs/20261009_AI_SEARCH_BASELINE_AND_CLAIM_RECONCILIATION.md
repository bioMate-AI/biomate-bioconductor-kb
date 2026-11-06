# AI-search baseline and benchmark evidence reconciliation

Status: measurement tooling prepared; no five-provider consumer results collected by this work. Published search visibility has not been shown to improve. This is a follow-up to the [five-provider strategy](20261009_AI_SEARCH_VISIBILITY_STRATEGY.md), not a replacement capability audit.

## Confirmed ADMET reporting error

The website attributes **96.3%** to multi-property molecular prediction accuracy, describes **60 compounds**, and claims **58/60** compounds had every property correct. The saved v3 results do not support those descriptions.

Source: `evaluation/results/admet_benchmark_v3/eval_matrix.xlsx`, `Per-Task!A1:H61`, and `Summary!A1:D15`. The 60 task scores average **0.963333**, across **20 distinct compounds** and three prompt types per compound:

| Prompt type | Tasks | Mean task score |
| --- | ---: | ---: |
| Complete compound request | 20 | 0.89 |
| Incomplete request | 20 | 1.00 |
| Negative control | 20 | 1.00 |

The runner (`evaluation/runners/run_admet_benchmark.py`) and adapter (`evaluation/adapters/admet_benchmark_adapter.py`) describe L1–L4 routing, parameter extraction and prerequisite handling, with optional execution scoring separately. The workbook summary reports routing accuracy **0.70**, parameter F1 **0.95**, prerequisite detection **1.00**, and negative-control routing **1.00**. The aggregate must not conceal the routing weakness. It is not a measured probability that a molecule's full ADMET profile is correct. Also, 58/60 is 96.7%, not 96.3%.

Recommended public replacement: “In an internal ADMET workflow-handling evaluation, BioMate averaged 96.3% task score across 60 prompts covering 20 compounds. The evaluation measures routing, input extraction and missing-input handling—not molecular predictive accuracy. Routing accuracy was 70%; parameter F1 was 95%.” Retain separate descriptions of supported ADMET property workflows, but do not present this result as their biological validation.

Affected surfaces include `benchmarks-drug.html` and `benchmarks.html`: visible cards, methodology, FAQ, metadata and JSON-LD. These surfaces have been corrected together, including removal of the unsupported solubility-failure story and unmatched general-LLM comparator. The correction was **published with the October 9 website UI repair**, with live files verified against local hashes. Separate PBPK and BixBench claims remain pending source reconciliation.

## Other claims requiring source reconciliation

- **BixBench 92.7%:** the May 17 handoff labels this a historical peak and describes benchmark-specific deterministic handlers. Its introductory mean and scoreboard mean also disagree (88.7% versus 87.7%). Verify original run records, later productionization and competitor evaluation conditions before presenting a current, directly comparable production score. A historical adapter limitation does not prove the current product lacks the capability.
- **Routing 94.6%:** April positioning material describes an aggregate score and includes partial matches. Reconcile the original result rows before calling it exact first-choice accuracy. Do not silently replace it with a different run's percentage.
- **PBPK 100% on 18 compounds:** the located v6 workbook measures 45 workflow-handling tasks across 15 compounds, not the claimed 18-compound pharmacokinetic validation. Locate the separate scientific execution outputs, observed PK references and pass criteria; this workbook neither validates nor disproves that claim.
- **ADMET scientific datasets:** a separate TDC result inspected during this audit labels its data source `hardcoded_fallback` and uses small endpoint-specific samples. It must not be substituted for a broad external-validation claim.

These are evidence/reporting issues, not a conclusion that BioMate lacks drug-development functionality. No new paid evaluations or production changes were made in this reconciliation.

## Reproducible search measurement

Run `node scripts/ai_search_baseline.cjs plan` to print the exact 24 prompts, categories and five providers. Three repeats require 360 consumer answers; a one-repeat round is preliminary. Use fresh conversations, preserve the actual product/model/settings and record whether search visibly ran. Do not infer an unseen retrieval failure.

Archive each answer and its sources locally. Maintain one JSON object per line in a round-specific observations file. A completed record has:

```json
{"provider":"ChatGPT","interface":"consumer","promptId":1,"repeat":1,"status":"completed","model":"actual displayed model","mode":"actual search setting","language":"en","region":"US","accountContext":"tier and relevant personalization state","capturedAt":"2026-10-09T23:00:00Z","answerPath":"/absolute/path/to/archived-answer.txt","searchRan":true,"citations":["https://biomate.ai/"],"review":{"reviewer":"actual reviewer","mentionsBioMate":true,"capabilityAccurate":null,"citationsSupportClaims":null}}
```

This is an illustrative schema, **not an observation**. Use `searchRan:null` when unknown. Review judgments may be null until checked against evidence. An unrun/error record needs provider, interface, promptId, repeat, status and reason; it cannot carry scored reviews. Never archive account tokens or credentials.

Run `node scripts/ai_search_baseline.cjs summarize /absolute/path/to/observations.jsonl`. It rejects duplicate cells, missing/empty answer archives and invalid records; separates consumer/API and prompt categories; reports explicit counts instead of converting missing tests into zeros. Divide own-site citations by searched answers, mentions by mention-reviewed answers, and scientific/citation judgments by their reviewed denominators. These are answer-level judgments, not per-claim accuracy. Preserve counts and coverage alongside percentages. A homepage citation alone is not scientific evidence.

The tool validates record integrity, not truthfulness of human annotations. It does not log into accounts, invoke paid APIs, submit prompts, schedule monitoring or claim to have tested any provider.

## 2026-10-11 reconciliation pass 2 — BixBench, PBPK, routing, workflow count

Continued the benchmark-evidence reconciliation flagged above. Each claim was traced to its source artifacts under `evaluation/` before any edit. Owner decision (2026-10-11): **BixBench and PBPK are on hold pending clean product-path re-runs** — their live claims were left untouched this pass. **Routing and the workflow-count conflation were corrected** on the static site.

### BixBench 92.7% — HELD for clean re-run (not edited)
Not traceable to any result file; the figure exists only in prose handoff docs. The one machine result in `evaluation/results/` shows early runs of 2.9%/26.7%, not 92.7%. The 92.7% was produced in `local_exec` mode with 9–18 capsule-specific hand-coded Python handlers (`evaluation/adapters/bixbench_adapter.py` `_SPECIALIZED_HANDLERS`) that bypass the LLM and that a real product user never triggers; internal audit `docs/20260516_AUDIT_BENCHMARK_VS_PRODUCTION_GAP.md` calls it "technically true but misleading" and estimates the no-handler product score at ~60–70% (unmeasured). Durable multi-run mean = 87.7% (one handoff intro misstates it as 88.7%, colliding with Biomni Lab's competitor score). **Also flagged for the owner's re-run pass:** `compare.html` misattributes BixBench authorship to "the BioMate team (Xu et al., 2025)"; the source is FutureHouse, arXiv:2503.00096. No clean product-path number exists to substitute, so nothing was published this pass.

### PBPK 100% on 18 compounds — HELD for clean re-run (not edited)
"18 compounds" appears in no PBPK source artifact; the dataset (`evaluation/datasets/pbpk_benchmark/cases.yaml`) is **15 compounds** (PK-001…PK-015). No result file validates predicted PK against observed clinical data. The only executed results (`evaluation/results/pbpk_benchmark_v6/eval_matrix.xlsx`) are L1–L4 workflow-handling: routing 100%, param F1 0.987, but **prerequisite detection 0.333 — a documented FAIL of its ≥0.90 target**. The predictive FDA 2-fold validation exists only as un-run code (`evaluation/scorers/pbpk_scorer.py`) targeting 0.70, never executed. The live "100% pass rate … production-ready for regulatory PBPK submissions" is unsupported and left in place only pending the owner's clean run.

### Routing 94.6% — CORRECTED (published surfaces edited)
94.6% is traceable (April 2026 v11 run, n=120, mean_score 0.946 in `evaluation/results/report_v1.md`) but is a **partial-credit aggregate**: per `run_routing.py` scoring (1.0 exact / 0.5 acceptable-alt / 0.0 wrong), 94.6% = (109×1.0 + 9×0.5 + 2×0)/120. The strict **exact first-choice rate is 90.8% (109/120)**. Corrections applied:
- Lead with **90.8% exact first-choice**; disclose 94.6% as "including closely-related equivalent pipelines (partial credit)".
- Removed the false **"all 36 biomedical domains"** test-coverage claim (the routing dataset spans ~13 domains; source docs only ever say "120-query diversity"). "36 domains" is retained only where it describes the **catalog**, which is defensible (~36 curated of 42 tags). Added the **April 2026** date (a later, non-comparable n=155 run scored 61.9%, per `docs/20260614_benchmark_ledger.md` — flagged to owner as reason to consider a routing re-run too).
- Fixed the cross-run stability methodology card: Kappa=1.0 was computed on a **20% subsample (24 queries)** per `evaluation/results/stability/routing_stability.json`, not "the same 120-query set".
- Files edited: `benchmarks-routing.html`, `benchmarks.html`, `features.html`, `compare.html`.

### Workflow catalog count "4,000+ validated workflows" — CORRECTED
Per the repo registry (CLAUDE.md, 2026-10-05) the catalog is ~4,210 workflows but the **validated-by-real-execution subset is ~1,092**. "4,000+" is a valid catalog floor; the word "validated" conflated the two. Changed "4,000+ validated workflows" → "a catalog of 4,000+ workflows" across `about.html`, `services.html`, `features.html`; in `llms.txt`/`llms-full.txt` the validated subset is now cited explicitly ("1,092 confirmed by real end-to-end execution"). The separate "15,641 Bioconductor KB steps" metric and the `features.html` per-domain catalog breakdown (sums to 4,015) were left as internally-consistent, non-conflating claims.

### Verification
`node scripts/prepare_marketing_shell.cjs --check` passes; `node --test` suite **57/57 pass** (added two regression guards in `tests/seo.test.cjs`: routing exact-first-choice disclosure, and catalog-vs-validated non-conflation). Not yet published to live — pending owner approval for `scripts/deploy_marketing.sh`. The five-provider consumer AI-search baseline remains blocked on account access (Claude/Perplexity sign-in, Grok terms) and webmaster indexing access (Google/Bing), unchanged from the entry above.

## 2026-10-11 reconciliation pass 3 — remaining headline numbers

Extended the sweep to the headline benchmark numbers not yet verified. Each traced to source under `evaluation/` + `docs/`. **Cross-cutting finding: no row-level scored result artifacts exist in the repo for any of these** (no `eval_results.db`, no per-task JSON/CSV); numbers live only in the eval matrix (`evaluation/results/eval_matrix_20260427.txt`), the ledger (`docs/20260614_benchmark_ledger.md`), and positioning docs — and the ledger's cited `…_raw_extract.csv` is absent. All are self-reported (`external_validated=no`) with the hallucination column "pending".

Note: this pass ran while another session was performing a site-wide marketing rewrite — `benchmarks-biology.html`, `benchmarks-drug.html`, `publications.html`, `index.html`, blogs, `sitemap.xml` were all uncommitted ("hot"). Edits were therefore confined to non-hot routing pages; the rest is documented here for the owner / that session to apply.

### CORRECTED (benchmarks-routing.html; non-hot; authorized routing scope)
- **License gating 98.2% → 98.1% (53/54).** Every source (eval matrix, ledger, positioning doc) reports 98.1%; 53/54 = 98.148% → 98.1%. 98.2% appeared nowhere and the page contradicted itself ("1 of 54 test cases" = 98.1%). All 7 occurrences fixed.
- **Parameter extraction 84.8% → relabeled as mean per-case F1 0.848 (partial credit).** Number is documented (v10, n=115) but the scorer (`param_prefill_adapter.py`) computes per-case precision/recall/F1 with a −0.2 `must_not_fill` penalty — a **mean F1**, not the all-or-nothing "a test case passes if all required parameters are extracted" the footnote claimed. Fixed footnote, JSON-LD, stat labels. Also **dropped the "~50% LLM-only baseline"** (cited three incompatible ways: 50% / 61.7% / 63.7%). Caveat for the owner: this figure was **withdrawn from `evaluation/datasets/public_export/leaderboard.md`** as a non-RealBio cross-harness value; consider whether to feature it at all.
- Regression guard added in `tests/seo.test.cjs` (license gating ≠ 98.2; parameter extraction labeled mean F1, not all-or-nothing).

### SUPPORTED AS STATED (no change)
- **Prerequisite recovery 97.5% (39/40, n=40).** Matches the ledger v2 row and the binary trajectory scorer; a later n=80 run also held 97.5%. Caveats: self-reported, hallucination-check pending, no scored artifact on disk.

### NEEDS OWNER DECISION — same "unsupported / no truthful substitute" class as BixBench/PBPK; several live on hot pages, so NOT edited this pass
- **BiomniEval1 — unsupported + self-contradicting.** Only traceable scored value is **64.6%** (n=223, Wilson CI 58.1–70.6%, Claude Sonnet 4.6, 2026-04-27; an earlier run was 22.0%). The site shows **65.9%** (`benchmarks-biology.html`, `benchmarks.html`) and **68–69%** (`compare.html`) — and the *same 65.9%* is presented as **BioMate's** score on one page and the **competitor's** score on another (`compare.html:79,658-659`). `benchmarks-biology.html` also describes it as a "223-question 4-option multiple-choice, 25% random baseline" test, which does not match the real agentic exact-match BiomniEval1 — a fabricated methodology. Honest figure: 64.6% with CI; the MCQ framing and the 65.9%/68–69% split must be reconciled.
- **LABBench 93.9% "highest across all categories" — mislabeled.** 93.9% is real but a **single run, n=33, CloningScenarios subtask ONLY** (1 of ≥3 LABBench subtasks), achieved after injecting subtask-specific sequence computation (restriction sites, Tm, fragment sizes) into the prompt — not a vanilla product path (a 2026-04-20 run scored 50.9% overall / 39.4% CloningScenarios). "Highest across all categories" is unsupported. Baseline comparator labeled inconsistently (Human 60% / Claude 3.5 Sonnet 60%). On `compare.html`.
- **"24/24 AWS Batch runs, not simulated, zero failures" — unsupported.** No 24-row Batch result exists. The only actual Batch-run logs are three single-workflow tests (`docs/20260417/0418/0420_DRUG_DEV_BATCH_TEST_RESULTS.json`) = **1 fail (id 12861 allometric_scaling timeout) + 2 pass**. "24/24" traces to auto-loop *test-case* counts, which an internal doc (`docs/20260616…:296`) states are "Playwright + mock SSE, not 96 real Batch GPU runs." The first cited run ID (12861) is logged as a failure. On `benchmarks-drug.html`, `benchmarks.html` (both hot). The most serious of the set — asserts real production executions that did not happen.
- **"15,641 validated Bioconductor steps" — mislabeled (count plausible).** Count traces to a named extraction DB (1,909 packages) per `docs/20260504…` but that DB is **absent from the repo** (unverifiable here). Internal sources call them "curated / NAMESPACE-validated" steps; `publications.html`'s own abstract says only the "validated head" is execution-confirmed — yet other copy says all 15,641 are "real-execution-validated" (overstatement, flagged by `docs/20261005_MARKETING_COMMITTEE_AUDIT.md`). Fix = describe as curated/NAMESPACE-validated with an execution-validated head. On `publications.html`, `benchmarks.html`, blogs (mostly hot).
- **compare.html "highest across all categories"** (BixBench/BiomniEval1/LABBench) is contradicted by the project's own scored matrix (BixBench 26.7%, SGI-Bench 21.0%, BiomniEval1 64.6%) and should be removed with the BixBench reconciliation.
