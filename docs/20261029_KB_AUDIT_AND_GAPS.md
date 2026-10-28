# Knowledge-base audit and gap analysis (2026-10-29)

Scope: the cyclic-peptide / BioMate knowledge bases under `research/guangzhou_all_atom/cyclic_llm/` (read-only), audited for the loop-improves-the-LLM study. Code and results: `research/guangzhou_all_atom/cyclic_llm/kb_audit/`. Rules followed: audit first, positive controls before any verdict, no tuning, IP content (`fto_kb`, FTO entries) not audited or edited per owner instruction. "Verified" below means only what a named check shows.

## 1. Inventory and verdicts
| KB | content (counted) | provenance | consumed? | verdict |
|---|---|---|---|---|
| `experience_kb.py` + `target_kb/*.json` (16 targets) | 151 per-target entry instances = 73 distinct statements: 20 config, 37 active knowledge (16 pharmacophore, 4 metal, 5 physchem, 4 eval_rule, 3 modality, 3 sar, 1 cmc, 1 liability), 16 candidate (FTO: quarantined, "unverifiable") | every active entry carries a citation and `verified=True` (self-asserted); `tier` T1/T2 | yes (loop_batch, methodology_close, register_experience_kb) | well-structured; **thin**: the 16 per-target pharmacophore entries are only 2 distinct statements (RGD-integrin/MIDAS for 4 integrin targets; one generic "PPI hot-spot" sentence for 12 others, including PD-L1) |
| `medchem_kb.py` | liability (RDKit FilterCatalog, 1,585 alerts, ingested), metal 7 elements (one shared citation set), modality 4 statements (cyclic peptide 3, stapled 1), pharmacophore class 5, physchem 5 | cited | yes (via experience_kb, radiopharm_kb) | good for small-molecule liability; peptide-relevant content = 4 modality statements |
| `medchem_kb_product.py` | 45 entries (ADMET 13, physchem 12, modality 10, pharmacophore class 10) | cited | **no non-test consumer found: DEAD** | small-molecule oriented; 11 entries duplicate `medchem_kb` (4 physchem, 5 pharmacophore class, 2 modality) |
| `medchem_kb_ingested_large.json` | summary counts only: RDKit descriptors 210, ChEMBL target classes 905, mechanisms 7,561, approved drugs 4,225 | source named | consumer not traced | no peptide-specific content; not usable as a rule base as stored |
| `pharmacophore_knowledge.py` / `acceptance_gate.py` / `rule_induction.py` | αvβ6 (and PD-L1) hard gates H1–H8; **9 αvβ6-specific predicates** (RGD, RGDL, D-Pro turn, N-methyl, handle, aromatic flanks, head-to-tail); induced rules for 2 targets | literature-grounded | yes (acceptance_gate 11 consumers) | correct for αvβ6; **not general** |
| `knowledge_liability_flags.py` | sequence CMC motifs (NG/NS/NH/NA deamidation, DG/DS isomerisation, Met/Trp oxidation, odd Cys), αvβ6 SAR (pan-RGD, RGDL, lock, renal charge), PD-L1 SAR | cited | yes | canonical-residue and sequence-motif level; not ncAA/stereo/topology aware |
| `peptide_availability.py` | 3-coefficient OLS fit on linear SH3/PDZ peptides (leave-one-domain-out ρ 0.40) | data cited | yes (score.py) | not validated for cyclic/ncAA peptides |
| `admet_tdc_ingested.json` | index of 38 public small-molecule datasets (incl. AqSolDB solubility, PAMPA) | named | — | **no cyclic-peptide data** |
| `fto_kb` | 1 patent | — | — | not audited (IP) |

## 2. Citation check (independent, Crossref)
57 bibliographic citations from `medchem_kb`, `medchem_kb_product` and `experience_kb` checked by author/journal/year/volume/page (`kb_audit/verify_citations.py`, `_pass2.py`, `citation_check.json`): **54 confirmed as real records with the cited triple**, **3 flagged**: Bagal et al. 2013, Nat Rev Drug Discov 12:35 (ion channels) — not found, likely a mis-citation (that title is a J Med Chem paper); Di et al. 2013, Drug Metab Dispos 41:1975 — not found; Hughes et al. 2008, Bioorg Med Chem Lett 18:4872 — paper exists, exact triple not confirmed. All three carry `verified=True`: the flag is self-asserted and not reliable. The check confirms existence only, not that the paper supports the KB claim. The 16 FTO entries are all "unverifiable" and quarantined. `target_kb` PDB IDs (19) all exist on RCSB; **one mislabel: `a4b1` cites 4IRZ, which is the α4β7 headpiece with natalizumab, not α4β1** (`target_kb_pdb_check.json`).

