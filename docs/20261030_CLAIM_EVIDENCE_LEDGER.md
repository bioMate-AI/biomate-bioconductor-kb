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

---
# UPDATE 3 — source-cluster bootstrap in the frozen L7 aggregate (2026-10-30)
Trigger: WS2 message — `aggregate_l7.py` now implements the L7j (3) source-cluster bootstrap; frozen aggregate hash superseded. Checked against `loop_retro/results/l7_aggregate.json` (sha256 prefix 6027888c, equal to `l7_aggregate.sha256`; commit ab688994d) and `test_aggregate_l7.py` (4 passed).
| ID | claim | artifact | re-derived | status |
|---|---|---|---|---|
| V1 | frozen hash 6027888c… | `l7_aggregate.sha256` | file hash prefix 6027888cf089 = recorded | MATCH |
| V2 | regime L, E source-rho, loop_sub − shuffled_sub: mean +0.071, seed-only CI [0.072, 0.187], cluster CI [−0.074, 0.184], 11 held-out labs | `contrasts_cluster` | mean 0.0708; seed-only [0.072, 0.187]; cluster **[−0.0794, 0.1812]** (WS2 quoted −0.074/0.184); 11 sources | MATCH on the substance, **MISMATCH** on the quoted cluster bounds |
| V3 | "the mean lies inside its own interval" (sanity) | same row | the reported mean 0.0708 is **below** the seed-only lower bound 0.072: a bootstrap CI of the mean cannot normally exclude the sample mean. The mean is a source-mean of seed-averages, whereas the seed-only bootstrap resamples seeds with sources fixed and sources are held out in only 6–10 of 10 seeds, so the two statistics differ | **NEW DEFECT** (estimator mismatch; seed-only interval for this row is not an interval for the reported mean) |
| V4 | "K_phys − K_shuffled and K_phys − none on E source-rho include 0 in A, B and L with cluster intervals" | `contrasts_cluster` | true for the plain-GBM arms (all six include 0; A: K_phys − K_shuffled −0.0531 to 0.0003, borderline). **False for the physchem-channel arms**: regime B K_phys − none [−0.0908, −0.0003] and K_phys − K_shuffled [−0.0900, −0.0012]; regime L K_phys − K_shuffled [−0.0686, −0.0071]; all negative (K_phys worse than shuffled knowledge on held-out source ranking) | **MISMATCH** (statement holds for plain GBM only) |
| V5 | plain-GBM regime B: held-out AUROC gain K_phys − K_shuffled +0.0326 [0.011, 0.055] (seed-based, 99 %) | `contrasts` vs `contrasts_cluster` | the cluster-bootstrap counterpart on source-rho: mean −0.0049, CI [−0.0372, 0.0322] includes 0. Different metrics (AUROC gain vs source-rho), same arm and regime; the seed-based positive does not survive resampling over the 9 held-out sources | consistent with WS2's note; the main-draft K_phys-in-B sentence must cite both |
| V6 | main draft §5.2: "random feedback improves held-out ranking more than the loop (−0.072, −0.113 to −0.014)" | `contrasts` (E-AUROC, seed-based) vs `contrasts_cluster` `loop − random_fb [E source-rho]` | cluster counterpart in regime L: mean −0.0322, CI [−0.0886, 0.0161] includes 0 (11 labs); the physchem arms in A and B are negative at the cluster level (−0.1201 [−0.2162, −0.028]; −0.1317 [−0.2279, −0.0431]) | the claim is seed-based and not supported at the source-cluster level for plain GBM in L; reword |
| V7 | planted lab-heterogeneity control (cluster width 0.307 vs seed-only 0.045; homogeneous 0.046 vs 0.040) | `test_aggregate_l7.py` | 4 tests pass; widths not recomputed from the test code | MATCH (tests pass); widths UNVERIFIED |
| V8 | loop_sub − shuffled_sub in A and B (cluster) | `contrasts_cluster` | A [0.189, 0.367] (6 sources), B [0.144, 0.373] (9 sources): exclude 0 | MATCH (consistent with feedback mattering vs shuffled labels) |
**Net effect on the red-team items:** N2 (seed-based intervals and generalisation) is now partly addressed by the implemented cluster bootstrap but only for E source-rho and only for the frozen aggregate; yield contrasts remain seed-based. The K_phys sentence (positive in regime B) rests on the seed-based E-AUROC and on yield; at the source level the plain-GBM contrasts include 0 and the physchem-channel K_phys is **worse** than shuffled knowledge in B and L. The three documents that say "no attributable K_phys effect" and the one that says "positive in B" are both over-simple: the evidence is mixed by learner (plain vs physchem channel), metric (yield, AUROC gain, source-rho) and interval type (seed vs source cluster).

## UPDATE 3b — re-verification of the estimator fix (commit c1250c1b8; 2026-10-30)
| ID | claim | re-derived | status |
|---|---|---|---|
| V9 | frozen hash e2302b87…871be, equal to `l7_aggregate.sha256`; deterministic across PYTHONHASHSEED values | file hash recomputed = recorded; determinism across hash seeds not re-run by me (tests pass) | MATCH (hash); determinism UNVERIFIED by me |
| V10 | seed-only interval now uses the reported estimator; mean lies inside both intervals in all 28 cluster entries | I checked every `contrasts_cluster` entry: 28 of 28 have the mean inside `ci_cluster` and `ci_seed_only`; regime L loop_sub − shuffled_sub: mean 0.0708, cluster [−0.0794, 0.1812], seed-only [0.0052, 0.1441] | MATCH (V3 resolved) |
| V11 | physchem-arm cluster values quoted in the preprint (B K_phys − none −0.0396 [−0.091, −0.0003]; B K_phys − K_shuffled −0.0387 [−0.090, −0.0012]; L K_phys − K_shuffled −0.0351 [−0.069, −0.0071]) | file: −0.0396 [−0.0908, −0.0003]; −0.0387 [−0.0900, −0.0012]; −0.0351 [−0.0686, −0.0071] | MATCH (V4 resolved in the preprint) |
| V12 | regime L pool: 18 eligible labs; 8 distinct held-out sets over seeds 0–9; each lab held out in 6–10 of 10 seeds | `regime_L_heldout_sets.json`: pool 18; seeds 0–9 give 8 distinct sets; per-lab counts 6–10 | MATCH. Observation: the held-out set size ranges 6–18 labs per seed (18 = every eligible lab, in 3 of 10 seeds), so some regime-L seeds train on the two largest laboratories only; the cluster analyses use 11 sources, not 18 |
| V13 | planted widths 0.310 vs 0.045 (heterogeneous), 0.046 vs 0.041 (homogeneous); tests | `test_aggregate_l7.py`: 5 passed (was 4); widths not recomputed by me | MATCH (tests); widths UNVERIFIED |
| V14 | preprint no longer carries the pooled numbers in the abstract or the "one in four" sentence | grep: no "397" in the abstract line, no "one in four"; physchem values present | MATCH |
**Open after this pass.** The main draft §5.2 still has to cite the cluster-level plain-GBM versus physchem split; the patch note P4 label; the audit-file recount (regime B). Held-out set size in regime L (6–18 labs, sometimes all eligible labs) should be stated in the caption because it changes what "leave-laboratories-out" means in those seeds.

