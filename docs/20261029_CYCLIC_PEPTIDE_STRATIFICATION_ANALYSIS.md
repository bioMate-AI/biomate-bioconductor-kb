# Cyclic-peptide structural stratification, feature and substructure analysis (2026-10-29)

> **CORRECTION NOTE (2026-10-30) — source count and source assignment.** An independent data review (`docs/committee_raw/20261030b/review_data_eval.md`, F6) found that this document said **45 sources** for the 6,960-peptide labelled set; the correct count is **41** (42 among all PAMPA rows, 42 among loader rows, 56 in the whole file; recounted from the raw CSV). Cause: the annotation took each structure's `Source` and `Year` from its first row of *any* assay rather than from its PAMPA (loader) row, as `loop_retro/run_loop.load` does; **177 of 6,960 peptides (2.5 %) had the wrong source** (150 were 2023_Ohta instead of 2013_CHUGAI, 9 2018_CHUGAI instead of 2013_CHUGAI, 18 others). 21 peptides have PAMPA rows from more than one source (label = mean, source = first loader row, as in the loop code). `build_annotations.py` is fixed (commit with this note). **Re-run on corrected annotation (numbers in this document updated):** matched pairs (B4 effect sizes), substructure enrichment and replication (B5), cross-assay agreement (B6), source concentration of strata (B2 caveat, concentration table). **All cross-validation-based analyses were then re-run on corrected annotation on spot EC2 (2026-10-29/30, instance i-042657b2ec2d4b9df, m6i.4xlarge, ~6 min compute, ~8 instance-minutes, spot price 0.29 USD/h, ≈ 0.04 USD, terminated by itself; outputs in `s3://biomate-nextflow-work/cyclic_peptide/stratification/res/`); every table and number in B2–B4 is now post-fix.** Pre-fix outputs are kept in `.../stratification/data_before_source_fix/`. **The one material change: leave-labs-out (source-grouped) overall Spearman fell from 0.313 / 0.301 / 0.264 to 0.223 / 0.212 / 0.250 (fingerprint blind / chirality-aware / descriptor).** Cause: in the pre-fix folds, 150 structures labelled CHUGAI by their PAMPA data were assigned to Ohta, so a held-out laboratory's near-copies sat in training under another source name (label leakage across folds); the structure-grouped and random CV numbers did not move (0.666→0.670, 0.708→0.710, 0.666→0.665; random 0.706→0.711, 0.757→0.760, 0.730→0.732). Other CV-derived changes: source-confound flags 29→34 of 50 features (flips: hbd, frac_aliphatic, n_ext, n_backbone_mod, n_sidechain_mod); leave-stratum-out for ≥3 D residues fell (blind 0.40→0.26, chiral 0.33→0.16); strata sized by source or year changed membership (see sizes below). All other CV-based figures changed by ≤ 0.03 (median change in stratified Spearman 0.015 for structure-grouped CV; 245 cells compared).
**Numbers that changed in this document:** sources 45→41; between-source share of raw-label variance 27.7 %→27.3 %; `lariat_nterm_sc` 81 % CHUGAI (3 sources) → 100 % CHUGAI (1 source); year ≤2013 97.4 %→97.7 % CHUGAI; matched-pair, enrichment and cross-assay numbers as listed in B4–B6. Unchanged: 15 sources with ≥30 peptides, Townsend share 41.4 %, annotation audit, binding, stability, overlap, benchmark-strata results.

Status: **Part A (registered method) committed BEFORE any stratified, importance, pair or enrichment result was computed.** Results (Part B) are appended below it. Code: `research/guangzhou_all_atom/cyclic_llm/stratification/`. What was looked at before registration (non-outcome only): the HELM connection strings, `Molecule_Shape`, the 385-token monomer vocabulary, label counts per assay column, and file inventories of the stability / conformational / renal data.

# PART A — REGISTERED METHOD

## A0. Data profile (non-outcome, measured 2026-10-29)
| property | source | n | notes |
|---|---|---|---|
| Permeability, PAMPA | CycPeptMPDB (`PAMPA`) | 7,298 rows (271 at the −10 detection floor, excluded) → 6,960-peptide loader set (`Permeability`>−9.99 & PAMPA present) | primary |
| Permeability, Caco-2 / RRCK / MDCK | same file | 1,332 / 186 / 64 rows (22 / 1 / 0 at floor) | separate analyses per assay; 414 rows carry ≥2 assay types (256 with PAMPA+Caco-2) |
| Binding | `data/raw/binding_affinity/binding_affinity_v1.csv`; frozen items in `retro_recovery/data/` (read-only) | 17,120 peptide macrocycles, 851 targets | SMILES only (no monomer tokens); only SMILES-computable transformations used |
| Stability | `data/processed/pepmsnd_stability_folds.csv` (PepMSND) | 605 unique SMILES, labels 265 stable / 340 unstable, 3 label conflicts, 10 folds, species/environment in the raw file (640 rows) | binary; not all cyclic; exploratory only |
| Conformational | `data/raw/macroconf` | 69 cyclic peptides with NOE constraints | no property labels; used for profiling only (see A9). CREMP data NOT present locally (only `prep_cremp_dataset.py`) |
| Renal | `renal/renal_seed_corpus.jsonl` | 163 entries, most fields null | profiling only; too small for stratified claims |
| Solubility | — | **no cyclic-peptide solubility data in the repo** (only small-molecule AqSolDB in the TDC ingest) | **data gap; no extrapolation made** |
Topology ground truth (HELM): all 8,466 CycPeptMPDB entries have exactly one connection: head-to-tail (R1–R2) 5,528; side-chain-to-C-terminus lariat (R3–R2) 1,526; N-terminus-to-side-chain (R1–R3) 1,412. No disulfide, stapled or bicyclic peptides occur in this dataset (their strata are empty here and must be treated as unsupported).

## A1. Annotation (per peptide, key `Structurally_Unique_ID`)
From HELM + `Sequence` (identical token lists, verified 8,466/8,466): topology class (HELM connection) and `Molecule_Shape`; ring residues, tail length and ring-atom size from RDKit; length (monomers, main chain); monomer token classes (`tokens.py`): standard/N-methyl/N-alkyl (peptoid)/D/β-γ-ω extended backbone/α,α-disubstituted/proline-like/backbone-modified (N→O)/side-chain-modified/anonymous `MonoNN`/terminal caps; composition fractions (aliphatic, aromatic, polar, positive, negative, proline) with token coverage reported; D-residue count and positions; N-methyl count, positions, adjacency (consecutive pairs) and alternation (i,i+2) counts; D×N-Me co-occurrence (same residue; adjacent); Pro/Gly content; caps; stereoisomer-group size (flat-structure group, RDKit `isomericSmiles=False`); source, year; flat-structure Murcko scaffold. Whole-molecule physchem (RDKit): MW, TPSA, Crippen logP, HBD, HBA, rotatable bonds, aromatic rings, heavy atoms, Fsp3. DB-supplied 3D descriptors (EPSA, 3DPSA) are NOT used.
**Annotation audit (before analysis):** (i) token N-methyl count vs SMARTS N-methyl-amide count on the SMILES; (ii) token D count vs CIP-derived backbone Cα configuration (excluding Cys-like S-priority, Gly, peptoids, β, unknown); (iii) HELM topology vs `Molecule_Shape` vs an RDKit SMILES-only topology rule (needed for the benchmark domain, where HELM is absent), reported as confusion matrices with accuracy; (iv) planted-structure unit tests; mismatches are inspected and listed, not silently dropped.

## A2. Labels and splits
Labels: PAMPA mean per structure (rows with PAMPA ≤ −9.99 removed), within-source z-score with `source_normalize` (sources <20 pooled); raw log Papp kept for within-source pair deltas. CV: 5-fold GroupKFold by flat structure (primary: no stereoisomer sibling in training) and by source (leave-sources-out); random 5-fold for reference. GBM = HistGradientBoosting (150 iterations, lr 0.1, seed 0), as in the loop.

