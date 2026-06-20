# BioMate Benchmark Ledger

**Owner:** yaoyun_dev
**Started:** 2026-06-14
**Purpose:** Append-only ledger of benchmark results. Every entry is `(benchmark, version, date, score, n, sha, notes)`. Old entries stay. A "moving number" is a trajectory, not a contradiction.

## Rules

1. **Append, never overwrite.** New runs add rows. Old rows stay. If you find an old number was wrong, *add a corrected row*; mark the original as `[superseded by row N]` in notes — do not delete.
2. **Every row needs a date.** ISO format `YYYY-MM-DD`.
3. **Cite a system identifier.** Prefer git SHA (`git rev-parse --short HEAD` at time of run). If unknown, use the matrix version (`v11`) or session-doc filename.
4. **Pitch material cites `(score, date, sha)`.** Never bare `score`.
5. **Score format:** `mean ± stderr (n=N)` when available. Otherwise `score% (n=N)`.
6. **Benchmark identity:** if you change the test set, definition, or scoring function, give it a new name (`PBPK_v5` vs `PBPK_v6`). Don't reuse `PBPK` for two different things.
7. **External audit column** — `external_validated` is `yes` only if a third party (leaderboard, advisor, paper reviewer) confirmed the number. Self-reported = `no`.

## Raw extract (supporting evidence)

Mechanical extract from `20260415..20260422_biomate_benchmark_matrix_v{1..13}.xlsx`:
`docs/20260614_benchmark_ledger_raw_extract.csv` (120 rows, deduplication / hand-curation needed before pitch use).

---

## Curated ledger (high-confidence rows only)

Columns: `benchmark | version_or_sha | date | score | n | external_validated | notes`

### Platform — Routing

| benchmark | version | date | score | n | ext.val | notes |
|---|---|---|---|---|---|---|
| cross_domain_routing | v5 | 2026-04-09 | 87.5% | 120 | no | baseline |
| cross_domain_routing | v6 | 2026-04-15 | 83.8% (mean=0.838) | 120 | no | IR-mode hardening; LLM nondeterminism |
| cross_domain_routing | v9 | 2026-04-17 | 91.2% exact / 89.2% P@1 | 120 | no | worst domain: epigenomics 70.6% |
| cross_domain_routing | v10 | 2026-04-19 | 93.3% | 120 | no | SGI/BixBench examples added |
| cross_domain_routing | v11 | 2026-04-20 | **94.6%** | 120 | no | current headline |
| ir_retrieval_search_ranked | v1 | 2026-04-15 | MRR=0.847 P@1=0.742 NDCG@3=0.920 Hit@5=0.967 | 120 | no | BGE bonus weight=0.5 neutral |
| prereq_recovery | v2 | 2026-04-10 | 97.5% | 40 | no | |
| prereq_recovery | v2 | 2026-04-22 | ~stable | 80 | no | n doubled, no degradation |
| license_gating | v5 | 2026-04-10 | 98.1% (53/54) | 54 | no | 1 fail: GROMACS free-vs-commercial |
| memory_benchmark | v1 | 2026-04-15 | 100% weighted (20/20) | 20 | no | aligned LongMemEval + LoCoMo |
| routing_consistency | v1 | 2026-04-13 | 100% consistent | 18 (6×3) | no | small sample |

### Platform — Parameter & QC

| benchmark | version | date | score | n | ext.val | notes |
|---|---|---|---|---|---|---|
| param_prefill | v8 | ~2026-04-17 | ~50% (baseline) | 115 | no | pre-rule layer |
| param_prefill | v10 | 2026-04-29 | **84.8%** | 115 | no | hybrid rule + LLM |
| autoloop_qc_convergence | v1 | 2026-04-17 | 96/96 green | 139 tasks (ADMET 39, CYP_DDI 30, Dock 40, NCA 30) | no | Playwright + real SSE; not real Batch GPU |
| protocol_thresholds | v4 | ~2026-04-22 | 92.5% | 20 | no | |

### Cognitive — BiomniEval1

