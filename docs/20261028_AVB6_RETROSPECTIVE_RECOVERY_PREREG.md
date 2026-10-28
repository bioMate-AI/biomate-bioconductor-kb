# αvβ6 retrospective recovery benchmark — pre-registration (DRAFT, 2026-10-28)

Status: **not yet run.** No αvβ6 recovery result exists today. This document fixes the question, data, baselines and decision rules before any run. Deck gate G1 ("Engine recovers published αvβ6 binders", status "In progress") refers to this study.

## 1. Question
Given no αvβ6 training signal, does the engine's selector/generator place held-out, published αvβ6 binders above matched non-binders, by more than trivial baselines?

## 2. What the data can and cannot support (measured 2026-10-28, `multitarget/integrin_chembl/data/long_all.csv.gz`)
| quantity | value |
|---|---|
| αvβ6 compounds (ChEMBL-derived, assay-filtered) | 842 from 37 documents (2002–2025) |
| of which macrocycles (largest ring ≥ 9 atoms) | 74 compounds, 8 documents; 51 from CHEMBL4411322 |
| macrocycles with exact pACT ≥ 7 | 31 compounds, 4 documents |
| macrocycles with exact pACT ≥ 8 | 5 compounds, 3 documents |
| all compounds with exact pACT ≥ 7 | 203 (172 non-macrocyclic) |

Consequences, stated in advance:
1. The ChEMBL macrocycle positives are too few and too concentrated (one document = 69 % of macrocycles) for a field-level claim. A document-clustered bootstrap over 4–8 documents will have wide intervals; a null here is **inconclusive**, not negative.
2. The ChEMBL set is dominated by small-molecule RGD mimetics, not cyclic peptides. The deck's target class (cyclic peptides / ncAA macrocycles) is under-represented in public data. This is itself the honest basis for "scarce in public data".
3. Published cyclic-peptide binders not in ChEMBL (A20FMDV2 lineage, Kapp 2017 panel of 34 ligands, Trivehexin monomer, other literature ligands) form the **external set** (E). Structures for E must be transcribed from the papers with the provenance rule already used in `multitarget/integrin_selectivity/ligands.csv`; entries without an unambiguous structure are excluded and listed.

## 3. Design
- **Held-out unit:** the source document (leave-one-document-out, LODO). Compounds from one document never appear in both fit and test sides.
- **Blind rule:** nothing trained or retrieved may contain αvβ6 compounds from the held-out document; for the external set E, from any ChEMBL αvβ6 document that reports the same compound. Retrieval indices and knowledge bases are rebuilt without them and the rebuild is logged.
- **Positives:** primary P1 = macrocycles with exact pACT ≥ 7 (n = 31, 4 documents); secondary P2 = all macrocycles in the 8 documents; external E as above.
- **Decoys:** property-matched macrocycles (heavy-atom count, ring size, ring count, charge, ±1 SD) drawn from CycPeptMPDB and from non-αvβ6 ChEMBL integrin macrocycles, 20 decoys per positive. A decoy set drawn only from non-RGD chemistry is forbidden (it would reward RGD detection); decoys must include RGD-bearing macrocycles active on other integrins.
- **Arms:** S (selector/scorer ranking of positives vs decoys, no αvβ6 fitting); G (generator, trained without αvβ6 rows, motif/scaffold recovery in top-k of N samples). Arm G requires its interface to be frozen in an amendment before running; until then only arm S is pre-registered.

## 4. Baselines (all must be computed)
B0 random (enrichment factor 1); B1 RGD-motif presence (the trivial baseline that most of the signal could reduce to); B2 size/charge-only model; B3 degree/annotation-depth null (for knowledge-graph features). The engine must beat max(B0, B1, B2, B3).

## 5. Metrics and decision rule
- Primary: enrichment factor at top 5 % (EF5) on P1, LODO-pooled; 95 % document-cluster bootstrap (B = 2000).
- Secondary: AUROC, top-1/top-10 recovery per held-out document, EF5 on E.
- **Supported** only if the lower 95 % bound of (engine EF5 − strongest baseline EF5) > 0 on P1 **and** EF5 on E is above the strongest baseline's point estimate.
- **Not supported:** upper bound ≤ 0. **Inconclusive:** otherwise (report as such; do not call it a null of the method).
- No threshold, feature set, decoy ratio or model choice may change after the first test-fold score is seen. Deviations are logged as dated amendments.

