# Cyclic-peptide structural stratification, feature and substructure analysis (2026-10-29)

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
(a) The mixed-model sensitivity analysis (A6) was not run. (b) Leave-stratum-out results have point estimates only (no bootstrap CI). (c) Permutation importance within strata was done for four stratifiers (topology, length, D bins, N-methyl bins), not all. (d) Ring-size change by one residue (A5f) was implemented for head-to-tail peptides only. (e) Cross-assay and binding SMARTS-panel results carry no multiplicity control (6 tests; exploratory). (f) The standalone importance and stratum-metric controls (`importance.py`, `test_controls.py`) test the same algorithms as the inlined code in `feat_analysis.py` / `strat_perf.py`; their equivalence is not machine-checked. (g) Length uses `n_monomers` (HELM monomers including caps). (h) The registered "8,466 entries" are rows; there are 7,991 unique structures and 6,960 with a PAMPA label (the loader set).

## B1. Annotation and its audit
Unique structures: 7,991 (HELM topology: head-to-tail 5,369; side-chain-to-C-terminus lariat 1,524; N-terminus-to-side-chain lariat 1,098; **no disulfide, stapled or bicyclic peptides occur**, so those strata are empty). Labelled (PAMPA) set: 6,960 peptides, 45 sources (15 with ≥30 peptides), 2,460 flat structures, years 2006–2024; Townsend alone is 41.4 % of peptides. Raw log Papp has mean −5.75, SD 0.79; **27.7 % of its variance is between sources.**
Prevalence among the 6,960: peptoid (N-substituted glycine) 30.1 %; anonymous `MonoNN` monomer 16.2 % (3.0 % of residues); β/γ/ω extended backbone 15.5 %; N-terminal cap 21.8 %; C-terminal cap 11.2 %; D-Pro 56.6 %; side-chain-modified residue 6.8 %; N→O backbone modification 0.3 % (n = 24); α,α-disubstituted 0.1 % (n = 6). Token coverage of the composition classes: 96.5 % of residues (3.0 % unknown, 0.4 % unclassified).
Audit (independent SMILES-derived quantities; `audit_annotation.json`): **D-residue count from tokens equals the CIP-derived count of R backbone α-carbons in 5,166 of 5,166 peptides (100 %)** (excluding peptides with extended-backbone, anonymous, backbone-modified or Cys-type residues). N-methyl count from tokens equals the SMARTS count in 6,404 of 6,684 peptides (95.8 %); among the 5,656 peptides with no anonymous monomer the agreement is 99.89 %, and 274 of the 280 mismatches contain an anonymous monomer — i.e. anonymous monomers hide N-methylation, so the SMILES-derived count (`n_nme_final`) is used as authoritative. HELM topology agrees with `Molecule_Shape` in 7,990 of 7,991 structures. **SMILES-only topology rule T2** (needed where HELM is absent, e.g. the benchmark): overall 95.4 %, head-to-tail recall 93.1 % (5,000/5,369), lariat recall 99.9 %; most of the 369 head-to-tail misses (321) carry side-chain-modified residues such as Asp-piperidide, where the ring is closed through the Asp side chain (examples inspected). The first version of the rule scored 93.7 % overall and 90.6 % head-to-tail recall because side-chain amides were counted as outside-ring backbone amides.

## B2. Stratified baseline performance
Overall Spearman (within-source z labels): grouped CV by flat structure — fingerprint GBM blind 0.67, chirality-aware 0.71, descriptor GBM 0.67; random 5-fold 0.71 / 0.76 / 0.73; **leave-labs-out (grouped by source) 0.31 / 0.30 / 0.26**. Skill roughly halves when the test laboratory is unseen.
**Source-concentration caveat (read before any stratum result).** Several strata are essentially one laboratory: `lariat_sc_cterm` is 99.8 % 2021_Kelly (3 sources); `lariat_nterm_sc` 81 % 2013_CHUGAI (3 sources); length 7 is 97.6 % 2020_Townsend; year ≤2013 is 97.4 % 2013_CHUGAI; `ext_backbone` 77 % and `peptoid` 69 % Townsend. Results for those strata are results for those laboratories' series.
Readings (n and CIs in the tables; Spearman, grouped CV by flat structure unless stated):
- Chirality-aware fingerprints are at least as good as blind ones in almost every stratum; the largest gains are source size 50–299 (0.38 [0.24, 0.54] → 0.64 [0.57, 0.69]), anonymous-monomer peptides (0.53 [0.41, 0.65] → 0.69 [0.64, 0.73]) and 3–4 N-methyl groups (0.50 [0.39, 0.61] → 0.62 [0.55, 0.70]).
- Weakest strata for the chirality-aware model: length 8 (0.52 [0.34, 0.67], n = 102), length ≤5 (0.55 [0.40, 0.66], n = 193); backbone-modified (n = 24, flagged).
- **The N-methyl-count rule alone** reaches 0.25 overall within source (head-to-tail 0.29 [0.21, 0.35]) but is near zero or negative in many strata, and is **−0.30 [−0.41, −0.12] among peptides with ≥5 N-methyl groups**: inside that group, more N-methylation goes with lower within-source permeability.
- Under leave-labs-out, fingerprint models have near-zero skill (CI includes 0) on peptides with anonymous monomers (blind 0.07 [−0.04, 0.16]; chiral 0.02 [−0.08, 0.12]), on peptides with no N-methylation (−0.05 [−0.15, 0.06] chiral) and on length ≤5 (0.11–0.12); the descriptor model scores 0.37 [0.29, 0.44] on the anonymous-monomer stratum.
- **Leave-stratum-out** (point estimates): unseen length ≤5 0.06–0.17; unseen head-to-tail (trained on lariats only) 0.28–0.38; unseen anonymous monomers: descriptor 0.49 vs fingerprints 0.14–0.23; unseen peptoids: descriptor 0.61 vs fingerprints 0.43–0.45; year 2014–2019: chiral fingerprint 0.07 vs blind 0.27. **Descriptor (physicochemical) features extrapolate to unseen chemistry better than fingerprints; fingerprints are better within seen chemistry.**

