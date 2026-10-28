# Claim–evidence ledger (independent audit, 2026-10-30)

Scope: every numerical or factual claim in `docs/20261029_MANUSCRIPT_LOOP_SMALL_LLM_DRAFT.md` (main draft; read at 9,280 words, re-read after it was updated during the audit), `docs/20261027_PREPRINT_V1_PUBLIC/manuscript_loop.md` (loop preprint) and `docs/20261028_MANUSCRIPT_cyclic_peptide_closed_loop_RSI.md` (RSI draft), plus stale wording in the satellite documents. Method: numbers recomputed from raw artifacts by me (data statistics from the CycPeptMPDB CSV and the affinity table with my own code; results read from the committed JSON; hashes recomputed; citations re-opened with WebFetch). "Re-derived" = value I obtained in this audit. Auditor's own scripts: `/private/tmp/.../scratchpad/qa/data_claims.py` (scratch; not committed, output pasted here).

Status legend: MATCH · MISMATCH (claim differs from artifact or source, or is incomplete) · NO-ARTIFACT (no committed artifact found for the claim) · STALE (superseded or contradicted by a later result, or wording no longer valid) · UNVERIFIED-CITATION (source not re-opened in this audit or not openable).

## Counts (99 rows)
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