## 6. Risks and how they are reported
- Power: see §2. The number of independent documents is the effective sample size and is reported beside every interval.
- Literature leakage: the engine's language/knowledge components were trained on public text and structures that may include these binders. Contamination is checked by n-gram / Tanimoto ≥ 0.9 search of corpora against P1 and E and reported; contaminated items are reported separately.
- Decoy bias: sensitivity analysis with a second decoy source.
- This benchmark cannot show selectivity or tumour residence; those remain wet-lab gates G3 and the residence assay.

## 7. Outputs
`multitarget/integrin_chembl/retro_recovery/` : frozen positive/decoy lists with hashes, per-fold scores, `results.json`, and a result section appended here. Manuscript use: results section of the engine paper, with the §2 limitations stated.

## 8. If the result is null or inconclusive: iterate, under these rules (added 2026-10-28 at the owner's direction)
A null is a diagnosis task, not an endpoint. The engine is improved until it works, and the study is structured so that a later positive is credible:
1. **Diagnose first.** Per-document error analysis (which documents/chemotypes fail, whether failures are RGD-motif, size, or decoy artefacts) before any change. No fix without an identified cause.
2. **Version, don't overwrite.** Each engine change is a new version (v1, v2, …) with its own dated amendment; the v1 result stays in the record permanently.
3. **Tune only on development data.** Model changes are developed on the 4 LODO documents (P1) and the ChEMBL non-macrocycle αvβ6 set. The external literature set E is a **final holdout**: scored once per frozen version, and a version that is changed after seeing its E score is a new version that needs fresh held-out data (new literature ligands, or the first wet-lab round).
4. **Report the whole history**: every version tried, its P1 and E result, and the number of versions, so selection among versions is visible.
5. **Real fixes only.** Improvements must come from the engine (selector, knowledge, training data, all-atom model), not from changing decoys, thresholds or positives to fit.
6. **The decisive test is prospective.** Whatever the retrospective result, the wet-lab SPR/BLI round (gate G2/G3) is the final test of any version.

## 9. Amendment A1 (2026-10-28, owner's direction): validate across ALL known cyclic binders and targets, not αvβ6 only
Reason: §2 shows αvβ6 alone cannot support a field-level claim (31 potent macrocycles, 4 documents). The engine claims generality, so the benchmark is multi-target; αvβ6 is a pre-declared reported subset, not the whole study.
- **Data (measured 2026-10-28, `data/raw/binding_affinity/binding_affinity_v1.csv`, rows flagged cyclic_bool):** 36,102 rows, 17,911 unique cyclic compounds, 923 targets; 353 targets have ≥10 and 197 have ≥30 distinct cyclic compounds; affinity types IC50/Ki/EC50/Kd. Additional sources: display-NGS pools (5 targets with binder labels), bound-cyclic PDB complexes (`data/bound_cyclic`), the 113 post-cutoff co-folding test complexes (Stage B). **Unverified:** how `cyclic_bool` was assigned (true cyclic peptides vs small-molecule macrocycles); it must be audited and the compound class stratified (peptide / ncAA peptide / non-peptide macrocycle) before the lists are frozen.
- **Held-out unit:** target family (UniProt-cluster / Pfam), with source document as a second grouping; no target family appears in both fit and test for any fitted component. Zero-fit scorers (S1) are checked for corpus contamination only.
- **Positives:** per target, cyclic compounds with measured affinity ≤ 1 µM. **Decoys:** (a) measured inactives on the same target (> 10 µM), where they exist — the strongest decoys; (b) property-matched cyclic binders of other targets (tests target-specificity, not just "looks like a cyclic binder").
- **Metrics:** per-target EF5 and AUROC, aggregated across targets with a target-cluster bootstrap (B = 2000); targets with < 5 positives or < 20 decoys are excluded by rule and listed. Same decision rule as §5, applied to the pooled and per-target-family results; αvβ6 and each display target reported separately.
- **Extra baselines:** nearest-neighbour Tanimoto to training binders of *other* targets (memorisation of chemotype), and size/charge only. The engine must beat these to claim target-specific recovery.
- **Known prior:** earlier cross-target results in this program were negative for cyclic peptides (state of the art 3–8 %), so a null here is plausible and is handled under §8.