## B3. Feature-family analysis
Descriptor GBM, grouped CV: all 50 features 0.67 [0.63, 0.70]; physchem alone 0.61 [0.57, 0.65]; every other family alone 0.23–0.36 (N-Me pattern 0.36, chirality 0.31, composition 0.26, ring/topology 0.23). Removing physchem costs 0.10 (→ 0.57); removing chirality costs 0.03 (→ 0.63); removing N-Me pattern, composition or ring/topology costs ≈0 (redundancy). **Permutation importance ranks differ from ablation because of that redundancy** (physchem 0.44, N-Me pattern 0.22, chirality 0.06, composition 0.035, ring/topology 0.032; N-Me information is partly duplicated by HBD/TPSA, so the model uses it when present but loses nothing when it is removed). Chirality matters more in the Kelly-lariat stratum (0.125) and peptides with ≥3 D residues (0.081) than in head-to-tail peptides (0.049).
Interaction (N-methyl × D grid): with ≥3 D residues the mean within-source z rises from −0.45 (no N-Me) to −0.23 (1–2), 0.37 (3–4) and 0.60 (≥5, n = 153, CI [0.08, 0.75], few flat groups); with no D residues the profile is flat (−0.17, 0.09, 0.11, −0.01). Additive ridge 0.23 [0.17, 0.27] → with product term 0.27 [0.21, 0.33] → GBM on the two counts 0.31 [0.25, 0.37]: the non-additive structure is real but modest.
Source confound: 29 of 50 features are flagged (pooled and within-source correlations differ in sign or by >0.15). **TPSA has pooled ρ −0.03 but within-source ρ −0.31 (15 sources); HBA 0.03 vs −0.25; peptide length 0.08 vs −0.27**: pooling across laboratories hides the expected physical dependence. Topology class is almost a source identifier (η² ≈ 1.0 for the lariat_sc_cterm indicator).

## B4. Matched molecular pairs and activity cliffs (PAMPA, within source)
33,398 within-source pairs across 28 transformation types (table). Direction is defined only for N-Me added, D flip (D minus L), D flip + N-Me swap, ring +1 residue and cross-class substitutions; for same-class substitutions, N-Me shift, decoration and cap/unknown changes only |Δ| is reported (the first version of this analysis reported signed means for those categories, which depend on arbitrary pair orientation; corrected before interpretation).
- **N-methyl added: +0.25 log Papp [0.16, 0.34]** pooled (4,156 pairs, 16 sources; pair-mean +0.32 [0.28, 0.36]); SD 0.53; heterogeneity I² = 0.90.
- **D↔L flip: mean −0.01 [−0.05, 0.02]** (7,451 pairs, 19 sources) but SD 0.52 and 19 % of pairs are within-source cliffs (|Δz| > 1): a single D flip has no consistent direction; the effect is context-dependent.
- D flip + N-Me swap: −0.18 [−0.28, −0.08] pooled (3,905 pairs, 9 sources; pair-mean −0.32). N-Me shift (one N-Me moved): mean |Δ| 0.29 [0.12, 0.46]. Cap or anonymous-monomer changes: mean |Δ| 0.61 [0.34, 0.88], with 36 % of pairs differing by >1 log unit.
- Ring +1 residue: pooled −0.14 [−0.49, 0.21] from only 5 sources (pair-mean −0.31 [−0.36, −0.26]); not interpretable as a direction. Aliphatic→polar substitution −1.01 [−1.45, −0.57] (31 pairs, 8 sources).
- **Pair ordering (pairs whose members are both held out; ties 0.5):** blind fingerprints order D-flip pairs at exactly 0.50 (they cannot distinguish them — a consistency check), chirality-aware 0.62, descriptor 0.56; N-Me added 0.71–0.72 for all models; N-Me shift is the weakest at 0.58–0.60; cap/unknown 0.76–0.81; ring +1 0.79–0.81. Cliff rates (|Δz| > 1 within source) are 19–37 % across transformation types.

## B5. Substructure enrichment with source adjustment
56 features were testable (≥10 peptides on each side, ≥3 sources with ≥5 per side). Five pass BH 10 %: Pr_Gly peptoid residue +0.34 [0.25, 0.42] (5 sources, I² 0.00); Bn_Gly −0.27 [−0.35, −0.20] (3 sources); ≥2 N-methyl groups +0.70 [0.34, 1.07] (8 sources, I² 0.93); ≥3 N-methyl +0.50 [0.24, 0.77]; alternating N-methyl motif +0.31 [0.09, 0.52] (12 sources). **None replicates under the leak-safe split:** mined on one source half, 0 of 11 testable features have a CI excluding 0 in the other half (sign agreement 7 of 11; median effect ratio −0.34 and +0.15), with only 3–7 sources per feature per half. Controls: permuting labels within source (5 repetitions) gave one repetition with one discovery (q = 0.024; expected under FDR 10 %); a planted shift of 0.4 on a random feature was recovered as 0.365 [0.282, 0.448]. **Conclusion: monomer- and substructure-level effects are source-specific in this dataset; the only direction shared by most sources is N-methyl count (75 % of sources positive), with large heterogeneity.** No substructure rule is supported as transferable.