---
# UPDATE 4 — rerun on main draft (0c490327b), RSI patch note, review brief (2026-10-30, continuous audit)
Method: every cluster-table cell programmatically compared with `contrasts_cluster` of the frozen aggregate (sha256 e2302b87…, verified); nine-configuration counts recomputed from `kshuf_paired_audit.json`; C2 Part A, T1b, L7m numbers compared with their JSON artifacts; mechanical checks by `research/guangzhou_all_atom/cyclic_llm/qa_audit/final_pass.py` (re-runnable: hashes, mean-inside-interval for 110 seed contrasts and 28 cluster rows, ci_level_pct present, L5 spread vs boot-mean from raw res5, provenance ancestry of 94efe092d, stale-string blacklist, citation-tag census, licence tags, result-claim heuristic). Script result on the current tree: **0 FAIL**; 8 REVIEW lines, all inspected (superseded-appendix rows; one genuine stale hash, W4).
| ID | claim | where | artifact | re-derived | status |
|---|---|---|---|---|---|
| W1 | all 28 cells of the plain-GBM vs physicochemical cluster table (means and 95 % cluster-boot intervals, ▲/▼ marks) | main draft §5.2 | `contrasts_cluster` | 28 of 28 equal within 0.0006; marks consistent (physchem B K_phys − none upper −0.0003 rounds to −0.000, ▼ correct) | MATCH |
| W2 | nine-configuration counts: 54 dependent contrasts, 15 exclude 0 at 99 % (percentile bootstrap); K_phys − shuffled E-AUROC excludes 0 in 2 of 9 (aware B +0.0146, blind B +0.0326); K_phys − none yield above 0 in 3 of 9 | draft §5.2, patch note P4, brief #8, KB audit 9a | `kshuf_paired_audit.json` | 54; 15; 2 of 9; recount agrees. At the paired-t 99 % interval only **9 of 54** exclude 0 (the six percentile-only exclusions include aware-B K_phys − shuffled E-AUROC and blind-B K_phys − shuffled yield). Draft §5.2 and KB audit report the t99 check; the brief and patch note quote 15 of 54 only | MATCH; **MISMATCH (minor) in the brief**: carry "9 of 54 under t99" next to "15 of 54" |
| W3 | brief finding 4: "with held-out laboratories as the unit, none of the plain-GBM held-out-ranking contrasts excludes 0" | brief §2 #4 | `contrasts_cluster` | true for regime L (5 of 5 include 0); false for regimes A and B: plain-GBM loop − shuffled-label A +0.278 [0.189, 0.367], B +0.255 [0.144, 0.372] and loop − frozen A, B exclude 0 above. The main draft states the scope correctly (readings (a)–(b)) | **MISMATCH** (scope missing in the brief) |
| W4 | brief claims table: IH-LM module status cites commits `d0eacfc14, 269c0e2af` | brief §8 | git | `d0eacfc14` descends from the provenance floor `94efe092d`; **`269c0e2af` precedes `94efe092d`** and is the commit the owner's team marked broken (a comment swallowed a gate line; M3 forward pass raised) | **MISMATCH** (provenance below the floor) |
| W5 | patch note P4 cites the L7 aggregate by hash prefix 8c7a6fe5… | patch note line 12 | `l7_aggregate.sha256` | current frozen aggregate is e2302b87…; 8c7a6fe5… is the first freeze (before the cluster bootstrap and estimator fix); the patch note does not cite e2302b87 anywhere | **STALE** |
| W6 | C2 Part A: reproduction aggregate 0.287 / 0.241 / 0.101 vs logged 0.299 / 0.249–0.250 / 0.117–0.118; max per-target differences 0.050 / 0.070 / 0.050; tolerance not met | C2 doc §6, draft §5.6, A28 | `results_A_aggregate.json` | identical (artifact computes the logged aggregate from per-target values: 0.299 / 0.250 / 0.117; the document quotes the stdout FINAL line 0.249 / 0.118) | MATCH |
| W7 | C2 40-target extension: 12 contrast cells (learn/fixed − random, learn − fixed, learn − nn × full / family-disjoint / none) with family-cluster CIs; H-leak ratio 0.568 (0.453 on 15 large-pool targets); shuffled and planted controls; 106-target and pool-size strata | C2 doc §6, draft §5.6 | `results_A_aggregate.json`, `results_A_ext_pool_ge300.json`, `results_A_full106_by_pool_size.json` | all values and intervals equal to three decimals | MATCH |
| W8 | C2 point estimates vs intervals | draft §5.6 ("the means are over targets"; CIs "family-cluster") | same | the point is the mean over targets while the interval is a bootstrap of family means (e.g. learn − nn, family-disjoint: point +0.002 over targets; family-mean +0.014; interval −0.018 to 0.047); the estimand of the interval is not stated. In the pool ≥ 300 stratum (7 families) learn − fixed is +0.061 with interval 0.063 to 0.122, i.e. the point lies outside its own interval (disclosed in the C2 doc as instability) | **MISMATCH** (estimator weighting of point vs interval not labelled) |
| W9 | T1b permeability (17/15/9 labs) and binding (45/44/39 targets) tables: arm means, F1b/F2b minus best comparator with 95 % and Bonferroni-adjusted intervals, parity with frozen baselines | T1b doc R2/R3, draft §5.7, brief #6 | `fusion_b/results/perm_b_summary.json`, `bind_b_summary.json` | all spot-checked cells identical (permeability k = 5/10/25: PT 0.419/0.368/0.381, PT+k 0.454/0.429/0.419, F2b − best −0.010/+0.006/+0.025 with adjusted bounds −0.055/−0.027/−0.070; binding F1b − best −0.049/−0.024/−0.002, F2b − best −0.127/−0.096/−0.016); parity max |diff| 0.0 | MATCH. Not re-derived: shuffled-label control values, analog-distance strata, plug-in contamination subset |
| W10 | L7m label-range diagnostic: recovered fraction 21 % / 12 % / −7 %; weighted − loop +0.036 [0.018, 0.053] (A), +0.011 [−0.015, 0.033] (B); gap +0.168 / +0.103 | results log §6, draft | `diag_label_range_refit.json` | identical | MATCH (diversity and source-matched results not re-derived) |
| W11 | brief finding 3 and claims row: remote-bin gain +0.064 (−0.002 to 0.135); MDE ≈ 0.11 AUROC on analysis I | brief §2 #3, §8 | `h4b_strata.json`, `power.json` | FP-k remote gain at k = 5: +0.0637 [−0.0015, 0.1350], 17 families; S1d − strongest baseline MDE 0.1106, 26 families, 128 families needed for 0.05 | MATCH |
| W12 | brief §7 spend (USD 4.2 API; 0.370 committee) and §5 limits | brief | L7 results log; `cost_log.csv`; live credits 3.961 | consistent with the earlier verification | MATCH |
**Counts for this pass (12 rows): MATCH 7 · MISMATCH 4 (W2-brief, W3, W4, W8) · STALE 1 (W5) · UNVERIFIED 0.** Unverified items carried forward: anchor row counts (57 rows; 8/6/0 sources), planted-control widths, T1b shuffled-label and strata values, determinism of the aggregator under other hash seeds, all citation items in Appendix B.
**Open defects to fix before the review (ranked):** (1) W4 brief cites commit 269c0e2af below the provenance floor; (2) W3 brief finding 4 lacks the regime-L scope; (3) W5 patch note quotes the superseded aggregate hash; (4) W2/W8 add "9 of 54 under t99" to the brief and state the estimand of the C2 intervals (target-weighted point vs family-mean interval); (5) §8 of the brief marks "T1 / T1b" and "Stratified skill" as D (document-level): T1/T1b values are now V for the tables above.

---
# UPDATE 5 — v2 draft, updated brief, review-response commits (46a4e7fff, 8dc8c04e3); the four checks the writer did not run (2026-10-30)
Files: `20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md` (v2), `20261030_REVIEW_BRIEF.md` (IH-LM box §1b, framing table §1c), main draft at HEAD, `committee_raw/20261030b/review_manuscript.md`, `FIGURES_STATUS.md`, `figures_paper/out/`. Primary sources re-opened this pass: Hugging Face model API (PeptideCLM licences), PMC10091415 (CycPeptMPDB, earlier), the Amirahmadi PDF text; `cycpeptmpdb.com/download` again failed (TLS error).
| ID | check | result | status |
|---|---|---|---|
| X1 | (1) draft lengths | `wc -w`: main draft **18,880**; v2 **3,637** (19.3 % of the main draft; the reviewer text itself gives **no numeric one-third target**: its restructuring list says only "cut to" a section list); brief 2,455; review 3,834. The brief §1c says the original is "about 14k words" and v2 "about one third" | **MISMATCH** (original is 18.9k; v2 is about one fifth) |
| X2a | (2) figure labels in v2 against FIGURES_STATUS and `out/` | cited: F1, FL5, T5, F5 (GBM arms only), F3, FH4b, T7, T_loops_classification, F8, FCV, FK; all exist as rendered (not PENDING) in the status table and as PDF/PNG or tables in `out/`; no pending figure (F4, F6, F7, F10, F11b, F12) is cited; assertion log 284 OK, 0 FAIL, determinism file `identical: true` | MATCH |
| X2b | figure data vs the frozen aggregate | F5 and T6 are rendered from `l7_aggregate.json`@5442beac3 (sha256 9bf6ec6d3d…); the frozen aggregate is e2302b87… (commit c1250c1b8). The F5 caption is hard-coded in `f5_controls.py` line 44: "regime B for 'gbm' has only 2 seeds and is drawn hollow/grey"; the frozen aggregate has n = 10 for regime B. v2 §3.2 cites "Fig. F5" next to numbers read from the frozen file. Outputs are in `.gitignore` (`out/`), so none of the cited PDFs is committed | **STALE** (F5, T6); REVIEW (figures not committed) |
| X3a | (3) brief §1b IH-LM facts | line counts 287 / 170 / 240 / 102 = 801 (re-counted); 14 tests, 3 `xfail` with the stated reasons (M3 net-only ρ 0.525 vs 0.113 without M3, threshold 0.70; leave-laboratory-out ρ 0.444 vs 0.60; verifier AUC 0.529 vs 0.90); untrained, no checkpoint; commit d0eacfc14 descends from 94efe092d | MATCH |
| X3b | brief §1b / v2 §6: those test numbers presented without saying they come from a planted synthetic 24-family world (per commit 688793522) rather than from real data; the sentence "the evidence so far (C2, L5, T1/T1b) suggests most value would come from the symbolic and retrieval parts" | none of C2, L5, T1 or T1b runs an IH-LM module, so they cannot bear on which IH-LM part adds value (they bear on lookup baselines) | **MISMATCH** (unsupported inference; missing "synthetic planted" qualifier) |
| X4 | (4) the writer's `verify.py` | exists only in the session scratch directory (`.../scratchpad/ms/verify.py`, not in the repository). Rerun: **26 checks; failed: []**. It compares artifact values with typed constants; it does not parse any manuscript and covers none of: the cluster table, nine-configuration counts, C2, T1b, L7m, strata, anchors, K_phys null, IH-LM facts (I verified those separately) | MATCH for the count; REVIEW (not committed; coverage) |
| X5 | v2: every number traces to a committed artifact | 244 distinct decimal or thousands numbers in v2; the only ones absent from the main draft are the four section numbers. Re-derived this pass: yield contrasts (156.0–175.7, 2.9–23.9, 68.0–94.0), one-shot (−0.034 to 0.037), the two minimal-detectable values (0.051 → "about 0.05"; 0.186 → "about 0.19"), regime-L set sizes (6–18 labs; 25.2–34.3 % of peptides; all 18 in seeds 0, 7, 9), all 28 table cells (earlier), gates, H4b, strata (remote +0.064 [−0.002, 0.135]), C2 cells, T1/T1b, anchor medians, K_phys null, 15/54 and 9/54, 30 % re-estimate ≈ 7 % of hits (Jaccard 0.867 → ≈ 50 hits replaced of 697) | MATCH |
| X6 | no unfinished item described as a result (v2 and brief) | v2 abstract and §6 label IH-LM, ladder, confirmatory seeds, T2, source-matched draw, L9 as planned; the script heuristic found one forward-looking sentence only | MATCH |
| X7 | v2 abstract, held-out sentence | "With held-out laboratories as the unit (11 sources) none of the plain-GBM contrasts … excluded zero": true for regime L only; the same plain GBM in regimes A and B excludes 0 (loop − shuffled-label +0.278, +0.255) and the physicochemical learner excludes 0 in L (+0.155); §3.2 states this, the abstract reports only the null | **MISMATCH** (abstract is selective; scope "regime L" missing) |
| X8 | v2 abstract and §3.3: the fingerprint control "above the zero-shot model's 0.539"; "the zero-shot pretrained model scores below the fingerprint control, so the task rewards compound-only features" | `validity_gate_I.json` 0.584 [0.533, 0.636] vs `h4b_baselines.json` zero-shot 0.539 [0.478, 0.605]: intervals overlap broadly; no paired family-cluster difference is computed | **MISMATCH** (inference without a test) |
| X9 | v2 §6 and main draft "size terms": external models "23 M to 337 M parameters" with ChemBERTa-77M listed among parameter counts | ChemBERTa-77M-MLM has 3.43 M parameters ("77 M" is the pretraining-set size; L7h correction); PeptideCLM v1 checkpoints of 12 M and 11 M exist on the Hugging Face API | **MISMATCH** (range and label) |
| X10a | licence of PeptideCLM weights: brief §6 and main draft §9.1 "PeptideCLM: code MIT, weights state no licence" | Hugging Face API (primary): all nine PeptideCLM-2 checkpoints and `PeptideCLM-23M-all` list **MIT**; `PeptideCLM-12M-smol` and `PeptideCLM-11M-pep` list none; the "no licence" statement came from the GitHub repository page | **MISMATCH** (needs a per-checkpoint statement) |
| X10b | CycPeptMPDB data licence | still UNVERIFIED (website TLS error for me as for the writer); the draft says "two statements exist and conflict": (a) an internal metadata record CC BY-NC-SA 4.0 of untraced provenance, (b) the 2023 article is CC BY 4.0 and points to cycpeptmpdb.com/download for the data, stating no data licence. (b) governs the article, not necessarily the data, so there is no verified conflict | MATCH (unverified status); **MISMATCH** (the word "conflict") |
| X11 | PeptideCLM-2 description in the main draft (32 / 114 / 337 M; 405-token k-mer vocabulary; AUROC 0.836 ± 0.011, hybrid objective; June 2026 version) | re-opened PMC12803269: identical; "using splits from prior work" not visible in the fetched summary | MATCH (split statement unverified) |
**Counts for UPDATE 5 (13 rows + 2 REVIEW): MATCH 6 (X2a, X3a, X4, X5, X6, X11) · MISMATCH 6 (X1, X3b, X7, X8, X9, X10a) plus two sub-items (X10b wording; X7 included) · STALE 1 (X2b).** Precisely: rows with status MATCH 6; MISMATCH 7 (X1, X3b, X7, X8, X9, X10a, X10b-wording); STALE 1; REVIEW 2 (figures not committed; verifier not committed).
**Top defects (ranked):** (1) X7 abstract reports only the plain-GBM regime-L null; (2) X8 an overlapping-interval comparison drives a substantive inference; (3) X2b F5/T6 stale against the frozen aggregate, with a hard-coded two-seed caption, and no cited figure is committed; (4) X1 the brief's length claims (14k, one third) are wrong (18.9k, about one fifth); (5) X10a licence statement for PeptideCLM contradicts the Hugging Face model cards; (6) X3b IH-LM test numbers need "planted synthetic world" and the C2/L5/T1 inference about IH-LM parts should go; (7) X9 size range and ChemBERTa label; (8) X4 the number verifier is outside the repository and checks constants only.