### A1 audit result (2026-10-28, before any scoring)
`cyclic_bool` audit (RDKit, largest ring and backbone-amide count): of 17,911 unique flagged compounds, 17,422 have a ring ≥ 9 atoms and 17,120 are peptide-like (≥ 3 `C(=O)N[CX4]` amides); 489 have ring < 9 and are excluded. Median size is 80 heavy atoms, so the flag marks genuine peptide macrocycles, not small-molecule rings. Study set: **17,120 compounds, 851 targets** (340 targets with ≥ 10 compounds, 186 with ≥ 30). Under the §9 rules: 351 targets have ≥ 5 positives (≤ 1 µM); only **30 targets have ≥ 20 measured-inactive (> 10 µM) same-target decoys** (101 with ≥ 5). Consequence: the strongest decoy type (same-target measured inactives) is available for a minority of targets; the full multi-target analysis therefore relies on cross-target property-matched decoys, and the same-target-inactive subset (30 targets) is reported as a separate, stricter analysis. Compound class stratification by ncAA content is still to be done before freezing.

## 10. Amendment A2 (2026-10-28, BEFORE any scorer was run) — frozen study set and rules
Code: `research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/` (`01_fetch_pfam.py`, `chem.py`, `02_build_set.py`, `test_chem.py`, `data/`). All numbers below are from `data/build_log.json`.
**Rules fixed here.** Compounds: cyclic_bool rows, largest ring ≥ 9, ≥ 3 backbone amides (`C(=O)N[CX4]`), largest fragment, 16,195 compounds / 14,599 flat structures (stereoisomers collapse: 1.11 isomers per flat structure). Affinity hygiene: 12 rows excluded (≤0 or >1e9 nM = unit/parse errors); 1,533 rows with null target dropped; relations handled per pair (below); assay types are mixed (IC50 19,098 / Ki 7,576 / EC50 4,439 / Kd 1,758 rows) — primary analysis pools them as A1 specified; a Ki/Kd-only sensitivity is pre-declared. Pair label per (compound, target): '=' rows → median; ≤ 1 µM positive, > 10 µM inactive, between = unlabeled (gray); no '=' rows → '<'/'<=' ≤ 1 µM positive, '>'/'>=' ≥ 10 µM inactive, else gray; conflicting '=' rows (min ≤ 1 µM and max > 10 µM) dropped (26). Result: 20,562 positive, 4,021 inactive pairs; 5,701 gray; 26 conflicts; 95 (target, flat structure) groups have opposite labels among stereoisomers.
**Strata** (heuristic, `chem.classify`): peptide / ncaa_peptide / non_peptide_macrocycle (< 4 α-amino-acid units — this also contains short ncAA macrocycles). Validated against HELM-derived truth on all 7,967 CycPeptMPDB structures: ncAA recall 98.3 % (7,831/7,970; 124 short ncAA macrocycles labelled non-peptide, 15 backbone-modified peptides (thio-ester variants) missed as peptide), 21/21 true canonical peptides recovered. Validation found and fixed four classifier defects before freezing (peptoid N-alkyl, D-Pro, β-amino-acid backbone, N-methyl only). Study table: 13,783 ncaa_peptide, 2,101 non-peptide, 311 peptide. The 'peptide' stratum is small and its precision on this dataset is uncertain; analyses by stratum report counts.
**Target families.** Targets = sorted UniProt accession set per row; Pfam from UniProt REST (fetched 2026-10-28, `data/uniprot_fetch.json`; 912 accessions, 0 missing; one malformed accession string 'Q15116 P01857' split on whitespace). Family = connected components of targets linked when Jaccard(Pfam sets) ≥ 0.67; targets without Pfam are singletons: 317 families over 793 targets (largest 130 = class-A GPCR-like). An earlier rule (link on any shared non-promiscuous Pfam) chained 356/793 targets into one family and made decoy matching impossible for them; it was rejected before any scoring.
**Eligibility (deviation from A1, stricter):** a target needs ≥ 5 positives with DISTINCT flat structures (A1 said ≥ 5 positives): 344 targets (348 under the A1 count), 141 families. Same-target-inactive analysis I: ≥ 20 flat-distinct inactives and ≥ 5 flat-distinct positives: 46 targets, 26 families. **Class balance in I is positive-heavy (median 62 positives vs 33 inactives per target), so AUROC is primary for I and EF5 is secondary.**
**Decoys (analysis M).** Up to 20 per positive from compounds that are positive on a target in a different family, never positive on a target of this family, not sharing a flat structure with any of this target's positives; matched on stratum, heavy atoms (±max(3,10 %)), approximate charge (±1), ring-size bin; seed 20261028. Positives with < 10 matched decoys were dropped: **9,784 of 17,922 flat-distinct positives in eligible targets (55 %)**; kept vs dropped have similar median size (83 vs 81 heavy atoms) but the dropped have a heavier tail (90th percentile 237 vs 148 heavy atoms) and are enriched for the canonical-peptide stratum (2.6 % vs 0.4 %). Final M: 299 targets, 120 families, 8,033 positives, 165,516 items. I: 46 targets, 26 families, 7,600 positives, 9,432 items. RGD fraction: M positives 2.8 % vs decoys 3.3 %; I positives 1.8 % vs decoys 3.4 % (no RGD shortcut by construction).
**Frozen files (SHA-256).**
| file | sha256 |
|---|---|
| `compounds.csv.gz` | `27c8ba7b23725d928b03f394d794713ae2c8fd0d3523493a25f0904ac80ea8a5` |
| `pair_labels.csv.gz` | `15a2c89c6864edfad3e374fa21aec17cfb807c178bff35a78acc7ecae53fe437` |
| `targets.csv` | `18302dfcbbf75cd30aa4262ec478a1af67a5363f0ad8add948ca1ac9b519acf1` |
| `items_M.csv.gz` | `bd8aa90e500b395dfbdcaef46dac9c50329c518b62b1737ea0bf4f3b8e996138` |
| `items_I.csv.gz` | `5da885424abe6cdeddff3b422524ce93bc617bb9ec7116965241feaedaae601e` |
| `uniprot_pfam.tsv` | `2bb209aa2bb79c65eb468c913a164654a8217b2f0a3dcad765a5071128d55668` |
| `02_build_set.py` | `3224de10d1e1485d765c7c5cadca61c23421c81e7c6ff9fe01f64fdcdf5d531c` |
| `chem.py` | `237a18a92f878ccfc287ff2de33f546b7faf6149e676e1c21e0599e6abaa4480` |
Nothing in this study has been scored at the time of this amendment.