## B6. Cross-property and other data
- **Permeability across assays:** PAMPA vs Caco-2: pooled ρ −0.16 (n = 558, 22 sources) but within source +0.56 (10 sources); vs RRCK 0.66 (n = 123; within source 0.79, 4 sources); vs MDCK 0.69 (n = 47; within source 0.73, 2 sources). The five directed transformations with data in both PAMPA and Caco-2 have the same sign (n_Caco-2 = 13–53 pairs each).
- **Binding (peptide-like macrocycles, exact relations):** 22,715 rows, 12,488 compounds, 689 targets, 977 target×assay-type units. Same-target stereoisomer pairs (3,443 pairs, 210 targets) differ by mean |ΔpAff| 0.58 vs 1.15 for random same-target pairs; 20 % vs 44 % differ by >1 log unit. **N-methyl added changes binding by −0.24 pAff [−0.34, −0.14]** (934 pairs, 66 targets, 34 with ≥3 pairs; I² 0.90) — the opposite sign to its permeability effect (+0.25). This is an association across different datasets and targets, not a controlled trade-off. SMARTS panel in binding: halogen +0.36 [0.14, 0.58] (78 units, 71 % positive, I² 0.94); the other five features have CIs including 0.
- **Stability (PepMSND, n = 602 after removing label conflicts; 262 positive-class; only 94 macrocyclic, 50 positive-class):** odds ratios (cluster-robust) aromatic ring 0.46 [0.34, 0.63] (all) / 0.13 [0.04, 0.40] (macrocyclic); carboxylic acid 0.33 [0.20, 0.55] / 0.24 [0.08, 0.71]; basic amine 0.37 [0.18, 0.76] / 0.36 [0.08, 1.50]. **The polarity of the PepMSND label was not verified** (README read, no definition found), so the direction cannot be stated; exploratory only. N-methyl amide had <10 positives.
- **Cross-table overlap by exact canonical SMILES:** CycPeptMPDB × binding 46; CycPeptMPDB × stability 0; binding × stability 9. Structures carrying both a permeability and a binding label: **7 structures (84 structure–target pairs, 49 targets)** — below the registered n ≥ 30, so **no permeability–binding trade-off is claimed** (descriptive Spearman 0.27).
- **Renal (163 entries):** kidney uptake non-null in 45 / 66 / 35 entries (1 h / 4 h / 24 h), tumour uptake in 2, net charge and logD in 0 — profile only. **Conformational (MacroConf):** 69 cyclic peptides with NOE constraints, no property labels — profile only; CREMP data are not present locally.
- **Solubility: no cyclic-peptide solubility data exist in the repository; this is a data gap and nothing was inferred.**

## B7. Benchmark-domain strata (retro_recovery frozen items; read-only)
16,195 benchmark compounds: SMILES-only topology T2 gives 12,694 lariat (78 %) and 3,501 head-to-tail (22 %) — compare 33 % lariat in CycPeptMPDB; the rule is validated only on CycPeptMPDB (95.4 %), so the benchmark split is an estimate. Chemistry strata from workstream 3: ncAA peptide 13,783; non-peptide macrocycle 2,101; peptide 311. Only 17.5 % of benchmark compounds belong to a stereoisomer group of ≥2 (71 % of CycPeptMPDB structures do), so the benchmark is far less stereo-redundant. Thin strata in `items_I` positives: ≥5 N-methyl groups (1,642 positives from 2 targets in 2 families), stereo-group size >7 (8 positives); the plain-peptide stratum has 63 positive items from 10 families.

## B8. Implications
**For the LLM representation.** (1) Explicit stereochemistry tokens: chirality-aware inputs improve overall skill by ~0.04, matter most for stereoisomer-rich and Kelly-lariat strata, and are the only way to order D-flip pairs above chance (0.62 vs 0.50). (2) N-methylation as positions and counts, not a rule: its effect is context- and source-dependent (I² 0.9), saturates, and reverses within the ≥5 group. (3) An open vocabulary for anonymous/unknown monomers (16 % of peptides) — fingerprints have no skill on unseen monomers under leave-labs-out, descriptors do. (4) A global physicochemical channel (TPSA, HBD, logP), as input or auxiliary target: physchem alone carries 0.61 of 0.67, and the physical dependence appears only within source (TPSA ρ −0.31). (5) Topology tokens, taken from ground truth where it exists and from the 95 %-accurate rule elsewhere, with the confound that topology is almost a source label in CycPeptMPDB. **For evaluation and the benchmark.** Evaluate within source or leave-lab-out (skill falls from 0.67 to 0.3); report subgroup n and source concentration; treat single-lab strata as lab effects; the benchmark's thin strata above need pooling or explicit exclusion; no transferable substructure rules were found, so rule-based knowledge arms should not expect to gain from CycPeptMPDB-derived substructure rules.

## B9. Errors found in the analysis code and data while working (and how they were handled)
Composition classes assigned by prefix (Nle/Nva→polar, Et_Phe→negative) — rebuilt with core-name matching; SMILES topology rule v1 counted side-chain amides — fixed (93.7 % → 95.4 %); anonymous monomers hide N-methylation — SMILES count made authoritative; matched-pair direction undefined for several categories — switched to magnitude; enrichment replication first reported only a strict CI test — sign agreement added; stability cluster IDs are multi-valued strings ("6;10") — parsed; benchmark-strata used a pandas attribute that collided with a method and mislabelled folds as families — fixed; a control-test threshold was tighter than null sampling noise — set at 3.4 SD (not a code defect). The registered "8,466 entries" were rows (7,991 structures).

## B10. Gaps
Solubility (no data); PepMSND label polarity unverified; conformational data unused beyond profiling; binding-side substructure analysis restricted to SMARTS and two SMILES-computable transformations (no monomer tokens); leave-stratum-out has no CIs; no mixed-model sensitivity; strata dominated by single laboratories limit every topology, length-7 and year ≤2013 statement; benchmark topology split rests on a rule validated only on CycPeptMPDB; trade-off analyses limited by 7 overlapping structures.

# Tables

**Grouped CV by flat structure (no stereoisomer sibling in training)** — Spearman [95 % cluster-bootstrap CI] per stratum; n = peptides, g = flat-structure groups. † n<30.

