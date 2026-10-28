# Review brief for the owner's midnight review (living document; first version written 15:35 CDT, to be refreshed as results land)

Draft: `docs/20261029_MANUSCRIPT_LOOP_SMALL_LLM_DRAFT.md` (v1.x). Audit trail: claim ledger `docs/20261030_CLAIM_EVIDENCE_LEDGER.md`, red-team `docs/20261030_REDTEAM_REVIEW.md`, committee synthesis `docs/20261030_COMMITTEE_SYNTHESIS.md` (two of three requested labs reviewed), RSI patch note `docs/20261030_RSI_MANUSCRIPT_PATCH_NOTE.md`, figures `docs/20261030_FIGURES_STATUS.md`, plan `docs/20261030_LESSONS_AND_TODAY_PLAN.md`. Evidence levels used below: **V** = number re-read from a committed result file by script; **D** = read in a committed analysis document, data file not re-read; **E** = exploratory (leads, not established); **U** = unverified; **P** = planned, no result.

## 1. One-paragraph status
The paper today is an **evaluation-instrument and baselines paper with controls**, not a model paper. The central comparison (IH-LM against larger pretrained peptide/chemistry models, both in the same loop) **has no result**: no IH-LM or larger model has been run through the loop, and IH-LM's own neural retrieval module and verifier head do not meet their own thresholds (M3 ablation gap 0.41 against 0.70; verifier AUC 0.53; marked expected-failure, thresholds not loosened). What exists is verified and mostly negative or conditional: the loop's advantage under scaffold shift is not established, a label-free physicochemical rule ties it there, no benchmark passes the validity gate, few-label gain is analog lookup, both fusion techniques failed or were null, and lab-offset anchors are not supported by public data. Everything unfinished is labelled planned.

## 2. Ranked headline findings (including nulls)
| # | finding | level | where |
|---|---|---|---|
| 1 | **Pre-registered claim "loop beats random in both primary regimes" is not met**: scaffold-shifted +22.2 hits per 500 (95 % spread −1.6 to 44.1; post hoc boot-mean 17.7 to 26.5); a physicochemical rule ties the loop there (−0.5; spread −20.0 to 17.2) | V | draft 5.1; `l5_aggregate.json` |
| 2 | **No benchmark passes the no-target validity gate** (primary analysis I fails the fingerprint control, 0.584; M2 typicality control 0.665; M3 not achievable), applied retrospectively; framed as an audit finding with stated limits | V / D | 5.4; `validity_gate_*.json`, V3/V4 docs |
| 3 | **Few-label gain is analog lookup**: nearest neighbour reaches AUROC 0.753 (k = 5) to 0.869 (k = 25) against 0.539 zero-shot; transferable gain not demonstrated (remote bin +0.064, CI −0.002 to 0.135) | V | 5.4; `h4b_baselines.json`, `h4b_strata.json` |
| 4 | **Loop benefit is selection yield, not demonstrated model improvement on new laboratories**: with held-out laboratories as the unit, none of the plain-GBM held-out-ranking contrasts excludes 0 (loop − shuffled +0.071, −0.079 to 0.181); random feedback beats the loop on held-out ranking in the physicochemical learner (unexplained; diagnostics so far exclude artefact and label-range as main causes) | V | 5.2; `l7_aggregate.json` `contrasts_cluster`, L7m log |
| 5 | **Across three retrospective loops on measured data (C2, L5, replay) model-guided selection beats random and lookup reproduces most of the margin under shift**; C2: learn − nearest-neighbour +0.002 (95 % family-cluster CI −0.018 to 0.047); original C2 logged numbers withdrawn | V / D | 5.6; `results_A_aggregate.json` |
| 6 | **Fusion techniques did not work as registered**: T1 permeability primary null, T1 binding failed non-inferiority; T1b permeability null (and its shuffled-label control failed as registered, so exploratory), T1b binding failed | D (V for binding point values) | 5.7 |
| 7 | **Lab-offset anchor calibration not supported on public data** (kill criterion met, median gain +0.005); a data-design finding: needs a shared anchor panel (only 57 anchor rows, small sources) | V (medians) / D (CIs) | 5.7 |
| 8 | **K_phys**: real but heterogeneous offline association in unseen laboratories (median per-lab ρ 0.25; permutation p < 10⁻³); in the loop only **exploratory leads** (held-out AUROC advantage over a shuffled channel in the scaffold-shifted regime for 2 of 3 GBM backends; 15 of 54 dependent contrasts exclude 0 at 99 %, no multiplicity correction); with laboratories resampled K_phys is never better than shuffled knowledge, and is worse in the physicochemical learner (unexplained) | V (offline, counts) / E (loop) | 5.2, 5.3 |
| 9 | **Skill roughly halves for unseen laboratories** (Spearman 0.67 grouped by structure vs 0.30 leave-laboratories-out); 52.8 % of within-source hits and 346 of 500 in-distribution picks come from one laboratory | D / V | 5.1, 5.5 |
| 10 | Cheap-tier general-purpose language models prompted in context are far behind a GBM on the same candidate subsets (exploratory, 4 seeds) | V | 4.5 |