## A3. Stratified baseline performance
Baselines: fingerprint GBM chirality-blind (useChirality=False), fingerprint GBM chirality-aware (True), descriptor GBM (physchem + annotation counts), N-methyl rule (rank by N-methyl count). Strata (each reported with n): topology (3 classes); length bins (≤5, 6, 7, 8, ≥9 monomers); N-methyl count bins (0, 1–2, 3–4, ≥5); D-residue bins (0, 1–2, ≥3); peptoid present (y/n); unknown `MonoNN` present (y/n); extended-backbone present (y/n); backbone-modified present (y/n); ring-atom-size terciles; stereoisomer-group size bins (1, 2–7, ≥8); source-size bins; year bins (≤2013, 2014–2019, ≥2020). Metrics per stratum on grouped-CV predictions: Spearman and MAE, 95 % CI by cluster bootstrap over flat-structure groups (B = 1000). **Near-zero skill** = CI includes 0. Strata with n < 30 are shown but flagged and excluded from conclusions. **Leave-stratum-out** (train on all peptides outside the stratum, test inside) for topology, length bins, D bins, peptoid y/n, unknown y/n, year bins, reporting the drop versus grouped-CV skill.

## A4. Feature-family analysis
Families: chirality (D counts/positions, chiral fingerprint), N-Me pattern (count, fraction, adjacency, alternation), ring/topology (class, ring size, tail length, length), composition (class fractions), physchem. Descriptor GBM under grouped CV: single-family models, leave-one-family-out ablations, family-grouped permutation importance (30 permutations, on held-out folds); the same within each large stratum (topology classes, length bins). Interactions: mean within-source label on the (N-Me bin × D bin) grid with CIs; additive (ridge) vs GBM skill; explicit product features. **Source confound:** for each feature, between-source share of variance (eta²) and the correlation with the label computed (a) pooled with raw log Papp and (b) within source (average within-source Spearman, random-effects pooled); a feature is "source-confounded" if its pooled and within-source correlations differ in sign or by >0.15.

## A5. Matched molecular pairs at peptide level
Pairs are formed WITHIN source, same topology class, from token sequences compared after cyclic-rotation alignment for head-to-tail peptides (minimum edit over rotations; reversal not allowed). A pair is "single-transformation" if exactly one residue position differs after alignment; categories: (a) N-Me added/removed (same base and stereo); (b) D↔L flip (same base and N-Me status); (c) D flip + N-Me change at the same position; (d) base substitution, sub-classified by composition-class change and, where n ≥ 10, by exact base pair; (e) side-chain modification (same core, different decoration); (f) ring-size change by one residue (single insertion/deletion); (g) N-Me shift (one N-Me removed at i and added at j, same base multiset; two positions). Effect per transformation = mean Δ(raw log Papp) (direction fixed: second − first, defined by the rule listed with each category), within source, pooled over sources by random-effects (DerSimonian–Laird) meta-analysis; 95 % CI by bootstrap over flat-structure groups; n pairs and n sources always reported; transformations with < 10 pairs or < 3 sources are listed but not interpreted. **Cliff analysis:** within-source pairs with |Δz| > 1 SD by transformation type (rate with CI); model ordering accuracy per type from grouped-CV predictions (blind predictions are identical for flat-identical pairs → ties counted as 0.5).

## A6. Substructure enrichment with source adjustment
Candidate features: monomer base identities with ≥ 30 occurrences, token-class flags, positional N-Me/D motifs (e.g. N-Me adjacent to Pro, D-Pro, alternating N-Me), and a SMARTS panel (tertiary amide N-Me; N-alkyl non-methyl; aromatic ring; basic amine; carboxylic acid; ester; halogen; β-amino acid). Effect = within-source standardised mean difference (feature present vs absent) in each source with ≥ 5 peptides on each side, pooled by random-effects meta-analysis (reports I²); sensitivity analysis: mixed model `y_raw ~ feature + length + topology + (1|source)` if statsmodels is available. Multiple testing: Benjamini–Hochberg FDR 10 % across all candidate features. **Leak-safe replication:** sources are split once by a fixed hash of the source name into halves A and B; features are mined on A only and tested (fixed direction and size, no refitting) on B, and vice versa; report the replication rate (same sign, CI excluding 0) and the shrinkage of effect size. **Negative control:** the whole pipeline is rerun after permuting labels within each source (expected discoveries ≈ FDR × tests, must not exceed it); **planted-effect control:** a known shift δ added to a random feature within sources must be recovered with CI covering δ.

## A7. Cross-property analysis
(1) Permeability across assays: agreement between PAMPA and Caco-2/RRCK/MDCK on the same structures (n pairs, Spearman, within-source where possible) and whether transformation effects (A5) agree in sign across assays; assay-specific floors handled as censoring (rows at −10 removed, count reported). (2) Binding: only the SMILES-computable transformations (stereo flip: same flat SMILES; N-demethylated-equal SMILES) within the same target, plus the SMARTS panel; effects as pKd/pIC50 differences within target × document; no mixing of assay types. (3) Stability (PepMSND): odds ratios of SMARTS-panel features (logistic, clusters by `source_clusters`), cyclic subset counts reported; exploratory only given n = 605. (4) Cross-property trade-offs are reported only for structures that appear in ≥ 2 property tables by exact canonical-SMILES match; the overlap n is reported before any trade-off statement; if n < 30 no trade-off is claimed. (5) Renal and conformational data: profile only.

## A8. Decision rules and reporting
No result is called supported unless its CI excludes 0 after FDR control and (for mined rules) it replicates in the held-out source half. Every subgroup statistic shows n. Subgroups with n < 30 (strata) or < 10 pairs (transformations) are descriptive only. All code has positive-control tests; every null triggers an audit of the code first. Solubility: stated as a data gap; no inference from permeability or logP.