## 3. Coverage on the benchmark
Strict target mapping (`kb_target_map.py`, tests include "α-v β-3 must not map to αvβ6"): the 16 KB targets map to **12 of 793 benchmark targets**: 8 of 344 eligible for the cross-target analysis, **1 of 46** in the primary analysis, 389 of 20,562 positives (1.9 %). A loose gene-token match would have given 20 (it counted αvβ3 as αvβ6). Targets with target-specific chemistry (αvβ6, α4β1, α4β7, αLβ2, PD-L1): 8 benchmark keys, 6 of 344, 1 of 46, 311 positives. No modality beyond head-to-tail/lariat peptides is covered; stereo and topology cases have no KB rule except the αvβ6 D-Pro lock. `target_kb` has no UniProt keys (the mapping above is the first).

## 4. Property × substructure coverage matrix
Level: C = count/presence, P = positional, S = stereo, T = topology. "Data" = checked against measured data in this repo, within source.
| property | KB rules (where) | substructures | level | validated / contradicted by data |
|---|---|---|---|---|
| Permeability | modality: backbone N-methylation raises it, at exposed NH only (medchem_kb, experience_kb); physchem: Ro5, Veber, bRo5, chameleon (medchem_kb, product) | N-methyl, TPSA, HBD, logP, MW | C (the "exposed NH" clause is prose, not computable) | **N-methyl count: INCONCLUSIVE within source** (pooled ρ 0.37 → median within-source ρ 0.01, CI −0.13…0.28; 9 of 18 sources positive). **TPSA, HBD, logP, Veber: VALIDATED within source** (median ρ −0.30, −0.41, +0.47, +0.23; both source halves agree). MW inconclusive; Ro5 too few pass |
| Binding | αvβ6: RGD, RGDL, RGDLxxL/I, D-Pro + N-methyl lock, aromatic flanks, single Lys handle (acceptance_gate, rule_induction); PD-L1: hot-spot text; 12 others: one generic PPI sentence | RGD motif, motif positions, D-Pro | P, S (αvβ6 only) | αvβ6 RGD rule equals the trivial RGD baseline (AUROC 0.826, workstream 3); knowledge arms at chance elsewhere (coverage 1/46) |
| Selectivity | pan-RGD vs RGDL → β6 selectivity (liability flags) | RGDL | P | not tested here (Kapp 34-ligand matrix exists; not re-analysed) |
| Solubility | none for peptides; AqSolDB small-molecule index only | — | — | **no cyclic-peptide solubility data in the repo: data gap** |
| Stability | CMC sequence motifs NG/NS/NH/NA, DG/DS, Met/Trp oxidation, odd Cys; D-amino acids → protease resistance (prose) | dipeptide motifs, D-residues | P (canonical residues), S (prose only) | not validated: only 605 PepMSND SMILES, binary labels, not all cyclic |
| Conformation / chameleon | statement-level (Rezai 2006, Over 2016); no computable rule | IMHB, 3D polarity | — | 69 NOE-constrained peptides, no property labels; not testable |
| Renal retention | cationic charge → kidney dose; extra Lys/Arg liability (αvβ6 only) | net charge, Lys/Arg count | C | peptide renal data: 163 seed entries, mostly null; earlier renal model flat for peptides; within-source n_pos tends negative with permeability (descriptive, not a renal test) |
| Toxicity / liability | RDKit PAINS/Brenk/NIH/ZINC alerts (1,585); ADMET endpoints (product, dead) | small-molecule alerts | C | PAINS: no peptide flagged (no variation); Brenk OR 2.1 (0.47–9.6), inconclusive |
| Availability (cell) | peptide_availability OLS | hydrophobicity, charge | C | linear SH3/PDZ only; no cyclic validation |
Not covered by any KB: D-flip / N-methyl-shift / residue-swap positional effects, ring-size or topology effects, ncAA classes, lariat vs head-to-tail, assay/source metadata.

