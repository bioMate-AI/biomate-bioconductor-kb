# Claim–evidence ledger (independent audit, 2026-10-30)

Scope: every numerical or factual claim in `docs/20261029_MANUSCRIPT_LOOP_SMALL_LLM_DRAFT.md` (main draft; read at 9,280 words, re-read after it was updated during the audit), `docs/20261027_PREPRINT_V1_PUBLIC/manuscript_loop.md` (loop preprint) and `docs/20261028_MANUSCRIPT_cyclic_peptide_closed_loop_RSI.md` (RSI draft), plus stale wording in the satellite documents. Method: numbers recomputed from raw artifacts by me (data statistics from the CycPeptMPDB CSV and the affinity table with my own code; results read from the committed JSON; hashes recomputed; citations re-opened with WebFetch). "Re-derived" = value I obtained in this audit. Auditor's own scripts: `/private/tmp/.../scratchpad/qa/data_claims.py` (scratch; not committed, output pasted here).

Status legend: MATCH · MISMATCH (claim differs from artifact or source, or is incomplete) · NO-ARTIFACT (no committed artifact found for the claim) · STALE (superseded or contradicted by a later result, or wording no longer valid) · UNVERIFIED-CITATION (source not re-opened in this audit or not openable).

## Counts, first pass (99 rows; superseded by "Updated counts" in UPDATE 2 below)
**MATCH 70 · MISMATCH 5 · NO-ARTIFACT 5 · STALE 10 · UNVERIFIED-CITATION 9.**
Not counted (artifact exists, not re-derived by me): see "Not re-derived" at the end.

