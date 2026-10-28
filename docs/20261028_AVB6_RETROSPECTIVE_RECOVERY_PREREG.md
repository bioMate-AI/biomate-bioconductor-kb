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