---

## UPDATE 6 — Aggregate integrity (T-QA, raw-file recomputation; trigger: code review C1)

Script: `research/guangzhou_all_atom/cyclic_llm/qa_audit/aggregate_integrity.py` (independent of `aggregate_l7.py`; own bootstrap, seed 12345, B=20000; `--strict` exits 1 on any duplicate key). Read-only on `results/l7_collect/small/`.

**Why earlier passes missed it:** the ledger compared drafts with `l7_aggregate.json`, never the aggregate with the raw inputs. This pass does the latter.

### I1. Input accounting (raw files on disk vs aggregate at 457236439, sha 386efae2…)

| input dir | backend | regime | files | arms |
|---|---|---|---|---|
| res7a_chemberta | chemberta | A / B | 3 / 3 | 14 |
| res7f_gbm_aware | gbm | A / B / L | 10 / 10 / 10 | 6 / 6 / 14 |
| res7f_gbm_blind | gbm | A / B / L | 10 / 10 / 10 | 6 / 6 / 14 |
| res7f_gbm_phys | gbm_physchem | A / B / L | 10 / 10 / 10 | 14 |

- Raw files on disk: **96**. `inputs.n_files` in the aggregate: **116** (and sha 9706ce46… of the file list). The 20-file difference is unexplained by what is on disk, so the declared input hash cannot be reproduced from the repository. Status: **MISMATCH**.
- **30 duplicate (backend, regime, seed) keys** across `res7f_gbm_aware` and `res7f_gbm_blind` (gbm A, B, L × seeds 0–9). `load_small` keys on `(backend, regime)` and `.update()`s, so the later directory (blind) overwrites the aware results. Aggregate keys `gbm|A/B/L` therefore hold **blind only**; the chirality-aware GBM appears nowhere in the aggregate. Status: **MISMATCH (C1 confirmed)**.
- No other collisions; phys and chemberta are each counted once. Required acceptance for the regenerated aggregate: ≥ 4 GBM-family learner keys (blind, aware, phys, chemberta), n per key = raw files (A/B/L 10 each; chemberta 3), `inputs.n_files` = files actually read.

### I2. Headline numbers recomputed from raw per-task files (own bootstrap; mean [95% boot-mean CI; 99% for kphys contrasts])

| quantity | aware | blind (= committed `gbm`) | review's reimplementation | status |
|---|---|---|---|---|
| A: `loop_sub` mean yield | 86.0 | 87.4 | 86.0 / 87.4 | MATCH |
| A: `loop_kphys_sub` mean yield | 90.7 | 89.8 | 90.7 / 89.8 | MATCH |
| A: zero-sibling stereo ρ (`loop_sub`) | 0.181 | 0.000 | 0.181 / 0.0 | MATCH |
| A: `loop_sub − frozen_sub` yield | +8.0 [3.5, 12.5] | +8.5 [5.9, 11.1] | – | derived |
| A: K_phys − K_shuf yield | +5.9 [2.8, 8.7] | +5.8 [3.0, 8.3] | – | derived |
| A: K_phys − `loop_sub` yield | +4.7 [2.3, 7.1] | +2.4 [−1.0, 5.4] | – | **learner-dependent: significant for aware only** |
| B: K_phys − K_shuf E-AUROC gain | +0.0146 [0.0009, 0.0304] | +0.0326 [0.0109, 0.0545] | review: kphys−kshuf aware > 0, blind sign differs | derived (aware CI lower bound ≈ 0) |
| L: `loop − frozen` yield | **+47.3** [34.1, 58.3] | **+13.2** [2.7, 23.8] | – | **learner-dependent by 3.6×** |
| L: `loop − shuffled` yield | **+117.7** [105.1, 127.9] | **+79.5** [68.0, 93.5] | – | **learner-dependent** |
| L: `loop − random_fb` yield | +186.1 [179.6, 192.8] | +165.0 [156.0, 175.7] | – | both large |
| L: K_phys − K_shuf yield | +1.8 [−2.1, 6.0] | +7.1 [3.2, 11.1] | – | opposite pattern (blind significant) |
| L: `loop − one_shot` E-AUROC gain | −0.006 [−0.034, 0.025] | +0.003 [−0.034, 0.038] | – | null both |

Notes: (i) the review's cluster values (`loop_sub − frozen_sub` 0.236 [0.176, 0.296] aware vs 0.134 [0.063, 0.207] blind) were not recomputed here — they need `aggregate_l7.cluster_contrast` with the compound table; to be checked on the regenerated file. (ii) These are seed-based intervals (spread across 10 seeds, development seeds); they carry no new-lab claim (see red-team Addendum 5).

### I3. Consequences for the drafts (still citing the pre-fix aggregate; hash e2302b87… deliberately)

- Every quoted number in the main draft, v2, preprint and brief that is a "GBM" L7 value is a **blind** number. They remain arithmetically correct as blind numbers, but (a) the drafts also describe K_phys contrasts as "chirality-aware GBM" in places — those would be the aware numbers, which are not what the aggregate holds → **MISMATCH of learner label vs source**; (b) regime-L headline "loop beats frozen/shuffled" magnitudes differ by learner (13.2 vs 47.3; 79.5 vs 117.7) and a pooled "GBM" statement must name the learner; (c) a claim "stereo-blind GBM has zero-sibling 0" is correct for blind only (aware 0.181).
- Pending after regeneration (rerun scheduled): hash in every draft, the 54-contrast/9-configuration counts (now 12 configurations if aware is added: 4 learners × A,B,L, with chemberta only A,B → 11), 15/54 and 9/54 counts, Holm counts, cluster-boot table, F5/T6 (still built from l7_aggregate@5442beac3), F5 "2 seeds" caption, [REGEN] markers, chemberta first GPU results (in aggregate, not in drafts: exploratory, 3 seeds, A/B only), and `verify_artifacts.py` coverage of new numbers.

---

## UPDATE 7 — Independent data/evaluation review (`docs/committee_raw/20261030b/review_data_eval.md`): recomputation from raw frozen data and doc propagation