| stratifier | level | n | g | fp blind | fp chiral | descriptor | N-Me rule |
|---|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 1509 | 0.66 [0.62, 0.70] | 0.72 [0.69, 0.75] | 0.68 [0.64, 0.72] | 0.29 [0.21, 0.35] |
| topology | lariat_sc_cterm | 1521 | 184 | 0.64 [0.50, 0.73] | 0.65 [0.52, 0.74] | 0.56 [0.44, 0.65] | 0.52 [0.33, 0.65] |
| topology | lariat_nterm_sc | 779 | 767 | 0.71 [0.66, 0.75] | 0.72 [0.68, 0.76] | 0.76 [0.73, 0.80] | -0.05 [-0.12, 0.02] |
| length | <=5 | 193 | 156 | 0.57 [0.44, 0.68] | 0.55 [0.40, 0.66] | 0.63 [0.51, 0.73] | 0.11 [-0.05, 0.27] |
| length | 6 | 1975 | 751 | 0.71 [0.66, 0.76] | 0.74 [0.69, 0.79] | 0.74 [0.69, 0.78] | 0.39 [0.29, 0.49] |
| length | 7 | 1904 | 182 | 0.64 [0.56, 0.70] | 0.68 [0.61, 0.73] | 0.57 [0.48, 0.65] | 0.49 [0.37, 0.57] |
| length | 8 | 102 | 100 | 0.50 [0.32, 0.66] | 0.52 [0.34, 0.67] | 0.57 [0.40, 0.71] | -0.04 [-0.27, 0.20] |
| length | >=9 | 2786 | 1271 | 0.61 [0.52, 0.69] | 0.67 [0.61, 0.73] | 0.63 [0.57, 0.68] | 0.23 [0.09, 0.35] |
| n_methyl | 0 | 916 | 321 | 0.67 [0.60, 0.73] | 0.71 [0.65, 0.76] | 0.67 [0.60, 0.73] | 0.00 [0.00, 0.00] |
| n_methyl | 1-2 | 3350 | 966 | 0.66 [0.60, 0.70] | 0.69 [0.64, 0.72] | 0.61 [0.55, 0.66] | 0.18 [0.08, 0.28] |
| n_methyl | 3-4 | 1817 | 460 | 0.50 [0.39, 0.61] | 0.62 [0.55, 0.70] | 0.56 [0.45, 0.65] | 0.03 [-0.10, 0.14] |
| n_methyl | >=5 | 877 | 713 | 0.70 [0.63, 0.76] | 0.70 [0.58, 0.77] | 0.75 [0.66, 0.81] | -0.30 [-0.41, -0.12] |
| n_D | 0 | 965 | 947 | 0.73 [0.69, 0.76] | 0.74 [0.71, 0.77] | 0.77 [0.74, 0.80] | 0.04 [-0.02, 0.11] |
| n_D | 1-2 | 3048 | 1378 | 0.68 [0.64, 0.72] | 0.73 [0.70, 0.76] | 0.70 [0.66, 0.73] | 0.23 [0.18, 0.29] |
| n_D | >=3 | 2947 | 641 | 0.62 [0.56, 0.68] | 0.68 [0.62, 0.72] | 0.60 [0.53, 0.64] | 0.39 [0.30, 0.46] |
| peptoid | yes | 2093 | 566 | 0.70 [0.63, 0.75] | 0.76 [0.72, 0.79] | 0.71 [0.65, 0.76] | 0.31 [0.21, 0.40] |
| peptoid | no | 4867 | 1894 | 0.65 [0.60, 0.70] | 0.69 [0.65, 0.72] | 0.64 [0.60, 0.68] | 0.26 [0.18, 0.32] |
| unknown_monomer | yes | 1129 | 725 | 0.53 [0.41, 0.65] | 0.69 [0.64, 0.73] | 0.69 [0.63, 0.75] | 0.00 [-0.10, 0.10] |
| unknown_monomer | no | 5831 | 1735 | 0.69 [0.65, 0.72] | 0.71 [0.68, 0.74] | 0.66 [0.62, 0.69] | 0.30 [0.24, 0.36] |
| ext_backbone | yes | 1078 | 358 | 0.71 [0.64, 0.75] | 0.72 [0.66, 0.77] | 0.71 [0.64, 0.76] | 0.42 [0.34, 0.49] |
| ext_backbone | no | 5882 | 2102 | 0.66 [0.62, 0.70] | 0.71 [0.67, 0.74] | 0.66 [0.62, 0.70] | 0.22 [0.15, 0.29] |
| backbone_mod | yes | 24† | 22 | 0.30 [-0.14, 0.64] | 0.48 [-0.00, 0.76] | 0.36 [-0.19, 0.70] | 0.03 [-0.50, 0.45] |
| backbone_mod | no | 6936 | 2438 | 0.67 [0.63, 0.70] | 0.71 [0.68, 0.73] | 0.67 [0.63, 0.70] | 0.25 [0.19, 0.30] |
| ring_atoms | low(<=21) | 3487 | 1007 | 0.70 [0.65, 0.73] | 0.73 [0.69, 0.76] | 0.69 [0.64, 0.73] | 0.34 [0.25, 0.41] |
| ring_atoms | mid | 1769 | 239 | 0.64 [0.51, 0.72] | 0.66 [0.55, 0.73] | 0.59 [0.49, 0.67] | 0.48 [0.30, 0.59] |
| ring_atoms | high(>22) | 1704 | 1214 | 0.62 [0.53, 0.70] | 0.70 [0.66, 0.74] | 0.68 [0.62, 0.72] | 0.07 [-0.02, 0.14] |
| stereo_group | 1 | 2048 | 2048 | 0.68 [0.66, 0.71] | 0.69 [0.67, 0.72] | 0.74 [0.71, 0.76] | 0.03 [-0.01, 0.07] |
| stereo_group | 2-7 | 724 | 194 | 0.72 [0.66, 0.77] | 0.76 [0.72, 0.80] | 0.69 [0.62, 0.74] | 0.41 [0.31, 0.50] |
| stereo_group | >=8 | 4188 | 218 | 0.64 [0.57, 0.70] | 0.70 [0.65, 0.74] | 0.62 [0.56, 0.67] | 0.36 [0.27, 0.44] |
| source_size | <50 | 571 | 481 | 0.66 [0.59, 0.72] | 0.66 [0.59, 0.72] | 0.66 [0.60, 0.72] | 0.04 [-0.07, 0.13] |
| source_size | 50-299 | 609 | 429 | 0.38 [0.24, 0.54] | 0.64 [0.57, 0.69] | 0.62 [0.53, 0.69] | 0.02 [-0.08, 0.11] |
| source_size | >=300 | 5780 | 1558 | 0.70 [0.65, 0.73] | 0.72 [0.68, 0.75] | 0.67 [0.63, 0.71] | 0.32 [0.25, 0.37] |
| year | <=2013 | 738 | 721 | 0.74 [0.69, 0.78] | 0.75 [0.71, 0.79] | 0.78 [0.73, 0.82] | -0.04 [-0.12, 0.04] |
| year | 2014-2019 | 930 | 635 | 0.68 [0.61, 0.74] | 0.70 [0.64, 0.75] | 0.78 [0.74, 0.82] | -0.01 [-0.12, 0.11] |
| year | >=2020 | 5292 | 1110 | 0.65 [0.59, 0.69] | 0.70 [0.66, 0.73] | 0.62 [0.58, 0.66] | 0.35 [0.29, 0.41] |

