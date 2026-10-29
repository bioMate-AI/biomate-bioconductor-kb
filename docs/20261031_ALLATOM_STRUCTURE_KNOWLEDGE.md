# Target-structure knowledge layer (workstream K3) — DRAFT, numbers filled from the committed run files

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

(Sections 2-9: pipeline, library counts, QC findings, priors with LOTO stability, target cards, exports, limitations, tests and spend are appended below when the run files are committed.)