## D. Data and audit statistics (main draft §4.1; loop preprint §4)
| ID | claim | where | claimed | artifact / source | re-derived | status |
|---|---|---|---|---|---|---|
| D1 | peptides after loader filters | draft §4.1 | 6,960 | `data/raw/CycPeptMPDB_Peptide_All.csv` (scratch copy) | 6,960 | MATCH |
| D2 | rows → ids → canonical SMILES | §4.1 | 7,027 → 6,960 → 6,958 | same | 7,027 → 6,960 → 6,958 | MATCH |
| D3 | `Permeability` ≠ `PAMPA` | §4.1 | 73 of 7,027 | same | 73 | MATCH |
| D4 | flat (stereo-free) structures | §4.1 | 2,460 | same (RDKit, isomericSmiles=False) | 2,460 | MATCH |
| D5 | distinct chirality-blind Morgan count fingerprints (r=2, 2,048) | §4.1 | 2,380 | same | 2,380 | MATCH |
| D6 | peptides in flat groups ≥2; max group; median spread | §4.1 | 4,912 (71 %); 116; 0.86 log units | same | 4,912 (70.6 %); 116; 0.855 | MATCH |
| D7 | HELM topology of 8,466 entries | §4.1 | 5,528 / 1,526 / 1,412 | `docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md` A0; I recomputed `Molecule_Shape` only | Circle 5,530 / Lariat 2,936 (= 1,526 + 1,412 = 2,938 ± 2; documented 1-structure disagreement) | MATCH (HELM connections not re-parsed) |
| D8 | Lariat share of rows | §4.4 (v4 audit) | 34.7 % | same CSV | 2,936 / 8,466 = 34.68 % | MATCH |
| D9 | CycPeptMPDB paper counts | §1, §2 | 7,334 peptides; 45 papers + 2 patents; PAMPA 6,941, Caco-2 649, RRCK 186, MDCK 40; Circle <70 % (5,115), Lariat ≈30 % (2,336); CC BY 4.0 article | WebFetch PMC10091415 | identical text on page | MATCH |
| D10 | database version used | §1 vs §4.1 | Intro quotes the paper (7,334 / PAMPA 6,941); Methods use the local file | local CSV `Version` column | local file = version 1.0 (7,451 rows) + 1.2 (1,015) = 8,466 rows, 7,991 unique structure ids, PAMPA non-null 7,298; the draft never states the version | **MISMATCH** (undocumented version difference; also paper's own counts disagree: 7,334 vs 5,115+2,336 = 7,451) |
| D11 | representative-value rule | §2 | "by assay rank (PAMPA, Caco-2, RRCK, MDCK)" | WebFetch PMC10091415 | page: the assay with **more data** is used; assay rank applies only when similar | **MISMATCH** (incomplete) |
| D12 | within-source standardisation: top source share of hits and of peptides | §1, §5.1; preprint §3.1/§4 | 52.8 % of hits (41 % of peptides), 2020_Townsend | `loop_retro/results/l5_label_audit.json` (368 / 697 = 52.8 %, PAMPA label) | mine on `Permeability` column: 52.6 % of 700 hits; peptides 41.4 % | MATCH (0.2 pp from label column) |
| D13 | 2021_Kelly | preprint §4 | 22 % of hits (22 % of peptides) | l5_label_audit.json (156 / 697) | 22.3 % / 21.8 % | MATCH |
| D14 | pooled-label concentration | preprint caveat; RSI §5 | 557 of 711 hits (78 %) from 2013_CHUGAI, 878 peptides | CSV | 557 / 711 (78.3 %); CHUGAI 12.6 % of peptides ≈ 877 | MATCH (±1 peptide) |
| D15 | label-statistic sensitivity | §5.1; preprint §4(iii) | 30 % subsample flips ≈100 labels; Jaccard 0.867 | l5_label_audit.json | 99.7; 0.867 | MATCH |
| D16 | binding table | §4.1, §9.1 | 136,730 rows: BindingDB 108,701; ChEMBL 16,861; both 11,168 | `data/raw/binding_affinity/binding_affinity_v1.csv` | identical | MATCH |
| D17 | peptide macrocycles | §4.1 | 17,120 compounds, 851 targets (ring ≥ 9, ≥ 3 backbone amides) from 36,102 cyclic rows / 17,911 compounds / 923 targets | same | 17,120 / 851; 36,102 / 17,911 / 923 | MATCH |

## L. Controlled loop (L5/L3) and the loop preprint
| ID | claim | where | claimed | artifact | re-derived | status |
|---|---|---|---|---|---|---|
| L1 | regime A | draft abstract, §5.1; preprint §3.1 | loop 236.1 vs random 49.8; +186.3 [158.5, 209.0] | `loop_retro/results/l5_aggregate.json` | identical | MATCH |
| L2 | regime B | same | 52.3 vs 30.1; +22.2 [−1.6, 44.1] | same | identical | MATCH |
| L3 | regime C | same | 212.5 vs 49.2; +163.4 [128.1, 196.3] | same | identical | MATCH |
| L4 | second hit definition, B | same | +41.7 [23.4, 61.6] | `SENSITIVITY_hit_within_group_top10` | identical (A +164.6, C +143.9) | MATCH |
| L5 | pre-registered claim C1 | same | not met | `CLAIM_loop_beats_random_both_regimes` | false (primary); true under second definition | MATCH |
| L6 | rule baselines | §5.1 | loop − N-methyl rule A +105.4 [78.3, 131.6], B +31.5 [10.7, 47.8], C +73.3 [40.5, 101.3]; loop − K_z A +53.6 [25.1, 77.0], B −0.5 [−20.0, 17.2] (rule 52.8 vs loop 52.3), C +53.7 [30.9, 74.3] | same | identical (all six) | MATCH |
| L7 | knowledge variants | §5.1; preprint §3.1 | all 15 99 % intervals include 0 (primary); 1 of 15 above 0 under second definition (descriptor arm B +25.0 [3.9, 54.5]) | same | 15/15 include 0; `kn_B` second-definition +25.0 [3.9, 54.5], 1 of 15 | MATCH |
| L8 | pick concentration | abstract, §5.1; preprint "where the gain comes from" | A: 346.1 of 500 from Townsend vs 206.1 random; C 324 vs 205; B 55 vs 60 | `PICK_SOURCE_MEANS` | 346.1 / 206.1; 323.5 / 204.8; 54.7 / 59.6 | MATCH |
| L9 | superseded L3 values | draft Appendix C/§5.1 | 226.7 vs 50.0 (+176.7 [146.3, 208.9]); 62.5 vs 29.9 (+32.6 [15.7, 51.8]) | `l3_aggregate.json` | identical | MATCH (correctly labelled superseded) |
| L10 | pooled analysis in the loop preprint | preprint §3 "Caveat…", Table 1, Fig. L2 | 396.7 vs 49.9; 366.7 vs 106.6; N-methyl rule 276.3 / 304.0 [304, 304] = "70–83 %" of loop yield | `loop_result.json`, `rule_baseline.json` (values match) | values reproduce, but the pooled outcome is confounded (78 % of hits from one lab), the L5 within-source results contradict the interpretation, and the 304 [304–304] has zero variance because of dataset-order tie breaking (fixed in L5: B rule 20.8) | **STALE** |
| L11 | loop preprint discussion | preprint §4 | "far better than random … including when the starting peptides share no scaffold with the pool" | l5_aggregate (B +22.2 [−1.6, 44.1]) | contradicted for the primary hit definition | **STALE** |
| L12 | explanation of the knowledge null | preprint §4 | "in this data the fingerprints already carry that information" | none | no experiment tests this; a non-detection with ±30-hit intervals is not evidence of redundancy | **NO-ARTIFACT** |
| L13 | N-methyl rule concentration | preprint caveat | 89 % / 93 % of picks, 272 of 276 and 301 of 304 hits from the same lab | none located (searched `loop_retro/results/*`, `docs/`) | not found | **NO-ARTIFACT** |
| L14 | RSI draft | RSI §5 | "the N-methyl-count baseline that recovers 70–83 % of the yield draws 98.5 % of its hits from that same source" | pooled analysis (see L10); 98.5 % not located | 70–83 % is the superseded pooled number; within source the N-methyl rule reaches 130.7 / 236.1 = 55 % (A) and 20.8 / 52.3 = 40 % (B) | **STALE** |

## M. Replay with controls (L7; main draft §5.2, abstract (iv))
All from `loop_retro/results/l7_aggregate.json`.
| ID | claim | claimed | re-derived | status |
|---|---|---|---|---|
| M1 | gbm, regime L, yield | loop − random feedback +165.0 [156.3, 175.6]; − frozen +13.2 [2.6, 23.7]; − shuffled +79.5 [67.9, 93.4] | identical | MATCH |
| M2 | physchem channel | A loop − random feedback +123.8 [112.5, 133.5]; B +20.0 [15.6, 24.6] | identical | MATCH |
| M3 | plain GBM regime B seeds | 2 seeds, inconclusive | n = 2 | MATCH |
| M4 | data-matched control, L, held-out AUROC gain | loop − one-shot +0.003 [−0.034, 0.038] | +0.003 [−0.0342, 0.038] | MATCH |
| M5 | random feedback, L | loop − random feedback −0.072 [−0.113, −0.014] | −0.0716 [−0.1133, −0.0143] | MATCH |
| M6 | K_phys on − off (yield) and contradicted | A +2.4 [−1.1, 5.4]; L −0.1 [−3.8, 4.8]; contradicted A −7.7 [−12.5, −2.7], L −5.7 [−9.2, −2.0] | identical | MATCH |
| M7 | knowledge-shuffle gain | A +0.056 [0.040, 0.070]; L +0.081 [0.046, 0.116] | A 0.0555 [0.0404, 0.0703]; L 0.0812 [0.0456, 0.1164] | MATCH (numbers; the inference drawn from them is defective — Red-team R4) |
| M8 | "shuffled and frozen controls pass in every reported regime" | passed | `controls` key of the aggregate is `{}`; pass/fail flags are not stored in the artifact | **NO-ARTIFACT** |
| M9 | exploratory API arms (appendix A15) | Haiku-class A loop 28.25, frozen 28.5, GBM 44.75 [40.5, 49.0], random 19.75; Gemini-class L loop 31.75, random 34.5, GBM 62.5 [59.25, 65.75] | identical (n = 4 each) | MATCH |

## B. Benchmark instrument (main draft §4.2, §5.4)
| ID | claim | claimed | artifact | re-derived | status |
|---|---|---|---|---|---|
| B1 | `items_I.csv.gz` SHA-256 | 5da88542…601e | `retro_recovery/data/` | recomputed identical | MATCH |
| B2 | `folds_v1.csv` SHA-256 | a896c580…c5c409 ("to be re-verified") | same | recomputed identical | MATCH |
| B3 | strongest baseline on analysis I | AUROC 0.620 | `results_V2_I.json` (B3_nn_neg) | 0.6197 | MATCH |
| B4 | physchem-profile arm | 0.565 [0.505, 0.622] | same (S1d_profile) | 0.5647 [0.5051, 0.6222] | MATCH |
| B5 | analysis I size | 46 targets, 26 families | same | 46 / 26 | MATCH |
| B6 | knowledge coverage | KB gate non-constant 0 of 46; RGD 3 | same (coverage) | 0 / 46; 3 / 46 | MATCH |
| B7 | gate, analysis I | 0.503 [0.458, 0.550]; 0.559 [0.499, 0.619]; 0.584 [0.533, 0.636] | `validity_gate_I.json` | identical; VALID = false (also fails o_frac, has_halogen) | MATCH |
| B8 | gate, M2 | 0.665 [0.551, 0.772]; 0.690 [0.578, 0.795]; 0.676 [0.541, 0.803] | `validity_gate_M2.json` | identical | MATCH |
| B9 | analysis M | 299 targets; NN baseline 0.914; fingerprint control 0.315 | `results_V2_M.json`, `validity_gate_M.json` | 299; 0.9141; 0.3150 [0.279, 0.352], 120 families | MATCH |
| B10 | M3 | loosest caliper 257 positives, 15 families; not achievable | `data/M3_build_log.json`, `validity_gate_M3.json` | 257 / 15; gate VALID = false | MATCH |
| B11 | few-label baselines | NN 0.753 [0.715, 0.789] / 0.822 / 0.869 [0.835, 0.899]; FP-k 0.750 / 0.817 / 0.861; PT+k 0.672 [0.617, 0.724] / 0.736 / 0.823; zero-shot 0.539 [0.478, 0.605] | `results/h4b_baselines.json` | identical | MATCH |
| B12 | gain over zero-shot | "+0.21 to +0.34" | same | +0.214 (k=5), +0.282 (k=10), +0.330 (k=25) | **MISMATCH** (+0.33) |
| B13 | v4 coverage | 2.5 % of analysis I items | `s3_v4eval_A1_v4.json` | items_scored_frac 0.025 (9 targets, 5 families) | MATCH |

## K. Models (main draft §4.4)
| ID | claim | claimed | artifact | re-derived | status |
|---|---|---|---|---|---|
| K1 | atom LM | 25.5 M params; 2.87 M molecules, 49,428 macrocycles | S3 `allatom/pretrain/pretrain.json` | 25,483,264; 2,873,244 training molecules (corpus file lists 2,878,245 unique SMILES); 49,428 | MATCH |
| K2 | v4 size | "5 M parameters" | `runs_helm/unified_cyclic_llm_v4.pt` | 5,022,976 | MATCH |
| K3 | v4 audit | regressor CV R² 0.069; 9.1 % verbatim overlap; 34.7 % Lariat | `v4_eval/audit_data_result.json` | 0.069; 115 / 1,269 = 9.06 %; 0.347 | MATCH |

## KB. Knowledge channel and audit (main draft §4.7, §5.3, §5.5)
| ID | claim | claimed | artifact | re-derived | status |
|---|---|---|---|---|---|
| KB1 | K_phys leave-one-lab-out | median 0.25 [0.13, 0.49], 19 / 21 labs, pooled 0.39; 21 labs, 6,776 peptides | `kb_audit/lolo_summary.json`, `lolo_pooled.json` | 0.2519 [0.1309, 0.4922]; 19 / 21; 0.3914; 21; 6,776 | MATCH |
| KB2 | K_nme | median −0.01, 10 / 20 | same | −0.0065 [−0.104, 0.282]; 10 / 20 (pooled held-out 0.324, lab-bootstrap CI includes 0) | MATCH |
| KB3 | TPSA alone | 0.41 pooled | `lolo_pooled.json` | 0.4147 | MATCH |
| KB4 | negative control | 2 of 180 rule tests active | `negative_control.json` | 30 shuffles × 6 rules: 2 active (hbd) | MATCH |
| KB5 | matched-pair counts | N-Me: 4,139 pairs, 10 labs, 9 / 10 same sign; D-flip 7,423 pairs, 8 labs, 4 of 8 | `peptide_sar_rules_v1.json` | identical | MATCH |
| KB6 | matched-pair effects | N-Me +0.45 z [0.19, 0.71]; D-flip −0.03 [−0.09, 0.03] | rules JSON has `weight`/`ci` = null for pair rules | effect sizes not located in the artifact | **NO-ARTIFACT** (counts verified; effects not) |
| KB7 | citation audit (KB audit doc; relayed in summaries) | 54 of 57 citations real | `kb_audit/citation_check.json` | verdicts: 45 MATCH, 5 MATCH_3of4, 5 PARTIAL, 2 NOMATCH | **MISMATCH** (strict tally 45 / 57) |
| KB8 | earlier N-methyl validation | "median within-laboratory Spearman 0.10; 7 of 8 laboratories" (`20261027_KB_RULE_VALIDATION.md`; earlier draft §4.7) | KB audit / `lolo_summary.json` | median −0.01, 10 / 20 in the larger lab set | **STALE** (removed from the current draft; still in the older doc) |

## S. Stratification and error analysis (main draft §5.5)
| ID | claim | claimed | artifact | re-derived | status |
|---|---|---|---|---|---|
| S1 | pooled Spearman by CV scheme | 0.67 / 0.71 grouped by flat structure; 0.31 / 0.30 leave-labs-out; descriptor 0.67 grouped, 0.26 leave-labs-out; N-methyl rule 0.25 | `stratification/data/cv_preds.csv.gz` | 0.666 / 0.708 / 0.666; 0.313 / 0.301 / 0.264; rule 0.25 | MATCH |
| S2 | chirality gain | ≈0.04 (and 0.05 in the earlier error analysis) | same; `BASELINE_ERROR_ANALYSIS.md` | grouped +0.042; random 0.706 → 0.757 (+0.051) | MATCH (two analyses report different random-CV values; see R9) |
| S3 | earlier error-analysis numbers | random CV 0.713 / 0.766; grouped 0.663 / 0.712; Faris 0.49, Bhardwaj 0.42; 28 % of identical-fingerprint pairs differ > 1 SD | script only in the auditor's session scratch (`err_analysis.py`); not in the repository | rerun started, not finished at commit; stored predictions give 0.706 / 0.757 and 0.666 / 0.708 | **NO-ARTIFACT** (no committed script) |

## P. Earlier replays
| ID | claim | artifact | re-derived | status |
|---|---|---|---|---|
| P1 | permeability replay hits: Townsend 29.0 ± 4.4 vs 9.0 ± 1.0; Kelly 17.3 ± 11.0 vs 7.3 ± 1.2; Faris 11.3 ± 3.2 vs 8.0 ± 2.0 | `results/permeability_replay.json` | identical (UCB vs random, 3 seeds) | MATCH |
| P2 | replay protocol (3 campaigns, 20 initial labels, 5 × 10, 3 seeds, 80/20 molecule-disjoint) | same | identical | MATCH |

## R. RSI draft (Stage B, binding model, other)
| ID | claim | artifact | re-derived | status |
|---|---|---|---|---|
| R1 | Stage B: 104 test complexes; default 57.7 %; selector 59.6 %; strongest baseline 60.6 %; oracle 76.9 %; oracle − default +19.2 pp [8.8, 28.5] | `cyclic_complex_benchmark/results/stageB_eval_S2.json` | 0.577; 0.596; 0.606; 0.769; 0.192 [0.088, 0.285] | MATCH |
| R2 | binding model: random-split RF R² ≈0.52, ρ 0.71; novel target (PD-L1 + αvβ6, n = 327) R² 0.18–0.26, ρ 0.42 | `results/binding_model_metrics_cyclic.json` | RF 0.523 / 0.714; novel RF R² 0.256, ρ 0.421 (n = 327) | MATCH |
| R3 | permeability scaffold-R² 0.231 ("leak-free Bemis–Murcko, n = 8,466") | `results/c4_dynamical_permeability.json` | `baseline_ref_r2` = 0.231 is a reference constant; the ECFP static model in the same file scores 0.237; n = 8,466 is rows, not unique or labelled structures; "leak-free" not verified given 71 % stereoisomer groups | **MISMATCH** |
| R4 | pooled confound | see D14 | 557 / 711 = 78 % | MATCH |

## T. Stale wording elsewhere in the repository
| ID | location | stale statement | status |
|---|---|---|---|
| T1 | `docs/20261029_HYPOTHESES_SMALL_LLM_LOOP.md` §1 fact 1 | quotes L3 (+176.7; +32.6) as the loop evidence | STALE (L5: +186.3; +22.2 n.s.) |
| T2 | same, H1 and H4 text | "the small LLM", "≈25 M, v5" | STALE (IH-LM definition, 2026-10-30) |
| T3 | `docs/20261029_MASTER_PLAN_AND_CRITICAL_PATH.md` WS1 row and cost-cap paragraph | "v5 small model"; "L7 frontier-LLM in-context … USD 25" | STALE |
| T4 | `docs/20261029_MANUSCRIPT_FIGURE_AND_TABLE_PLAN.md` F4, F6 | "small cyclic-peptide LM / v5" | STALE |
| T5 | `docs/20261029_MODEL_COMPARISON_ANALYSIS_SPEC.md` line 3 | "small LLMs (atom LM 25 M; v5 …)" | STALE |
| T6 | `docs/20261028_CYCLIC_PROGRAM_MANUSCRIPT_INVENTORY.md` §G | C2 log "learn 0.299 / random 0.118 (+0.181)" presented as pending reproduction; the later C2 audit reports that most of the margin came from a fixed cross-target transfer model and 7 of 10 targets are paralogs | STALE |

## C. Citations (spot-check, 15 attempted, 11 re-opened and confirmed)
| ID | work | claim as written in the draft | result of re-opening | status |
|---|---|---|---|---|
| C1 | Li et al. 2023 CycPeptMPDB (PMC10091415) | counts, shapes, licence | confirmed (but see D10, D11) | MATCH |
| C2 | Amirahmadi et al., arXiv 2511.21566 | AttentiveFP 86.2 → 66.1; Tanimoto-kernel GP 0.897 / 0.804; Murcko "ignoring chirality"; stereo/closure ablations as future work | all four confirmed in the full text (converted PDF); caveat: the GP result is on a length-focused subset of 5,826 samples with binary labels (permeable ≥ −6) | MATCH |
| C3 | Praski et al., arXiv 2508.06199 | 25 models, 25 datasets, nearly all negligible or no improvement over ECFP | confirmed; omits the stated exception (CLAMP, fingerprint-based, significantly better) | MATCH |
| C4 | Huang et al., arXiv 2507.21404 | 2,491 2D-identical inactives; memorisation baseline matches published models | confirmed | MATCH |
| C5 | Feller et al. PeptideCLM-2 (PMC12803269) | 32 M / 114 M / 337 M; 405-token vocabulary; AUROC 0.836 ± 0.011; June 2026 version | confirmed (also: 108.6 M PubChem + 9.6 M ESMAtlas + 49 k lipids) | MATCH |
| C6 | Lee et al. HELM-BERT, arXiv 2512.23175 | DeBERTa on HELM; 39,079 peptides; cyclic permeability gains | confirmed | MATCH |
| C7 | White et al. 2011 (PMC3210067) | partial vs full N-methylation; 28 % oral bioavailability in rat | confirmed | MATCH |
| C8 | Bhardwaj et al. 2022 (PMC9490236) | 84 designs > 1e-6 cm/s; 29 of 35 structures within 1.2 Å | confirmed | MATCH |
| C9 | Chen et al. 2019 DUD-E (PLoS One) | ligand-only AUC 0.98; analogue and decoy bias | confirmed | MATCH |
| C10 | BindingDB licence page | CC BY 3.0 curated; CC BY-SA 3.0 ChEMBL-imported | confirmed | MATCH |
| C11 | wwPDB usage policy | CC0 1.0 | confirmed | MATCH |
| C12 | Graber et al. 2025 (Nat Mach Intell) | ≈600 PDBbind–CASF similarities, 49 % of CASF complexes | publisher page redirects to an authentication wall; not re-opened | UNVERIFIED-CITATION |
| C13 | Jablonka et al. 2024 (Nat Mach Intell) | fine-tuned GPT-3 vs conventional ML in the low-data limit | same wall; draft already tags "search level" | UNVERIFIED-CITATION |
| C14 | Li, Yanagisawa, Akiyama 2024 (CycPeptMP, Brief Bioinform) | MAE 0.355, correlation 0.883 | Europe PMC returned 503 / 403 on repeated tries | UNVERIFIED-CITATION |
| C15 | Feller and Wilke 2024 (PeptideCLM, PMC11326283) | 6-layer, 12-head, 768-d; 23 M molecules (10 M peptides); leave-one-cluster-out ROC-AUC 0.781 ± 0.067 | PMC page returns a CAPTCHA; a web search confirmed only the title, authors and abstract (no numbers); bioRxiv returned HTTP 429 | UNVERIFIED-CITATION |
| C16 | Geylan et al. 2024 | cited as described by Amirahmadi | draft already tags LIT-UNVERIFIED | UNVERIFIED-CITATION |
| C17 | Liu et al. 2025 (13-method benchmark) | same | draft already tags LIT-UNVERIFIED | UNVERIFIED-CITATION |
| C18 | ChEMBL licence (CC BY-SA 3.0) | §9.1 | not re-opened in this audit | UNVERIFIED-CITATION |
| C19 | CREMP Zenodo records (CC BY 4.0) | §9.1 | not re-opened | UNVERIFIED-CITATION |
| C20 | Landry data (preprint CC BY-NC-ND 4.0; repository CC0-1.0) | §9.1 | not re-opened | UNVERIFIED-CITATION |

## Not re-derived (artifact exists; values taken from the stated document)
Stratification Part B beyond S1 (physchem alone 0.61 of 0.67; removing physchem −0.10; extrapolation 0.49 vs 0.14–0.23 and 0.61 vs 0.43–0.45; N-methyl ≥ 5 −0.30 [−0.41, −0.12]; 0.50 → 0.62 and 0.38 → 0.64 chirality gains; source concentration 99.8 % / 97.6 %); v4 reproduction AUCs; renal ρ 0.27 → −0.26 and the FEP control edge (−0.18 vs −0.95); BoltzGen LOTO smoke Δ ipTM −0.16; contamination fractions (58 % / 45 %); PeptideCLM-2 corpus overlap 8.06 %.

## Notes on the audit itself
The loop draft changed three times during this pass (abstract, §5, appendix); the ledger refers to the version at commit time of this file. The error-analysis rerun (S3) was still running when this ledger was committed.

---
# UPDATE 2 — re-run on the updated drafts (2026-10-30, later session)
Scope of the re-run: `20261029_MANUSCRIPT_LOOP_SMALL_LLM_DRAFT.md` (re-read at 14,150 words, commit e51b106ff; it was edited while I read it), `20261027_PREPRINT_V1_PUBLIC/manuscript_loop.md` (commit 5442beac3), `20261030_RSI_MANUSCRIPT_PATCH_NOTE.md`, and the four new items requested by the coordinator: (1) interval types (L7j/L7k), (2) K_phys permutation null and paired contrasts (KB audit §9a), (3) T1 fusion and anchor test, (4) committee synthesis. Re-derivation: L5 from the 810 raw per-seed files on S3 (`res5/`, my own bootstrap), the paired knowledge contrasts for all 30 arm-regime-definition cells from the same files, `l7_aggregate.json` (regenerated since my first pass; gbm|B now 10 seeds), `kshuf_paired_audit.json`, the permutation-null JSONs, T1 `perm_summary.json` / `bind_summary.json` / `k_null_control.json`, anchor `results_B_aggregate.json`, the committee `cost_log.csv`, and re-opened sources (LLMNN, PepBenchmark, Klamt et al., ACNet; PubMed 40877984 blocked by a cookie wall).

## U-series (new or changed rows)
| ID | claim | where | artifact | re-derived | status |
|---|---|---|---|---|---|
| U1 | L5 intervals: spread vs bootstrap CI of the mean | all three drafts | `l5_aggregate.json` (`ci95` vs `ci95_mean`); raw res5 | A spread 158.5–209.0, mean-CI 181.1–191.5 (mine 181.1–191.3); B −1.6–44.1 vs 17.7–26.5 (mine 17.7–26.4); C 128.1–196.3 vs 155.5–171.2 (mine 155.8–171.0). The artifact's `ci95` is the percentile spread of the 30 per-seed differences, not a CI | MATCH |
| U2 | main draft §5.1 labels spread vs boot-mean per table column and explains rule C1 | draft §4.9, §5.1, 8e | as U1 | correct and complete for loop-minus-random, rule baselines (both intervals shown) and knowledge variants | MATCH |
| U3 | preprint §3.1 loop-minus-random labels spread vs CI of the mean | preprint | as U1 | correct | MATCH |
| U4 | preprint rule-baseline sentence: "exceeds the N-methyl rule by 105.4 (78.3 to 131.6) … both intervals above zero" | preprint §3.1 | `fp_minus_rule_*` | these are spreads, unlabelled in the preprint (boot-mean 100.2–110.7 etc.); regime B vs K_z: spread −20.0–17.2, boot-mean −4.2–3.2 | **MISMATCH** (interval type not stated) |
| U5 | "five of 15 comparisons have a mean-based 99 % lower bound above zero" and their identities (A: resid_z, fuse_z; B: kn, fuse_nme, fuse_z) | preprint abstract, §3.1; main draft §5.1 | raw res5, all 30 cells | recomputed: exactly those five (lower bounds 0.2, 1.8, 17.4, 1.0, 7.2) | MATCH |
| U6 | Bonferroni-30 survivors: primary B kn, B fuse_z; secondary A kn +11.1, B kn +25.0, B fuse_z +6.9 | preprint §3.1 | raw res5 | recomputed: same five; additionally secondary regime C descriptor arm (+9.1, lower ≈ +0.1 at 99.83 %) is borderline and not listed | MATCH (one borderline omission) |
| U7 | patch note P1/P2/P4: L5 intervals quoted as "(158.5 to 209.0)", "(−20.0 to 17.2)", and "no knowledge-prior or fusion variant improved the loop (all 15 99 % intervals include zero)" | patch note | as U1/U5 | the quoted ranges are spreads without a label; the unlabelled statement "no variant improved the loop" conflicts with 5/15 mean-based positives (and with the preprint, which says so) | **STALE / MISMATCH** |
| U8 | preprint abstract opens with pooled results: "397 vs 50 … 367 vs 107 … N-methylation rule found 276 and 304 … 98 % of the rule's hits … 5.7 N-methyl groups against 1.9 elsewhere" | preprint abstract | `loop_result.json` (396.7/49.9, 366.7/106.6 reproduce); the 98 % and 5.7/1.9 figures: none found, and the same preprint's Supplement S1 withdraws the 89 %/93 %, 272/276, 301/304 concentration figures | superseded, confounded, and the concentration figures are withdrawn elsewhere in the same file | **STALE** (and NO-ARTIFACT for 98 %, 5.7/1.9) |
| U9 | preprint limitation: "about one in four hit labels would change if source statistics were estimated from a 30 % subsample (hit-set Jaccard 0.87)" | preprint §4 Limitations | `l5_label_audit.json`: 99.7 flips of 6,960 labels; 697 hits; Jaccard 0.867 | Jaccard 0.867 on two hit sets of ≈697 means ≈50 hits lost and ≈50 gained, i.e. ≈7 % of hits (≈1 in 14); label flips are 1.4 % of all peptides. "One in four" is not supported | **MISMATCH** |
| U10 | main draft §5.2 / 8e / figure plan row 127: "the plain GBM B has only 2 seeds and is inconclusive" | draft §5.2, 8e; figure plan | `l7_aggregate.json` (regenerated) | `gbm|B` now has n = 10 for every contrast | **STALE** |
| U11 | main draft §5.2 K_phys bullet: "[all intervals: 95 % boot-mean]" | draft §5.2 | `aggregate_l7.py` line 72 | the aggregator uses 99 % (0.5–99.5) for every contrast whose arm name contains `kphys` or `kn`, 95 % otherwise; e.g. +2.4 (−1.1 to 5.4005) is 99 % | **MISMATCH** (level mislabelled) |
| U12 | main draft §5.2 and patch note P4: "no attributable K_phys effect on held-out ranking or on yield in the loop; AUROC-gain K_phys − shuffled interval includes 0 in every configuration (7 of 7)" | draft §5.2, A14; patch note P4; KB audit §9a | `l7_aggregate.json` regime B plain GBM (10 seeds, 99 %): K_phys − none yield **+4.9 [1.7, 7.8]**; K_phys − shuffled yield **+3.2 [0.7, 6.1]**; E-AUROC K_phys − none **+0.0625 [0.0242, 0.1081]**; K_phys − shuffled **+0.0326 [0.011, 0.055]**; contradicted −5.4 [−9.9, −0.1] | in the headline scaffold-shift regime the stereo-blind GBM shows an attributable K_phys effect on yield and held-out ranking; the 7-configuration audit file predates this arm and the draft/patch note never mention regime B | **MISMATCH** (claim contradicted by the current aggregate) |
| U13 | main draft §5.2: "3 of 6 configurations", "one of six" next to "7 of 7" | draft §5.2 | `kshuf_paired_audit.json` has 7; counts recomputed: E-AUROC K_phys − shuffled 7/7 include 0; yield K_phys − shuffled CI > 0 in 3/7; K_shuffled − none CI < 0 in 2/7 (6/7 negative points); K_phys − none yield CI > 0 in 1/7 | internal inconsistency inside one paragraph (denominators 6 and 7) | **MISMATCH** |
| U14 | KB audit §9a numbers | `20261029_KB_AUDIT_AND_GAPS.md` 9a | `lolo_permutation_null.json`, `lolo_group_permutation_null.json` | median 0.2519; null 0.000 ± 0.024 (95 % −0.050 to 0.049); p = 5.0 × 10⁻⁵; pooled 0.3914 vs 0.0002 ± 0.0121, p = 5 × 10⁻⁴; 11 of 21 labs p < 0.05 (expected 1.05); sign test 19/21, p = 1.1 × 10⁻⁴; group-level null 0.0008 ± 0.0355, p = 2 × 10⁻⁴, 10 of 21 labs | MATCH |
| U15 | main draft §5.3: K_nme "indistinguishable from the null (median −0.006, p = 0.62)" | draft §5.3 | `lolo_permutation_null.json` K_nme | median −0.0065, p = 0.617 ✓; but the same file reports pooled held-out ρ 0.325 (p = 5 × 10⁻⁴) and 7 of 20 labs individually p < 0.05 (expected 1.0) | **MISMATCH** (incomplete: significant pooled and per-lab heterogeneity omitted) |
| U16 | T1 permeability table (K, A, F1, F2; paired differences; labs 17/15/9) | `20261030_TECHNIQUE_T1_FUSION.md` R2 | `fusion/results/perm_summary.json` | K 0.261/0.212/0.180, A 0.227/0.309/0.333, F1 0.301/0.350/0.364, F2 0.302/0.336/0.329; F1 − best +0.041 [−0.044, 0.142] / +0.041 [−0.002, 0.084] / +0.031 [0.007, 0.055]; F2 − best +0.041 [−0.001, 0.091] / +0.027 [−0.066, 0.115] / −0.004 [−0.105, 0.074] | MATCH |
| U17 | T1 binding table and registered outcomes | T1 R3, R4 | `bind_summary.json` | NN 0.753/0.822/0.869; F1(P_B) − NN −0.009/−0.003/+0.005 [−0.000, 0.011]; F2(P_B) − NN −0.056 [−0.086, −0.025] / −0.042 [−0.064, −0.021] / −0.004; parity with frozen NN/PT: max |diff| 0.0 (640 and 686 cells); permeability criteria flags: F1 (b) true at k=25 only; F2 (b) false everywhere | MATCH |
| U18 | T1 shuffled-label K control | T1 R1 | `k_null_control.json` | 40 shuffles, 840 rows, 55 non-constant; pooled mean ρ +0.015; mean of shuffle means −0.0335 [−0.089, 0.019] | MATCH (the doc's wording on the ±0.03 rule is accurate) |
| U19 | T1 is absent from the drafts | main draft §5.7 row "T1 … pre-registered; results section empty"; §4.5 | T1 doc has results | **STALE**: T1 has results (permeability F2 null; F1 fragile; binding F1 partial, F2 failed) | STALE |
| U20 | anchor-test result | `20261030_C2_RERUN_AND_ANCHOR_TEST.md` §5 | `c2_audit/results_B_aggregate.json` | real raw within-source median 0.281 [0.106, 0.409]; z-score reference 0.209; z − raw +0.020 [−0.083, 0.071]; gain k=5 median +0.005, mean +0.031, CI [−0.015, 0.129], 60 % positive; k=3 +0.004 [−0.103, 0.122]; pooled 0.3265 vs 0.3266; planted (real coverage) −0.096 [−0.189, 0.089], r 0.975; planted (full coverage) +0.151 [0.032, 0.246], r 0.963, pooled 0.682 vs 0.217; null −0.0005 [−0.008, 0.011]; kill criterion met | MATCH |
| U21 | anchor coverage ("57 anchor rows; ≥3/≥5/≥10 anchors = 8/6/0 sources") | same §5 | not re-derived (needs the anchor-prep script output) | — | UNVERIFIED (artifact present, not recomputed) |
| U22 | main draft §5.7 row "C2 rerun and the laboratory-offset anchor test: pre-registered; no result" and candidate contribution (i) in §8 | draft | anchor test has a result | the offset candidate is now tested on public anchors and not supported (coverage-limited); the draft still lists it as "to be tested" | **STALE** |
| U23 | committee cost reconciliation | `COMMITTEE_SYNTHESIS.md` §1 | `committee_raw/20261030/cost_log.csv`; live credits | balance 4.339 → 3.961 (drop 0.378) = Gemini 0.0906 + GPT 0.2796 + 0.008 lag; live credits now 440 − 436.039 = 3.961. Caveat: the log shows the 0.280 drop on the second Opus row; attribution to GPT's lagged billing is an inference, not shown | MATCH (with caveat) |
| U24 | committee gate numbers (C1 0.476 (M), C2 0.469 (M), C3 0.315 (M); I: C3 0.584) | synthesis §4 row 7 | `validity_gate_M.json`, `validity_gate_I.json` | 0.476 / 0.469 / 0.315; 0.584 | MATCH |
| U25 | committee row 8 (L5 values) and row 12 (secondary-definition kn_B +25.0 [3.9, 54.5]) | synthesis §4 | `l5_aggregate.json` | fuse_z_A 244.1 vs fp_A 236.1, +8.0 [−14.7, 48.0]; kn_B +23.8 [−4.0, 54.0]; secondary kn_B +25.0 [3.9, 54.5], `lower_gt0` true (spread rule); mean-based 99 % CI 20.1–30.2 (mine) | MATCH |
| U26 | LLMNN, EMNLP 2025, arXiv 2509.21403 (hybrid LLM-guided nearest neighbour; agents insensitive to permuted labels; classical methods beat agents) | synthesis row 1; draft §8 | re-opened arXiv abstract page | confirmed (Gupta, Hartford, Liu) | MATCH |
| U27 | ACNet (arXiv 2302.07541): > 400K MMPs, 190 targets, 16 models; ECFP outperforms deep models on most subsets | synthesis row 3; draft §8 | re-opened abstract | confirmed | MATCH |
| U28 | PepBenchmark (arXiv 2604.10531): 29 canonical + 6 non-canonical datasets in 7 groups; abstract silent on cyclic, splits, leakage | synthesis row 10 | re-opened abstract | confirmed; the draft's "ICLR 2026" venue is not stated on the abstract page | MATCH (venue UNVERIFIED) |
| U29 | Klamt, Nejdl, Tang (arXiv 2605.11764): 0.124 AUROC bound; LOTO plateau ≈ 0.67 across eight architectures and ESM-2 ≤ 3B; k = 5 few-shot 0.668 → 0.7050; no anchors in the abstract | synthesis row 11; draft §8 | re-opened abstract | confirmed; the chair's claim "no lab-held-out splits" and the draft's 0.802 → 0.678 (CI 0.051–0.197) cannot be seen in the abstract | MATCH (abstract facts); **UNVERIFIED** (0.802/0.678/CI; "no lab-held-out splits") |
| U30 | Liu et al., J Cheminformatics 2025 (PubMed 40877984): 13-method benchmark; not addressing source effects or stereochemistry | synthesis row 4; draft §8 | PubMed returned a cookie wall | not re-opened | UNVERIFIED-CITATION |

## Updated counts (first-pass rows re-evaluated against the current drafts, plus the 30 U rows)
First-pass rows (99): resolved by the revisions — D10, D11, B12 (MISMATCH → MATCH); L12, L13, M8, KB6, S3 (NO-ARTIFACT → MATCH or removed; KB6 re-derived this pass from `stratification/data/mmp_effects_pampa.csv`: N-methyl added +0.252, random-effects meta interval 0.164 to 0.341, 4,156 pairs, 16 sources, I² 0.90; D↔L flip −0.013, −0.049 to 0.023, 7,451 pairs, 19 sources; M8 flags are stored per arm under `small[regime]["controls"]` and read `passes: true` for the shuffled and frozen arms); L10, L11, T1, T2, T3, T5, T6 (STALE → resolved in the files that were fixed; the loop preprint's pooled analysis now sits in Supplement S1 under a superseded banner, but its abstract still opens with it: see U8). Still open from the first pass: KB7 (citation tally 54 vs strict 45 in the KB audit document), R3 (permeability scaffold-R² 0.231 reference constant, RSI draft unchanged), STALE L14 (RSI "70–83 %"; RSI file unedited, patch note exists), KB8 (old KB-rule validation document), T4 (figure plan F4/F6 still "small cyclic-peptide LM / v5"), and the 9 unreachable or unopened citations (C12–C20).
First-pass total: **MATCH 85 · MISMATCH 2 · NO-ARTIFACT 0 · STALE 3 · UNVERIFIED-CITATION 9** (99 rows).
U-series (30 rows): **MATCH 17 · MISMATCH 7 (U4, U7, U9, U11, U12, U13, U15) · STALE 4 (U8, U10, U19, U22) · UNVERIFIED 2 (U21, U30)**; sub-claims left unverified inside rows marked MATCH: U8 (98 %, 5.7/1.9: no artifact), U28 (venue "ICLR 2026"), U29 (0.802→0.678, CI 0.051–0.197, "no lab-held-out splits").
**Combined, 129 rows: MATCH 102 · MISMATCH 9 · STALE 7 · NO-ARTIFACT 0 (three sub-claims) · UNVERIFIED-CITATION 11.**

## Documents still contradicting each other (after this pass)
1. **K_phys in the loop.** Main draft §5.2 / A14, patch note P4 and KB audit §9a conclude "no attributable K_phys effect on held-out ranking or yield (7 of 7)"; the regenerated L7 aggregate (regime B, plain GBM, 10 seeds) shows K_phys − none yield +4.9 [1.7, 7.8] and E-AUROC +0.0625 [0.024, 0.108], K_phys − shuffled yield +3.2 [0.7, 6.1] and E-AUROC +0.0326 [0.011, 0.055]; the loop preprint §3.3 reports these B numbers and concludes "no claim until confirmatory seeds". The three documents need one statement: development seeds show a positive K_phys effect in regime B only (stereo-blind GBM), absent in A/L and in the physchem-channel arms, to be confirmed on seeds 10–29.
2. **"Knowledge variants did not improve."** Patch note P4 and the earlier draft sentence versus preprint §3.1 and main draft §5.1 (5/15 mean-based).
3. **Seeds in regime B.** Draft 8e and figure plan row 127 (2 seeds) versus aggregate (10).
4. **Anchor/offset module.** Draft §8 "candidate (i) to be tested" and §5.7 "no result" versus the anchor-test result (kill criterion met; coverage-limited).
5. **T1.** Draft §5.7 "results section empty" versus a complete T1 results section.
6. **Interval-level wording.** Draft §5.2 "95 %" versus the aggregator's 99 % for knowledge arms; the aggregator's bootstrap is unseeded across regenerations (values moved by up to 0.2 between two runs, e.g. 156.3 → 156.2, 175.6 → 175.4).