| benchmark | version | date | score | n | ext.val | notes |
|---|---|---|---|---|---|---|
| biomni_eval1_overall | v1 | 2026-04-15 | 23.3% | 30 | no | initial run |
| biomni_eval1_overall | v3 | 2026-04-16 | 32.0% | 30 (mean of 5 subtasks) | no | format + DB lookup fixes |
| biomni_eval1_overall | v16 | 2026-04-19 | 61.9% (138/223) | 223 | no | gwas_variant +6pp |
| biomni_eval1_overall | v17 | 2026-04-20 | **65.9% (147/223)** | 223 | no | beats Biomni-R0-32B-Preview (~65%) |
| biomni_eval1_patient_gene | v17 | 2026-04-29 | 86.0% | 50 | no | gene-level HPO |
| biomni_eval1_rare_disease | v17 | 2026-04-20 | 66.7% (20/30) | 30 | no | IDF scoring fix |
| biomni_eval1_rare_disease | v17 | 2026-04-29 | 83.3% | 30 | no | |
| biomni_eval1_gwas_causal | v17 | 2026-04-29 | 70.0% | — | no | |
| biomni_eval1_gwas_variant | latest | 2026-04-30 | 69.8% (30/43) | 43 | no | persistent GWAS HTTP cache |
| biomni_eval1_gwas_variant | latest | 2026-04-29 | 74.4% | — | no | |
| biomni_eval1_screen_gene | v17 | 2026-04-29 | **42.0% (BELOW TARGET 70%)** | — | no | ceiling without paper access |

### Cognitive — External benchmarks