**Leave-labs-out (GroupKFold by source)** — Spearman [95 % cluster-bootstrap CI] per stratum; n = peptides, g = flat-structure groups. † n<30.

| stratifier | level | n | g | fp blind | fp chiral | descriptor | N-Me rule |
|---|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 1509 | 0.29 [0.23, 0.35] | 0.25 [0.18, 0.31] | 0.28 [0.22, 0.34] | – |
| topology | lariat_sc_cterm | 1521 | 184 | 0.47 [0.28, 0.59] | 0.44 [0.28, 0.57] | 0.22 [-0.02, 0.45] | – |
| topology | lariat_nterm_sc | 779 | 767 | 0.38 [0.32, 0.44] | 0.40 [0.34, 0.45] | 0.46 [0.40, 0.52] | – |
| length | <=5 | 193 | 156 | 0.12 [-0.03, 0.26] | 0.11 [-0.04, 0.25] | 0.27 [0.12, 0.42] | – |
| length | 6 | 1975 | 751 | 0.42 [0.34, 0.49] | 0.37 [0.28, 0.44] | 0.42 [0.34, 0.49] | – |
| length | 7 | 1904 | 182 | 0.47 [0.36, 0.55] | 0.34 [0.23, 0.43] | 0.19 [0.08, 0.30] | – |
| length | 8 | 102 | 100 | 0.22 [0.01, 0.42] | 0.24 [0.05, 0.45] | 0.46 [0.29, 0.60] | – |
| length | >=9 | 2786 | 1271 | 0.35 [0.25, 0.43] | 0.35 [0.26, 0.43] | 0.31 [0.20, 0.42] | – |
| n_methyl | 0 | 916 | 321 | 0.09 [-0.05, 0.25] | -0.05 [-0.15, 0.06] | 0.06 [-0.06, 0.18] | – |
| n_methyl | 1-2 | 3350 | 966 | 0.27 [0.18, 0.36] | 0.25 [0.16, 0.35] | 0.31 [0.22, 0.41] | – |
| n_methyl | 3-4 | 1817 | 460 | 0.33 [0.24, 0.41] | 0.26 [0.17, 0.34] | 0.23 [0.11, 0.36] | – |
| n_methyl | >=5 | 877 | 713 | 0.48 [0.40, 0.52] | 0.48 [0.38, 0.53] | 0.46 [0.36, 0.52] | – |
| n_D | 0 | 965 | 947 | 0.28 [0.22, 0.34] | 0.33 [0.26, 0.38] | 0.38 [0.32, 0.43] | – |
| n_D | 1-2 | 3048 | 1378 | 0.32 [0.27, 0.38] | 0.30 [0.24, 0.35] | 0.32 [0.26, 0.38] | – |
| n_D | >=3 | 2947 | 641 | 0.33 [0.23, 0.41] | 0.33 [0.23, 0.41] | 0.19 [0.08, 0.31] | – |
| peptoid | yes | 2093 | 566 | 0.24 [0.14, 0.34] | 0.22 [0.13, 0.30] | 0.20 [0.12, 0.27] | – |
| peptoid | no | 4867 | 1894 | 0.35 [0.27, 0.41] | 0.33 [0.26, 0.39] | 0.31 [0.23, 0.39] | – |
| unknown_monomer | yes | 1129 | 725 | 0.07 [-0.04, 0.16] | 0.02 [-0.08, 0.12] | 0.37 [0.29, 0.44] | – |
| unknown_monomer | no | 5831 | 1735 | 0.38 [0.31, 0.43] | 0.36 [0.30, 0.42] | 0.25 [0.18, 0.33] | – |
| ext_backbone | yes | 1078 | 358 | 0.34 [0.24, 0.43] | 0.34 [0.24, 0.42] | 0.09 [-0.01, 0.19] | – |
| ext_backbone | no | 5882 | 2102 | 0.32 [0.25, 0.38] | 0.30 [0.23, 0.36] | 0.30 [0.23, 0.38] | – |
| backbone_mod | yes | 24† | 22 | 0.07 [-0.36, 0.46] | 0.18 [-0.28, 0.57] | 0.45 [-0.03, 0.72] | – |
| backbone_mod | no | 6936 | 2438 | 0.32 [0.25, 0.37] | 0.30 [0.24, 0.35] | 0.26 [0.20, 0.33] | – |
| ring_atoms | low(<=21) | 3487 | 1007 | 0.34 [0.27, 0.41] | 0.29 [0.21, 0.36] | 0.32 [0.24, 0.39] | – |
| ring_atoms | mid | 1769 | 239 | 0.38 [0.18, 0.51] | 0.41 [0.24, 0.52] | 0.09 [-0.12, 0.31] | – |
| ring_atoms | high(>22) | 1704 | 1214 | 0.27 [0.20, 0.34] | 0.28 [0.21, 0.35] | 0.38 [0.32, 0.44] | – |
| stereo_group | 1 | 2048 | 2048 | 0.24 [0.20, 0.28] | 0.23 [0.19, 0.27] | 0.40 [0.36, 0.44] | – |
| stereo_group | 2-7 | 724 | 194 | 0.29 [0.16, 0.39] | 0.30 [0.20, 0.41] | 0.15 [0.03, 0.27] | – |
| stereo_group | >=8 | 4188 | 218 | 0.39 [0.30, 0.47] | 0.38 [0.29, 0.47] | 0.25 [0.13, 0.36] | – |
| source_size | <50 | 571 | 481 | 0.25 [0.14, 0.35] | 0.23 [0.13, 0.32] | 0.39 [0.30, 0.47] | – |
| source_size | 50-299 | 609 | 429 | 0.12 [0.02, 0.24] | 0.10 [0.01, 0.23] | 0.34 [0.25, 0.43] | – |
| source_size | >=300 | 5780 | 1558 | 0.36 [0.30, 0.42] | 0.35 [0.28, 0.41] | 0.25 [0.17, 0.33] | – |
| year | <=2013 | 738 | 721 | 0.38 [0.31, 0.45] | 0.41 [0.35, 0.48] | 0.46 [0.39, 0.53] | – |
| year | 2014-2019 | 930 | 635 | 0.26 [0.14, 0.35] | 0.21 [0.11, 0.31] | 0.44 [0.37, 0.52] | – |
| year | >=2020 | 5292 | 1110 | 0.35 [0.28, 0.42] | 0.34 [0.28, 0.41] | 0.24 [0.15, 0.33] | – |

