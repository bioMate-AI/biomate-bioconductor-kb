# Peptide / Macrocycle Pretraining Corpus Survey (2026-10-30)

Purpose: our in-house cyclic-peptide chemical language model (atom-level SMILES, chirality, ring-closure/topology tokens, non-canonical residues) was pretrained on 2.87M ChEMBL molecules (1.7% macrocycles). This note lists open sources for a much larger peptide/macrocycle-rich corpus (target: millions of structures, at least 1M peptides/macrocycles), with a ranked recipe.

Method and honesty rules: every count and licence below was read from a page or paper fetched in this session (URL given). Items I could not open, or whose page did not state the number, are in Section 7 (UNVERIFIED) and are not used in the recipe's arithmetic except as explicitly flagged targets.

## 1. Headline finding

There is no open source of real, experimentally defined cyclic peptides with ncAA/stereo content anywhere near 1M. The verified real sources are in the 10^3 to 10^5 range (CycPeptMPDB 7,334; Macrocycle-DB 45,525; NPAtlas 36,545; COCONUT 695,133 of which only a small fraction are macrocycles; CREMP 36,198). The only verified million-scale peptide sources are (a) PeptideCLM's released generated peptide SMILES (about 10M, synthetic, built from sequences) and (b) PubChem (119M compounds, of which the peptide/macrocycle subset size is not verified by me). So a >=1M peptide/macrocycle corpus necessarily consists mostly of generated/augmented structures, and the real-data core (~0.3-0.5M) must be upweighted rather than diluted. The recipe in Section 5 is built around that fact.

## 2. Source-by-source

### 2.1 Directly peptide/macrocycle-specific