## 3. What the paper can claim today
**Can claim (with the stated limits and interval types):** a validity-gated, family-disjoint retrospective instrument with pre-registered controls; the baseline loop behaviour above; the audit sequence (similarity, typicality, leave-one-out artefacts, estimator and interval-type corrections) as methodology; that loop-specific learning beyond analog/physicochemical lookup is not demonstrated on measured data; the anchor-coverage data-design finding. **Cannot claim:** that IH-LM or any small model matches or beats larger pretrained models; that the loop improves a model on new laboratories; that K_phys or any knowledge helps; novel generation; a first cyclic-peptide benchmark; transferable few-label learning; anything about wet-lab hit rates (no measured data from our own campaigns; wet-lab ingestion and simulation fixtures are integration tests only).

## 4. Planned (pre-registered, no result; none described as a result)
IH-LM ladder R0–R4 and larger pretrained comparators in the loop (PREREG_LOOP L7h/L7j; GPU jobs pending); IH-LM P1 pretraining and gates (`20261030_IHLM_PRETRAINING_PLAN_P1.md`); T2 provenance-aware acquisition; confirmatory seeds 10–29 for the K_phys contrasts (L7k; Holm over three regimes); source-matched random draw (`random_srcmatch`, L7m); sensitivity regime L9; stereoisomer-resolved ranking and per-source curves for language models; S2 physics pilot (cost plan only); PT / PT+k information-privileged baselines in the loop (L7l; parity test pending).

## 5. Known weaknesses
(a) The central claim is untested. (b) Inference rests on one library of 6,960 peptides in which two laboratories hold about two thirds of the peptides and most hits; seed-based intervals do not support statements about new laboratories, and cluster intervals exist only for E-metrics (11 held-out sources in regime L). (c) The gate was applied retrospectively and has low power (about ±0.06 to ±0.10 on 14 to 26 families; zero-shot analyses exclude only effects above about 0.11 AUROC on I and 0.19 on M2). (d) Several results are development data uncorrected for multiplicity. (e) Unexplained negatives (physicochemical K_phys; random feedback beating the loop in that learner). (f) Citations: only Amirahmadi et al. was read in primary text; Graber, Jablonka, CycPeptMP and PeptideCLM 2024 numbers are tagged unverified; others are fetch summaries; the survey and model-survey items (parameter counts, licences) are unverified. (g) The earlier cyclic-LLM work (v4 selector) does not support a binding claim (AUC at chance against hard negatives on 4 of 5 targets; abundance sort 0.996–1.0). (h) IH-LM components below their own thresholds. (i) Intervals have several types (spread, boot-mean, cluster-boot, meta) and are labelled; the pre-registered L5 judgements used the spread.

## 6. Decisions needed from you
| decision | context | my recommendation |
|---|---|---|
| **Licences and weights share-alike** | CycPeptMPDB data licence (recorded CC BY-NC-SA 4.0 internally; website not opened, so unverified); BindingDB/ChEMBL-derived tables are CC BY-SA 3.0; our atom-LM weights were trained on ChEMBL-derived structures (CC BY-SA 3.0); PeptideCLM weights and ChemBERTa state no licence; Landry data preprint CC BY-NC-ND vs repository CC0 (unresolved; not used in any reported result) | Confirm the CycPeptMPDB licence at its download page and get a legal read on whether share-alike attaches to weights before any release; release identifiers plus rebuild recipes for ND-sourced data |
| **Dedicated OpenRouter key** | The shared key had fallen to about USD 4 and other consumers draw on it; the exploratory API arms ran on it | Create a dedicated, capped key if any further API arm is wanted; none is needed for the central comparison |
| **S2 physics pilot (cap USD 80)** | The only arm that would run the product's own co-fold and MM-GBSA chain; frozen 60-compound αvβ6 subset; not executed | Decide after the central comparison exists; low priority for this paper |
| **PeptideCLM-2 route** | The strongest larger peptide-aware comparator (license and remote-code caveats in the model survey, unverified); vendoring and auditing its modelling file is the planned route | Approve vendoring (no remote code) or drop it from the comparison set |
| **Submit or release** | Nothing is submission-ready: central comparison missing, citations unverified, licence questions open | Do not submit; circulate the draft internally; decide on a preprint only after the central comparison and a final ledger rerun |
| **One paper or two** | Instrument-first draft vs the separate RSI governance manuscript (patch note lists the six claims there that must change) | Keep the RSI paper as a companion; apply the patch note |

