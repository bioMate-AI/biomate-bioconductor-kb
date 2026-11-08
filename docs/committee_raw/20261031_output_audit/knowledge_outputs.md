# Knowledge-layer outputs: independent audit (2026-10-31)

Auditor: independent Claude agent. Read-only except this file. Sources opened: Europe PMC full-text XML (REST), arXiv PDF, RCSB mmCIF and data API, repo docs. No heavy compute (only quote search, mmCIF parsing of about 25 small files, on the laptop). Not committed.

Scope note: the 40-entry sample judged "faithful" if (S) quote is verbatim in the opened source AND the statement states no more and nothing different from what the quoted passage (plus its immediate context) supports. "E" (entry-level) additionally requires correct tier, direction and scope fields. Tier rule applied: T1 = result is the source's own experiment/simulation/analysis; otherwise T2.

## 1. Gold set `knowledge/knowledge_kb_v1.json` (107 entries)

Sample: seed 20261031 (`random.Random`, entries sorted by id inside each stratum). 40 entries: T1 16 (rule 8, card 4, caution 2, fundamental 2); T2 16 (fundamental 8, rule 5, caution 2, card 1); T-internal 8 (card). 13 of the 40 are weight-eligible. Sample ids: see scratch list reproduced by the seed; failures below.

Quote verbatim: 40/40 found in the source (internal ones in the cited docs/ file). A few needed whitespace-insensitive matching because of XML spacing; none were altered. Card-specific quotes (arXiv PepMLM) were found in the arXiv PDF text.

| Tier | n | S (statement faithful) | E (statement + tier + direction/scope) |
|---|---|---|---|
| T1 | 16 | 13/16 = 81.2% (CP 54.4-96.0%) | 13/16 = 81.2% (54.4-96.0%) |
| T2 | 16 | 15/16 = 93.8% (69.8-99.8%) | 13/16 = 81.2% (54.4-96.0%) |
| T-internal | 8 | 8/8 (63.1-100%) vs the internal docs; underlying data UNVERIFIED | 8/8 |
| All | 40 | 36/40 = 90.0% (76.3-97.2%) | 34/40 = 85.0% (70.2-94.3%) |
| Weight-eligible only | 13 | 12/13 = 92.3% (64.0-99.8%) | 10/13 = 76.9% (46.2-95.0%) |

Failures (all listed):