**Leave-stratum-out** (train on all peptides outside the stratum, excluding flat groups that intersect it) — Spearman on the held-out stratum.

| stratifier | level | n test | n train | fp blind | fp chiral | descriptor |
|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 2300 | 0.33 | 0.28 | 0.38 |
| topology | lariat_sc_cterm | 1521 | 5439 | 0.45 | 0.39 | 0.22 |
| topology | lariat_nterm_sc | 779 | 6181 | 0.29 | 0.43 | 0.42 |
| length | <=5 | 193 | 6767 | 0.11 | 0.06 | 0.17 |
| length | 6 | 1975 | 4985 | 0.48 | 0.39 | 0.45 |
| length | 7 | 1904 | 5056 | 0.61 | 0.59 | 0.40 |
| length | 8 | 102 | 6858 | 0.29 | 0.29 | 0.51 |
| length | >=9 | 2786 | 4174 | 0.17 | 0.21 | 0.26 |
| n_D | 0 | 965 | 3312 | 0.52 | 0.54 | 0.57 |
| n_D | 1-2 | 3048 | 1207 | 0.33 | 0.36 | 0.45 |
| n_D | >=3 | 2947 | 1974 | 0.40 | 0.33 | 0.40 |
| peptoid | yes | 2093 | 4867 | 0.43 | 0.45 | 0.61 |
| unknown_monomer | yes | 1129 | 5831 | 0.23 | 0.14 | 0.49 |
| year | <=2013 | 738 | 6213 | 0.35 | 0.43 | 0.42 |
| year | 2014-2019 | 930 | 6021 | 0.27 | 0.07 | 0.36 |
| year | >=2020 | 5292 | 1665 | 0.29 | 0.32 | 0.33 |

**Matched pairs (PAMPA, within source)** — directed rows: mean Δ log Papp (random-effects pooled [95 % CI]; pair-mean [cluster-bootstrap CI]); undirected rows: mean |Δ|. I² = between-source heterogeneity.

| transformation | n pairs | sources | statistic | pooled [CI] | I² | pair mean [boot CI] | SD | share \|Δ\|>1 |
|---|---|---|---|---|---|---|---|---|
| D flip (D minus L) | 7451 | 19 | mean delta | -0.01 [-0.05, 0.02] | 0.60 | -0.01 [-0.02, 0.00] | 0.52 | 0.06 |
| substitution with D/N-Me change | 5755 | 23 | mean |delta| | 0.53 [0.42, 0.63] | 0.93 | 0.41 [0.39, 0.43] | 0.37 | 0.06 |
| N-Me added (with minus without) | 4156 | 16 | mean delta | 0.25 [0.16, 0.34] | 0.90 | 0.32 [0.28, 0.36] | 0.53 | 0.10 |
| D flip + N-Me swap ((D,nonMe) minus (L,Me)) | 3905 | 9 | mean delta | -0.18 [-0.28, -0.08] | 0.93 | -0.32 [-0.35, -0.28] | 0.55 | 0.11 |
| cap_or_unknown_change | 3621 | 17 | mean |delta| | 0.61 [0.34, 0.88] | 1.00 | 0.86 [0.83, 0.90] | 0.72 | 0.36 |
| substitution: aliphatic->aromatic | 3019 | 13 | mean delta | 0.02 [-0.13, 0.16] | 0.94 | -0.10 [-0.16, -0.05] | 0.87 | 0.19 |
| N-Me shift (one N-Me moved) | 2252 | 13 | mean |delta| | 0.29 [0.12, 0.46] | 0.99 | 0.45 [0.41, 0.47] | 0.40 | 0.08 |
| ring +1 residue (any) | 1254 | 5 | mean delta | -0.14 [-0.49, 0.21] | 0.97 | -0.31 [-0.36, -0.26] | 0.47 | 0.07 |
| substitution: aliphatic->aliphatic | 1177 | 21 | mean |delta| | 0.50 [0.40, 0.60] | 0.94 | 0.62 [0.58, 0.66] | 0.52 | 0.21 |
| substitution: aromatic->aromatic | 604 | 12 | mean |delta| | 0.37 [0.22, 0.51] | 0.96 | 0.55 [0.50, 0.60] | 0.56 | 0.18 |
| substitution: aliphatic->polar | 31 | 8 | mean delta | -1.01 [-1.45, -0.57] | 0.85 | -0.66 [-0.98, -0.19] | 0.84 | 0.45 |