## A9. Implications section (written after results)
Which tokens/features an LLM representation needs (topology tokens, positional N-Me/D patterns, peptoid/ncAA vocabulary) and which strata are too thin for the benchmark (including the benchmark domain's topology mix via the SMILES-only rule).

# PART B — RESULTS (computed after Part A was committed; commit 690861c1d)

All code is in `research/guangzhou_all_atom/cyclic_llm/stratification/` (19 unit tests, all passing: annotation 6, statistics 5, matched pairs 5, importance/stratum controls 3). Result files are in `.../stratification/data/`. Tables below are generated from those files by `report_tables.py`.

## B0. Deviations from the registered method (stated first)
(a) The mixed-model sensitivity analysis (A6) was not run. (b) Leave-stratum-out results have point estimates only (no bootstrap CI). (c) Permutation importance within strata was done for four stratifiers (topology, length, D bins, N-methyl bins), not all. (d) Ring-size change by one residue (A5f) was implemented for head-to-tail peptides only. (e) Cross-assay and binding SMARTS-panel results carry no multiplicity control (6 tests; exploratory). (f) The standalone importance and stratum-metric controls (`importance.py`, `test_controls.py`) test the same algorithms as the inlined code in `feat_analysis.py` / `strat_perf.py`; their equivalence is not machine-checked. (g) Length uses `n_monomers` (HELM monomers including caps). (i) Source-assignment error found 2026-10-30 and corrected; all source-dependent and CV-based results re-run (see correction note). (j) The registered "8,466 entries" are rows; there are 7,991 unique structures and 6,960 with a PAMPA label (the loader set).

## B1. Annotation and its audit
Unique structures: 7,991 (HELM topology: head-to-tail 5,369; side-chain-to-C-terminus lariat 1,524; N-terminus-to-side-chain lariat 1,098; **no disulfide, stapled or bicyclic peptides occur**, so those strata are empty). Labelled (PAMPA) set: 6,960 peptides, **41 sources** (15 with ≥30 peptides; corrected from 45), 2,460 flat structures, years 2006–2024; Townsend alone is 41.4 % of peptides. Raw log Papp has mean −5.75, SD 0.79; **27.3 % of its variance is between sources** (27.7 % before the source fix). 21 peptides have PAMPA rows from more than one source.
Prevalence among the 6,960: peptoid (N-substituted glycine) 30.1 %; anonymous `MonoNN` monomer 16.2 % (3.0 % of residues); β/γ/ω extended backbone 15.5 %; N-terminal cap 21.8 %; C-terminal cap 11.2 %; D-Pro 56.6 %; side-chain-modified residue 6.8 %; N→O backbone modification 0.3 % (n = 24); α,α-disubstituted 0.1 % (n = 6). Token coverage of the composition classes: 96.5 % of residues (3.0 % unknown, 0.4 % unclassified).
Audit (independent SMILES-derived quantities; `audit_annotation.json`): **D-residue count from tokens equals the CIP-derived count of R backbone α-carbons in 5,166 of 5,166 peptides (100 %)** (excluding peptides with extended-backbone, anonymous, backbone-modified or Cys-type residues). N-methyl count from tokens equals the SMARTS count in 6,404 of 6,684 peptides (95.8 %); among the 5,656 peptides with no anonymous monomer the agreement is 99.89 %, and 274 of the 280 mismatches contain an anonymous monomer — i.e. anonymous monomers hide N-methylation, so the SMILES-derived count (`n_nme_final`) is used as authoritative. HELM topology agrees with `Molecule_Shape` in 7,990 of 7,991 structures. **SMILES-only topology rule T2** (needed where HELM is absent, e.g. the benchmark): overall 95.4 %, head-to-tail recall 93.1 % (5,000/5,369), lariat recall 99.9 %; most of the 369 head-to-tail misses (321) carry side-chain-modified residues such as Asp-piperidide, where the ring is closed through the Asp side chain (examples inspected). The first version of the rule scored 93.7 % overall and 90.6 % head-to-tail recall because side-chain amides were counted as outside-ring backbone amides.

## B2. Stratified baseline performance
*All numbers in B2 and B3 are from the post-fix re-run (see correction note).*

Overall Spearman (within-source z labels): grouped CV by flat structure — fingerprint GBM blind 0.670, chirality-aware 0.710, descriptor GBM 0.665; random 5-fold 0.711 / 0.760 / 0.732; **leave-labs-out (grouped by source) 0.223 / 0.212 / 0.250**. Skill falls to about a third when the test laboratory is unseen (0.67 → 0.22 for fingerprints); the descriptor model loses least (0.665 → 0.250).
**Source-concentration caveat (read before any stratum result).** Several strata are essentially one laboratory: `lariat_sc_cterm` is 99.8 % 2021_Kelly (3 sources); `lariat_nterm_sc` is **100 % 2013_CHUGAI (1 source; was reported as 81 % and 3 sources)**; length 7 is 97.6 % 2020_Townsend; year ≤2013 is 97.7 % 2013_CHUGAI; `ext_backbone` 77 % and `peptoid` 69 % Townsend. Results for those strata are results for those laboratories' series.
Readings (n and CIs in the tables; Spearman, grouped CV by flat structure unless stated):
- Chirality-aware fingerprints are at least as good as blind ones in almost every stratum; the largest gains are source size 50–299 (0.35 [0.16, 0.55] → 0.61 [0.53, 0.68]), anonymous-monomer peptides (0.54 [0.42, 0.66] → 0.69 [0.64, 0.73]) and 3–4 N-methyl groups (0.50 [0.38, 0.60] → 0.63 [0.55, 0.70]).
- Weakest strata for the chirality-aware model: length 8 (0.50 [0.31, 0.66], n = 102), length ≤5 (0.58 [0.46, 0.69], n = 193); backbone-modified (n = 24, flagged).
- **The N-methyl-count rule alone** reaches 0.25 overall within source (head-to-tail 0.28 [0.21, 0.35]) but is near zero or negative in many strata, and is **−0.33 [−0.44, −0.16] among peptides with ≥5 N-methyl groups**: inside that group, more N-methylation goes with lower within-source permeability.
- Under leave-labs-out, fingerprint models have near-zero skill (CI includes 0) on peptides with anonymous monomers (blind 0.05 [−0.06, 0.15]; chiral 0.01 [−0.08, 0.11]), on peptides with no N-methylation (−0.03 [−0.12, 0.07] chiral) and on length ≤5 (0.02 [−0.12, 0.17] blind, 0.12 [−0.05, 0.26] chiral); the descriptor model scores 0.40 [0.33, 0.47] on the anonymous-monomer stratum.
- **Leave-stratum-out** (point estimates): unseen length ≤5 0.11–0.13; unseen head-to-tail (trained on lariats only) 0.28–0.34; unseen anonymous monomers: descriptor 0.48 vs fingerprints 0.14–0.21; unseen peptoids: descriptor 0.61 vs fingerprints 0.46; year 2014–2019: chiral fingerprint 0.10 vs blind 0.24; unseen ≥3 D residues: fingerprints 0.16–0.26. **Descriptor (physicochemical) features extrapolate to unseen chemistry better than fingerprints; fingerprints are better within seen chemistry.**

## B3. Feature-family analysis
Descriptor GBM, grouped CV: all 50 features 0.665 [0.633, 0.699]; physchem alone 0.615 [0.567, 0.661]; every other family alone 0.24–0.37 (N-Me pattern 0.37, chirality 0.32, composition 0.27, ring/topology 0.24). Removing physchem costs 0.08 (→ 0.58); removing chirality costs 0.03 (→ 0.63); removing N-Me pattern, composition or ring/topology costs ≈0 (redundancy). **Permutation importance ranks differ from ablation because of that redundancy** (physchem 0.44, N-Me pattern 0.21, chirality 0.061, composition 0.041, ring/topology 0.031; N-Me information is partly duplicated by HBD/TPSA, so the model uses it when present but loses nothing when it is removed). Chirality matters more in the Kelly-lariat stratum (0.120) and peptides with ≥3 D residues (0.081) than in head-to-tail peptides (0.050).
Interaction (N-methyl × D grid): with ≥3 D residues the mean within-source z rises from −0.45 (no N-Me) to −0.23 (1–2), 0.37 (3–4) and 0.60 (≥5, n = 153, CI [0.08, 0.75], few flat groups); with no D residues the profile is flat (−0.16, 0.10, 0.09, −0.03). Additive ridge 0.22 [0.17, 0.27] → with product term 0.27 [0.21, 0.33] → GBM on the two counts 0.31 [0.25, 0.37]: the non-additive structure is real but modest.
Source confound: 34 of 50 features are flagged (pooled and within-source correlations differ in sign or by >0.15). **TPSA has pooled ρ −0.03 but within-source ρ −0.32 (15 sources); HBA 0.03 vs −0.26 (12 sources); peptide length 0.09 vs −0.28 (6 sources)**: pooling across laboratories hides the expected physical dependence. Topology class is almost a source identifier (η² ≈ 1.0 for the lariat_sc_cterm indicator).

## B4. Matched molecular pairs and activity cliffs (PAMPA, within source)
33,457 within-source pairs across 28 transformation types (all re-run after the source fix) (table). Direction is defined only for N-Me added, D flip (D minus L), D flip + N-Me swap, ring +1 residue and cross-class substitutions; for same-class substitutions, N-Me shift, decoration and cap/unknown changes only |Δ| is reported (the first version of this analysis reported signed means for those categories, which depend on arbitrary pair orientation; corrected before interpretation).
- **N-methyl added: +0.24 log Papp [0.14, 0.33]** pooled (4,166 pairs, 15 sources; pair-mean +0.32 [0.28, 0.36]); SD 0.53; heterogeneity I² = 0.93.
- **D↔L flip: mean −0.01 [−0.05, 0.02]** (7,467 pairs, 18 sources) but SD 0.52 and 19 % of pairs are within-source cliffs (|Δz| > 1): a single D flip has no consistent direction; the effect is context-dependent.
- D flip + N-Me swap: −0.21 [−0.30, −0.12] pooled (3,908 pairs, 9 sources; pair-mean −0.32). N-Me shift (one N-Me moved): mean |Δ| 0.30 [0.10, 0.49]. Cap or anonymous-monomer changes: mean |Δ| 0.62 [0.36, 0.89], with 36 % of pairs differing by >1 log unit.
- Ring +1 residue: pooled −0.14 [−0.49, 0.21] from only 5 sources (pair-mean −0.31 [−0.36, −0.26]); not interpretable as a direction. Aliphatic→polar substitution −1.01 [−1.45, −0.57] (32 pairs, 8 sources).
- **Pair ordering (pairs whose members are both held out; ties 0.5):** blind fingerprints order D-flip pairs at exactly 0.50 (they cannot distinguish them — a consistency check), chirality-aware 0.62, descriptor 0.57; N-Me added 0.72–0.74 for all models; N-Me shift is the weakest at 0.59–0.64; cap/unknown 0.77–0.79; ring +1 0.79–0.82. Cliff rates (|Δz| > 1 within source) are 19–37 % across transformation types.

## B5. Substructure enrichment with source adjustment
54 features were testable (≥10 peptides on each side, ≥3 sources with ≥5 per side; 56 before the source fix). Five pass BH 10 %: Pr_Gly peptoid residue +0.34 [0.25, 0.43] (5 sources, I² 0.00); Bn_Gly −0.27 [−0.35, −0.20] (3 sources); ≥2 N-methyl groups +0.67 [0.31, 1.04] (8 sources, I² 0.93); ≥3 N-methyl +0.48 [0.21, 0.76] (8 sources); alternating N-methyl motif +0.31 [0.08, 0.54] (11 sources). **None replicates under the leak-safe split:** mined on one source half, 0 of 8 testable features have a CI excluding 0 in the other half (sign agreement 5 of 8; median effect ratio −0.71 and +0.14), with only 3–7 sources per feature per half. Controls: permuting labels within source (5 repetitions) gave no discoveries; a planted shift of 0.4 on a random feature was recovered as 0.369 [0.287, 0.452]. **Conclusion: monomer- and substructure-level effects are source-specific in this dataset; the only direction shared by most sources is N-methyl count (75 % of sources positive for ≥2 N-methyl groups, 62 % for ≥3), with large heterogeneity.** No substructure rule is supported as transferable.

## B6. Cross-property and other data
- **Permeability across assays:** PAMPA vs Caco-2: pooled ρ −0.16 (n = 558, 17 sources) but within source +0.56 (9 sources); vs RRCK 0.66 (n = 123, 9 sources; within source 0.77, 5 sources); vs MDCK 0.69 (n = 47, 6 sources; within source 0.73, 2 sources). The five directed transformations with data in both PAMPA and Caco-2 have the same sign (n_Caco-2 = 14–63 pairs each).
- **Binding (peptide-like macrocycles, exact relations):** 22,715 rows, 12,488 compounds, 689 targets, 977 target×assay-type units. Same-target stereoisomer pairs (3,443 pairs, 210 targets) differ by mean |ΔpAff| 0.58 vs 1.15 for random same-target pairs; 20 % vs 44 % differ by >1 log unit. **N-methyl added changes binding by −0.24 pAff [−0.34, −0.14]** (934 pairs, 66 targets, 34 with ≥3 pairs; I² 0.90) — the opposite sign to its permeability effect (+0.25). This is an association across different datasets and targets, not a controlled trade-off. SMARTS panel in binding: halogen +0.36 [0.14, 0.58] (78 units, 71 % positive, I² 0.94); the other five features have CIs including 0.
- **Stability (PepMSND, n = 602 after removing label conflicts; 262 positive-class; only 94 macrocyclic, 50 positive-class):** odds ratios (cluster-robust) aromatic ring 0.46 [0.34, 0.63] (all) / 0.13 [0.04, 0.40] (macrocyclic); carboxylic acid 0.33 [0.20, 0.55] / 0.24 [0.08, 0.71]; basic amine 0.37 [0.18, 0.76] / 0.36 [0.08, 1.50]. **The polarity of the PepMSND label was not verified** (README read, no definition found), so the direction cannot be stated; exploratory only. N-methyl amide had <10 positives.
- **Cross-table overlap by exact canonical SMILES:** CycPeptMPDB × binding 46; CycPeptMPDB × stability 0; binding × stability 9. Structures carrying both a permeability and a binding label: **7 structures (84 structure–target pairs, 49 targets)** — below the registered n ≥ 30, so **no permeability–binding trade-off is claimed** (descriptive Spearman 0.27).
- **Renal (163 entries):** kidney uptake non-null in 45 / 66 / 35 entries (1 h / 4 h / 24 h), tumour uptake in 2, net charge and logD in 0 — profile only. **Conformational (MacroConf):** 69 cyclic peptides with NOE constraints, no property labels — profile only; CREMP data are not present locally.
- **Solubility: no cyclic-peptide solubility data exist in the repository; this is a data gap and nothing was inferred.**

## B7. Benchmark-domain strata (retro_recovery frozen items; read-only)
16,195 benchmark compounds: SMILES-only topology T2 gives 12,694 lariat (78 %) and 3,501 head-to-tail (22 %) — compare 33 % lariat in CycPeptMPDB; the rule is validated only on CycPeptMPDB (95.4 %), so the benchmark split is an estimate. Chemistry strata from workstream 3: ncAA peptide 13,783; non-peptide macrocycle 2,101; peptide 311. Only 17.5 % of benchmark compounds belong to a stereoisomer group of ≥2 (71 % of CycPeptMPDB structures do), so the benchmark is far less stereo-redundant. Thin strata in `items_I` positives: ≥5 N-methyl groups (1,642 positives from 2 targets in 2 families), stereo-group size >7 (8 positives); the plain-peptide stratum has 63 positive items from 10 families.

## B8. Implications
**For the LLM representation.** (1) Explicit stereochemistry tokens: chirality-aware inputs improve overall skill by ~0.04, matter most for stereoisomer-rich and Kelly-lariat strata, and are the only way to order D-flip pairs above chance (0.62 vs 0.50). (2) N-methylation as positions and counts, not a rule: its effect is context- and source-dependent (I² 0.9), saturates, and reverses within the ≥5 group. (3) An open vocabulary for anonymous/unknown monomers (16 % of peptides) — fingerprints have no skill on unseen monomers under leave-labs-out, descriptors do. (4) A global physicochemical channel (TPSA, HBD, logP), as input or auxiliary target: physchem alone carries 0.62 of 0.67, and the physical dependence appears only within source (TPSA ρ −0.32). (5) Topology tokens, taken from ground truth where it exists and from the 95 %-accurate rule elsewhere, with the confound that topology is almost a source label in CycPeptMPDB. **For evaluation and the benchmark.** Evaluate within source or leave-lab-out (skill falls from 0.67 to 0.22); report subgroup n and source concentration; treat single-lab strata as lab effects; the benchmark's thin strata above need pooling or explicit exclusion; no transferable substructure rules were found, so rule-based knowledge arms should not expect to gain from CycPeptMPDB-derived substructure rules.

## B9. Errors found in the analysis code and data while working (and how they were handled)
Composition classes assigned by prefix (Nle/Nva→polar, Et_Phe→negative) — rebuilt with core-name matching; SMILES topology rule v1 counted side-chain amides — fixed (93.7 % → 95.4 %); anonymous monomers hide N-methylation — SMILES count made authoritative; matched-pair direction undefined for several categories — switched to magnitude; enrichment replication first reported only a strict CI test — sign agreement added; stability cluster IDs are multi-valued strings ("6;10") — parsed; benchmark-strata used a pandas attribute that collided with a method and mislabelled folds as families — fixed; a control-test threshold was tighter than null sampling noise — set at 3.4 SD (not a code defect). The registered "8,466 entries" were rows (7,991 structures).

## B10. Gaps
Solubility (no data); PepMSND label polarity unverified; conformational data unused beyond profiling; binding-side substructure analysis restricted to SMARTS and two SMILES-computable transformations (no monomer tokens); leave-stratum-out has no CIs; no mixed-model sensitivity; strata dominated by single laboratories limit every topology, length-7 and year ≤2013 statement; benchmark topology split rests on a rule validated only on CycPeptMPDB; trade-off analyses limited by 7 overlapping structures.

# Tables
*All tables below are post-fix (re-run 2026-10-29/30 on corrected annotation).*

**Grouped CV by flat structure (no stereoisomer sibling in training)** — Spearman [95 % cluster-bootstrap CI] per stratum; n = peptides, g = flat-structure groups. † n<30.

| stratifier | level | n | g | fp blind | fp chiral | descriptor | N-Me rule |
|---|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 1509 | 0.67 [0.62, 0.71] | 0.72 [0.68, 0.75] | 0.68 [0.64, 0.71] | 0.28 [0.21, 0.35] |
| topology | lariat_sc_cterm | 1521 | 184 | 0.64 [0.49, 0.73] | 0.66 [0.53, 0.75] | 0.56 [0.43, 0.64] | 0.52 [0.33, 0.65] |
| topology | lariat_nterm_sc | 779 | 767 | 0.75 [0.71, 0.79] | 0.74 [0.71, 0.78] | 0.80 [0.76, 0.82] | -0.09 [-0.16, -0.02] |
| length | <=5 | 193 | 156 | 0.61 [0.48, 0.71] | 0.58 [0.46, 0.69] | 0.64 [0.51, 0.74] | 0.09 [-0.06, 0.26] |
| length | 6 | 1975 | 751 | 0.71 [0.64, 0.76] | 0.74 [0.69, 0.79] | 0.74 [0.69, 0.78] | 0.39 [0.29, 0.48] |
| length | 7 | 1904 | 182 | 0.65 [0.57, 0.70] | 0.68 [0.61, 0.73] | 0.56 [0.47, 0.64] | 0.49 [0.37, 0.57] |
| length | 8 | 102 | 100 | 0.56 [0.40, 0.71] | 0.50 [0.31, 0.66] | 0.52 [0.33, 0.68] | -0.05 [-0.28, 0.19] |
| length | >=9 | 2786 | 1271 | 0.61 [0.52, 0.69] | 0.68 [0.61, 0.73] | 0.63 [0.57, 0.69] | 0.23 [0.08, 0.35] |
| n_methyl | 0 | 916 | 321 | 0.68 [0.61, 0.73] | 0.71 [0.65, 0.76] | 0.67 [0.61, 0.73] | 0.00 [0.00, 0.00] |
| n_methyl | 1-2 | 3350 | 966 | 0.66 [0.60, 0.70] | 0.69 [0.64, 0.72] | 0.61 [0.55, 0.65] | 0.18 [0.08, 0.28] |
| n_methyl | 3-4 | 1817 | 460 | 0.50 [0.38, 0.60] | 0.63 [0.55, 0.70] | 0.55 [0.45, 0.65] | 0.03 [-0.10, 0.14] |
| n_methyl | >=5 | 877 | 713 | 0.73 [0.65, 0.79] | 0.72 [0.63, 0.78] | 0.77 [0.67, 0.83] | -0.33 [-0.44, -0.16] |
| n_D | 0 | 965 | 947 | 0.74 [0.71, 0.77] | 0.75 [0.71, 0.78] | 0.78 [0.74, 0.81] | 0.03 [-0.04, 0.09] |
| n_D | 1-2 | 3048 | 1378 | 0.69 [0.65, 0.73] | 0.73 [0.70, 0.76] | 0.70 [0.66, 0.73] | 0.23 [0.17, 0.28] |
| n_D | >=3 | 2947 | 641 | 0.63 [0.56, 0.68] | 0.68 [0.63, 0.72] | 0.59 [0.53, 0.64] | 0.39 [0.30, 0.46] |
| peptoid | yes | 2093 | 566 | 0.70 [0.63, 0.75] | 0.76 [0.72, 0.79] | 0.70 [0.64, 0.75] | 0.31 [0.21, 0.40] |
| peptoid | no | 4867 | 1894 | 0.66 [0.60, 0.70] | 0.69 [0.65, 0.73] | 0.65 [0.60, 0.69] | 0.25 [0.17, 0.32] |
| unknown_monomer | yes | 1129 | 725 | 0.54 [0.42, 0.66] | 0.69 [0.64, 0.73] | 0.69 [0.63, 0.74] | -0.01 [-0.11, 0.09] |
| unknown_monomer | no | 5831 | 1735 | 0.69 [0.65, 0.73] | 0.71 [0.68, 0.74] | 0.66 [0.62, 0.69] | 0.30 [0.24, 0.35] |
| ext_backbone | yes | 1078 | 358 | 0.70 [0.64, 0.75] | 0.73 [0.67, 0.78] | 0.72 [0.65, 0.77] | 0.42 [0.34, 0.50] |
| ext_backbone | no | 5882 | 2102 | 0.67 [0.62, 0.70] | 0.71 [0.67, 0.74] | 0.66 [0.62, 0.70] | 0.22 [0.15, 0.28] |
| backbone_mod | yes | 24† | 22 | 0.37 [-0.12, 0.69] | 0.43 [0.00, 0.72] | 0.28 [-0.23, 0.68] | 0.01 [-0.55, 0.43] |
| backbone_mod | no | 6936 | 2438 | 0.67 [0.63, 0.70] | 0.71 [0.68, 0.74] | 0.67 [0.63, 0.70] | 0.25 [0.19, 0.30] |
| ring_atoms | low(<=21) | 3487 | 1007 | 0.70 [0.65, 0.74] | 0.73 [0.69, 0.76] | 0.68 [0.64, 0.73] | 0.33 [0.25, 0.40] |
| ring_atoms | mid | 1769 | 239 | 0.64 [0.51, 0.72] | 0.67 [0.56, 0.73] | 0.60 [0.49, 0.67] | 0.47 [0.29, 0.59] |
| ring_atoms | high(>22) | 1704 | 1214 | 0.63 [0.54, 0.71] | 0.70 [0.66, 0.74] | 0.68 [0.62, 0.73] | 0.06 [-0.03, 0.14] |
| stereo_group | 1 | 2048 | 2048 | 0.70 [0.68, 0.72] | 0.70 [0.67, 0.72] | 0.75 [0.72, 0.77] | 0.02 [-0.03, 0.06] |
| stereo_group | 2-7 | 724 | 194 | 0.73 [0.67, 0.78] | 0.76 [0.71, 0.80] | 0.69 [0.62, 0.75] | 0.41 [0.31, 0.50] |
| stereo_group | >=8 | 4188 | 218 | 0.64 [0.57, 0.70] | 0.70 [0.66, 0.74] | 0.61 [0.55, 0.66] | 0.36 [0.27, 0.44] |
| source_size | <50 | 567 | 473 | 0.67 [0.60, 0.72] | 0.66 [0.59, 0.72] | 0.66 [0.59, 0.73] | 0.01 [-0.09, 0.11] |
| source_size | 50-299 | 454 | 276 | 0.35 [0.16, 0.55] | 0.61 [0.53, 0.68] | 0.59 [0.50, 0.68] | -0.03 [-0.18, 0.12] |
| source_size | >=300 | 5939 | 1712 | 0.70 [0.66, 0.73] | 0.72 [0.69, 0.75] | 0.67 [0.63, 0.70] | 0.30 [0.24, 0.36] |
| year | <=2013 | 899 | 875 | 0.72 [0.67, 0.77] | 0.73 [0.69, 0.77] | 0.77 [0.72, 0.81] | -0.04 [-0.11, 0.04] |
| year | 2014-2019 | 922 | 629 | 0.67 [0.60, 0.74] | 0.70 [0.64, 0.75] | 0.78 [0.73, 0.82] | -0.03 [-0.14, 0.09] |
| year | >=2020 | 5139 | 959 | 0.65 [0.59, 0.69] | 0.70 [0.66, 0.73] | 0.62 [0.57, 0.66] | 0.36 [0.29, 0.43] |

**Leave-labs-out (GroupKFold by source)** — Spearman [95 % cluster-bootstrap CI] per stratum; n = peptides, g = flat-structure groups. † n<30.

| stratifier | level | n | g | fp blind | fp chiral | descriptor | N-Me rule |
|---|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 1509 | 0.23 [0.17, 0.30] | 0.22 [0.15, 0.28] | 0.25 [0.19, 0.31] | – |
| topology | lariat_sc_cterm | 1521 | 184 | 0.45 [0.26, 0.58] | 0.29 [0.14, 0.43] | 0.36 [0.14, 0.53] | – |
| topology | lariat_nterm_sc | 779 | 767 | 0.21 [0.14, 0.28] | 0.31 [0.25, 0.38] | 0.47 [0.41, 0.53] | – |
| length | <=5 | 193 | 156 | 0.02 [-0.12, 0.17] | 0.12 [-0.05, 0.26] | 0.28 [0.12, 0.43] | – |
| length | 6 | 1975 | 751 | 0.34 [0.25, 0.42] | 0.30 [0.21, 0.39] | 0.40 [0.31, 0.46] | – |
| length | 7 | 1904 | 182 | 0.38 [0.26, 0.47] | 0.26 [0.15, 0.35] | 0.15 [0.03, 0.27] | – |
| length | 8 | 102 | 100 | 0.16 [-0.05, 0.37] | 0.08 [-0.14, 0.29] | 0.44 [0.28, 0.58] | – |
| length | >=9 | 2786 | 1271 | 0.28 [0.17, 0.36] | 0.22 [0.13, 0.30] | 0.28 [0.16, 0.37] | – |
| n_methyl | 0 | 916 | 321 | 0.05 [-0.10, 0.21] | -0.03 [-0.12, 0.07] | 0.08 [-0.05, 0.22] | – |
| n_methyl | 1-2 | 3350 | 966 | 0.25 [0.14, 0.36] | 0.21 [0.12, 0.30] | 0.32 [0.22, 0.42] | – |
| n_methyl | 3-4 | 1817 | 460 | 0.31 [0.19, 0.41] | 0.23 [0.11, 0.36] | 0.22 [0.13, 0.32] | – |
| n_methyl | >=5 | 877 | 713 | 0.39 [0.24, 0.48] | 0.45 [0.31, 0.54] | 0.53 [0.41, 0.57] | – |
| n_D | 0 | 965 | 947 | 0.18 [0.11, 0.24] | 0.28 [0.22, 0.34] | 0.35 [0.29, 0.40] | – |
| n_D | 1-2 | 3048 | 1378 | 0.24 [0.17, 0.30] | 0.24 [0.18, 0.30] | 0.29 [0.24, 0.35] | – |
| n_D | >=3 | 2947 | 641 | 0.25 [0.14, 0.37] | 0.21 [0.12, 0.29] | 0.24 [0.13, 0.35] | – |
| peptoid | yes | 2093 | 566 | 0.16 [0.06, 0.26] | 0.18 [0.09, 0.26] | 0.22 [0.14, 0.30] | – |
| peptoid | no | 4867 | 1894 | 0.25 [0.17, 0.33] | 0.23 [0.16, 0.29] | 0.28 [0.20, 0.34] | – |
| unknown_monomer | yes | 1129 | 725 | 0.05 [-0.06, 0.15] | 0.01 [-0.08, 0.11] | 0.40 [0.33, 0.47] | – |
| unknown_monomer | no | 5831 | 1735 | 0.26 [0.18, 0.33] | 0.26 [0.20, 0.31] | 0.23 [0.16, 0.29] | – |
| ext_backbone | yes | 1078 | 358 | 0.10 [-0.00, 0.20] | 0.16 [0.04, 0.25] | 0.00 [-0.11, 0.12] | – |
| ext_backbone | no | 5882 | 2102 | 0.26 [0.18, 0.33] | 0.23 [0.16, 0.29] | 0.30 [0.23, 0.37] | – |
| backbone_mod | yes | 24† | 22 | -0.33 [-0.74, 0.32] | 0.46 [0.05, 0.75] | 0.20 [-0.27, 0.58] | – |
| backbone_mod | no | 6936 | 2438 | 0.22 [0.16, 0.29] | 0.21 [0.15, 0.26] | 0.25 [0.19, 0.31] | – |
| ring_atoms | low(<=21) | 3487 | 1007 | 0.30 [0.22, 0.37] | 0.26 [0.18, 0.33] | 0.29 [0.21, 0.36] | – |
| ring_atoms | mid | 1769 | 239 | 0.26 [0.04, 0.44] | 0.24 [0.09, 0.38] | 0.25 [0.05, 0.43] | – |
| ring_atoms | high(>22) | 1704 | 1214 | 0.15 [0.06, 0.24] | 0.18 [0.08, 0.28] | 0.29 [0.22, 0.37] | – |
| stereo_group | 1 | 2048 | 2048 | 0.20 [0.15, 0.24] | 0.19 [0.15, 0.23] | 0.33 [0.29, 0.36] | – |
| stereo_group | 2-7 | 724 | 194 | 0.15 [0.03, 0.27] | 0.25 [0.15, 0.35] | 0.24 [0.13, 0.34] | – |
| stereo_group | >=8 | 4188 | 218 | 0.29 [0.18, 0.40] | 0.27 [0.18, 0.37] | 0.26 [0.15, 0.37] | – |
| source_size | <50 | 567 | 473 | 0.26 [0.16, 0.35] | 0.27 [0.17, 0.35] | 0.42 [0.33, 0.50] | – |
| source_size | 50-299 | 454 | 276 | 0.09 [-0.06, 0.25] | 0.04 [-0.10, 0.23] | 0.26 [0.15, 0.38] | – |
| source_size | >=300 | 5939 | 1712 | 0.23 [0.15, 0.30] | 0.23 [0.17, 0.29] | 0.24 [0.17, 0.31] | – |
| year | <=2013 | 899 | 875 | 0.25 [0.18, 0.31] | 0.33 [0.26, 0.40] | 0.46 [0.38, 0.53] | – |
| year | 2014-2019 | 922 | 629 | 0.14 [0.04, 0.25] | 0.08 [-0.02, 0.17] | 0.51 [0.43, 0.57] | – |
| year | >=2020 | 5139 | 959 | 0.28 [0.19, 0.37] | 0.28 [0.21, 0.35] | 0.26 [0.18, 0.35] | – |

**Leave-stratum-out** (train on all peptides outside the stratum, excluding flat groups that intersect it) — Spearman on the held-out stratum.

| stratifier | level | n test | n train | fp blind | fp chiral | descriptor |
|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 2300 | 0.28 | 0.30 | 0.34 |
| topology | lariat_sc_cterm | 1521 | 5439 | 0.41 | 0.31 | 0.27 |
| topology | lariat_nterm_sc | 779 | 6181 | 0.31 | 0.45 | 0.45 |
| length | <=5 | 193 | 6767 | 0.13 | 0.11 | 0.13 |
| length | 6 | 1975 | 4985 | 0.45 | 0.46 | 0.48 |
| length | 7 | 1904 | 5056 | 0.59 | 0.60 | 0.41 |
| length | 8 | 102 | 6858 | 0.35 | 0.29 | 0.48 |
| length | >=9 | 2786 | 4174 | 0.15 | 0.13 | 0.25 |
| n_D | 0 | 965 | 3312 | 0.53 | 0.54 | 0.59 |
| n_D | 1-2 | 3048 | 1207 | 0.32 | 0.37 | 0.50 |
| n_D | >=3 | 2947 | 1974 | 0.26 | 0.16 | 0.38 |
| peptoid | yes | 2093 | 4867 | 0.46 | 0.46 | 0.61 |
| unknown_monomer | yes | 1129 | 5831 | 0.21 | 0.14 | 0.48 |
| year | <=2013 | 899 | 6058 | 0.29 | 0.35 | 0.45 |
| year | 2014-2019 | 922 | 6027 | 0.24 | 0.10 | 0.41 |
| year | >=2020 | 5139 | 1820 | 0.32 | 0.27 | 0.35 |

**Matched pairs (PAMPA, within source)** — directed rows: mean Δ log Papp (random-effects pooled [95 % CI]; pair-mean [cluster-bootstrap CI]); undirected rows: mean |Δ|. I² = between-source heterogeneity.

| transformation | n pairs | sources | statistic | pooled [CI] | I² | pair mean [boot CI] | SD | share \|Δ\|>1 |
|---|---|---|---|---|---|---|---|---|
| D flip (D minus L) | 7467 | 18 | mean delta | -0.01 [-0.05, 0.02] | 0.62 | -0.01 [-0.02, 0.00] | 0.52 | 0.06 |
| substitution with D/N-Me change | 5768 | 21 | mean |delta| | 0.54 [0.43, 0.66] | 0.94 | 0.41 [0.39, 0.43] | 0.37 | 0.06 |
| N-Me added (with minus without) | 4166 | 15 | mean delta | 0.24 [0.14, 0.33] | 0.93 | 0.32 [0.28, 0.36] | 0.53 | 0.10 |
| D flip + N-Me swap ((D,nonMe) minus (L,Me)) | 3908 | 9 | mean delta | -0.21 [-0.30, -0.12] | 0.90 | -0.32 [-0.36, -0.28] | 0.55 | 0.11 |
| cap_or_unknown_change | 3625 | 17 | mean |delta| | 0.62 [0.36, 0.89] | 0.99 | 0.86 [0.83, 0.90] | 0.72 | 0.36 |
| substitution: aliphatic->aromatic | 3019 | 12 | mean delta | 0.02 [-0.12, 0.16] | 0.94 | -0.10 [-0.16, -0.05] | 0.87 | 0.19 |
| N-Me shift (one N-Me moved) | 2250 | 12 | mean |delta| | 0.30 [0.10, 0.49] | 0.99 | 0.45 [0.41, 0.47] | 0.40 | 0.08 |
| ring +1 residue (any) | 1254 | 5 | mean delta | -0.14 [-0.49, 0.21] | 0.97 | -0.31 [-0.36, -0.26] | 0.47 | 0.07 |
| substitution: aliphatic->aliphatic | 1186 | 20 | mean |delta| | 0.52 [0.41, 0.62] | 0.94 | 0.61 [0.58, 0.66] | 0.52 | 0.20 |
| substitution: aromatic->aromatic | 605 | 11 | mean |delta| | 0.40 [0.23, 0.56] | 0.97 | 0.55 [0.49, 0.60] | 0.56 | 0.18 |
| substitution: aliphatic->polar | 32 | 8 | mean delta | -1.01 [-1.45, -0.57] | 0.85 | -0.64 [-0.99, -0.21] | 0.84 | 0.44 |

**Cliffs (|Δz|>1 SD within source) and pair-ordering accuracy** (same-fold pairs = neither partner label in training; ties 0.5).

| transformation | pairs | cliff rate [CI] | same-fold pairs | acc blind | acc chiral | acc descriptor |
|---|---|---|---|---|---|---|
| D flip (D minus L) | 7467 | 0.19 [0.17, 0.21] | 7467 | 0.50 | 0.62 | 0.57 |
| substitution with D/N-Me change | 5768 | 0.26 [0.24, 0.29] | 1123 | 0.70 | 0.75 | 0.69 |
| N-Me added (with minus without) | 4166 | 0.33 [0.30, 0.37] | 806 | 0.72 | 0.73 | 0.71 |
| D flip + N-Me swap ((D,nonMe) minus (L,Me)) | 3908 | 0.36 [0.33, 0.39] | 767 | 0.72 | 0.74 | 0.70 |
| cap_or_unknown_change | 3625 | 0.37 [0.35, 0.40] | 603 | 0.78 | 0.79 | 0.77 |
| substitution: aliphatic->aromatic | 3019 | 0.34 [0.31, 0.36] | 594 | 0.71 | 0.72 | 0.66 |
| N-Me shift (one N-Me moved) | 2250 | 0.30 [0.27, 0.33] | 361 | 0.59 | 0.64 | 0.60 |
| ring +1 residue (any) | 1254 | 0.32 [0.27, 0.37] | 287 | 0.82 | 0.82 | 0.79 |
| substitution: aliphatic->aliphatic | 1186 | 0.34 [0.30, 0.38] | 234 | 0.75 | 0.77 | 0.78 |
| substitution: aromatic->aromatic | 605 | 0.26 [0.22, 0.30] | 90 | 0.65 | 0.75 | 0.74 |
| substitution: aliphatic->polar | 32 | 0.44 [0.23, 0.62] | 4 | – | – | – |

**Feature-family models** (descriptor GBM, grouped CV by flat structure).

| model | features | Spearman [CI] |
|---|---|---|
| full | 50 | 0.67 [0.63, 0.70] |
| only:physchem | 9 | 0.62 [0.57, 0.66] |
| only:ring_topology | 10 | 0.24 [0.17, 0.30] |
| only:nme_pattern | 7 | 0.37 [0.29, 0.43] |
| only:chirality | 7 | 0.32 [0.28, 0.36] |
| only:composition | 17 | 0.27 [0.20, 0.33] |
| without:physchem | 41 | 0.58 [0.54, 0.62] |
| without:ring_topology | 40 | 0.67 [0.63, 0.70] |
| without:nme_pattern | 43 | 0.67 [0.63, 0.70] |
| without:chirality | 43 | 0.63 [0.59, 0.68] |
| without:composition | 33 | 0.67 [0.63, 0.70] |

**Permutation importance by family** (drop in held-out Spearman; 30 permutations).

| family | mean drop [2.5, 97.5 %] |
|---|---|
| physchem | 0.439 [0.423, 0.454] |
| ring_topology | 0.031 [0.029, 0.035] |
| nme_pattern | 0.211 [0.200, 0.224] |
| chirality | 0.061 [0.056, 0.066] |
| composition | 0.041 [0.038, 0.045] |

**N-methyl × D-residue grid** — mean within-source z [CI] (n).

| N-Me \ D | 0 | 1-2 | >=3 |
|---|---|---|---|
| 0 | -0.16 [-0.29, -0.02] (168) | -0.35 [-0.53, -0.20] (475) | -0.45 [-0.67, -0.21] (273) |
| 1-2 | 0.10 [-0.01, 0.21] (227) | -0.04 [-0.13, 0.03] (1643) | -0.23 [-0.42, -0.08] (1480) |
| 3-4 | 0.09 [-0.05, 0.23] (157) | 0.38 [0.22, 0.55] (619) | 0.37 [0.25, 0.49] (1041) |
| >=5 | -0.03 [-0.13, 0.06] (413) | -0.02 [-0.15, 0.10] (311) | 0.60 [0.08, 0.75] (153) |

**Additive vs interaction** (grouped CV Spearman)

| model | Spearman [CI] |
|---|---|
| ridge_additive(nMe,nD) | 0.22 [0.17, 0.27] |
| ridge_with_product | 0.27 [0.21, 0.33] |
| gbm(nMe,nD) | 0.31 [0.25, 0.37] |

**Source confound** — features with highest between-source share of variance (eta²) and pooled vs within-source Spearman with raw log Papp.

| feature | eta² | pooled ρ | within-source ρ (k) | confounded |
|---|---|---|---|---|
| n_cap_n | 1.00 | -0.13 | -0.03 (2) | False |
| topo_lariat_sc_cterm | 1.00 | -0.13 | -0.03 (2) | False |
| hba | 0.90 | 0.03 | -0.26 (12) | True |
| n_monomers | 0.89 | 0.08 | -0.28 (6) | True |
| tpsa | 0.88 | -0.03 | -0.32 (15) | True |
| topo_lariat_nterm_sc | 0.87 | 0.35 | -0.22 (1) | True |
| n_cap_c | 0.87 | 0.35 | -0.22 (1) | True |
| n_residues | 0.85 | 0.07 | -0.27 (6) | True |
| mw | 0.82 | 0.11 | 0.15 (15) | False |
| heavy | 0.81 | 0.10 | 0.11 (15) | False |
| frac_polar | 0.81 | 0.11 | -0.21 (6) | True |
| tail_res | 0.80 | 0.08 | -0.19 (3) | True |
| ring_atoms_max | 0.79 | 0.09 | -0.10 (8) | True |
| frac_proline | 0.79 | -0.22 | -0.12 (9) | False |

Features flagged source-confounded: 34 of 50.

**Substructure enrichment** (within-source standardised effect, random-effects across sources; BH 10 %). Top 14 by p.

| feature | n present | sources | effect [CI] | I² | sources with + effect | q |
|---|---|---|---|---|---|---|
| has_base:Pr_Gly | 601 | 5 | 0.34 [0.25, 0.42] | 0.00 | 1.00 | 0.000 |
| has_base:Bn_Gly | 1209 | 3 | -0.27 [-0.35, -0.20] | 0.00 | 0.00 | 0.000 |
| n_Nme>=2 | 4293 | 8 | 0.67 [0.31, 1.03] | 0.93 | 0.75 | 0.005 |
| n_Nme>=3 | 2694 | 8 | 0.48 [0.21, 0.76] | 0.90 | 0.62 | 0.009 |
| motif_alternating_Nme | 2464 | 11 | 0.31 [0.08, 0.54] | 0.86 | 0.73 | 0.083 |
| has_peptoid | 2093 | 8 | 0.32 [0.06, 0.59] | 0.89 | 0.88 | 0.133 |
| has_D_base:L | 4295 | 13 | 0.31 [0.04, 0.58] | 0.89 | 0.69 | 0.133 |
| has_Nme_base:L | 5318 | 11 | 0.44 [0.06, 0.82] | 0.94 | 0.82 | 0.133 |
| arom_fraction>=0.3 | 1173 | 11 | -0.43 [-0.82, -0.05] | 0.93 | 0.18 | 0.133 |
| has_D_and_Nme_same_residue | 3493 | 12 | 0.22 [0.02, 0.42] | 0.85 | 0.58 | 0.133 |
| has_nalkyl_nonmethyl | 2206 | 8 | 0.23 [0.02, 0.43] | 0.78 | 0.88 | 0.133 |
| motif_Nme_adjacent_D | 3811 | 12 | 0.27 [0.02, 0.51] | 0.89 | 0.67 | 0.133 |
| smarts:halogen | 140 | 3 | -0.59 [-1.14, -0.05] | 0.90 | 0.00 | 0.133 |
| has_base:iBu_Gly | 113 | 4 | 0.50 [0.01, 0.99] | 0.78 | 1.00 | 0.172 |


**Source concentration of strata** (share of the stratum's peptides from its largest source).

| stratifier | level | n | sources | largest source | share | top-2 share |
|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 40 | 2020_Townsend | 0.62 | 0.76 |
| topology | lariat_sc_cterm | 1521 | 3 | 2021_Kelly | 1.00 | 1.00 |
| topology | lariat_nterm_sc | 779 | 1 | 2013_CHUGAI | 1.00 | 1.00 |
| length | <=5 | 193 | 13 | 2020_Le Roux | 0.24 | 0.46 |
| length | 6 | 1975 | 20 | 2020_Townsend | 0.52 | 0.85 |
| length | 7 | 1904 | 10 | 2020_Townsend | 0.98 | 0.98 |
| length | 8 | 102 | 5 | 2013_CHUGAI | 0.48 | 0.77 |
| length | >=9 | 2786 | 13 | 2021_Kelly | 0.55 | 0.84 |
| n_methyl | 0 | 916 | 28 | 2020_Townsend | 0.49 | 0.65 |
| n_methyl | 1-2 | 3350 | 24 | 2020_Townsend | 0.58 | 0.76 |
| n_methyl | 3-4 | 1817 | 18 | 2021_Kelly | 0.42 | 0.68 |
| n_methyl | >=5 | 877 | 11 | 2013_CHUGAI | 0.75 | 0.91 |
| n_D | 0 | 965 | 23 | 2013_CHUGAI | 0.58 | 0.73 |
| n_D | 1-2 | 3048 | 30 | 2020_Townsend | 0.48 | 0.67 |
| n_D | >=3 | 2947 | 16 | 2021_Kelly | 0.44 | 0.87 |
| peptoid | yes | 2093 | 9 | 2020_Townsend | 0.69 | 0.91 |
| peptoid | no | 4867 | 41 | 2021_Kelly | 0.31 | 0.61 |
| unknown_monomer | yes | 1129 | 20 | 2016_Furukawa | 0.45 | 0.63 |
| unknown_monomer | no | 5831 | 33 | 2020_Townsend | 0.49 | 0.75 |
| ext_backbone | yes | 1078 | 5 | 2020_Townsend | 0.77 | 0.97 |
| ext_backbone | no | 5882 | 41 | 2020_Townsend | 0.35 | 0.61 |
| backbone_mod | yes | 24 | 3 | 2015_Ahlbach | 0.50 | 0.79 |
| backbone_mod | no | 6936 | 40 | 2020_Townsend | 0.41 | 0.63 |
| ring_atoms | low(<=21) | 3487 | 29 | 2020_Townsend | 0.67 | 0.86 |
| ring_atoms | mid | 1769 | 5 | 2021_Kelly | 0.69 | 0.96 |
| ring_atoms | high(>22) | 1704 | 19 | 2013_CHUGAI | 0.49 | 0.66 |
| stereo_group | 1 | 2048 | 37 | 2013_CHUGAI | 0.42 | 0.60 |
| stereo_group | 2-7 | 724 | 20 | 2020_Townsend | 0.62 | 0.77 |
| stereo_group | >=8 | 4188 | 9 | 2020_Townsend | 0.58 | 0.88 |
| source_size | <50 | 567 | 33 | 2015_Wang | 0.09 | 0.17 |
| source_size | 50-299 | 454 | 4 | 2024_Faris | 0.46 | 0.75 |
| source_size | >=300 | 5939 | 4 | 2020_Townsend | 0.48 | 0.74 |
| year | <=2013 | 899 | 3 | 2013_CHUGAI | 0.98 | 0.99 |
| year | 2014-2019 | 922 | 17 | 2016_Furukawa | 0.72 | 0.79 |
| year | >=2020 | 5139 | 21 | 2020_Townsend | 0.56 | 0.86 |

**Benchmark-domain strata** (frozen `items_I` positives, read-only; topology by the SMILES-only rule T2).

| stratifier | level | positive items | compounds | targets | families | thin |
|---|---|---|---|---|---|---|
| topology_T2 | head_to_tail | 1211 | 1145 | 30 | 17 | False |
| topology_T2 | lariat | 6389 | 4436 | 45 | 25 | False |
| stratum | ncaa_peptide | 6573 | 4902 | 45 | 26 | False |
| stratum | non_peptide_macrocycle | 964 | 627 | 20 | 15 | False |
| stratum | peptide | 63 | 52 | 16 | 10 | False |
| n_nme | (-1, 0] | 4695 | 3143 | 45 | 25 | False |
| n_nme | (0, 2] | 1164 | 742 | 27 | 16 | False |
| n_nme | (2, 4] | 99 | 54 | 11 | 6 | False |
| n_nme | (4, 100] | 1642 | 1642 | 2 | 2 | True |
| flat_size | (0, 1] | 6720 | 4927 | 46 | 26 | False |
| flat_size | (1, 7] | 872 | 646 | 41 | 22 | False |
| flat_size | (7, 10000] | 8 | 8 | 5 | 4 | True |