**CycPeptMPDB** (downstream benchmark; do NOT pretrain on it).
- Content: 7,334 cyclic peptides from 45 papers and 2 patents; 312 monomer types (305 backbone, 7 terminal); includes N-methylated residues and D-amino acids; 5,115 "circle" (N-to-C) and 2,336 "lariat" entries (sum 7,451 as reported in the same paper, which differs from the 7,334 headline; the paper is internally inconsistent or counts differently, so use the downloaded file's own row count); 2-15 residues, MW 342-1,778 Da.
- Format: SMILES, SDF, HELM at http://cycpeptmpdb.com/download/. Licence: CC BY 4.0 per the paper.
- URL opened: https://pmc.ncbi.nlm.nih.gov/articles/PMC10091415/ (the database site itself failed with an SSL error, so the licence statement is from the paper, not the site).
- Role: held-out evaluation set; see leakage section.

**CREMP** (Scientific Data 2024).
- Content: 36,198 unique macrocyclic peptides, 4-, 5-, 6-mer homodetic; canonical 20 side chains with L/D and N-methyl variations; about 31.3M conformers (3D, xTB-annotated). A CREMP-CycPeptMPDB subset has 3,258 macrocycles (about 8.7M conformers) with 6-, 7-, 10-mer heterodetic peptides taken from CycPeptMPDB.
- Zenodo 10.5281/zenodo.7931444 (CREMP) and 10.5281/zenodo.10798261 (CREMP-CycPeptMPDB); pickle plus SDF/JSON. Licence CC BY 4.0.
- URL opened: https://pmc.ncbi.nlm.nih.gov/articles/PMC11316032/
- Quality: 2D topology set is small (36k) but the 2D graphs are systematically enumerated; the CycPeptMPDB subset is by construction the held-out set: exclude it entirely.

**Macrocycle-DB**.
- 45,525 synthetic macrocyclic compounds (76 approved drugs, 105 clinical candidates, 2,533 protein targets); bioactivity, co-crystal structure links. Downloadable at https://macro-db.dpbio.tech/. Licence not stated on the page I read (UNVERIFIED, Section 7).
- URL opened: https://tagteam.harvard.edu/hub_feeds/4353/feed_items/17195942 (abstract aggregator, not the site).
- Overlap with ChEMBL is expected (bioactivity compiled from literature); dedupe.

**NORINE** (nonribosomal peptides).
- A search summary (not the primary page; the NORINE site fetch was blocked) reports 1,744 peptides and 526 distinct monomers, with monomeric structure, activity, organism. Cyclic, many non-proteinogenic monomers. Counts are from a snippet of mixed-date papers: treat as approximate. Licence unverified.
- URLs: search result pointing to https://bioinfo.cristal.univ-lille.fr/norine and PMC2238963 / PMC3482460 (not opened directly).
- Use: small but the highest-density source of exotic monomers; the monomer table can drive augmentation (Section 4).

**DBAASP**.
- v3: more than 15,700 entries (more than 14,500 monomers); of monomers about 12,000 synthetic, about 2,700 ribosomal, about 170 non-ribosomal. A 2024 paper reports 597 non-ribosomal and 1,413 ribosomal cyclic peptides. These counts come from a web-search summary of NAR 2021 and PMC11279581 (not opened directly). The DBAASP homepage I fetched showed placeholder zero counters and no licence text.
- Format: sequences with modification annotations; SMILES availability not verified.

**APD (APD3/APD6)**: 2,619 AMPs in APD3 (search snippet of PMC), 3,306 entries in the latest version per the same snippet. Natural, mostly linear/disulfide. Not opened directly; licence unverified.

**THPdb2**: 6,385 entries describing 894 FDA-approved protein/peptide therapeutics (search snippet from the site). Small; useful as a therapeutically relevant sanity subset, not for scale.

**Peptipedia v2.0**: more than 3.8M peptide sequences from 76 sources (PMC11734279, opened); more than 100k with reported activity; FASTA/CSV. Licence: web platform CC BY-NC-ND 4.0 and database ODbL restricted to non-commercial use per the paper. These terms are a problem if the model is a commercial product component: treat as research-only, do not include in a corpus we may ship weights from without legal review. Mostly canonical sequences; the paper did not quantify cyclic content.

**SmProt 2**: 638,958 unique small proteins (3,165,229 primary records) from Ribo-seq and literature across 8 species (search snippet of the SmProt 2 paper). Linear canonical sequences; licence unverified. PeptideCLM used SmProt2 in its pretraining data.

### 2.2 Natural-product / small-molecule macrocycle sources

**COCONUT 2.0**: 695,133 unique natural-product structures from 63 collections, with stereoisomers kept as distinct entities (539,350 with stereo, 82,220 without stereocentres, 73,563 undefined) (https://pmc.ncbi.nlm.nih.gov/articles/PMC11701633/). Download page (https://coconut.naturalproducts.net/download) lists SDF/CSV and states CC0; the paper states CC BY. The two statements differ: use CC BY terms to be safe. The macrocycle fraction is not reported in the paper I opened: compute it with RDKit ring-info (ring size >= 12). A general literature figure from a search snippet says macrocycles were 2.8% of a 130,000-compound natural-product set, which would imply roughly 20k macrocycles in COCONUT; this is an extrapolation, not a measurement.

**NPAtlas 3.0**: 36,545 microbial natural products (search snippet of NAR 2024). Download (TSV/SDF/JSON/GraphML) at https://www.npatlas.org/download; licence CC BY-NC 4.0 (opened). Non-commercial restriction: same caution as Peptipedia. Contains NRPS/RiPP macrocycles with real stereo.

**ChEMBL**: licence CC BY-SA 3.0 (https://www.ebi.ac.uk/chembl/ opened); share-alike clause applies to derived databases, which may be relevant for a released corpus (not for model weights per most readings; get legal view). The page did not state current compound counts. We already used 2.87M ChEMBL molecules; the macrocycle/peptide subset is extracted by SMARTS (below).

**PubChem**: 119M compounds, 322M substances, 295M bioactivities (PubChem 2025 update, via aggregator). NCBI places no restrictions on use, but individual submitters may claim rights (snippet of the NCBI policy). The downloads page was blocked by a bot check, so FTP layout is not verified by me; the standard route is the bulk Compound_*.sdf.gz / CID-SMILES FTP files (UNVERIFIED by me). PeptideCLM-2 used 108,583,157 unique PubChem SMILES after filtering.

**Enamine Macro Space**: virtual library of 180,000 macrocycles from 12,283 scaffolds (https://enamine.net/blog/macro-space-the-real-space-of-macrocycles via search snippet). Virtual and enumerated, not bioactive; availability as a download and its terms are unverified. ChemBridge advertises more than 20,000 purchasable macrocycles (snippet); commercial catalogue terms apply.

**ZINC22/REAL macrocycles**: no macrocycle count found. Not usable in the recipe until measured.

### 2.3 Structure- and sequence-derived peptide sources

**PDB (RCSB)**: data files CC0 (https://www.rcsb.org/pages/policies opened). Peptide ligands and short chains with ncAAs are described in the Chemical Component Dictionary; I did not verify CCD licence or counts. Extract peptide-like entities (chain length <= ~30, or CCD polymer-linking components) and cyclic ones via ring-closing bonds in mmCIF struct_conn. Expect tens of thousands of entries at most, heavily redundant (many identical peptides across entries): dedupe to unique flat SMILES. Count not measured.

**PepBDB / Propedia**: peptide-protein complexes derived from the PDB; PepBDB's total was not found in my searches. UNVERIFIED.

**UniProt**: CC BY 4.0 on all copyrightable parts (search snippet of the UniProt licence file). Use propeptide/peptide/signal-peptide features and short reviewed sequences as the linear pool for cyclisation augmentation. Counts not measured.

**ESMAtlas peptides** (used by PeptideCLM-2): about 9.6M sequences filtered to pTM > 0.7 and pLDDT > 0.7, length <= 100, clustered at 30% identity (MMseqs2), converted to SMILES with p2smi (PMC12803269, opened). Predicted, not natural peptides; linear canonical.

**Display libraries (phage, mRNA display/RaPID, DEL)**: I did not find a verified open, large, machine-readable set. Excluded; UNVERIFIED.

### 2.4 Public pretraining sets of peptide chemical language models

**PeptideCLM (v1)**: 10.8M peptides + 12.6M small molecules (HF model card, MIT licence, https://huggingface.co/aaronfeller/PeptideCLM-23M-all). Per the GitHub README: small molecules are "PubChem + SureChEMBL", peptides are "SmProt + RandPept"; the README says version 1.1 fixed ring-closure numbering errors in generated cyclised peptides (https://github.com/AaronFeller/PeptideCLM). Data on Zenodo, CC BY 4.0 (https://zenodo.org/records/14194469, which resolved to DOI 10.5281/zenodo.15042141, version 1.1, files: Generated_peptides.csv 10.8 GB with 10 million peptide SMILES, a FASTA of the sequences, PubChem-10M-Canonicalized.csv, SureChEMBL33_single_molecules.csv, SmProt2_All.csv; 14.0 GB total).
- Quality: "RandPept" are randomly generated sequences, so they carry no biological prior; whether they include ncAAs, N-methylation or D-residues was not stated on the pages I read. Check by sampling before use. Cyclisation is by ring closure within SMILES; the v1 files had a numbering bug, so use v1.1 only and re-validate every string with RDKit.
- Overlap: the README's finetuning uses CycPeptMPDB PAMPA data, clustered. Overlap of the v1 pretraining set with CycPeptMPDB was not reported on the pages I read.

**PeptideCLM-2**: more than 100M molecules per the search summary; pretraining = 108,583,157 PubChem SMILES + about 9.6M ESMAtlas peptides + 49,145 LIPID MAPS lipids; data on Zenodo and HuggingFace datasets, CC BY 4.0 for the paper. The paper's leakage table reports structural overlap of the pretraining corpus with downstream benchmarks: CycPeptMPDB 8.06%, PepMSND 28.43%, other tasks < 3.2%. This is the only published overlap figure I found, and it matters: any large PubChem pull will contain a non-trivial fraction of CycPeptMPDB (many of its compounds are deposited in PubChem or ChEMBL), so the leakage filter in Section 6 is mandatory, not optional. (The PeptideCLM v1 bioRxiv/PMC11326283 page was blocked by a bot check, so v1 overlap is unverified.)

## 3. How to query the big repositories (recipes; not executed here)

All are RDKit-based and run on the downloaded flat files; none require executing downloaded code.
- Macrocycle: any ring of size >= 12 in the smallest-set-of-smallest-rings (SSSR) is not sufficient because fused polycycles can hide large rings; use a SMARTS `[r{12-}]` on atoms in a ring of 12+ members (RDKit supports `r{12-}`), and additionally compute ring sizes via the symmetrised SSSR plus a bond-removal macrocycle detector for bridged cases. Keep ring size 12-40 as "macrocycle"; flag >40 separately.
- Peptide: at least 3 amide bonds in a contiguous alpha-backbone motif `[NX3][CX4][CX3](=O)[NX3][CX4][CX3](=O)[NX3]` (with `[CX4]` replaced by `[CX4,CX3]` to admit dehydro residues, and `[N;H0,H1]` for N-methyl). Peptidomimetic filters (heavy atoms 25-250, MW 400-3,000).
- Cyclic peptide: peptide motif above AND ring size >= 12 containing at least 3 backbone amides (computed with substructure match on the ring atom set).
- ChEMBL: apply on the SQLite `compound_structures` table; no API needed. PubChem: apply on the bulk SMILES; do the cheap heavy-atom and amide-count prefilter before RDKit parse. I did not measure the resulting counts.

## 4. Augmentation strategies and risks

1. **Linear to cyclic conversion of UniProt/SmProt/ESMAtlas/DBAASP sequences** (head-to-tail lactam, side-chain-to-tail lariat via Lys/Asp/Glu, disulfide Cys-Cys, thioether). Source of scale. Risk: most random linear sequences do not cyclise well or exist; the model learns syntax and topology tokens, not realistic chemistry. Mitigation: constrain to length 4-15, chemically valid motifs only, label the provenance token ("synthetic-cyclised"), and cap its share (Section 5). PeptideCLM v1's own ring-closure bug is a warning: validate every SMILES by round trip (parse, canonicalise, count rings, compare intended ring size).
2. **Enumerated macrocyclisations** of linear precursors (RCM, lactamisation, click, Suzuki-style macrocyclisation templates applied by reaction SMARTS to ChEMBL/ZINC fragments; Enamine Macro Space is an example of a scaffold-pairing approach with 180,000 products). Risk: reaction-template products reflect the template, not what chemists make; overweighting teaches the template.
3. **Residue substitution from the NORINE/CycPeptMPDB monomer tables** (replace L by D, add N-methyl, swap for a known ncAA monomer). These produce valid, plausible edits but are not measured compounds. Risk (high for our downstream task): stereo flips and N-methyl shifts have large, context-dependent effects on permeability; if the augmented molecule is used with a copied label, you manufacture false labels. For pretraining (no labels), this is acceptable; do NOT use this for supervised fine-tuning without measured matched pairs. Also do NOT build "edit augmentation from known matched-pair effects" into pretraining targets: that injects the benchmark's SAR into the corpus and is a leakage vector.
4. **SMILES randomisation** (non-canonical atom order) for all real structures: low risk, standard, but ring-closure digit reuse differs by ordering, so make it consistent with our topology tokens; keep stereo tags intact (re-validate chirality after reordering).
5. **CREMP 3D to 2D** is already 2D enumerated; no extra value beyond the 36k unique topologies.

General risk: synthetic-heavy corpora can drive validation loss down (easy templated structure) while adding nothing for held-out real chemistry. Track a real-only validation split (NPAtlas+Macrocycle-DB+DBAASP-cyclic, scaffolds not seen) and stop on that, not on overall loss.

## 5. Ranked recipe

Target: about 3.0M training structures, of which at least 1.0M are peptide/macrocycle (as defined in Section 3). Counts for real sources are caps from verified totals; "expected" after dedupe and filters is my estimate and is flagged as such.

| Rank | Source | Role | Target count | Basis |
|---|---|---|---|---|
| 1 | Existing ChEMBL 2.87M subset (already used) | Backbone chemistry; macrocycle/peptide subset upweighted | keep 1.0M random + all macrocycles/peptides | ours |
| 2 | PeptideCLM Zenodo generated peptides v1.1 (CC BY 4.0) | Scale for peptide syntax/cyclisation | sample 600k (of about 10M), after RDKit validation and sampling check for ncAA/stereo content | verified size 10M |
| 3 | PubChem peptide/macrocycle subset (Section 3 filters) | Real, diverse peptide-like and macrocyclic compounds | up to 500k (uncapped by me; needs measurement) | UNVERIFIED subset size |
| 4 | COCONUT 2.0 (macrocycle subset, plus all for natural-product chemistry) | Real stereo-rich macrocycles | macrocycles (measure, ~20k est.) + 100k random | 695,133 verified |
| 5 | NPAtlas 3.0 (check non-commercial licence first) | Real NRPS/RiPP macrocycles | all 36.5k | verified |
| 6 | Macrocycle-DB (check licence) | Drug-like macrocycles | all 45.5k (dedupe vs ChEMBL) | verified |
| 7 | NORINE + DBAASP cyclic + APD + THPdb2 | ncAA and cyclic natural peptides | all that can be converted to SMILES (low thousands) | partly verified |
| 8 | PDB peptide entities incl. cyclic and ncAA (CC0) | Real topology/ncAA | all unique (measure) | UNVERIFIED count |
| 9 | Linear-to-cyclic augmentation from UniProt/SmProt (CC BY 4.0 UniProt; SmProt licence unverified) | Topology diversity | 300k, capped at 10% of peptide/macrocycle share | generated |
| 10 | Enumerated macrocyclisation (Section 4.2) | Macrocycle breadth | 200k, capped | generated |
| - | Residue-substitution augmentation (Section 4.3) | ncAA/N-Me/D coverage | 100k, label-free only | generated |
| - | CREMP 36k topologies | Systematic 4-6-mer coverage | exclude the CycPeptMPDB-linked subset; use rest | verified |

Excluded: CycPeptMPDB (evaluation), CREMP-CycPeptMPDB subset (3,258 macrocycles from CycPeptMPDB), Peptipedia (licence not usable commercially; also canonical), PeptideCLM-2's PubChem re-use unless re-filtered.

Real-versus-synthetic balance of the peptide/macrocycle portion: a real core (items 1 macrocycle share, 3-8) of order 0.3-0.7M after dedupe (my estimate; depends on the PubChem pull), plus synthetic (2, 9, 10) of order 1.1M. Training sampling should weight real sources 2-3x per epoch so real:synthetic effective exposure is about 1:1.

**Minimum viable corpus**: about 1.0M unique peptide/macrocycle structures of which at least 300k are real (PubChem/ChEMBL/COCONUT/NPAtlas/Macrocycle-DB/PDB), plus the 1.0M ChEMBL background. Below 300k real macrocycles the corpus is dominated by synthetic syntax and I would not expect it to fix the 1.7% problem in a meaningful way. This is a judgement, not a measured threshold; test it with a corpus-size ablation (e.g., 100k, 300k, 1M) scored on the real-only validation split, not the held-out folds.

## 6. Deduplication and leakage filtering

Order of operations (all with RDKit; deterministic):
1. Standardise: strip salts/solvents, neutralise charges, keep the largest fragment, canonical SMILES; keep stereo. Keep atom-mapped ring-closure tokens only in our tokeniser stage, not in the dedupe key.
2. Flat-structure dedupe: key = InChIKey first block (14 characters, connectivity) or canonical SMILES with stereo removed. Keep one record per flat key for the "diversity" pool; keep stereoisomers as separate entries in a second pass (stereo-aware key = full InChIKey, or canonical isomeric SMILES) for the stereo-aware pool, since stereo differences are what the model must learn and COCONUT 2.0 deliberately keeps them (82k+539k+74k).
3. Tautomer/charge normalisation applied before keying, so zwitterion forms do not escape the filter.
4. Held-out filtering: for every compound in every held-out fold (CycPeptMPDB folds plus any other evaluation set), remove from the pretraining corpus (a) all entries with the same flat key, (b) all entries with Morgan (radius 2, 2048 bit) Tanimoto >= 0.9 to any held-out compound, and (c) all stereoisomers/N-methyl/ring-size analogues falling under (b). Also apply to a lowered backup threshold (Tanimoto >= 0.8) as a reported sensitivity analysis, because PeptideCLM-2 reports 8.06% structural overlap for CycPeptMPDB without such filtering, so expect a comparable fraction (about 8%) to be removed from a PubChem-heavy pull; if our removal fraction is far lower than that, check the filter.
5. Fingerprint choice: because Morgan fingerprints are weak for large peptides that differ by one residue, add a second filter on the monomer/HELM level where available (same sequence of monomers with different cyclisation), and a sequence-identity filter for DBAASP/UniProt/PDB sources against held-out sequences.
6. Scaffold/cluster sanity check: report the nearest-neighbour Tanimoto distribution corpus-to-held-out before and after filtering. The post-filter maximum must be < 0.9 by construction; report the 99th percentile.
7. Synthetic augmentations are generated from already-filtered parents and then re-filtered (an augmented child can land within 0.9 of a held-out compound).
8. Record provenance and licence per row (source, version, licence tag) so non-commercial sources (NPAtlas, Peptipedia) can be dropped for a commercial model without rebuilding.

## 7. UNVERIFIED items (not opened, or page did not state; not relied on for numbers)

- PubChem peptide/macrocycle subset size; PubChem bulk-download layout (page blocked by bot check).
- ChEMBL release compound count and the macrocycle/peptide subset count (page did not state counts).
- Macrocycle-DB licence; NORINE licence and exact current count (the 1,744 / 526 figures are from a search summary mixing multiple papers); DBAASP licence and SMILES download availability; DBAASP and APD counts are from search summaries, not the primary pages (DBAASP homepage showed zero placeholders); APD licence.
- SmProt licence; THPdb2 licence; PepBDB total; Propedia counts.
- PDB peptide-entity and cyclic-peptide counts; Chemical Component Dictionary licence.
- ZINC22 / Enamine REAL macrocycle counts and download terms; Enamine Macro Space download availability.
- Display-library (phage, RaPID, DEL) open sequence sets: none found.
- COCONUT macrocycle fraction (not reported in the paper I opened; the 2.8% natural-product figure is from a generic search snippet about a different 130,000-compound set).
- PeptideCLM v1 overlap with CycPeptMPDB (v1 paper page blocked); whether PeptideCLM "RandPept" strings contain ncAAs, N-methylation, or D residues.
- CycPeptMPDB licence from the site itself (the site failed to open; licence is from the paper).
- COCONUT licence discrepancy: CC0 on the download page vs CC BY in the paper.

## 8. URLs opened (or search-summarised)

Opened: https://github.com/AaronFeller/PeptideCLM ; https://huggingface.co/aaronfeller/PeptideCLM-23M-all ; https://zenodo.org/records/14194469 ; https://pmc.ncbi.nlm.nih.gov/articles/PMC12803269 ; https://pmc.ncbi.nlm.nih.gov/articles/PMC10091415/ ; https://pmc.ncbi.nlm.nih.gov/articles/PMC11316032/ ; https://pmc.ncbi.nlm.nih.gov/articles/PMC11701633/ ; https://coconut.naturalproducts.net/download ; https://www.npatlas.org/download ; https://www.ebi.ac.uk/chembl/ ; https://pmc.ncbi.nlm.nih.gov/articles/PMC11734279/ ; https://www.rcsb.org/pages/policies ; https://tagteam.harvard.edu/hub_feeds/4353/feed_items/17195942 ; https://dbaasp.org/home.
Search-summary only (not opened): NORINE, DBAASP v3 and cyclic counts, APD3/APD6, THPdb2, SmProt 2, NPAtlas 3.0 count, PubChem 2025 update, UniProt licence, Enamine Macro Space, PeptideCLM-2 headline size.
Blocked/failed: cycpeptmpdb.com (SSL), Nature CREMP page (redirect), PubChem downloads (bot check), UniProt licence page, PMC11326283 (bot check), DBAASP/IMTECH (connection refused).