| benchmark | version | date | score | n | ext.val | notes |
|---|---|---|---|---|---|---|
| bixbench_mc | v4 | 2026-04-13 | 26.7% (8/30) | 30 | no | ≈ random baseline (25%); MCQ format issue |
| bixbench | v10 | 2026-05-04 | 80.0% (24/30) | 30 | no | judge=None fix; specialized BUSCO/SCOGS |
| bixbench | v15-v17 | 2026-05-05 | 65.4% → in-progress | 30+ | no | PhyKIT DVMC/evo_rate/LBS formula fixes |
| bixbench | v21 | 2026-05-07 | **80%** (30/30 early signal) | 30 | no | notebook full-context + Sonnet extraction |
| bixbench | v36 | 2026-05-15 | **92.7%** (peak, n=205) | 205 | no | local_exec + per-task handlers; commit 165885eac |
| bixbench | v39 | 2026-06-17 | **96.7%** (29/30) | 30 | no | local_exec, HEAD ac18cf6d1; 30-task sample at HEAD after 1276 commits since v36 — system held within 95% CI of v36 |
| bixbench_verified50 | v39-projected | 2026-06-17 | 100% (8/8) | 8/50 | no | projection from v39 30-task sample onto Phylo V50 IDs — small sample, NOT comparable to v38 full-50 92% |
| bixbench | v40 | 2026-06-17 | killed-stalled (HF capsule download bottleneck, not bug) | — | — | superseded by v40c |
| **bixbench_local_exec** | **v36** | **2026-05-15** | **92.7% (peak, n=205)** | **205** | no | **HEADLINE NUMBER.** local_exec = (a) 17 specialized handlers calling BioMate's `/api/nextflow/execute` and other workflows, + (b) for non-handler tasks, BioMate's notebook-grounded extraction pipeline (`_answer_from_notebook_context` in `bixbench_adapter.py:943` — reads BixBench's pre-executed reference notebook through BioMate's LLM-extraction prompt builder + config + verifier-aware answer format). **Same mode Biomni Lab uses to publish 88.7% and K-Dense Web publishes 90.0%.** BioMate beats both. Commit 165885eac. |
| **bixbench_local_exec** | **v40c** | **2026-06-17** | **89.8% ±4.2% (184/205)** | **205** | no | Same mode as v36 at HEAD ac18cf6d1 (1276 commits later). Within 95% CI of v36 peak — system held. **Earlier note that this number was "withdrawn" was wrong — corrected 2026-06-19 after re-reading `bixbench_adapter.py:680-728`: the non-handler path goes through BioMate's `_answer_from_notebook_context`, which is part of BioMate's extraction pipeline, not "BixBench reference notebooks running locally" as I had hastily framed it.** |
| bixbench_local_exec_handler_subset | v40c | 2026-06-17 | 79.6% (43/54) | 54 | no | The 17 specialized handlers (handler-call path only). v36→v40c delta localized to bix-55/56/61 capsule extraction bug; bix-61 q2-q4 need gatk+bcftools ops install (deferred) |
| bixbench_local_exec_extraction_subset | v40c | 2026-06-17 | 93.4% (141/151) | 151 | no | Non-handler subset — BioMate's notebook-grounded extraction (BioMate LLM reading BixBench reference notebooks with our prompt). Improved over time as the prompt and answer-format enforcement evolved. **Earlier label "generic-agent path" was misleading and the row was wrongly withdrawn 2026-06-18; restored here.** |
| bixbench_verified50_local_exec | v40c | 2026-06-17 | 88.0–90.0% (44–45/50) | 50 | no | Projection from v40c full-205 onto the Phylo Verified-50 subset. Matches Biomni Lab 88.7% baseline; matches K-Dense Web 90.0%. **Earlier withdrawal also corrected — this is a real BioMate-pipeline measurement.** |
| bixbench_biomate_exec | v43 | 2026-06-18 | 70.0% ±28.4% (7/10) | 10 | no | Pilot sample (n=10, wide CI). All 7 bix-10 tasks ✅; 3 failures on bix-1 + bix-11. v43 was non-representative (entire bix-10 capsule is easy). Superseded by v44 |
| bixbench_biomate_exec | v44 | 2026-06-19 | 44.0% ±13.8% (22/50) | 50 | no | First credible clean BioMate biomate_exec (pre-biotools-image-build). Per-verifier: range 63.6%, str 35.7%, llm 21.4%. Cost: $0.0041/q; latency 52.5s/q. Failures hypothesized to be Docker-image-bound — partially wrong; see v45 |
| **bixbench_biomate_exec** | **v45** | **2026-06-19** | **40.0% ±13.6% (20/50)** | **50** | no | **Post `biomate-biotools:1` Docker build** (5.46 GB, R + Bioconductor + samtools/bcftools/bwa/mafft + phykit). **Result essentially flat vs v44 (within CI).** The Docker image was NOT the binding constraint — failure-pattern re-audit shows BioMate's `run_code` IS being called and IS executing code (bix-11 response: *"All 10 uploaded files are IQ-TREE logs from `scogs_animals/`* *— none are from fungi"*). **Real bottleneck found in `evaluation/adapters/bixbench_adapter.py:384`: `files[:10]` cap drops half of multi-directory capsules silently.** For bix-11 (fungi vs animals comparison), only animals files reach BioMate alphabetically — fungi files dropped. Cost: $0.0036/q; latency 43s/q. Next leverage: fix the upload cap (sorted is too crude) + fix misrouting to workflow_card for direct-compute questions. |
| bixbench_biomate_exec | v46 | 2026-06-19 | 42.0% ±13.7% (21/50) | 50 | no | After upload-recursion fix (`rglob` + smart size-sorted selection, cap 30). Recovered 1 task. Failure-pattern re-audit: **25 of 29 failures (86%) are the same generic placeholder string** "I processed your request using the available tools" — traced to `frontend/server/galaxy-assistant.ts:6357`, a fallback that fires when Claude's final tool-use turn returns `stop_reason` without an accompanying text block. The agent's tool_result containing the actual answer was being silently dropped at that fallback |
| **bixbench_biomate_exec** | **v47** | **2026-06-19** | **48.0% ±13.8% (24/50)** | **50** | no | **Post agent-fix `78e9098151`** — surface last tool_result content (parsing `stdout`/`output`/`result`) before falling back to placeholder. **Placeholder fallback count dropped 25 → 3** — architectural fix worked. But only +3 PASSED, meaning newly-surfaced outputs were verbose (R install messages, cell-source dumps, file listings) and the judge couldn't extract the answer. Cost: $0.0061/q; latency 51s/q. Current failure layers: 3 placeholder (unparseable JSON in tool_result), 4 workflow_card misrouting, 4 wrong-numeric, **15 verbose** (the next-leverage bucket). Next moves: (1) run_code prompt enforcement to print only answer value, (2) post-process tool_result to extract last `ANSWER:` / non-empty line. **Trajectory:** v44 44% → v45 40% → v46 42% → **v47 48%**. **vs published exec mode: GPT-4o 40.2% (now exceeded); Claude Code 65.3%; Biomni Lab 88.7%.** |
| cross_domain_routing | v13 | 2026-06-17 | **61.9% (96/155)** | 155 | no | NOT directly comparable to v11 98.3% (n=120) — v13 added 35 new test queries + my session changes (14435/14437 description boosts + chain-index bugfix surfacing chains). Per-domain: meta 92%, adv/imm 80%, var/vc/epi/gen/prot 60-67%, dd/sc/tx 50-54%, rna 40%. Need offline analysis to decide if real regression or test-set staleness |
| admet_tdc_hERG | v1 | 2026-06-17 | ~~AUROC 0.9062 (TDC test split, n≈98)~~ **RETRACTED** | 20 | **NOT-COMPARABLE** | ⚠️ **RETRACTED 2026-06-19.** Audit (`/tmp/tdc_admet.log`) shows this was a 2-parameter logP formula (`log10(IC50)=1.4−0.30·logP`) on **20 hand-picked literature compounds** (`run_tdc_admet_benchmark.py:85` `FALLBACK_HERG`), NOT a model on the TDC scaffold split — the run logged "TDC unavailable… using hardcoded reference set." Not comparable to leaderboard GNNs on the 131-compound scaffold test set (wrong model + wrong data + n=20 + selection bias). "TDC test split, n≈98" was a conflation with a different runner's docstring. DO NOT cite externally. Defensible candidate instead: ADMET-AI on official scaffold split (admet_tdc_hERG v2, pending). |
| admet_tdc_DILI | v1 | 2026-06-17 | AUROC 0.7188 | ~71 | external-comparable | Below all 3 baselines (Chemprop 0.847). Uses Lammert 2010 logP+MW heuristic. Honest weakness |
| admet_tdc_PPBR_AZ | v1 | 2026-06-17 | MAE 13.55% | ~424 | external-comparable | Below all 3 baselines (Chemprop 8.4%). Uses Lobell-Sivarajah 2003 sigmoid (fu→PPB%). Honest weakness |
| sgi_bench | latest | 2026-04-19 | 10–17% range | 30 | no | not designed for code-exec tasks |
| labbench | v10 | ~2026-04-20 | 72.7% | — | no | ProtocolQA +15pp over baseline |