**Cliffs (|Δz|>1 SD within source) and pair-ordering accuracy** (same-fold pairs = neither partner label in training; ties 0.5).

| transformation | pairs | cliff rate [CI] | same-fold pairs | acc blind | acc chiral | acc descriptor |
|---|---|---|---|---|---|---|
| D flip (D minus L) | 7451 | 0.19 [0.17, 0.21] | 7451 | 0.50 | 0.62 | 0.56 |
| substitution with D/N-Me change | 5755 | 0.27 [0.25, 0.29] | 1120 | 0.70 | 0.75 | 0.69 |
| N-Me added (with minus without) | 4156 | 0.33 [0.29, 0.37] | 804 | 0.72 | 0.71 | 0.69 |
| D flip + N-Me swap ((D,nonMe) minus (L,Me)) | 3905 | 0.36 [0.32, 0.39] | 767 | 0.73 | 0.71 | 0.70 |
| cap_or_unknown_change | 3621 | 0.37 [0.35, 0.39] | 601 | 0.81 | 0.79 | 0.76 |
| substitution: aliphatic->aromatic | 3019 | 0.34 [0.31, 0.36] | 594 | 0.71 | 0.74 | 0.68 |
| N-Me shift (one N-Me moved) | 2252 | 0.30 [0.27, 0.34] | 361 | 0.58 | 0.60 | 0.56 |
| ring +1 residue (any) | 1254 | 0.32 [0.27, 0.37] | 287 | 0.81 | 0.80 | 0.79 |
| substitution: aliphatic->aliphatic | 1177 | 0.34 [0.31, 0.38] | 234 | 0.77 | 0.76 | 0.77 |
| substitution: aromatic->aromatic | 604 | 0.26 [0.22, 0.30] | 89 | 0.65 | 0.69 | 0.75 |
| substitution: aliphatic->polar | 31 | 0.45 [0.26, 0.61] | 4 | – | – | – |

**Feature-family models** (descriptor GBM, grouped CV by flat structure).

| model | features | Spearman [CI] |
|---|---|---|
| full | 50 | 0.67 [0.63, 0.70] |
| only:physchem | 9 | 0.61 [0.57, 0.65] |
| only:ring_topology | 10 | 0.23 [0.16, 0.30] |
| only:nme_pattern | 7 | 0.36 [0.28, 0.43] |
| only:chirality | 7 | 0.31 [0.27, 0.35] |
| only:composition | 17 | 0.26 [0.19, 0.32] |
| without:physchem | 41 | 0.57 [0.53, 0.61] |
| without:ring_topology | 40 | 0.67 [0.64, 0.70] |
| without:nme_pattern | 43 | 0.66 [0.63, 0.70] |
| without:chirality | 43 | 0.63 [0.59, 0.68] |
| without:composition | 33 | 0.66 [0.62, 0.69] |

**Permutation importance by family** (drop in held-out Spearman; 30 permutations).

| family | mean drop [2.5, 97.5 %] |
|---|---|
| physchem | 0.440 [0.423, 0.455] |
| ring_topology | 0.032 [0.028, 0.036] |
| nme_pattern | 0.220 [0.207, 0.234] |
| chirality | 0.060 [0.055, 0.066] |
| composition | 0.035 [0.032, 0.039] |

**N-methyl × D-residue grid** — mean within-source z [CI] (n).

| N-Me \ D | 0 | 1-2 | >=3 |
|---|---|---|---|
| 0 | -0.17 [-0.30, -0.03] (168) | -0.36 [-0.53, -0.20] (475) | -0.45 [-0.67, -0.22] (273) |
| 1-2 | 0.09 [-0.02, 0.20] (227) | -0.04 [-0.13, 0.03] (1643) | -0.23 [-0.42, -0.08] (1480) |
| 3-4 | 0.11 [-0.03, 0.25] (157) | 0.38 [0.22, 0.54] (619) | 0.37 [0.25, 0.49] (1041) |
| >=5 | -0.01 [-0.11, 0.09] (413) | -0.03 [-0.16, 0.10] (311) | 0.60 [0.08, 0.75] (153) |

**Additive vs interaction** (grouped CV Spearman)

| model | Spearman [CI] |
|---|---|
| ridge_additive(nMe,nD) | 0.23 [0.17, 0.27] |
| ridge_with_product | 0.27 [0.21, 0.33] |
| gbm(nMe,nD) | 0.31 [0.25, 0.37] |

**Source confound** — features with highest between-source share of variance (eta²) and pooled vs within-source Spearman with raw log Papp.

| feature | eta² | pooled ρ | within-source ρ (k) | confounded |
|---|---|---|---|---|
| n_cap_n | 1.00 | -0.13 | -0.03 (1) | False |
| topo_lariat_sc_cterm | 1.00 | -0.13 | -0.03 (1) | False |
| hba | 0.90 | 0.03 | -0.25 (12) | True |
| n_monomers | 0.89 | 0.08 | -0.27 (6) | True |
| tpsa | 0.88 | -0.03 | -0.31 (15) | True |
| topo_lariat_nterm_sc | 0.87 | 0.35 | -0.23 (2) | True |
| n_cap_c | 0.87 | 0.35 | -0.23 (2) | True |
| n_residues | 0.85 | 0.07 | -0.26 (6) | True |
| mw | 0.82 | 0.11 | 0.15 (15) | False |
| heavy | 0.81 | 0.10 | 0.11 (15) | False |
| tail_res | 0.81 | 0.08 | -0.22 (3) | True |
| frac_polar | 0.81 | 0.11 | -0.08 (6) | True |
| ring_atoms_max | 0.79 | 0.09 | -0.10 (8) | True |
| frac_proline | 0.79 | -0.22 | -0.10 (9) | False |

Features flagged source-confounded: 29 of 50.