## 11. Amendment A3 (2026-10-28, BEFORE any scorer was run) — arms, baselines, BioMate component audit, contamination
Written in response to the owner's instruction that the study must use BioMate's chained workflow and knowledge sources, not only hand-written rules. Code: `retro_recovery/harness.py` (+ `test_harness.py`: planted-signal, shuffled-label, constant, anti-signal and tie-handling controls, 6 pass), `retro_recovery/chem.py` (12 tests pass).

### 11.1 Audit of the existing components (read-only; what each can and cannot do for this study)
| component | what it is | usable here? | decision |
|---|---|---|---|
| `target_kb/*.json` + `experience_kb.all_entries(target)` | provenance-tiered KB for **17 targets**; only avb6 and pdl1 carry example binders (avb6: 3 actives + 2 controls + 4 non-actives; pdl1: 1 active, 3 non-actives); `_target_class()` returns None for any target without a KB spec | maps onto ≈ 15 of 344 eligible targets (ITGB6 ×2, ITGA4 ×3, C5 ×4, FCGRT, IL23 ×2, CD274 ×2, TNF); only **integrin-MIDAS** (RGD) gives a computable gate; the `ppi-groove` etc. class rules are textual (need a pose) | S1b-KB arm on KB-mapped targets; reported with its coverage; **contaminated** (below) |
| `medchem_kb.py`, `medchem_kb_product.py`, `medchem_kb_ingested_large.json`, `admet_tdc_ingested.json` | general liability (RDKit FilterCatalog), physchem, modality rules, ingested summaries | target-agnostic developability, not binding; ingested JSONs contain no structures (0 SMILES-like strings) → no compound-level contamination | not a binding scorer; not run; liability flags can be reported as covariates only |
| `rule_induction.induce` | greedy conjunction over HELM predicates hard-wired to αvβ6 (RGD, D-Pro, N-Me-Lys…), requires a predicate true for **all** actives (few-shot design) | the learner is reusable if `predicates` is swapped for SMILES-derived predicates; with many actives it returns an empty rule, so it is used in its designed few-shot regime (k = 5 actives vs 5 non-actives, 100 resamples) | S1b-induction arm, analysis I only (in M the decoys are binders, so there are no non-actives to induce against) |
| `acceptance_gate.avb6_gate`, `pharmacophore_knowledge.py`, `knowledge_liability_flags.py` | HELM/sequence gates for αvβ6 (H1–H8), pharmacophore presence, liability flags | HELM input; our table is SMILES without monomer sequences; RGD (H1) can be evaluated on SMILES; H2–H5 (RGDL, turn, flanks, Lys handle) cannot without sequences | RGD only (S1a); H2–H8 documented as not applicable |
| `score.py`, `scorer_config.py` | cheap tier (rules, FTO, developability) + hooks for MM-GBSA ΔG, selectivity gap; `config_for(target)` derives metal/cofactor needs from the KB | the expensive tier needs a prepared receptor per target; only αvβ6 (9xmm, Mn ×3) is prepared | S2 only for αvβ6 |
| chain `loop.py`/`loop_batch.py` → `physics_dispatch`/`physics_batch` (Boltz-2 cofold, MM-GBSA) → `execution_grader` | proposes HELM candidates, dispatches Batch spot jobs, grades by execution contract (`complex.cif`, `mmgbsa_result.json`) | the loop is built for HELM candidates; `smiles_cofold_adapter.py` exists for SMILES input; measured Boltz-2 cost 3.5 / 18 / 43 min per complex at 250 / 621 / 1,069 tokens (GB10, `20261026_INTEGRATED_PROGRAM_PLAN`) | **S2 cost estimate only; not executed** (below) |
| `rule_conditioned_generator.py`, `neural_generator.py` | generators (αvβ6 only: `gen_avb6`) | generate, do not score | not applicable to a retrospective scoring study |
| BioMate workflow DB (`workflows` table, 4,2xx workflows) | docking/affinity workflows present: *Run Diffdock With Smiles*, *Docking Autodock Vina*, *OpenFE RBFE*, *boltz*, *boltz_structure_prediction*, *Predict Binding Affinity Protein 1D Sequence*, *Qsar Rf Model*, *cyclic_peptide_design*, *fda_protein_ligand_affinity*; among 34 name matches `real_exec_status` is ok = 2, exec_error = 4, unrecorded = 28 | all need a receptor structure or per-target training data (QSAR) → outside the family-holdout design for 299 targets | listed; not run |
| multi-source data layer (60+ sources, 3 silos) | public sources | the study table already merges BindingDB + ChEMBL; other sources not wired here | bypassed |