### Domain — Drug discovery

| benchmark | version | date | score | n | ext.val | notes |
|---|---|---|---|---|---|---|
| admet | v1 | ~2026-04-22 | 89.3% | 60 | no | initial |
| admet | v3 | 2026-04-29 | **96.3%** | 60 | no | |
| pbpk | v1 | 2026-04-18 | (broken — 102,000% mass-balance error) | — | no | lung-blood ODE bug |
| pbpk | v2 | 2026-04-18 | 71.7% | 60 | no | post mass-balance fix |
| pbpk | v3 | 2026-04-29 | 98.5% (per `20260429_PHARMA_BENCHMARK_PREREQ_GATE`) | 60 | no | rule-based gate added |
| pbpk | v5 | 2026-04-22 | 75.6% | 45 | no | different test set — DO NOT compare to v3 directly |
| pbpk | pharma-run | 2026-04-29 | 100% | 18 | no | curated pharma benchmark subset |
| boin | v1 | 2026-05-01 | 79% → 100% | small | no | intent classifier domain catalog fix |
| boin | v6 | 2026-04-29 | 80.0% | 60 | no | |
| docking | v2 | ~2026-04-29 | 78.9% | — | no | |
| pharmacology_benchmark | post-P1 | 2026-04-29 | 18/18 (100%) | 18 | no | post P1 wiring fixes |

### Domain — CryoEM / multi-modal