**Substructure enrichment** (within-source standardised effect, random-effects across sources; BH 10 %). Top 14 by p.

| feature | n present | sources | effect [CI] | I² | sources with + effect | q |
|---|---|---|---|---|---|---|
| has_base:Pr_Gly | 601 | 5 | 0.34 [0.25, 0.42] | 0.00 | 0.80 | 0.000 |
| has_base:Bn_Gly | 1209 | 3 | -0.27 [-0.35, -0.20] | 0.00 | 0.00 | 0.000 |
| n_Nme>=2 | 4293 | 8 | 0.70 [0.34, 1.07] | 0.93 | 0.75 | 0.003 |
| n_Nme>=3 | 2694 | 9 | 0.50 [0.24, 0.77] | 0.89 | 0.67 | 0.003 |
| motif_alternating_Nme | 2464 | 12 | 0.31 [0.09, 0.52] | 0.85 | 0.75 | 0.054 |
| has_Nme_base:L | 5318 | 12 | 0.47 [0.10, 0.83] | 0.93 | 0.83 | 0.121 |
| has_peptoid | 2093 | 8 | 0.31 [0.04, 0.58] | 0.89 | 0.75 | 0.144 |
| has_nalkyl_nonmethyl | 2206 | 9 | 0.23 [0.02, 0.43] | 0.75 | 0.89 | 0.144 |
| smarts:halogen | 140 | 3 | -0.57 [-1.07, -0.06] | 0.88 | 0.00 | 0.144 |
| smarts:basic_aliphatic_amine | 165 | 3 | -0.51 [-0.97, -0.05] | 0.37 | 0.00 | 0.144 |
| arom_fraction>=0.3 | 1173 | 11 | -0.42 [-0.80, -0.04] | 0.92 | 0.18 | 0.144 |
| has_base:V | 629 | 5 | -0.27 [-0.51, -0.02] | 0.52 | 0.00 | 0.144 |
| has_base:T | 2375 | 7 | -0.52 [-1.02, -0.03] | 0.69 | 0.14 | 0.163 |
| has_D_base:L | 4295 | 12 | 0.28 [0.01, 0.55] | 0.89 | 0.67 | 0.166 |


**Source concentration of strata** (share of the stratum's peptides from its largest source; a stratum dominated by one laboratory cannot be separated from that laboratory's effect).

| stratifier | level | n | sources | largest source | share | top-2 share |
|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 44 | 2020_Townsend | 0.62 | 0.76 |
| topology | lariat_sc_cterm | 1521 | 3 | 2021_Kelly | 1.00 | 1.00 |
| topology | lariat_nterm_sc | 779 | 3 | 2013_CHUGAI | 0.81 | 0.99 |
| length | <=5 | 193 | 13 | 2020_Le Roux | 0.24 | 0.46 |
| length | 6 | 1975 | 22 | 2020_Townsend | 0.52 | 0.85 |
| length | 7 | 1904 | 10 | 2020_Townsend | 0.98 | 0.98 |
| length | 8 | 102 | 5 | 2013_CHUGAI | 0.48 | 0.77 |
| length | >=9 | 2786 | 16 | 2021_Kelly | 0.55 | 0.79 |
| n_methyl | 0 | 916 | 29 | 2020_Townsend | 0.49 | 0.65 |
| n_methyl | 1-2 | 3350 | 25 | 2020_Townsend | 0.58 | 0.76 |
| n_methyl | 3-4 | 1817 | 20 | 2021_Kelly | 0.42 | 0.68 |
| n_methyl | >=5 | 877 | 13 | 2013_CHUGAI | 0.61 | 0.77 |
| n_D | 0 | 965 | 25 | 2013_CHUGAI | 0.48 | 0.63 |
| n_D | 1-2 | 3048 | 32 | 2020_Townsend | 0.48 | 0.67 |
| n_D | >=3 | 2947 | 18 | 2021_Kelly | 0.44 | 0.87 |
| peptoid | yes | 2093 | 10 | 2020_Townsend | 0.69 | 0.91 |
| peptoid | no | 4867 | 45 | 2021_Kelly | 0.31 | 0.61 |
| unknown_monomer | yes | 1129 | 22 | 2016_Furukawa | 0.45 | 0.63 |
| unknown_monomer | no | 5831 | 38 | 2020_Townsend | 0.49 | 0.75 |
| ext_backbone | yes | 1078 | 7 | 2020_Townsend | 0.77 | 0.93 |
| ext_backbone | no | 5882 | 45 | 2020_Townsend | 0.35 | 0.61 |
| backbone_mod | yes | 24 | 3 | 2015_Ahlbach | 0.50 | 0.79 |
| backbone_mod | no | 6936 | 44 | 2020_Townsend | 0.41 | 0.63 |
| ring_atoms | low(<=21) | 3487 | 29 | 2020_Townsend | 0.67 | 0.86 |
| ring_atoms | mid | 1769 | 5 | 2021_Kelly | 0.69 | 0.96 |
| ring_atoms | high(>22) | 1704 | 22 | 2013_CHUGAI | 0.39 | 0.57 |
| stereo_group | 1 | 2048 | 40 | 2013_CHUGAI | 0.34 | 0.53 |
| stereo_group | 2-7 | 724 | 24 | 2020_Townsend | 0.62 | 0.77 |
| stereo_group | >=8 | 4188 | 11 | 2020_Townsend | 0.58 | 0.88 |
| source_size | <50 | 571 | 36 | 2015_Wang | 0.08 | 0.17 |
| source_size | 50-299 | 609 | 5 | 2024_Faris | 0.34 | 0.59 |
| source_size | >=300 | 5780 | 4 | 2020_Townsend | 0.50 | 0.76 |
| year | <=2013 | 738 | 3 | 2013_CHUGAI | 0.97 | 0.99 |
| year | 2014-2019 | 930 | 20 | 2016_Furukawa | 0.71 | 0.79 |
| year | >=2020 | 5292 | 22 | 2020_Townsend | 0.54 | 0.83 |

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