### 11.2 Arms (all fixed now)
Baselines (all must be computed; direction fixed a priori; both directions reported for the two memorisation-type baselines): B0 random (seeded); B1 RGD indicator (+), heavy atoms (+/−), |charge| (+/−); B3 nearest-neighbour Tanimoto (Morgan r=2, 2,048 bits, chirality on; max over positives of **other-family** targets, excluding any reference with the same flat structure as the item) (+ and −); B4 annotation depth = number of distinct targets (excluding the evaluated target) on which the compound has any labelled pair (+ and −). Because M decoys are binders of other targets by construction, B3(+) and B4(+) are expected to rank decoys above positives; B3(−)/B4(−) are the correct controls for that design artefact and the **strongest baseline is chosen over all of them** (conservative).
Arms: **S1a** rules only (RGD for integrin targets = genes ITG*; constant otherwise: reported as not applicable, EF = 1, AUROC = 0.5). **S1b-KB** knowledge-base path: `experience_kb.all_entries(kb_key)` resolved for KB-mapped targets; gate = RGD when a pharmacophore entry requires RGD; constant otherwise; provenance of resolved entries logged. **S1b-leaky** (diagnostic only, never a claim): max Tanimoto to the KB's own actives/controls for that target, to measure how much contaminated knowledge would inflate recovery. **S1b-induction** (analysis I only): 100 resamples of `rule_induction.induce` on 5 actives + 5 non-actives drawn only from targets of OTHER families (never the held-out family), SMILES predicates {RGD, D-residue, N-substituted, ≥1/≥2 aromatic rings, charge ≥ 1 / ≤ 0, ring ≥ 15, heavy ≥ 80, ncAA stratum}; score = fraction of resampled rules satisfied. **S2** chain-executed Boltz-2 co-fold + MM-GBSA on a prespecified αvβ6 subset (10 positives + 50 matched decoys, seeded): **estimate only** (§11.4). **S3** plug-in scores from workstream 1 (v4 / atom-LM) through `harness.py`; scored on all items AND on the contamination-controlled subset (compound absent from the model's pretraining corpus).
Subsets reported for every arm: all analyses M and I; αvβ6 targets (genes ITGB6); integrin targets; by stratum (peptide / ncAA / other); Ki/Kd-only sensitivity (positives retained only if a Ki or Kd measurement exists). Decision rule: §5 (lower 95 % family-cluster-bootstrap bound of arm − strongest baseline > 0 for AUROC, and same for EF5 in M); AUROC primary for I (positive-heavy).