## 7. Spend summary (what is recorded; not a full accounting)
Exploratory API arms (Tier A, cheap-tier models): about USD 4.2 including controls and probes (above the USD 3.4 estimate; Haiku underestimated 2×) [`docs/20261029_L7_RESULTS_LOG.md`]. Committee review: USD 0.370 counted (cap 6.00; two of three labs; the Anthropic review returned no content) [`docs/20261030_COMMITTEE_SYNTHESIS.md`]. Spot compute: L5/L7 CPU jobs, the C2 audit (about two instances, estimated under USD 3), and the 2026-10-27 atom-LM pretraining (49 minutes on one GPU) were run on spot instances and are **not itemised**; the earlier Stage B co-folding work used Spark and spot Batch and is outside this paper. GPU comparators, P1 pretraining and S2 have not started, so no spend is attributable to them. The shared OpenRouter account's balance history is documented in the L7b amendment.

## 8. Claims table with evidence level
| claim in the draft | level | artifact |
|---|---|---|
| L5 in-distribution loop − random +186.3 (spread 158.5 to 209.0) | V | `l5_aggregate.json` |
| L5 scaffold-shift +22.2; claim C1 not met by the rule | V | same |
| Physicochemical rule ties the loop in regime B | V | same |
| All 15 knowledge-variant spreads include 0 (C2 not met); 5 of 15 mean-based post hoc, not claimed | V | same |
| Loop picks 346 of 500 from one laboratory in-distribution | V | same (`PICK_SOURCE_MEANS`) |
| Regime-L yield contrasts (loop − random feedback +165.0; − frozen +13.2; − shuffled +79.5; seed-based) | V | `l7_aggregate.json` (SHA-256 e2302b87…) |
| Held-out-ranking contrasts with laboratories as the unit (regime L, plain GBM, all include 0) | V | same, `contrasts_cluster` |
| Validity-gate numbers (I 0.584; M2 0.665; M3 not achievable) | V / D | `validity_gate_*.json`, V3/V4 |
| Few-label NN AUROC 0.753 / 0.822 / 0.869; strata; power MDE ≈ 0.11 | V | `h4b_baselines.json`, `h4b_strata.json`, `power.json` |
| K_phys offline association (median ρ 0.252; permutation p; group-level 2×10⁻⁴) | V | `lolo_*permutation_null.json` |
| K_phys loop contrasts, nine configurations; 15 of 54 exclude 0 at 99 % | V (counts recomputed) / E (interpretation) | `kshuf_paired_audit.json` |
| C2 rerun and 40-target family-disjoint extension | V (means, family-cluster CIs) | `results_A_aggregate.json` |
| Anchor test: kill criterion met; planted full coverage +0.151 | V (medians, verdicts) / D (CIs) | `results_B_aggregate.json` |
| T1 / T1b fusion results | D (binding point values spot-checked) | T1, T1b documents |
| Stratified skill (0.67/0.71 grouped; 0.31/0.30 leave-labs-out), feature families, N-methyl ≥ 5 reversal | D | stratification analysis Part B |
| Matched-pair effects (N-methyl +0.252; D↔L flip −0.013) | V | `mmp_effects_pampa.csv` |
| IH-LM design and module status | D (commit messages) | IH-LM spec, commits d0eacfc14, 269c0e2af |
| Literature statements (CycPeptMPDB, PeptideCLM-2, HELM-BERT, Praski, DUD-E, LIT-PCBA, White, Bhardwaj) | fetch summaries (re-check before submission) | draft references |
| Amirahmadi et al. scaffold and Table 3/6 statements | primary text read | converted PDF |
| Graber, Jablonka, CycPeptMP, PeptideCLM 2024, Geylan, Liu, model-survey parameters and licences | **U** | draft Appendix B |
| IH-LM vs larger models; K_phys confirmatory effect; T2; P1; S2 | **P** (no result) | Section 5.8 |