| id | tier | what is wrong | corrected |
|---|---|---|---|
| CARD-CPCOMP-001 | T1 | Card says the comparator DiffPepBuilder "fails completely on disulfide and bicycle patterns". The quote concerns the energy-guided BASELINE. DiffPepBuilder gets 23.07%/32.78% (Table 3) and is beaten by CP-Composer. Statement "a comparator fails" is ambiguous; card field wrong. | "The energy-guided baseline fails completely on disulfide and bicycle patterns; DiffPepBuilder (designed for disulfides) reaches 23-33% vs CP-Composer 41-62%." |
| CARD-RANDLIB-001 | T1 | "The hit has 2 HBD vs 9 in native Nrf2". The 2-HBD figure is for optimised peptide 30 (Ki 53 nM), not the library hit. | "Optimised peptide 30 has 2 HBD (vs 9 in Nrf2 peptide)." |
| LIT-SD-002 | T1 | Single cyclic decapeptide (CDP5) generalised to "peptide membrane permeability"; clause "kinetic models correlated better for small compounds" is a cited claim (ref 18) in the introduction, not the source's result (T2 material under a T1 label). | "For one cyclic decapeptide (CDP5), ISDM permeability was about one order of magnitude below the PAMPA value (log P -8.1 vs -6.7)." Drop the kinetic-model clause or make it a separate T2 entry. |
| LIT-SD-001 | T2 | Extra clause "the basis of solubility-diffusion reasoning" is not in the quote (the passage is about ADMET software and Overton's rule). Sign "+" is only implied by "correlated". | "Log Pow, used by ADMET software, can be correlated with passive permeability via Overton's rule." |
| LIT-OB-001 | T2 | direction "multi", feat hbd -1 / tpsa -1, weight-eligible. The quote ("target of >=20% by modulating TPSA, HBD count, LogD") states a project goal with NO direction. The entry's own note says "project goal, not a measured law". | Set weight_eligible=false (direction unsupported). |
| LIT-IMHB-004 | T2 | direction "-" / exposed_nh -1, weight-eligible: the quote says only that aMD IMHB donor contribution "correlates well" with PAMPA (no sign). Tier is also conservative-wrong: it is the source's own aMD result (should be T1). | Statement fine; set direction "context", weight_eligible=false, tier T1. |

Non-failure observations: LIT-NME-001 (direction "+", n_nme +1, eligible) is supported only as "selective" N-methylation (entry notes the caveat; a monotone weight overstates it). LIT-NME-003 (eligible) rests on one matched pair. LIT-SEQ-001 quotes "up to 30-fold" while the same passage reports about 50-fold and >100-fold (understated, safe). LIT-NMEPOS-003 note calls sanguinamide examples "small-molecule" (they are cyclic peptides; cosmetic). I skimmed the 19 unsampled eligible entries by statement and quote only (not opened in the source): LIT-POL-002 has direction "window" with clogp 0 and LIT-NME-004 quotes "excellent permeability" while the statement states a computed 6-fold ratio; these are UNVERIFIED and worth a look.

Do the 32 weight-eligible entries support use as priors? Partly. 10 of 13 sampled eligible entries were clean at entry level (76.9%, CI 46-95%); all 3 problems were weight-relevant (direction not stated by the quote, over-generalised clause). Quote fidelity and tier are good; the weak point is the `direction`/`feat` mapping. Estimated 19-37% of the 32 (about 5-9 entries) could carry an unsupported direction. Recommendation: USE WITH FILTERS: require that the quote itself states the direction (increase/decrease/higher/lower/"reduce"), drop goal statements and correlation-only quotes, re-tier own-simulation entries, and have a human re-read the 32 eligible entries (cheap) before weights are fitted. Cards: use as retrieval context only (weight 0 already).

## 2. Prior-work ledger cards (28)

Checked 23 of 28: 8 T-internal against their docs (statements match the docs verbatim; the numbers inside the docs, e.g. DockQ 0.506, qNEHVI +37.6%, were NOT re-derived: UNVERIFIED) and 15 external (5 from the sample plus 10 drawn with seed 20261031 from the 12 remaining: CYCLINAB-001, CYCDIFF-001, MACRODRUG-001, BINDCRAFT-001, AFCYC-001, PEPINVENT-001, PEPMLM-001, PEPTUNE-001, HIGHFOLD-001, BINDCRAFT-002).

External card fidelity: 13/15 = 86.7% (CP 59.5-98.3%); failures CPCOMP-001 and RANDLIB-001 (table above). Hit rates and designs verified against the sources: BindCraft 10-100%, mean 46.3%, PD-L1 binder Kd* 615 nM (7 of 9 PD-L1 designs bound), CLDN4 functional failure (CpE about 400-fold higher affinity); AfCycDesign 8 crystal structures RMSD<1.0 A, 55 predictions pLDDT>0.85 with 44 (80%) correct, 27 designs synthesised; BindCraft-peptides MDM2 7/15, WDR5 6/9, PD-1/PD-L1 none; PepMLM 16/60 (25-49%) + 8/60 (>50%), RFdiffusion in-silico hit rate <30%; Cyclin A/B MDCK 0.2/1.1/14.9, oral F 27/17/23/6.2%, D-Pro lowering MDCK permeability; CycloSEL <1% to 11-16%; CycDiff-DPO 56 unseen targets, predicted not measured. Minor: CARD-MACRODRUG-001 `failure_modes` ("ML trained on public data under-represents successful chemotypes") is an inference not in the source. Recommendation: USE AS IS for numbers; fix the two cards; label inferred fields.

## 3. Structure knowledge `structure_knowledge/results/`

Method: mmCIF from RCSB re-read with an independent script (struct_conn author-annotated bonds, chem_comp type/name for D and N-methyl, own phi/psi turn windows = the declared TURN_WINDOWS). Sample: seed 20261031 over library_v1.jsonl rows sorted by (pdb_id, chain): 5AGU/C, 4KEL/B, 8GJS/B, 8EI5/E, 5NXQ/D, 24SQ/J, 6P81/B, 1QR3/I, 3WNG/C, 4MZJ/T. Note 5AGU and 6P81 are the same compound (not independent).

| Field | Correct | Notes |
|---|---|---|
| Closure type | 10/10 (CP 69-100%) | |
| Ring size | 9/10 (55.5-99.7%) | 8EI5/E wrong: Cys7 and Cys14 are bridged by an external linker residue WHL listed last in the chain, so the library measures Cys7 to the linker = 12. True ring: 8 residues + linker. |
| D count | 9/10 | 8GJS/B: library 1, CCD says 2 (0EH is (2R)-2-methyl-nonanoic residue, D-peptide linking, plus DAL). Staple quaternary residue missed by the chirality-volume rule. |
| N-methyl count | 8/10 | 5AGU and 6P81: library 4; CCD names give 3 N-methyl (MVA x2, MLU) + NZC "N-methylidene-L-threonine" counted as N-methyl (chemically debatable). |
| cis amide, turn calls | 10/10 | NOT independent: same thresholds/windows re-implemented; checks code, not definitions. Type-I "turns" are also called inside stapled helices (5NXQ, 8GJS). |

Any-field error: 4/10 entries (40%; CP 12.2-73.8%), or 2/10 (20%) if NZC is accepted. Pattern is systematic: linker-bridged bicycles. Checked 7UX5, 7UXO, 7UXP, 7UXQ (PD-L1 Helicon peptides, struct_conn confirms Cys7/Cys14-WHL): library/card ring 12, true 8 + linker, so 4 of 9 PD-L1 template rows are wrong. Proxy over the whole library (thioether, last residue X, ring >= length-2): 16 of 69 thioether rows (23%, unverified individually), so `ring_residues|thioether` priors are contaminated.

Target cards (reference + templates against RCSB data API / mmCIF; 3 cards, 9+3+5 templates; extra 10 template rows geometry-checked):
- PD-L1: reference 5O45 (0.99 A, Angew 2017, 10.1002/anie.201707707, PMID 28881104), UniProt Q9NZQ7 and all 9 template titles/resolutions/DOIs match RCSB. Closures/ring/N-Me correct for 5O45 (amide N-term to CCS, ring 13, 5 N-Me), 8ALX, 6YCR, 7OUN; ring wrong for the 4 Helicon rows. Verdict: metadata correct, 4 of 9 rings wrong.
- FcRn: reference 4N0U (3.8 A, JBC 2014), P55899 correct. 3M17/3M1B/5BJT metadata, disulfide rings (11, 11, 9) and N-Me (Sar, MLE = 2) correct. Weakness: "5 cyclic complexes" are 5 peptide chains from only 3 PDB entries (inflated n).
- BAFF: reference 1OQD, Q9Y275, DOIs correct. Templates (1OQE, 1OQD, 1OSG, 8ZUJ, 4V46) are natural receptor CRD fragments (BAFF-R/BCMA/BR3 hairpin, up to 2 disulfides), not drug-like cyclic peptides; ring sizes (14, 14, 12, 14) correct; the card itself flags "AMBIGUOUS" accession. Usable as structural templates with that caveat.
Recommendation: USE WITH FILTERS. Exclude rows with a non-residue linker in the ring (recompute ring from the closing atoms excluding the linker), recompute D with CCD type, treat N-methylidene separately, dedupe by PDB entry for n.

## 4. Knowledge-scale pilot (K2)

`docs/20261031_ALLATOM_KNOWLEDGE_SCALE.md` does not exist (only `..._SCALE_PREREG.md`). Pilot outputs exist on S3: `s3://biomate-nextflow-work/cyclic_peptide/allatom/k2/k2pilot5_20261029/extract/rules_verified.jsonl` (2,624 verified rules, 99 papers, Qwen3-8B fp8 on L4). That run is INCOMPLETE: `extract rc=1`, 1,280 passages processed (stats.json), so it is a partial pilot. I did not touch the registered seed-20261031 coordinator audit sample; I used seed 20261101 to stay independent.

Sample: 40 rules, stratified sar_rule 14, structure_property 12, prior_work 10, target_structure 4 (tiers T1 18, T2 22). #34 (K2-809fef60394f) quote is a table row not matched in the XML text: UNVERIFIED, excluded, n = 39. All other 39 quotes verbatim in the source.

- S (statement faithful to quote/source): 30/39 = 76.9% (CP 60.7-88.9%). By topic: sar_rule 10/14, structure_property 10/12, prior_work 6/9, target_structure 4/4.
- A (also tier, direction, property correct and on-topic): 17/39 = 43.6% (27.8-60.4%).
- Tier errors: 3/39 (T1 for a background claim from refs; T1 for a future-work suggestion): 7.7%.
- Fails S (9): statement says something the quote does not (macrocyclization vs stability, "ring sizes" for ACE2 selectivity, topology vs affinity, "higher likelihood", peptide-only scope widened, "explicit topology improves affinity", future-work as finding, chameleonicity from chirality, statement from neighbouring sentence). Fails A only (13): off-topic chemistry (patellamide Cu, MPTP, crystalline sponge, JNK inhibitors, cyclo[2]malonates), wrong property/direction labels ("no_effect" for "can influence"). `proxy_entailment == NO` rules passed the verifier (5 of 39 in sample).
- Precision against the gold set: not computable (the pilot's gold-overlap measure `k2_measure.json` holds only n_rules=2311; no recall block). UNVERIFIED.
Against the pre-registered 0.80 precision bar the RAW arm (S 76.9%, A 43.6%) does not clearly pass; the CI upper bound for S is 88.9%. Recommendation: DO NOT USE as priors. Usable only as retrieval context after filtering (entailment YES, cyclic/peptide term, T2 unless own experiment, direction/property re-check by a second model or human). Do not scale on this evidence.

## UNVERIFIED
- Underlying numbers inside the 8 internal docs (DockQ, qNEHVI, MM-GBSA, permeability R2).
- INT-SNAT2-001 claim "no experimental SNAT2 structure" not checked against RCSB.
- 19 unsampled weight-eligible gold entries beyond statement skim; 13 unsampled cards.
- K2 sample item #34 (table quote); K2 gold-recall.
- Library-wide extent of the ring-size/D-residue errors beyond the proxy count.

## Reproducibility
Seeds: gold 20261031; cards 20261031 (from the 12 not in sample); structure 20261031; K2 20261101. Scratch scripts (show.py, chk.py, chk2.py, cardchk.py, show2.py) in the session scratchpad, not in the repo.