### 11.3 Contamination (measured before scoring; `data/contamination_corpora.json`)
1. **KB examples**: avebehexin `cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])` (in avb6.json actives AND controls) is **in the frozen set** (identical isomeric SMILES, 8 labelled pairs on ITGB6/ITGAV-ITGB6/ITGB-type targets); the other two avb6 actives (Y-/W-variants) are not. Any KB-fed arm on ITGB6 is contaminated by construction.
2. **Atom-LM pretraining corpus** (ChEMBL-37, 2,878,245 SMILES): **2,972 of 5,123 (58 %) M-positive compounds and 2,514 of 5,581 (45 %) I-positive compounds are present with identical canonical SMILES** (3,138/5,123 at flat-structure level for the >60-character subset). Any S3 model pretrained on it has seen these molecules (without labels); results must be reported on the contamination-controlled subset and on all items, side by side.
3. **CycPeptMPDB** (training data of the v4 / HELM LMs): 42 item compounds identical, 69 flat-identical (negligible).
4. `medchem_kb_ingested_large.json`, `admet_tdc_ingested.json`: no structures → none.

### 11.4 S2 cost estimate (not run; prices are ASSUMED, not measured)
αvβ6 is the only target with a prepared receptor + Mn configuration (`scorer_config`: 3 Mn at the β6 I-like MIDAS/ADMIDAS/SyMBS). Receptor assemblies of this size are ≈ 1,000+ tokens (the 1,069-token class measured 43 min per fold on the GB10). 60 compounds × ~40 min ≈ 40 GPU-hours for co-folding alone (spot g6/g5-class at an assumed 0.4–1.0 USD/h ≈ 16–40 USD) plus MM-GBSA per pose; with the 9,000-line chain adapted for SMILES input (`smiles_cofold_adapter.py`) untested for this panel. Expected information: one target, 10 positives → cannot support a field-level claim; it would test whether the physics tier ranks known αvβ6 binders above matched decoys. Decision: **not executed in this pass**; execute only on the owner's approval of the cost.