| benchmark | version | date | score | n | ext.val | notes |
|---|---|---|---|---|---|---|
| cryoem_gap_tests | latest | 2026-04-29 | 4 pass / 6 skip | 10 | no | skips need live CryoSPARC |
| modality_smoke (5 drugs) | v1 | 2026-05-09 | 5/5 recover known | 5 | no | ADC/PROTAC/mRNA/AAV/CAR-T; smoke not benchmark |
| atlas_modality_triage | v1 | 2026-05-11 | 9/10 retrospective | 10 | no | one tuning pass; mild overfit risk |

### P0 validation (4-test pilot dry-run, 2026-04-16)

| test | metric | result | target | pass? |
|---|---|---|---|---|
| P0-B mRNA codon (SARS-CoV-2 spike 2P) | CAI / MFE | 1.00 / −1480.5 kcal/mol | CAI ≥ 0.85 | **PASS** |
| P0-D pharmacophore GLP-1R (PDB 7KI0) | AUC-ROC | 0.92 | ≥ 0.80 | **PASS** |
| P0-E semaglutide PK/PD vs SUSTAIN-1 | Cmax_ss | 33.27 nM (target 21–39) | in band | **PASS** |
| P0-C nirmatrelvir/Mpro (PDB 7RFS) | docking RMSD | 3.18 Å | ≤ 2.0 | **FAIL** (4/4 H-bonds reproduced; SMILES atom mismatch) |

P0 sha / commit: not recorded at time of run — **back-fill needed**.

### Production E2E

| suite | version | date | result | notes |
|---|---|---|---|---|
| 24 drug-dev workflows on AWS Batch | IDs 12861–12884 | 2026-04-18 | **24/24 pass** | CE `biomate-nextflow-ce-v2`, LT v9 |
| pilot-study.e2e.ts | v1 | ~2026-04-26 | 9/9 sessions | S1 ADMET → DD-1/2/3 |
| autoloop suites (ADMET / CYP-DDI / Docking / NCA-PK) | v1 | 2026-04-17 | 96/96 | Playwright |

---

## Trajectories worth pitching (the "trajectory > snapshot" point)

These are pitch-worthy *because* they move. Cite as trajectory, not as single number:

- **Cross-domain routing:** 87.5 (v5) → 83.8 (v6) → 91.2 (v9) → 93.3 (v10) → **94.6 (v11)** — six versions in 12 days, monotonic except v6 LLM-nondeterminism dip we documented.
- **BiomniEval1 overall:** 23.3 → 32.0 → 61.9 → **65.9%** (v17) — beats Biomni-R0-32B-Preview ~65% baseline.
- **ADMET:** 89.3 → **96.3** — one version cycle.
- **PBPK:** 71.7 → 98.5 → 100% (with caveat: each cycle had a different test set; see notes column).
- **BixBench:** 26.7 (random-baseline MCQ) → 65.4 → **80%** under v21 notebook-full-context.
- **Param Prefill:** ~50% → **84.8%** after hybrid rule + LLM layer.

## Inconsistencies that need resolution before external use

1. **PBPK three numbers** (75.6% / 98.5% / 100%) — different test sets and different scoring functions. **Decision needed:** which test set is the canonical "PBPK benchmark" going forward? Recommend: define `PBPK_canonical_v1` as the n=60 set from 20260429, score=98.5%, freeze it, append future runs against same set.
2. **BixBench MCQ vs open** — 26.7% MCQ ≈ random; 80% under v21 notebook format. These are different benchmarks under one name. Recommend split: `bixbench_mc` vs `bixbench_notebook`.
3. **BiomniEval1 patient_gene** — 23.3 (v1, n=30) → 86.0 (v17, n=50). The n changed. Document.

## What's missing — to be back-filled

- [ ] `system_sha` column populated by running `git log --until=DATE --format='%h'` for each historical row
- [ ] `external_validated` column — currently every row is `no`. Submit at least one entry (ADMET v3 96.3% to TDC ADMET leaderboard) to flip one to `yes`
- [ ] Re-run P0-C nirmatrelvir/Mpro docking with SMILES fix; append row
- [ ] Single source of truth: this file. Update `MEMORY.md` to point pitch claims at this ledger