## 5. Data check of KB-claimed rules (leak-safe, source-aware)
Harness `kb_rule_validity.py` (within-source Spearman over 18–20 sources with ≥ 20 peptides, source-bootstrap CI, replication in two source halves fixed by sha256; features from monomer tokens and RDKit, no labels used; tests `test_kb_rule_validity.py`: planted within-source effect recovered, pure between-source confound NOT validated while pooled ρ is fooled, shuffled labels inconclusive, reversed rule contradicted, too few sources insufficient — 5 passed). Result file `kb_rule_validity_result.json`. Main finding: **the KB's flagship cyclic-peptide rule (N-methylation) is mostly a between-laboratory effect**; the physchem rules (TPSA, HBD, logP) hold within source. Rules that make no permeability claim (D-count, ring size, charge) are descriptive only. Caveat: 2D descriptors, one assay (PAMPA), permeability only.

## 6. Contamination, dating, duplicates
Contamination: CycPeptMPDB contains small sources from papers the KB cites (Rezai 2006 ×2, White 2011, Hewitt 2015, Bockus 2015; ≈70 peptides); Trivehexin/avebehexin (KB αvβ6 actives) are in the benchmark set (workstream 3); the KB's αvβ6 receptor asset is derived from 9XMM, which is also a Stage B test complex (9XMM_3). Dating: entries carry `version "1.0"` and citation years (1967–2022) but no ingestion date → **no leak-safe time slicing possible**. Duplicates: 11 entries across `medchem_kb` and `medchem_kb_product`; the product KB is dead.

## 7. Gaps, ranked by expected value for the loop-improves-the-LLM study
1. **Source/assay-aware provenance with within-source validation per rule** (schema: assay, n_sources, within-source effect + CI, replication). Cheap; prevents injecting between-lab confounds as priors (N-methyl). Prototype delivered (§5).
2. **Peptide-level positional and stereo SAR rules from matched pairs** (N-methyl shift, D-flip, residue swap, within source and topology class) as distributions (effect, n, sources, replication), consumed as prior mean shifts conditional on the transformation. Highest value: 71 % of CycPeptMPDB peptides are stereoisomers of each other and 28 % of identical-fingerprint pairs are label cliffs. **Mined only from training sources/families; workstream 4's matched-pair table (33,398 within-source pairs) is used read-only as input. A prototype is delivered (§9).** Proposed record: `{transformation, context, effect_mean, effect_sd, n_pairs, n_sources, replicated, assay, mined_from}`.
3. **Structure-derived per-target pharmacophores/hot-spots** from the 776 bound-cyclic PDB complexes, replacing the generic PPI sentence for 14 of 16 targets; the manifest has metadata only, so coordinates must be fetched; mined only from training families (exclude the held-out receptor cluster).
4. **UniProt/ChEMBL keys on every KB entry** (prototype: `kb_target_map.py`).
5. **Negative knowledge**: harvest the same-target measured inactives (46 targets in the primary analysis) and failed designs as KB entries.
6. Peptide stability/liability beyond canonical sequence motifs (ncAA-, stereo-, topology-aware); needs data beyond 605 binary labels.
7. Cyclic-peptide solubility: no data; do not extrapolate from AqSolDB.
8. Fix or remove: dead product KB, the 3 flagged citations, the `a4b1` receptor structure, self-asserted `verified` flags.

## 8. Prototypes and what is not done
Delivered and tested: `kb_rule_validity.py` (+5 tests), `kb_target_map.py` (+5 tests, coverage CSV), citation checks. Not built: structure-derived pharmacophores (needs PDB fetch), any use of these rules inside a loop run (no value claim is made for them there; see §9 for held-out value of the rules themselves). Not audited: FTO/patent content; correctness of metal/force-field parameters; `target_kb` indication and mechanism fields; `medchem_kb_ingested_large` consumers; the BioMate-side multi-source data layer (60+ sources in silos) was not re-traced here.