Recomputed by me with pandas from `multitarget/integrin_chembl/retro_recovery/data/{pair_labels,items_I,compounds,targets,folds_v1}` and `data/raw/CycPeptMPDB_Peptide_All.csv` (not from the review's scratch scripts). Docs checked: main draft, v2, preprint `manuscript_loop.md`, brief, patch note, plus the older source docs that carry the profile numbers.

| # | claim | review value | my recomputation | status |
|---|---|---|---|---|
| Y1 | frozen set size | 16,195 compounds / 793 targets / 24,583 pairs (20,562 pos, 4,021 inactive) | compounds.csv 16,195; targets 793; pair_labels 24,583 (pos 20,562, inactive 4,021); 14,492 compounds and 13,161 flat keys in labelled pairs | **MATCH** |
| Y2 | I censoring | 63.6 % of inactives ">"; 0 % of positives | inactives with ">" in the relation string: 1,166 / 1,832 = **63.6 %** (pure ">" 1,143). Positives: pure ">" **0**, but **190 / 7,600 = 2.5 %** carry a ">" component in a multi-measurement string ("=;>", "<;>"; 182 + 8) | MATCH for inactives; **"0 % of positives" is true only for pure-censored positives (2.5 % have a mixed ">")** — drafts' "0 % of positives" needs "pure" or the 2.5 % |
| Y3 | cross-fold compounds | 1,057 / 14,492 (7.3 %); 1,007 flat; I rows 11.6 % | 1,057 / 14,492 = 7.3 %; 1,007 / 13,161; I rows 11.6 % | **MATCH** |
| Y4 | accession spread | 29 of 775 accessions in >1 family; 24 span >1 fold | 775 accessions; 29; 24 | **MATCH** |
| Y5 | αvβ6 twin | P06756,P18564 (fold 3) and P18564 (fold 2): 77 pairs each, 70 shared compounds | folds 3 and 2; 77 and 77 pairs; 70 shared compounds (positives per target: 72 each in pair_labels; the review's "39" is the M subset, not recomputed) | **MATCH** |
| Y6 | I composition | 9,432 items, 7,600 pos (80.6 %), 46 targets | 9,432 / 7,600 / 80.6 % / 46 | **MATCH** |
| Y7 | CycPeptMPDB profile | 7,027 PAMPA rows → 6,960 unique; **41 sources**; 20 with ≥ 20 | 7,027 → 6,960; **41**; 20 | **MATCH** (so "45 sources" is wrong for this set) |

Not recomputed by me (reviewer-only or needs compute): C3 purge results (0.580/0.578/0.583–0.588), regime-leakage table (F5), single-seed causal-standardisation experiment (F4), relation/assay AUROCs (0.186), near-duplicate rates by class. These stay at [REPORTED] level; the drafts cite them as the review's.

### Propagation of the review's points

| # | where | finding | status |
|---|---|---|---|
| Y8 | v2 draft §Benchmark for binders (line 20) | still says "**17,120 peptide macrocycles across 851 targets**" as the frozen benchmark; main draft §4.2 already corrects this (16,195/793/24,583; 17,120/851 labelled pre-freeze) | **MISMATCH** (v2 only) |
| Y9 | `20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md:55`, `20261030_COMMITTEE2_PACKET.md:427` ("6,960 peptides, 45 sources"); `20261029_KB_AUDIT_AND_GAPS.md:81` ("a different set of 45 sources") | 41 sources for the 6,960 set; the KB-audit "45" may refer to a different set (leave-labs-out set) and was not recomputed | **STALE** (source docs; manuscripts use 41) |
| Y10 | preprint `manuscript_loop.md` abstract (line 9) | "with near-duplicates removed (+163.4 …)" labels regime C as near-duplicate-free; review F5: C removes identical flat structures only (26.9 % still ≥ 0.9, 62.6 % ≥ 0.8). Abstract also gives no transductive-standardisation caveat for the +186.3 headline (review F4: about half of the A gain may disappear under causal standardisation, n = 1 seed). | **MISMATCH / over-claim** (public preprint; main draft line 168 and Appendix F carry the qualifications) |
| Y11 | main draft §4.2 line 63, Appendix F; brief line 64 | folds described as "Pfam-family-disjoint, not protein-, compound- or analogue-disjoint"; 29/775, 6/46, 9/20 (44 %), 77/70 all as in the review (Y4, Y5 recomputed) | **MATCH** |
| Y12 | main draft Appendix F table (regime leakage), "Loop standardisation" paragraph, P4 row | numbers equal the review's (21.7/60.9/42.2/69.3/0.873 etc.); 84.8 %/14.4 %; single-seed 251/151/64/47 labelled n = 1 | **MATCH to the review** (REPORTED, not mine) |
| Y13 | main draft/v2/brief "0 % of positives" | see Y2 | **MISMATCH (precision)** |
| Y14 | main/v2/brief "blind" and "held-out target" wording | αvβ6/integrin qualified in line 63 (main), 20 (v2), 64 (brief). Not re-audited: every remaining "family-disjoint" instance (main lines 20–22, 34, 62, 66, 227–229, 276, 363; v2 20, 31, 58, 63; brief 46, 81; patch note 13) should read "Pfam-family-disjoint"; spot-read, qualifier absent in at least the abstract-level mentions (main 20–22) | **UNVERIFIED → check after next writer update** |

Counts for this update: 9 MATCH (Y1, Y3–Y7, Y11, Y12 + Y2 inactives), 3 MISMATCH (Y8, Y10, Y13), 1 STALE (Y9), 1 UNVERIFIED (Y14).

### UPDATE 7a — writer fixes (commit 49d4938ed), re-checked

- Y8 (v2 "17,120 / 851"): **now MATCH** — v2 line 20 reads "16,195 compounds"; no "17,120" or "851" remains. My earlier read predated the writer's data-review commit; the row is closed, not a persisting defect.
- Y10, Y13, Y14: writer reports preprint abstract (regime C wording, transductive caveat), precise censoring wording (190 / 7,600 mixed ">") and "Pfam-family-disjoint" now applied in both abstracts, §4.2, Methods, §1, v2 claims table/gate paragraph and the brief; writer's `verify_artifacts.py` 88/0 and `final_pass.py` FAILS 0. I have **not** re-read every instance; status **UNVERIFIED-FIXED** until the full rerun after the regenerated aggregate.
- Y9 (45 sources in older docs) remains STALE (not manuscript files).

---

## UPDATE 8 — Regenerated aggregate (ab35481bb, sha e5da79e9…ef13) re-verified; IH-LM integration paragraph; brief §7 spend table and Cost Explorer

### 8a. Aggregate integrity after the C1 fix (script `qa_audit/aggregate_integrity.py --strict`, `qa_audit/cluster_recompute.py`)
- File sha256 of `results/l7_aggregate.json` = `e5da79e9ab27086a505ced08fd18845deafd98e6c949428b1bbe4f357c80ef13` = the announced value. **MATCH.**
- 11 keys: chemberta A/B (3 files each), gbm_aware, gbm_blind, gbm_physchem × A/B/L (10 each) = **96 small files, each under exactly one key**; duplicates across directories by (learner, regime, seed): **0**; aggregate `n_seeds` equals raw file count for all 11 keys. `inputs.n_files` 116 = 96 small + 20 LLM files (`n_small_files_loaded`, `n_llm_files`, `files_per_key` recorded). This resolves my earlier "116 vs 96" flag: the 20 are the LLM-arm files, not phantom small files. **MATCH.** (The inputs `sha256` field is still 9706ce46… because it hashes the file name/size list, which did not change; it is not a content hash.)
- 237 of 244 yield and E-AUROC cells recomputed from raw per-task files agree with the aggregate to 1e-3 (mean and n); the 7 flagged cells are the `one_shot` arm, whose `hits` list is empty (aggregate n = 0, raw sum 0): not a defect. Script patched to skip empty-hits arms.
- Regression test `test_no_input_is_dropped_or_overwritten_and_aware_blind_stay_apart` (7/7 tests in `test_aggregate_l7.py` pass). I simulated the pre-fix keying on the real files: it retains **66 of 96** tasks, so the test's `total tasks == files` assertion (and the explicit aware/blind assertions) **would have failed on the old code**: it covers the failure. Limit: learner keys are assigned from the input directory name, so a new directory with a non-conforming name falls to a default key; the overlapping-arm check raises only on repeated arms for the same task.

Independent recomputation vs WS2's reported values (own bootstrap; same point estimates, intervals within resampling noise):

| quantity | aware | blind | WS2 report | status |
|---|---|---|---|---|
| regime L K_phys − K_shuf yield (99%) | +1.8 [−2.1, 6.0] | +7.1 [3.2, 11.1] | +1.8 [−2.5, 5.8] / +7.1 [3.3, 10.9] | MATCH (points exact) |
| regime L cluster `loop_sub − frozen_sub` E source-rho, 11 labs | +0.075 [0.037, 0.116] | +0.011 [−0.072, 0.082] | +0.075 [0.037, 0.115] / +0.011 [−0.071, 0.080] | MATCH |
| regime L cluster `loop_sub − shuffled_sub` | +0.033 [−0.061, 0.121] | +0.071 [−0.074, 0.182] | – | derived; blind equals the draft's P3 "+0.071 (−0.079 to 0.181)" |
| regime L cluster K_phys − K_shuf | −0.010 [−0.055, 0.036] | −0.013 [−0.041, 0.019] | – | derived; both null |
| regime A `loop_sub` / `loop_kphys_sub` yield | 86.0 / 90.7 | 87.4 / 89.8 | agg: same | MATCH (aggregate gbm_aware|A, gbm_blind|A) |
| regime L loop − frozen / loop − shuffled yield | +47.3 / +117.7 | +13.2 / +79.5 | – | derived from raw; agrees with aggregate cells |
| zero-sibling ρ `loop_sub`, regime A | 0.181 | 0.000 | WS2: loop aware in L = 0.103 (my 0.107 for `loop_sub` in L); 0.181 is regime A `loop_sub` | MATCH; WS2's note conflates regimes; no discrepancy |

Consequence for the drafts: the blind-GBM numbers already quoted keep their values but must now be labelled `gbm_blind` (the aggregate no longer has a plain `gbm` key); the aware-GBM numbers are new. A key finding: the pooled-L cluster result "loop beats frozen" holds for aware (+0.075, CI excludes 0) and not for blind. Remaining for the full rerun after the writer's update: hash, [REGEN] marks, learner label for every L7 number, F5/T6 regeneration, 12-vs-11 configuration counts, 54-contrast counts (11 keys now), K_phys_channel vs K_phys_textbook assignments.

### 8b. IH-LM integration paragraph (commit d7c31eb80) vs `docs/20261030_IHLM_V2_INTEGRATION.md` and `ihlm_v2/smoke_result.json`
| claim | source value | status |
|---|---|---|
| 22-row inventory | doc table rows 1–22; my tally of first verdicts: 6 AS-IS, 7 FIX, 6 PATTERN, 3 NO (several rows carry compound verdicts, e.g. "NO (as evidence) / PATTERN"); **no verdict counts are quoted in the paragraph or the doc** | MATCH (22); counts not stated, none to verify |
| 11 tests pass | doc §3.1 "11 passed"; 11 test functions; I ran `pytest -q test_ihlm_v2.py`: **11 passed in 81 s** | MATCH (rerun) |
| v4 coverage ~15 % | `v4_coverage_in_random_300` = 0.1533 | MATCH |
| Townsend 37/112, Kelly 0/79, CHUGAI 0/40 | JSON `v4_coverage_note`: same (also Furukawa 0/22, Faris 0/10, Bhardwaj 6/6, omitted by the paragraph) | MATCH |
| smoke mean hits 9.0 vs 3.0, 2 seeds | JSON `mean_hits` ihlm 9.0, random 3.0; seeds 2; per-seed 12/4 and 6/2 | MATCH (and correctly labelled no-claim) |
| checkpoint SHA unchanged | JSON `checkpoint_unmodified: true` (boolean; hash value not stored in the JSON, test asserts equality of sha before/after) | MATCH |
| 25-minute full-size run not finished | doc §3.2; smoke run itself 365.8 s | MATCH (REPORTED) |
| 34.7 % lariat, no topology token | doc row 1 and `20261027_V5_PREREG…`/`20261028_MANUSCRIPT_v4…` | MATCH (REPORTED) |
| earlier paragraph (a): "about 800 lines (model 287, symbolic 170, tests 240, intrinsic 102); 3 of 14 tests expected-failure" | current files: model 287, **symbolic 195**, **test_ihlm.py 248**, p0_intrinsic 102 (total 832); **15** test functions, 3 xfail | **STALE** (files changed after 87f4f6718; update to 195/248/15 or "about 830 lines, 15 tests") |

### 8c. Brief §7 spend table vs cost logs
| row | claim | evidence | status |
|---|---|---|---|
| Tier A API | about 4.2 (relay 4.3); Haiku cap 1.6, cost 2× estimate | `20261029_L7_RESULTS_LOG.md` line 21: "≈ 4.2", Haiku 0.175 vs 0.088/seq, stopped at 1.6 cap | LOGGED, MATCH |
| committee round 1 | 0.370 = 0.0906 + 0.2796, cap 6.00 | `committee_raw/20261030/cost_log.csv` (sum 0.3702); synthesis states 0.370 and cap 6.00; balance 4.339 → 3.961 (drop 0.378, billing lag) | LOGGED, MATCH |
| committee round 2 | 0.772 counted = 0.2987 + 0.1128 + 0.3606 (0.2404 × 1.5), cap 2.00; Opus refused 0 | `ext_cost_log.csv` (sum 0.7721); balance 3.961 → 3.309 = **0.652 actually billed** (= reported 0.2987 + 0.1128 + 0.2404) | LOGGED, MATCH; the brief should add that the key was debited 0.652, not 0.772 (0.772 includes a 1.5× safety multiplier) |
| key balance 3.96 before round 2 | csv `balance_before` 3.961 | LOGGED, MATCH |
| GPU L7 comparators 3.58, 4.70/h, nine instances, cap 40 | L7 log line 42 | LOGGED, MATCH |
| Tier B 93–116 / ~198 with Opus | L7 log line 29 | LOGGED (an estimate in the log), MATCH |
| C2 under 3 (relay: under 1) | C2 doc line 71 "estimated < USD 3"; relay figure has no committed source | ESTIMATE, correctly flagged |
| canary under 1 | P1 plan line 43 "< USD 1" | ESTIMATE, MATCH |
| T2 6–7, hard cap 20 | T2 doc line 56 says cost "estimated from timed debug tasks … and recorded here" but records no figure | ESTIMATE without committed figure, correctly flagged |
| S2 planned cap 80 ("needs your approval") | not checked in an S2 document | UNVERIFIED |

### 8d. Cost Explorer command (read-only; nothing changed)
- `aws ce get-cost-and-usage --time-period Start=2026-10-27,End=2026-10-29 --granularity DAILY --metrics UnblendedCost --filter '{"Tags":{"Key":"project","Values":["cyclic-selector"]}}' --group-by Type=DIMENSION,Key=SERVICE` **runs** (aws-cli 2.13.20, account 399683337364, root identity) but returns **USD 0 and no groups for both days**.
- Cause: `aws ce list-cost-allocation-tags --tag-keys project` shows `project` **Status: Inactive** (LastUsedDate 2026-10-01). The brief's statement that the tag is "activated for cost allocation" is therefore **false**; no spend can be attributed by this filter until it is activated (activation is not retroactive for earlier days; I did not change it).
- Untagged account-wide cost for the same window (not attributable to this paper; all account activity): 2026-10-27 EC2 compute 29.30, S3 11.43, VPC 2.86, EC2-other 2.49, ECR 1.54; 2026-10-28 (partial, estimated) EC2 compute 5.60, VPC 0.76, ECR 0.45, GuardDuty 0.23, RDS 0.21 (USD, top five groups by service).
- Brief fix: say the tag is inactive and the filter returns 0; either activate the tag (owner action, not retroactive) or filter by service/instance type and date, stating that figures are account totals.

---

## UPDATE 9 — Full rerun on writer commit a88c61593 (aggregate e5da79e9…ef13, ab35481bb)

Scope: main draft (23,819 words), v2 (6,043), preprint `manuscript_loop.md`, patch note, brief, FIGURES_STATUS, committed figures + MANIFEST. Tools: `qa_audit/final_pass.py` (FAILS: 0), writer's `verify_artifacts.py` (119 checks, failed: []), manual greps, direct reads of `l7_aggregate.json`.

| # | check | result | status |
|---|---|---|---|
| Z1 | cited aggregate hash | e5da79e9ab27… cited in main (4), v2 (3), brief (3), patch note (2); the file hashes to it; old hashes e2302b87… and 386efae2… appear only as "superseded" (main line 188, brief line 15) | MATCH |
| Z2 | [REGEN] resolved | `[REGEN]` absent from main and v2; `[REGEN-K]` (K_phys vs shuffled; WS2's permutation-order fix pending, res7q_* `_detK` re-run not launched) in main ×4, v2 ×3, brief ×1; the brief's two other REGEN lines are explanatory text | MATCH for the old markers; **K_phys − K_shuffled numbers PROVISIONAL (open by design)** |
| Z3 | learner labelled for every L7 number (sampled: 12 contrasts) | aware/blind cluster loop_sub − frozen_sub +0.0752 [0.0373, 0.1148] / +0.0111 [−0.0713, 0.0799]; loop_sub − shuffled_sub +0.0335 [−0.0628, 0.1205] (quoted +0.034, −0.063 to 0.120) / +0.0708; K_phys − K_shuf yield A +5.9 [2.9, 8.8], B +2.3 [−0.5, 5.6] aware, +3.2 B blind, L +1.8 [−2.5, 5.8] aware / +7.1 [3.3, 10.9] blind; B E-AUROC gain +0.0146 [0.0011, 0.0298] / +0.0326 [0.0105, 0.054]; K_phys − none A +4.7 / +2.4, B +4.8 / +4.9; L loop − frozen 47.3 / 13.2 | all MATCH the aggregate |
| Z4 | writer's question: why my UPDATE 8 intervals differ slightly | My intervals come from my own bootstrap (seed 12345, B = 20,000, percentile) on the raw files; the aggregate's come from its own seeded resample. Point estimates are identical; endpoints differ by resampling noise (e.g. aware L K_phys − K_shuf [−2.1, 6.0] mine vs [−2.5, 5.8] aggregate). **The manuscript should quote the aggregate's intervals**, as it does. | MATCH (no defect) |
| Z5 | `verify_artifacts.py` | 119 checks, failed [] (re-run by me); it asserts learner keys, aware zero-sibling nonzero vs blind zero, aware L yield contrasts, chemberta n = 3; it asserts blind L loop−frozen/shuffled but I could not see aware L cluster checks by name | MATCH; coverage of aware cluster rows UNVERIFIED |
| Z6 | brief length cells | brief says "about 20.5k words" (main) and "about 4.3k" (v2); `wc -w` now **23,819** and **6,043** | **STALE** |
| Z7 | brief §7 spend fixes | tag Inactive and Cost Explorer returns zero (line 80/103); round 2 debited 0.652 vs 0.772 counted (line 92); S2 80 = stop rule "projected total > 80 USD" in the S2 plan step 1 (line 101; doc line 16 confirms) | MATCH |
| Z8 | IH-LM line counts | main line 282: 830 lines, symbolic 195, tests 248, intrinsic 102 | MATCH |
| Z9 | IH-LM provenance floor | main/v2/brief state floor 87f4f6718 (94efe092d now only "invalid below"); `final_pass.py` now tests 87f4f6718 (patched by me) | MATCH |
| Z10 | figures | F5 pdf/png committed with MANIFEST; MANIFEST file hashes equal `shasum` of the committed files; sources `l7_aggregate.json`@ab35481bb; FIGURES_STATUS "2 seeds" note obsolete (collision symptom). **T6 is named in MANIFEST but no committed T6 file exists in `figures_paper/committed/`** | F5 MATCH; **T6 UNVERIFIED (artifact not committed)** |
| Z11 | nine-configuration wording (patch note) | gbm_aware/blind/physchem × A/B/L = 9; chemberta (A/B, 3 seeds) outside | MATCH |
| Z12 | chemberta exploratory results | in aggregate (n = 3); verifier asserts n; drafts treat as exploratory | MATCH |
| Z13 | "stereo-blind" / "plain GBM" wording | remaining uses are generic definitions or explicit "earlier plain-GBM numbers were blind" notes | MATCH |

Counts for this rerun: 11 MATCH (Z1, Z3, Z4, Z7–Z9, Z11–Z13 and Z10-F5, Z5), 1 STALE (Z6), 1 UNVERIFIED (T6), 1 PROVISIONAL-by-design (K_phys vs shuffled, until the `_detK` aggregate). Standing items: Appendix B citation census unchanged (LIT-VERIFIED 5, LIT-SUMMARY 31, LIT-SNIPPET 4, LIT-UNVERIFIED 16 in the main draft); red-team Addenda 5 and 6 items still open.

---

## UPDATE 10 — Retrospective-benchmark restatements (A10/A11, `20261030_RETRO_RECOVERY_RESULTS_V5.md`, 756a0f0aa)

Recomputed by me from the frozen data (`retro_recovery/data/`, own pandas code, not the benchmark workstream's scripts):

| claim (workstream message) | my recomputation | status |
|---|---|---|
| I: 6,619 distinct compounds; 1,731 in > 1 target; 364 in > 1 family; 1,093 rows (11.6 %) with the compound in another fold | 6,619 / 1,731 / 364 / 1,093 (11.6 %) | MATCH |
| folds_v2: 317 → 298 families; I 26 → 23 families; accession/fold inconsistencies → 0 | `folds_v2.csv` 298 families (v1 317); I targets map to 23 families; accessions in > 1 family 0 and in > 1 fold 0 (v1: 29 and 24) | MATCH |
| censoring: 63.6 % of inactives vs 3.1 % of positives | inactives 63.6 % with ">"; positives 2.5 % with ">" and **3.1 % with ">" or "<"**. The 3.1 % is the any-direction censoring; the ">"-only figure is 2.5 % (190 / 7,600), which the drafts use | MATCH (definitions differ: state "any censoring relation") |
| `overlap_audit.json` figures | 6,619 / 1,731 / 364 / 1,093 / 0.1159 present in the file | MATCH |
| gate numbers (I C3 0.575–0.621 by variant; M C3 0.461 / 0.515; M2 C2/C3 0.743 / 0.739; I_EX infeasible 1,473 positives vs 72 inactives; H4b NN 0.753/0.822/0.869) | read from result JSONs only for I v1/v2 and M items C1 (0.503, 0.502, 0.476); the C3 values are not recomputed by me (needs their pipeline) | REPORTED, not recomputed |

Propagation into the manuscript set (all cite the pre-A11 gate numbers):
- Main draft line 222 (Results table): "M … fingerprint control 0.315 (below chance)" is stated **without** the label-inversion qualification that the same document gives in Appendix line 463 ("registered C3 0.315 is a label-inversion artefact; corrected 0.461 (0.423, 0.498)"). Line 368 (artifact list) also quotes 0.315. **MISMATCH (internal contradiction; the table should carry 0.461 / 0.515 with the scope).**
- Brief line 17 correctly says 0.315 is an artefact (0.461 flat-disjoint). **MATCH.**
- Analysis-I gate numbers in the drafts (0.584 registered; 0.580 / 0.578 / 0.583 purged) come from the data/eval review and the earlier gate; A11 restates them (0.575–0.621 by variant, primary flag level 98.3 %, ±0.05 equivalence at 90 % intervals, so even unbiased benchmarks are NOT_VALID_NOT_EQUIVALENT at 14–26 families). The drafts do not yet cite A10/A11 or V5 (main draft cites RESULTS_V3). **STALE** pending the writer's update; also "26 families" for I appears in main (9×), v2 (3×) and brief (1×) while folds_v2 gives 23. The qualifier is that folds_v2 is a re-freeze after the results were seen: the 98.3 % level and the ±0.05 margin were chosen after seeing intervals (disclosed by the workstream in A11): the drafts must call these post hoc.
- Position: the qualitative verdict ("no benchmark passes the gate") is unchanged in the workstream's statement; the numbers behind it moved.

### UPDATE 10a — gate values re-derived from the stored family-level AUROC vectors (`results/gate_A11_*.json`)

Method: mean of the stored `family_means` (points) and my own percentile cluster bootstrap over families (seed 1, B = 20,000, 98.3 % level). No classifier was rerun, so this checks the aggregation, not the model fits.

| file | control | families | point (file = mean of family means) | my 98.3 % | file |
|---|---|---|---|---|---|
| I v1 | C1 / C2 / C3 | 25 / 25 / 26 | 0.503 / 0.559 / 0.584 | [0.447, 0.560] / [0.487, 0.636] / [0.522, 0.648] | same except C2 hi 0.631 |
| I v2 (folds_v2) | C1 / C2 / C3 | 22 / 22 / 23 | 0.502 / 0.582 / 0.596 | [0.441, 0.563] / [0.515, 0.647] / [0.539, 0.653] | same within 0.002 |
| M (item-scope) | C1 / C2 / C3 | 114 / 114 / 120 | 0.476 / 0.556 / **0.461** | [0.431, 0.521] / [0.502, 0.609] / [0.414, 0.507] | same within 0.001 |
| M2 (flat-disjoint) | C1 / C2 / C3 | 14 / 14 / 14 | 0.665 / 0.743 / 0.739 | [0.526, 0.796] / [0.613, 0.850] / [0.595, 0.863] | same within 0.003 |

Status: **MATCH** for all 12 points (and the M C3 0.4607 and M2 0.743 / 0.739 quoted by the benchmark workstream); intervals agree to resampling noise. The v2-fold I C3 is **0.596**, above the v1 0.584: the drafts' "robust, 0.575–0.583" statement is for compound/Tanimoto-purged training on v1 folds; on folds_v2 the control is slightly stronger. The gate verdict (control well above 0.5 on I and M2) is unchanged; note the benchmark workstream confirmed (V5 §5, commit 263b4c2e6) that the 98.3 % level and the ±0.05 margin are post hoc and loosen the bias flag relative to the 95 % rule.

---

## UPDATE 11 — Stratification source-annotation defect (report from the stratification workstream; dated correction note in `20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md`)

Reported defect: Source/Year in `build_annotations.py` were taken from the first row of any assay instead of the PAMPA (loader) row; 177 of 6,960 peptides (2.5 %) wrongly sourced (150 "Ohta" that should be CHUGAI, 9 2018_CHUGAI, 18 others); 45 sources reported, 41 correct. Rerun changes: matched pairs 4,156 / 16 sources → 4,166 / 15; D-flip 7,451 / 19 → 7,467 / 18; features tested 56 → 54; replication 0/11 → 0/8; leave-labs-out Spearman 0.313 / 0.301 / 0.264 → 0.223 / 0.212 / 0.250 (blind / chiral / descriptor); confound flags 29 → 34 of 50; LSO for ≥ 3 D residues 0.40 / 0.33 → 0.26 / 0.16; structure-grouped and random CV essentially unchanged (0.666 → 0.670).

My recomputation from `CycPeptMPDB_Peptide_All.csv` (de-duplicated on Structurally_Unique_ID): the PAMPA-row source gives **41 sources**, the first-row source gives **45**: the 45 → 41 correction reproduces. The count of wrongly sourced peptides under my keying is 21 (0.3 %), not 177 (2.5 %): the workstream's annotation table is keyed differently (it carries "Ohta" labels my keying never produces), so **177 is not reproduced** [UNVERIFIED; the other counts above are REPORTED, not recomputed].

Propagation:
- `20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md:55`, `20261030_COMMITTEE2_PACKET.md:427`: carry "45 sources" (the first has a correction note at the top, the second does not) — STALE.
- `20261029_KB_AUDIT_AND_GAPS.md:81` "a different set of 45 sources": same defect candidate, not verified.
- Main draft (1× "4,156", 3× "7,451", "16 sources"), v2 (1/1/1) and brief (1/1/1) still cite matched pairs 4,156 pairs / 16 sources and D-flip 7,451: **STALE** after the correction (4,166 / 15 and 7,467 / 18). The N-methyl matched-pair effect (+0.252, CI 0.164–0.341) comes from the same pairs and must be re-read from the rerun; the KB-audit rules and the K_phys channel mined from "21 laboratories, 6,776 peptides" use their own loader and are not shown to be affected; this needs confirmation from the KB-audit owner.
- The leave-labs-out values reported in the correction (0.223 / 0.212 / 0.250) are the ones the drafts should use if they cite the stratification LSO at all; I found no draft quoting 0.313 / 0.301 / 0.264.

### UPDATE 11a — 177 vs 21 reconciled (I ran `stratification/verify_source_defect.py` on the raw CSV, read-only)

Output reproduced by me: 6,960 labelled structures; sources 45 (old rule) vs 41 (first loader row), 42 (any loader row), 56 (whole file); **21** structures whose old-rule source differs under a stable file-order rule (= the 21 structures with PAMPA rows from > 1 source); the committed pre-fix annotation has **178** labelled peptides whose Source differs from the first loader row, and the defective build's row choice (unstable sort + drop_duplicates) reproduces the committed Source for all 6,960 (True), differing from stable file-order for 184 structures. Two defects: (1) source taken from any assay's row, not the PAMPA row (gives 45 vs 41 and the 21); (2) the "first row" choice was arbitrary (unstable sort), explaining the remaining ~157 (150 Ohta ↔ CHUGAI). Status: **178 and 45 → 41: MATCH (reproduced by running the committed script)**; my earlier "177 not reproduced" is withdrawn (their first report said 177; corrected to 178). The rerun values (matched pairs, D-flip, features, leave-labs-out 0.223 / 0.212 / 0.250, flags 34 / 50) remain REPORTED, not recomputed by me. The stale-draft findings in UPDATE 11 stand.

### UPDATE 11b — post-fix state (stratification workstream message; I re-checked the drafts and recomputed the CV table)

- Drafts: main draft lines 244 and 373 now cite **4,166 pairs / 15 sources, D-flip 7,467 / 18, N-Me +0.24 (0.14 to 0.33)**; the remaining "4,156 pairs / 16 sources; D-flip 7,451 / 19" in main line 114, v2 line 99 and brief line 15 describe the pooled analysis behind the **old IH-LM edit priors** (intentional history of the leak), not a current result; "7,451 rows" elsewhere is the CycPeptMPDB v1.0 row count. My UPDATE 11 statement that main/v2/brief "still cite" the old figures is **withdrawn: those rows are MATCH/closed** (the line-373 note itself says "CSV not re-read", an open verification gap).
- Ledger row S1 (first pass) compared the drafts to the pre-fix CV values (0.313 / 0.301 / 0.264) and is **STALE**. Recomputed now from `stratification/data/cv_preds.csv.gz` (pooled Spearman with y) — values in the next line.
- Stale pre-fix copies remain in `20261030_COMMITTEE2_PACKET.md` (45 sources, 0.31/0.30 leave-labs-out, 4,156 / 16, 7,451 / 19) and `20261030_COMMITTEE_PACKET.md:281` ("29 of 50"; post-fix 34): committee artefacts not owned by the writer; footnote or refresh is the coordinator's call. Status **STALE (committee packets)**.
Recomputed pooled Spearman (blind / chiral / descriptor): grouped by flat structure 0.670 / 0.710 / 0.665; **leave-labs-out (grouped by source) 0.223 / 0.212 / 0.250**; random 0.711 / 0.760 / 0.732; N-methyl rule 0.246 (0.25). These equal the stratification workstream's post-fix values: **MATCH**. Row S1's old values (0.313 / 0.301 / 0.264) are superseded; the pre-fix grouped values (0.666 / 0.708 / 0.666) were nearly unchanged, as reported.

---

## UPDATE 12 — Stale-value sweep after the stratification fix (coordinator request; committee packets exempt as historical)

Method: regex sweep over main draft, v2, brief, patch note, preprint, FIGURES_STATUS, figure plan, `LESSONS_AND_TODAY_PLAN`, `20261029_KB_AUDIT_AND_GAPS`, `20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER`, and `figures_paper/*.py`; patterns: leave-labs-out 0.30/0.31/0.26, "45 sources/papers", 17,120 / 851, +0.151, "plain GBM", 4,156 / 16, 7,451 / 19, 0.313 / 0.301 / 0.264, "29 of 50".

| occurrence | label | status |
|---|---|---|
| main 30, v2 14: "7,334 peptides from 45 papers" | describes the published CycPeptMPDB (LIT-SUMMARY), not our 6,960 set; main line 444 states this | correct, CLOSED |
| main 72, 462; brief 85: "17,120 / 851" | explicitly "earlier / pre-freeze profile, not the benchmark's count" | correctly labelled pre-fix |
| main 114, v2 99, brief 15: "4,156 pairs / 16 sources; D-flip 7,451 / 19" | IH-LM edit-prior-leak history (old pooled analysis) | correctly labelled |
| main 3, v2 3, brief 5, 7: "plain GBM" | "earlier 'plain GBM' L7 numbers were the blind learner" | correctly labelled |
| main 372 (A21): "0.22 / 0.21 leave-labs-out (post-fix)" | post-fix | MATCH |
| "+0.151" | none found in the files swept | CLOSED |
| "about a third" phrasing | no occurrence found in drafts/brief | CLOSED (no statement to reconcile) |
| `20261030_FIGURES_STATUS.md:48` and `figures_paper/make_status.py:41`: figures "checked against … (0.31/0.30/0.26 leave-labs-out)" | pre-fix values, not labelled | **STALE** |
| `20261030_LESSONS_AND_TODAY_PLAN.md:11`: "0.67 vs 0.30 leave-labs-out" | plan doc, unlabelled; post-fix is 0.22 / 0.21 / 0.25 | **STALE** |
| `20261029_KB_AUDIT_AND_GAPS.md:81`: "workstream 4's leave-labs-out fingerprint models (0.30–0.31, a different set of 45 sources …)" | pre-fix values and "45 sources"; the physchem channel comparison "ρ 0.39 vs 0.30–0.31" changes to 0.39 vs 0.21–0.22 | **STALE** (KB-audit owner) |
| `20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER.md` | no stale value found by the patterns | CLOSED |

### Figures (committed copies and provenance)
- **FCV_evaluation_schemes (committed, a88c61593, 16:21 on 2026-10-28):** I opened the PNG. It still shows **"n = 6,960 peptides, 45 sources"** and leave-labs-out bars **0.31 / 0.30 / 0.26**; post-fix is 0.223 / 0.212 / 0.250 and 41 sources. The MANIFEST cites `cv_preds.csv.gz`@59d654cbc (pre-fix); the correction commit is 50c5deea6 (19:16). **STALE: not regenerated.**
- Other figures whose MANIFEST sources predate the fix commit and whose inputs the fix changed: **F8_strata_heatmap** (`strata_perf.csv`@59d654cbc; changed in 50c5deea6, 488 lines), **F9_mmp_forest** (`mmp_effects_*`@59d654cbc, matched pairs 4,156 / 16 → 4,166 / 15), **F2_dataset_structure** and **FL5_loop_results** (`annotations.csv.gz`@2fe624487; the annotation file was corrected later, e2d1069bf). **STALE or UNVERIFIED until regenerated** (F2/FL5 only if the plotted quantities depend on Source; I did not open those PNGs).
- `f_cv_schemes.py` asserts the figure's leave-labs-out values against the analysis document (tolerance 0.011); it would fail on the pre-fix figure against the post-fix document, so a regeneration run will show it. I did not run it, because it writes into the gitignored `out/` directory.

### UPDATE 12a — figures regenerated (writer commit 0eb4949b8), re-checked

- MANIFEST: 28 files hashed, **0 mismatches** against the committed files.
- FCV (opened): "n = 6,960 peptides, 41 sources"; leave-labs-out 0.22 / 0.21 / 0.25, grouped by flat structure 0.67 / 0.71 / 0.67, random 0.71 / 0.76 / 0.73: **MATCH** my recomputation from `cv_preds.csv.gz` (0.223 / 0.212 / 0.250; 0.670 / 0.710 / 0.665; 0.711 / 0.760 / 0.732).
- F9 (opened): PAMPA N-Me added n = 4,166 / 15 (effect about +0.24, CI about 0.14–0.33), D flip n = 7,467 / 18: **MATCH** the corrected pair counts. MANIFEST sources for F2/FL5/F9 now cite annotations / mmp files @e2d1069bf and F8 strata @50c5deea6 (post-fix). The F9 MDCK file's cited commit was not checked.
- F1: file bytes unchanged in size; the manifest source commit for `PREREG_LOOP.md` moved (405ed42cc → 37a839a65), which explains the re-save; contents not diffed. F2, F8, FL5 not opened (whether Source enters their plotted values is unverified).
- T6: still **no committed T6 file** in `figures_paper/committed/` (manifest names it as a source entry only): UNVERIFIED.
- `verify_artifacts.py` was not rerun by the writer after regeneration; I did not rerun it either.
- Status: FCV/F9 STALE → **MATCH**; F2/F8/FL5 provenance MATCH, plotted values UNVERIFIED; T6 open.

---

## UPDATE 13 — FINAL claim-to-artifact audit of Paper 1 (v2 at HEAD 8f2113579; brief §0; morning package)

Scope: `docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md` (122 lines, 5,052 words by `wc -w`), `docs/20261030_REVIEW_BRIEF.md` §0/§0.0, `docs/20261031_PAPER1_MORNING_PACKAGE.md`. Method: every tabled and quoted number re-read by script from the committed result files (`l7_aggregate.json`, `l5_aggregate.json`, `frozen_ab_aggregate.json`, `regime_L_heldout_sets.json`, `gate_A11_*.json`, `h4b_baselines.json`, `h4b_strata.json`, `c2_audit/results_A_aggregate.json`, `results_B_v2_aggregate`, `reeval_intervals.json`, `kphys_multiplicity_l7q.json`, `pilot4/results/test_summary.json`), plus recomputation from raw data where cheap (CycPeptMPDB, frozen binding lists). Tools rerun: `verify_artifacts.py` 123 checks, failed []; `final_pass.py` FAILS 0; aggregate sha256 = ebc525090740249f50ec4e2d96cd809e6b6b802c0f42ad2f7815f2dbdb76387e (**matches** v2 lines 3 and 107).

### 13.1 Ranked problems (WRONG first; file:line are in v2 unless stated)

**WRONG**
1. **v2:122 (Appendix B): "every paired interval includes 0" is false.** `test_summary.json` gate, `f0_1000|k10`, overall paired difference vs the best test baseline (GP): **−0.124 (−0.199 to −0.049)**, which excludes 0; the table itself shows the meta-learned predictor at 0.367 against GP 0.491 (k = 10) and 0.474 against 0.628 (k = 25). Only the registered hard-stratum intervals all include 0. Fix: "the registered hard-stratum paired intervals all include 0; overall, the meta-learned predictor is detectably below the best lookup baseline at k = 10 (−0.124, −0.199 to −0.049)."
2. **v2:11 and v2:71: censoring AUROC "0.206 (0.134 to 0.280)" carries the wrong interval level and wrong unit.** In `gate_A11_I_v1.json` the secondary control `C4_censored_label` has `lo/hi` = 0.134 / 0.280 at the Bonferroni secondary level **0.9972**; the 95 % interval is **0.159 to 0.253** (90 %: 0.166 to 0.245). Line 71 introduces the list as "95 % family-cluster CI". It is also a family-mean AUROC over 26 families, not a "per-target AUROC". Fix: "0.206 (95 % family-cluster 0.159 to 0.253; 99.7 % 0.134 to 0.280)".
3. **v2:27 (and brief §0.0 item 4): "2013_CHUGAI and 2016_Furukawa are held out in 10 of 10 and 40 of 40 seeds respectively" mixes denominators.** `regime_L_heldout_sets.json` (30 seeds): both are held out in **30 of 30**; in the development seeds 0–9 both are held out in **10 of 10**; 40 of 40 is the Appendix A frozen-experiment seed set. Fix: "in all 10 development seeds (and in all 40 seeds of the Appendix A experiment)". (The rest of line 27 re-derived: 6 to 18 held-out laboratories, 25.2 % to 34.3 % of peptides per seed, all 18 in 3 of 10 seeds, 8 distinct sets in seeds 0–9: MATCH.)
4. **v2:71: "equivalence is unreachable at 14 to 26 families (90 % intervals about ±0.04 to ±0.07)" understates the 14-family case.** From `lo90/hi90`: I v1 C3 ±0.044, I v2 C3 ±0.040, strict compound-disjoint list (15 families) C2 ±0.065, **M2 (14 families) C1/C2/C3 ±0.092 / ±0.082 / ±0.095**. Fix: "about ±0.04 to ±0.09".
5. **v2:3 (banner item 3) and v2:107 are stale and contradict the body.** Banner: "the permeability few-label cells of the fusion study predate the source correction and are not used here", yet §6 (v2:104) reports the corrected T1/T1b cells (f595013b3). v2:107: "(to be re-checked after the pending re-aggregation)", but the cited hash is the post-re-aggregation one. Remove both clauses.
6. **v2:80: "…and in the blind learner" overreaches.** The blind learner has development seeds only (`gbm_blind_detK`, seeds 0–9: +6.00, +4.10, +5.20 with Holm 0.018 / 0.068 / 0.16); only regime A passes Holm and the replication on seeds 10–29 exists for the aware learner only. Fix: "in the aware learner (replicated on seeds 10–29) and, with development seeds only, in the blind learner in regime A".
7. **v2:77 and v2:41 (P6): the C2 point estimates and their intervals refer to different estimators.** `results_A_aggregate.json`, `A_ext`: learn − NN (family-disjoint background) mean over targets **+0.0017**, mean over families **+0.0138**, CI [−0.018, 0.047] is the family-cluster interval of the family mean; learn − random +0.143 (target mean) vs +0.149 (family mean) with CI [0.102, 0.197]; "no background, NN beats GBM by 0.077" is the target mean (family mean 0.057, CI 0.026 to 0.091). Fix: quote the family mean with its family CI (learn − NN **+0.014**, −0.018 to 0.047; learn − random +0.149; NN − GBM 0.057) or label the point as target-weighted.

**MISLEADING (numbers right, framing stronger or mixed)**
8. **Protocol mixing (coordinator's item) at v2:11, v2:36 (P1), brief §0.0 item 3, morning package §1.** The aggregate holds, for aware/blind GBM, **only `_sub` arms in regimes A and B** (the full-protocol `loop`/`frozen` arms exist for A/B only for the physicochemical learner: +15.0 / +9.3). `_sub` = per round, selection of 50 from a seeded **random 150-peptide candidate subset** of the original pool (`run_l7a.py` `subset()`, `n_cand = 150`; pool 4,475 in L), so the loop has a 3:1 choice only; `loop`/`frozen` select from the whole pool. v2 puts A +8.0 and B +1.5 (sub) next to L +47.3 / +13.2 (full) as one series; the **matched-protocol L values are +8.4 (5.8 to 11.2) aware, +3.1 (−0.6 to 6.9) blind, +3.1 (1.3 to 5.2) physicochemical**, about the same as A. The 75 % / 92 % shares are full-protocol L only (verified: (201.3−62.5)/(248.6−62.5) = 74.6 %; (214.3−62.5)/(227.5−62.5) = 92.0 %). v2:3.1's table keeps the columns apart; the abstract and P1 do not. Fix wording for the abstract: "…+8.0 (A) and +1.5 (B) under the equal-footing candidate-subset protocol (selection from 150 random candidates per round) and +8.4 aware / +3.1 blind in regime L under the same protocol; selecting from the whole pool the regime-L gain is +47.3 aware / +13.2 blind, and 75 % to 92 % of the full-pool loop-minus-random gain is already in the frozen model." Presenting +47.3 beside +8.0 / +1.5 overstates the regime-L loop effect by about 6× relative to A/B (a protocol effect, not a regime effect); equally the full-pool +47.3 should not be called "small".
9. **v2:11 and v2:36 (P1 "supported as small") versus v2:59–67.** "Small" holds for **yield**. In §3.2 the loop − frozen **held-out ranking** gain is large and its cluster CI excludes 0 in every learner in A and B (aware +0.236 and +0.210; blind +0.134 and +0.235; physicochemical +0.142 and +0.292); only regime L is learner-dependent. The abstract's sentence "feedback effects on within-source ranking are learner- and regime-dependent" understates A/B. Fix: state "small in yield; sizeable in held-out ranking in A and B; mixed in L".
10. **v2:80 interval type for K_phys.** v2:5 says K_phys contrasts are 99 % CI of the mean (that is what the aggregate stores: `ci_level_pct` 99.0, e.g. aware confirmatory A +4.95 [2.3, 7.5]); §3.6 says "seed-bootstrap 95 % CI" (those are the 95 % intervals in `kphys_multiplicity_l7q.json`, aware A [2.95, 6.9]) and uses the sign-flip Holm over a 12-group family. The pre-registered L7q rule (PREREG_LOOP Addendum 2) is Holm over **3 regimes** on two-sided **bootstrap** p-values with CI levels 98.33 / 97.5 / 95 %, and a "supported" reading limited to aware GBM, seeds 10–29, one library. State which analysis is reported and that the registered one is not (yet) reported in a results document. The conclusion (aware confirmatory +4.95, +4.85, +4.90; CIs far above 0 in all three) would hold under either.
11. **v2:104 (T1).** "fails the Bonferroni-corrected reading": from `reeval_intervals.json` F2 at k = 5 fails only the **t Bonferroni(3)** reading (lower bound −0.012); the **percentile Bonferroni(3)** lower bound is +0.0034 (passes). Also "supported at k = 5 only" is by the registered rule with 10 of 16 laboratories positive and 1 of 6 cells; the wording "exploratory, not a claim of this paper" is adequate. Fix: "fails the t-based Bonferroni(3) reading; passes the percentile one narrowly".
12. **Brief §0 has two layers that contradict each other** (brief lines 7–30, the 2026-10-28 23:20 "midnight update", versus §0.0, lines 3–5). Line 16: L7q "not aggregated; the frozen aggregate (hash ebc52509) predates it" (now aggregated: line 5 and commit 9190e64c8); line 17: "T2 … no T2 result is reported" (v2 §6 reports verdict PARTIAL); line 18: "IH-LM ladder … no ladder result exists" (commit eee659696 "T-LADDER results: complete"); line 19: "Frozen aware-vs-blind … no results section is committed" (Appendix A, bf530d27e). Mark §0 lines 7–30 as superseded or refresh.
13. **Morning package §1 and §2.** "v2 ~4,100 words" (wc: 5,052); "verifier 120 checks" (rerun: 123); §5 gives the K_phys offline row as "10 of 21 laboratories" while `20261029_KB_AUDIT_AND_GAPS.md:75` and `20261030_IHLM_V2_INTEGRATION.md` row 18 give **19/21**: one of the two is wrong; I did not recompute it (pre-source-correction analysis).

### 13.2 What was VERIFIED (by script, from the cited committed file)
- **L7 aggregate cells in v2 §3.1** (aware / blind / physicochemical × A, B, L; loop − frozen sub, loop − shuffled sub, loop − frozen full, loop − random full, 95 % intervals) and the abstract's +8.0 (3.6 to 12.5), +1.5 (−1.9 to 4.8), +47.3 (34.6 to 58.2), +13.2, +4.9 (−4.4 to 14.1); frozen 201.3 / random 62.5 / loop 248.6 (blind 214.3 / 227.5): MATCH. E-AUROC loop − one-shot aware −0.006 (−0.033 to 0.025), blind +0.003 (−0.034 to 0.037): MATCH.
- **§3.2 cluster table**, all 27 cells (means and intervals) and the 6 / 9 / 11 cluster counts, and the ▲▼ marks: MATCH.
- **L5** (+186.3; spread 158.5 to 209.0; CI of the mean 181.1 to 191.5; B +22.2 spread −1.6 to 44.1, CI of the mean 17.7 to 26.5; 346.1 of 500 picks from 2020_Townsend; loop − K_z −0.5, spread −20.0 to 17.2): MATCH; interval types correctly labelled (spread vs CI of the mean).
- **Appendix A** (frozen aware − blind, 40 seeds): A −0.5 (t −2.4 to 1.3), B −1.1 (−2.5 to 0.3), L −16.4 (−23.9 to −8.9; Holm 0.00023), source-cluster −16.4 (−64.8 to 17.4) over 20 sources, Townsend −21.0, planted flat control in L −5.7 (90 % t −21.5 to 10.1) failing the ±10 rule, `controls_valid` False: MATCH.
- **Validity gate** (v2:71): fingerprint 0.584 (0.533 to 0.636), 0.575 (0.524 to 0.628), 0.579 (0.529 to 0.631), 0.596 (0.549 to 0.643), 0.621 (0.555 to 0.685), typicality 0.503 (0.458 to 0.550), multi-proxy 0.559 (0.499 to 0.619), M 0.461 (0.423 to 0.498), M2 typicality 0.665 (0.551 to 0.772), NOT_VALID_BIASED under every variant, I_EX infeasible (1,473 positives, 72 inactives): MATCH (95 % level). Binder counts (16,195 / 14,599 / 793 / 24,583 / 20,562 / 4,021), 6,619 compounds, 1,731, 364, 11.6 %, folds_v2 298 / 23: MATCH (recomputed from the frozen lists).
- **H4b** (§3.4): NN 0.753 / 0.822 / 0.869 with CIs, fit-on-revealed 0.750 / 0.817 / 0.861, pretrained-plus-revealed 0.672 / 0.736 / 0.823, zero-shot 0.539 (0.478 to 0.605), close-bin gain +0.351 (0.259 to 0.448), folds_v2 NN 0.758 / 0.827 / 0.871: MATCH. (The +0.351 is the FP-k fit-on-revealed arm's gain over zero-shot, not the NN's.)
- **C2 / anchors**: 0.287 / 0.241 / 0.101 vs 0.299 / 0.25 / 0.117 (`A_repro10`); 40 targets, 23 families; anchor k = 5 mean +0.004 (−0.061 to +0.050) and planted full-coverage +0.100 [0.031, 0.201]; best design power 0.34 (document): MATCH.
- **T2** +16.7 [7.0, 26.3] regime B, B2 +6.2 [−2.4, 14.8]: MATCH (document). **T1** F2 k = 5 +0.058, percentile 0.010 to 0.108, t 0.002 to 0.113; F2 − PT+k −0.132: MATCH (`reeval_intervals.json`, T1 doc).
- **L7q K_phys** (§3.6): confirmatory +4.95 / +4.85 / +4.90 (aware, n = 20), shuffled-knowledge below the plain loop by 2.2 / 1.2 / 3.65, Holm values from `kphys_multiplicity_l7q.json`: MATCH; development and blind values: MATCH (see problem 6 for scope).
- **Appendix B**: all 20 overall / hard cells of the five methods equal `test_summary.json`; MDE 0.13 to 0.19; "0 of 50" repeated splits (f and g `frac_pass` 0.0); hard-stratum prior-ahead-of-lookup claims (0.155 vs 0.065 / 0.069 at k = 3; lookup catches up by k = 10): MATCH (problem 1 is the only error).
- Stratification (§3.6): leave-labs-out 0.223 / 0.212 (0.22 and 0.21 quoted), grouped 0.670 / 0.710, random 0.711 / 0.760: MATCH (UPDATE 11b). Label-range recovery 21 % / 12 % / −7 %: MATCH (L7 log).

### 13.3 DOCUMENT-ONLY, UNVERIFIED, or close-but-not-exact
- DOCUMENT-ONLY (read in a committed document, data file not re-read by me): §3.7 power table (three pilot docs; edit-effect sources 5 / 7 and MDE 0.191 / 0.089 present in the prereg/results docs), single-seed 251 / 151 / 47 check (n = 1, labelled REPORTED), anchor design power 0.34, T1 shuffle-null 5 of 15, K_phys offline 0.252 / p 5 × 10⁻⁵ (labelled pre-source-correction).
- Close but not exact: raw hit rate in the two largest laboratories **1.8 %** (committee review) vs my recomputation **1.6 %** (24.4 % elsewhere matches; normalised 11.9 % matches, 6.8 % vs my 6.5 %); my keying (first PAMPA row per structure, top 10 % of the pooled raw label) may differ slightly; keep "about" or recompute with the code review's script.
- UNVERIFIED: CycPeptMPDB data licence; PeptideCLM-2 checkpoint licence statement; literature numbers (Amirahmadi 86.2 → 66.1 AUROC, Tables 3 and 6: tagged LIT-VERIFIED, not re-opened by me), all LIT-SUMMARY / LIT-UNVERIFIED items.
- Claims stronger than their evidence, checked and found acceptably hedged: K_phys (labelled exploratory, yield only, "used in no claim above"); T1 F2 k = 5 ("not a claim of this paper"); chirality (Appendix A attributes the difference to a laboratory, not to chirality; abstract reports aware and blind separately); "pretrained" for the frozen arm (v2:26 defines it as an initial-fit model, not pretrained; "pretrained" in v2 refers to the atom-LM typicality / zero-shot control and PeptideCLM-2). No stale pre-fix number found in v2 (45 sources, 17,120 / 851, 0.31 / 0.30 / 0.26, 4,156 / 16, 0.315) outside labelled-superseded mentions.

### 13.4 Counts for this audit
WRONG 7 (items 1–7), MISLEADING 6 (items 8–13), DOCUMENT-ONLY 5 groups, UNVERIFIED 4 groups, VERIFIED about 350 individual numbers across 15 files (all of §3.1, §3.2, §3.3 intervals, §3.4, Appendix A, Appendix B, plus the L5, C2, anchor, T2, T1 and K_phys figures).
