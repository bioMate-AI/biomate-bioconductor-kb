# Target-structure knowledge layer (workstream K3) — results from committed run files (2026-10-29)

Scope (owner): fundamental structure knowledge for cyclic peptides — how they bind, in which bound conformation, with which contacts — for our targets and for cyclic-peptide binders in general. Contract: `20261031_ALLATOM_IMPLEMENTATION_PLAN.md`. Code: `research/guangzhou_all_atom/cyclic_llm/allatom_paper/structure_knowledge/`. All compute ran on EC2 spot (no laptop compute). Nothing below uses a number that is not in a committed result file.

## 1. What came from an existing resource and what is our own parsing (coordinator request)
| field / layer | source | how obtained |
|---|---|---|
| bound cyclic complex candidates (776 rows, PDB ids, peptide + receptor chains) | **our September miner** `data/bound_cyclic/v2/bound_cyclic_manifest.jsonl` (`mine_bound_cyclic_complexes.py`, RCSB, coordinate-based) | reused as is; its cyclisation LABEL is re-checked (see QC) |
| peptide-ligand complexes (bulk candidate list), ligand chain, receptor chains, UniProt (BioLiP column), PubMed, merged affinities (manual survey, Binding MOAD, PDBbind-CN, BindingDB) | **BioLiP2** flat file (`zhanggroup.org/BioLiP/download/BioLiP.txt.gz`, downloaded on EC2; parse validated: 100% lines >= 17 columns, 100% valid PDB ids, UniProt column pattern-valid in 83.5% of rows) | imported by `import_biolip.py`; column layout from the BioLiP README as recalled by the script author, validated empirically (`biolip_parse_check.json`) |
| entry metadata: title, method, resolution, primary-citation DOI/PubMed, UniProt per receptor chain, RCSB-deposited binding affinities | **RCSB Data API (GraphQL)** | fetched verbatim by `rcsb_meta.py`, retrieval date stored |
| 3D coordinates | RCSB mmCIF files | downloaded on EC2 |
| **cyclisation detection (ring chemistry: disulfide, head-to-tail, amide-like/lactam, thioether, ester-like, C–C link; ring size in residues)** | **our parsing** (`features.py`, geometric distance tests) | independent of every resource's label |
| D-residue and N-methyl flags | **our parsing** (chirality volume vs the receptor's L-amino-acid majority; backbone-N carbon with no other heavy neighbour) | no CCD code table assumed |
| backbone dihedral classes, beta-turn types I/I'/II/II', gamma-turn-like, cis amides | **our parsing** (textbook windows, declared in `TURN_WINDOWS`) | descriptive classes, not fits |
| interface features: contacts, H-bonds, salt bridges, apolar contacts, metal contacts, buried SASA (polar/apolar), hotspots, pocket residues | **our parsing** | own Shrake–Rupley, 96 points, probe 1.4 A |
| intramolecular H-bonds / exposed NH accounting | **our parsing** | N…O <= 3.3 A, |i−j| >= 2 |
| covalent-link QC (peptide chain covalently bonded to its 'receptor') | **our parsing** | S–S < 2.3 A; C–N/C–O/C–C/C–S < 1.85 A |
| target cards, priors, leave-one-target-out stability | **our computation** | `cards.py`, `aggregate.py` |
Propedia v2.3 and PepBDB were not imported: the survey (`20261031_SURVEY_EXISTING_CYCLIC_PEPTIDE_KNOWLEDGE.md`) says they derive from the same PDB source as BioLiP2 and contain no cyclic-specific annotation; BioLiP2 plus our own cyclic layer covers their content for this purpose. This is a scoping decision, not a verified equivalence.

## 2. Pipeline (all on EC2 spot; code in `structure_knowledge/`)
1. `import_biolip.py`: BioLiP2 flat file -> peptide-ligand groups (PDB id, ligand chain, receptor chains) U old miner manifest -> `candidates_union` (30,773 candidates: 129 manifest-only, 647 in both, 29,997 BioLiP2-only).
2. `run_library.py`: RCSB metadata (GraphQL), mmCIF download, `features.py` per complex (own parsing). Sharded over 3 instances; chunked process pool; giant-assembly guard (CIF > 12 MB skipped); results resumable.
3. `aggregate.py`: QC, de-duplication (best resolution per (target, sequence, closure class)), priors with leave-one-target-out stability, exports. `cards.py`: target cards. `merge_shards.py`, `launch_final.py`: merge and final run.
4. Tests (`test_structure_knowledge.py`): **23 pass on EC2** (`results/pytest.log`): analytic SASA checks, hand-checked complexes {11MG, 1A7F, 1AI0, 1APH, 1BCK, 1C5F, 1CWA, 1AXD, 148L, 1ACY} (sequence length, disulfide distance and ring span against the manifest's independent evidence string), determinism, insulin A chain flagged covalent, priors/LOTO/exclusion mechanics, card flags, an end-to-end CLI regression.

## 3. Library (results/library_summary.json; library_v1.jsonl holds every QC-passing complex incl. antibody-like receptors, flagged)
- Candidates with a valid parse: 28,789 of 30,773 (the rest: peptide chain > 40 residues, CIF > 12 MB, < 3 residues, empty receptor).
- QC flags (overlapping): {"covalent_to_receptor": 2096, "no_closure_redetected": 26004, "length_outside_5_30": 2617, "ring_lt4": 102, "no_interface": 6, "manifest_label_disagrees": 1}. **90% of parsed BioLiP2/miner peptide-ligand rows are linear** (no closure re-detected).
- **Library after QC and de-duplication: 888 cyclic-peptide complexes over 451 receptor (UniProt-set) targets**; 802 with non-antibody receptors (primary), 86 antibody-like receptors (epitope-peptide complexes, kept but flagged).
- By closure (our detection): {"disulfide": 366, "head_to_tail": 187, "amide_like": 140, "ester_like": 48, "c_c_link": 78, "thioether": 69}. Methods: {"ELECTRON MICROSCOPY": 110, "X-RAY DIFFRACTION": 765, "SOLUTION NMR": 13}; median resolution 2.2 A.
- Composition: 527 with non-standard residues, 226 with >= 1 D residue, 118 with >= 1 N-methyl, 134 with a cis amide; 806 with a primary-citation DOI (RCSB).
- **Source of the library rows:** 670 BioLiP2-only, 204 in both BioLiP2 and the old miner, 14 miner-only. Of the old miner's 776 rows only **218 (28%) remain in the library after QC and de-duplication**: it labelled insulin A chains (disulfide-bonded to their B chains), 3-4-mers and chain-broken fragments as 'bound cyclic peptides'; its `sidechain_backbone` label was unreliable (4 of 4 sampled re-detected as no closure).
- **Affinity: none.** 0 of 818 distinct library entries have an RCSB binding-affinity annotation; BioLiP2 has 1 affinity string for 41,544 peptide-ligand lines (its merged affinities attach to small-molecule ligands: {"small_molecule": {"aff_moad": 25976, "aff_bindingdb": 19329, "aff_manual": 80}, "peptide": {"aff_manual": 1}}). The requested ligand-efficiency proxy therefore cannot be built from open tables; flagged, not approximated.

## 4. Bound-conformation priors with leave-one-target-out (LOTO) stability (results/priors_v1.json; primary set 802 complexes, 378 targets, target-set sha256 `419f8bf3d8dc7334`)
Target = receptor UniProt set. 'Deviation' = total-variation distance (categorical priors) or max absolute change (rates) when one target is removed. Stable = >= 20 targets, median dev <= 0.05, max dev <= 0.25 (thresholds fixed in `aggregate.py` before the run).
| prior | n | stable | LOTO median | p95 | max |
|---|---|---|---|---|---|
| ring_residues/disulfide | 301 | yes | 0.0 | 0.0109 | 0.0464 |
| ring_residues/head_to_tail | 174 | yes | 0.0 | 0.0105 | 0.0751 |
| ring_residues/amide_like | 137 | yes | 0.0 | 0.0129 | 0.0359 |
| ring_residues/thioether | 67 | yes | 0.0 | 0.0145 | 0.0778 |
| beta_turn_presence/disulfide | 301 | yes | 0.0 | 0.0057 | 0.0165 |
| beta_turn_presence/head_to_tail | 174 | yes | 0.0 | 0.0054 | 0.0647 |
| beta_turn_presence/amide_like | 137 | yes | 0.0 | 0.0069 | 0.0296 |
| beta_turn_presence/thioether | 67 | yes | 0.0 | 0.0063 | 0.0409 |
| position_rates/all | 10443 | yes | 0.0002 | 0.0015 | 0.0075 |
| position_rates/disulfide | 5002 | yes | 0.0 | 0.0017 | 0.0135 |
| position_rates/head_to_tail | 1589 | yes | 0.0 | 0.0047 | 0.0155 |
| residue_enrichment/all | 8494 | NO | 0.015 | 0.0896 | 0.5015 |
| residue_enrichment/disulfide | 4629 | NO | 0.0 | 0.1071 | 0.6257 |
| residue_enrichment/head_to_tail | 986 | NO | 0.0 | 0.2569 | 1.898 |
| nh_fate/all | 8909 | yes | 0.0003 | 0.0019 | 0.0055 |
| nh_fate/disulfide | 4475 | yes | 0.0 | 0.0018 | 0.01 |
| nh_fate/head_to_tail | 1248 | yes | 0.0 | 0.0025 | 0.0327 |
Readable summaries (results/retrieval_snippets_v1.jsonl): disulfide-closed ring spans 8-13 residues (IQR, median 10, n=301); head-to-tail 7-11 (median 8, n=174); amide-like 5-10 (median 7, n=137); thioether 9-12 (median 12, n=67). Among disulfide complexes 56.5% contain a type I beta turn (I' 9.0%, II 6.3%, II' 7.3%). N-methylation is about 2x more frequent at positions in contact with the target (4.7% vs 2.2%); D residues are not enriched at the interface (5.3% vs 6.9%). Backbone NH groups: 47% intramolecularly H-bonded, 10% H-bonded to the receptor only, 43% free. Interface residue enrichment (log2 odds): I +1.92, W +1.69, F +1.41, Y +0.93, V +0.70; depleted Q -0.94, A -0.82, C -0.82, E -0.72, K -0.45 -- **this prior is NOT stable under LOTO (max deviation 0.50 log2) and is exported with weight 0**.
Reading: ring-size, turn, position-rate and NH-fate priors are population statistics that no single target changes; they say nothing about a specific new target class.

## 5. Target cards (results/cards_v1.json; reference structure = the PDB id in `target_kb/<t>.json`; accessions chosen by entity-name match to the target name, method recorded per card)
| target | reference | cyclic complexes | non-antibody receptor | status | best template |
|---|---|---|---|---|---|
| a4b1 | 4IRZ | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| a4b7 | 3V4V | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| avb6 | 9XMM | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| baff | 1OQD | 5 | 5 | cyclic-peptide complexes available | 1OQE (disulfide, ring 14, 2.5 A, DOI 10.1038/nature01543) |
| c5 | 5I5K | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| cd20 | 6Y92 | 1 | 0 | ONLY antibody-epitope complexes (the 'receptor' chains are ant | 2OSL (disulfide, ring 17, 2.6 A, DOI 10.1074/jbc.M701654200) |
| cd40 | 3QD6 | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| fcrn | 4N0U | 5 | 5 | cyclic-peptide complexes available | 3M17 (disulfide, ring 11, 2.6 A, DOI 10.1074/jbc.M110.120667) |
| il17a | 4HSA | 1 | 1 | cyclic-peptide complexes available | 5VB9 (disulfide, ring 14, 1.7 A, DOI 10.1371/journal.pone.0190850) |
| il17f | 5N92 | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| il23 | 6WDP | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| il2ra | 1Z92 | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| il6r | 1P9M | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| lfa1 | 5E6U | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
| pdl1 | 5O45 | 9 | 9 | cyclic-peptide complexes available | 5O45 (amide_like, ring 13, 0.99 A, DOI 10.1002/anie.201707707) |
| tnfa | 2AZ5 | 1 | 1 | cyclic-peptide complexes available | 7TA6 (disulfide, ring 23, 2.67 A, DOI 10.1021/jacs.1c13717) |
| grpr | - | 0 | 0 | NO cyclic-peptide complex in the library for this target | - |
- **No cyclic-peptide complex in the library: alpha4beta1, alpha4beta7, alphavbeta6, C5, CD40, IL-17F, IL-23, IL-2Ra, IL-6R, LFA-1 and GRPR.** For alphavbeta6 this does not prove that none exists in the PDB: complexes deposited with the macrocycle as a hetero-ligand (non-standard residues) rather than a peptide chain are outside both BioLiP2's 'peptide' class and the old miner; the card says 'no structure available' and the binding mode for these targets must be transferred from other targets.
- GRPR: RCSB text search returns 12 entries; the peptide ligands in them are linear (CCK-8, GRP, bombesin, neuromedin C). The card's accession list includes fusion partners from chimeric entities (e.g. P0AEX9) -- reported as found, not cleaned.
- CD20: the only complex (2OSL) has the CD20 epitope peptide bound by a Fab, i.e. antibody-epitope, not a cyclic-peptide binder of CD20 (card status says so).
- `paper_opened` is false on every card: DOIs are RCSB primary-citation metadata. Binding-mode numbers are medians computed from the structures, not statements from papers. Residue numbering is per entry, not harmonised across entries.

## 6. Exports for the other workstreams
- `results/retrieval_snippets_v1.jsonl`: text snippets with provenance (n, target-set hash, stability flag) for prompt context (I-B).
- `results/soft_potentials_v1.json`: sequence-level log-probability tables for ring size per closure class (default weight 0.5 where stable; **defaults are not tuned here: weights must be tuned on source group A only downstream**), plus an informational position-rate record (weight 0; it needs a target).
- `results/library_v1.jsonl`, `results/cards_v1.json`: for retrieval and target conditioning.
- **Arm G exclusion:** `python aggregate.py ... --exclude-targets FILE` (a UniProt accession or exact target key per line) recomputes every prior without the matching targets; `results/priors_excl_armG_example.json` removes the alphavbeta6/PD-L1 accessions (P06756, P18564, Q9NZQ7); it also removed the alphavbeta3 targets that share the alphaV accession (conservative by design). Every prior carries the sha256 of the target set it was computed from. Structure priors never see labels or affinities.

## 7. Limitations (stated, not softened)
1. Coverage is bounded by BioLiP2's peptide class plus our September miner; cyclic peptides deposited with non-standard residues as hetero-ligands can be missed (see alphavbeta6).
2. Crystallisable, soluble, disulfide-rich binders dominate (X-ray 765 of 888); cryo-EM 110, NMR 13. Priors describe what is in the PDB, not what binds best.
3. Cyclisation is detected by distance cut-offs on deposited coordinates (S-S < 2.3 A; amide/ester/C-C < 1.6-1.7 A; thioether < 2.0 A); alternate conformations are dropped to the first.
4. D-residue and N-methyl calls are geometric and depend on model quality; the L-reference is the receptor majority; the row-level flag `d_sign_ref_found` records whether a reference sign was found.
5. The antibody-like receptor flag is a text heuristic on entity descriptions (>= half of the receptor entities match).
6. Target = UniProt set of the receptor chains; the LOTO therefore treats a heterodimer as one target; entries without UniProt are their own target.
7. No affinity or ligand-efficiency data (see 3); no papers were opened for the cards.
8. Priors are not fitted to any benchmark label; they are not validated as design aids -- that is for the downstream held-out evaluation.

## 8. Engineering notes (what went wrong and was fixed; kept for audit)
- The old miner's manifest was ~72% non-qualifying (see 3); detected by independent cyclisation re-detection plus a covalent-link filter.
- The first sharded runs died with `BrokenProcessPool`: two tasks for the same PDB entry (different peptide chains) raced on the shared CIF download/delete. Fixed by grouping tasks per PDB id, atomic downloads, and isolated-subprocess fallback; all shard outputs were produced after the fix or resumed from resumable files (no result was edited by hand).
- Card accession selection first matched every UniProt in the reference entry (pulling in albumin and beta2-microglobulin for FcRn); fixed by entity-level name matching and a superset rule. The antibody-like flag was tightened twice after false positives (IgG receptor FcRn; factor VIIa heavy chain), each with a regression assertion.
- A merge step written as a shell heredoc was silently swallowed by a `;` join; moved into `merge_shards.py`.

## 9. Spend and reproducibility
About USD 1 in spot compute (estimate: ~30 short instances, c5/c6i/c6a/m6i 2xlarge-4xlarge, listed with launch times in `orchestrator/cost_log_ia.csv` under `allatom-k3`; terminated instances no longer appear in `describe-instances`). No instance is left running. Large files on S3 (`s3://biomate-nextflow-work/cyclic_peptide/allatom/k3/`): merged `features.jsonl` sha256 `3ad12c15f7a9a397bb154c1684e3bdfc6222786c6be837b18e9b3994c09f02d1`, `meta.jsonl` `29dc87f5be0cbdac280d205bebf3267ac454ba2b1a7d369712eb76464c9247ff`, `candidates_union.jsonl` `be63ec7bac6797807c8b985e2e84ba7845607d4d4aad7847df9b9a7d240f91c3`; final run prefix `final-185814`. Small result files are committed under `structure_knowledge/results/`.