## 9. Prototype: leak-safe peptide SAR rule set and knowledge channel (v1)
Code `kb_audit/peptide_sar_kb.py`; tests `test_peptide_sar_kb.py` (7) and the earlier harness tests (10): all 17 pass. Rules are mined from the training laboratories only (sources with ≥ 20 labelled peptides; 21 labs, 6,776 peptides, 33,211 within-source pairs from workstream 4), validated within source, stored with provenance (`mined_from` labs), status and a validity score (= 2 × fraction of sources agreeing in sign − 1, for status `rule`), and exposed as per-peptide features `K_phys`, `K_nme`, `K_dflip`, `K_total`, standardised within source so the scale matches within-source labels (the L4 lesson). `fuse(pred, K, n_labeled)` gives the same prior/fusion form as the L2/L4 arm. Status rules and the 99 % intervals were fixed on synthetic data before any real held-out result: with 95 % intervals the synthetic null false-rule rate was 5.5 %, with 99 % it is 2.2 % (13/600), and planted effects are found in 100/100 worlds.

**Rules mined from all 21 labs (shipped as `peptide_sar_rules_v1.json`; do not use it to score those same labs):**
| rule | status | estimate [99 % CI] | sources agreeing | validity |
|---|---|---|---|---|
| TPSA | rule, agrees with KB | within-source ρ −0.29 [−0.41, −0.23] | 21/21 | 1.00 |
| H-bond donors | rule, agrees | −0.42 [−0.49, −0.08] | 14/16 | 0.75 |
| logP | rule, agrees | +0.49 [0.00, 0.70] | 16/21 | 0.52 |
| Veber pass | rule, agrees | +0.23 [0.14, 0.53] | 6/6 | 1.00 |
| N-methyl added (pair) | rule | +0.45 z [0.19, 0.71] (4,139 pairs, 10 labs) | 9/10 | 0.80 |
| D↔L flip (pair) | **no consistent direction** (encoded as zero prior) | −0.03 z [−0.09, 0.03] (7,423 pairs, 8 labs) | 4/8 | 0 |
Matches workstream 4 (N-Me added +0.25 log Papp raw, D-flip −0.01).

**Leave-one-lab-out test of the rules themselves** (mine on the other 20 labs, score the held-out lab, Spearman with its within-source labels; 21 labs):
| channel | median within-lab ρ [95 % lab-bootstrap CI] | labs with ρ > 0 | pooled held-out ρ [CI] |
|---|---|---|---|
| K_phys | 0.25 [0.13, 0.49] | 19/21 | 0.39 [0.08, 0.49] |
| K_nme | −0.01 [−0.10, 0.28] | 10/20 | 0.32 [−0.04, 0.46] |
| K_total (sum) | 0.15 [0.04, 0.49] | 16/21 | 0.39 [0.01, 0.51] |
Mined direction of TPSA agreed with the held-out lab's own direction in 21/21 labs, HBD in 14 of 16 where defined. Cross-lab duplicate structures: only 5 flat structures occur in more than one lab; excluding them changes nothing (0.391). Negative control: over 30 within-lab label shuffles on the real features only 2 of 180 rule tests (1.1 %) came out active (HBD twice), and the held-out skill where any rule was active was ≈ 0 (mean −0.05, n = 3 shuffles: uninformative, consistent with 0). The first version of this control averaged over only the shuffles in which a rule happened to be active; the corrected control reports those counts.

**What this shows and does not show.**
(1) The physchem channel is a real, zero-fit signal for unseen laboratories: pooled held-out ρ 0.39, comparable to workstream 4's leave-labs-out fingerprint models (0.30–0.31, a different set of 45 sources, so not strictly comparable). (2) It is dominated by two large labs (Townsend and Kelly are 65 % of peptides): the median across labs (0.25) and the wide lab-bootstrap CI show the effect is heterogeneous; TPSA alone in the KB direction (no mining) scores 0.41 pooled, so mining adds nothing over the single textbook feature. (3) The N-methyl pair rule is real at the pair level (adding an N-methyl to the same peptide raises permeability) but as a per-peptide ranking feature (centred N-methyl count) it is ≈ 0 for the median held-out lab; combining it into K_total lowers the median (0.15 vs 0.25). Recommendation: expose K_phys as the default prior; offer K_nme only for series/analogue proposals where the pair is defined, not as a general ranking prior. (4) D-flip: no direction, so the knowledge channel carries nothing there; an LLM must learn stereo effects from data. (5) No claim is made that these rules improve a loop; that is a separate test (L7 knowledge-on versus knowledge-off). (6) Scope: PAMPA permeability only; the pair rules rest on 10 labs (N-Me) and 8 labs (D-flip) and are conditional on same-source, same-topology, single-position pairs.
