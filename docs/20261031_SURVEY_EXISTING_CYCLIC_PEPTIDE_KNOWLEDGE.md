# Survey: existing cyclic-peptide / macrocycle knowledge collections (2026-10-31)

Question from the owner: "isn't there an existing collection of such knowledge? are we the first to collect it?"

Method and honesty rules. Web reading only. The primary record for each item was opened through Europe PMC's REST API (title, authors, journal, year, DOI, abstract) or the publisher/PMC page. Many pmc.ncbi.nlm.nih.gov pages returned a reCAPTCHA wall, so for those items only the abstract is verified, not the full-text details (file formats, sizes, last-update). Wherever a detail was not seen in an opened primary record it is marked "not verified". Database web sites were not all reachable (cycpeptmpdb.com failed with an SSL error), so access routes are stated only where the paper says so. Anything I could not open is in the UNVERIFIED section at the end. Licences are not discussed, per instruction.

Knowledge types: A = structure-property rules (permeability, solubility, stability, N-methylation, conformations, intramolecular H-bonds). B = target-structure knowledge (peptide-protein complexes, binding modes, interfaces). C = prior-work knowledge (design campaigns, benchmarks, hit rates, method comparisons, surveys).

---

## 1. Inventory

### 1.1 CycPeptMPDB (A)
- Citation: Li J, Yanagisawa K, Sugita M, Fujie T, Ohue M, Akiyama Y. CycPeptMPDB: A Comprehensive Database of Membrane Permeability of Cyclic Peptides. J Chem Inf Model 2023. DOI 10.1021/acs.jcim.2c01573. URL http://cycpeptmpdb.com (site fetch failed with SSL error; paper abstract opened via Europe PMC).
- Contents (abstract): 7,334 cyclic peptides with structure and measured membrane permeability, from 45 papers and 2 pharma patents. Uniform sequence representation in HELM. Online visualisation, analysis, download.
- Assays: the abstract does not list assays. A later paper (Frontiers Bioinf 2025, DOI 10.3389/fbinf.2025.1566174) reports models for PAMPA, Caco-2, RRCK and MDCK endpoints on this data, so those four assay types are in the database (inferred from that abstract, not from the CycPeptMPDB page).
- Type: A (permeability only). Access: web, download feature (format not verified). Last update: not verified (my "7,451" figure from memory was NOT confirmed; only 7,334 is verified).
- Limitations: permeability only, no stability/solubility; assay heterogeneity across 45 sources; mostly sub-1500 Da synthetic peptides from a few groups (Lokey/Kihlberg-type series) - bias statement is my inference, not verified. Lamers (J Med Chem 2026, DOI 10.1021/acs.jmedchem.6c00507) is titled "The Biggest Challenge for Prediction of Membrane Permeability of Cyclic Peptides: Scarce Data Availability" - an independent confirmation that data volume is the bottleneck.
- Import: HELM -> RDKit via HELM toolkit or the SMILES column; join key InChIKey (computed) and the source-paper DOI. Effort: 1-2 days (download, normalise assay units, harmonise PAMPA/Caco-2/RRCK/MDCK onto log Papp with an assay flag).

### 1.2 CREMP (A, conformations)
- Citation: Grambow CA, Weir H, Cunningham CN, Biancalani T, Chuang KV. CREMP: Conformer-rotamer ensembles of macrocyclic peptides for machine learning. Sci Data 2024. DOI 10.1038/s41597-024-03698-y. Opened via PMC11316032.
- Contents: 36,198 unique 4-, 5-, 6-mer homodetic macrocyclic peptides, about 31.3 M unique geometries (CREST, GFN2-xTB, chloroform ALPB, 6 kcal/mol window; ~3.9 M CPU-h). Plus 3,258 6-, 7-, 10-mer macrocycles with experimental permeability (from CycPeptMPDB), about 8.7 M conformers.
- Access: Zenodo 10.5281/zenodo.7931444 (main), 10.5281/zenodo.10798261 (permeability subset); GitHub Genentech/cremp. Formats: Python pickle (RDKit >= 2022.09.5) or SDF + JSON. Size not verified.
- Limits (paper): homodetic, 4-10 residues; canonical L/D residues with optional N-methyl; chloroform implicit only, weaker for aqueous.
- Import: SDF reader; join via sequence name and InChIKey to CycPeptMPDB. Effort: 1 day for permeability subset; main set is large (storage planning).

### 1.3 SweMacrocycleDB - nonpeptidic macrocycle permeability (A)
- Citation: Feng Q, De Chavez D, Kihlberg J, Poongavanam V. A membrane permeability database for nonpeptidic macrocycles. Sci Data 2025. DOI 10.1038/s41597-024-04302-z. URL https://swemacrocycledb.com/.
- Contents: 5,638 permeability datapoints for 4,216 nonpeptidic macrocycles from literature, patents, bioactivity repositories; introduces the "amide ratio" descriptor separating peptidic / semipeptidic / nonpeptidic.
- Type A. Access: web (download format not verified). Import: SMILES -> InChIKey; effort 1 day. Complements CycPeptMPDB (the two together cover the peptidic to nonpeptidic spectrum).

### 1.4 Macrocycle-DB (A + B)
- Citation: Jiang M, Liu T, Hussain M, Luo Y, Zheng R, Hou T, Lu X, Zhou Y. Macrocycle-DB: a comprehensive database for macrocycle-based drug discovery. Nucleic Acids Res 2026 (54, D1469-D1476). DOI 10.1093/nar/gkaf1107. URLs https://macro-db.dpbio.tech/ , https://macro-db.cn/.
- Contents (abstract): 45,525 macrocycles incl. 76 approved drugs and 105 clinical candidates targeting 2,533 proteins; structures, bioactivity, physchem properties, co-crystal structures for protein-ligand interactions, scaffold/linker descriptors, downloadable datasets.
- Type: A (physchem), B (co-crystal links). Not specific to peptides (synthetic macrocycles included; peptide share not verified). Access: web + downloadable datasets (format not verified).
- Import: SMILES/InChIKey, PDB ids for co-crystals. Effort: 1-2 days. Most useful B-side source for macrocycle-protein structures with bioactivity.

### 1.5 CyclicPepedia (knowledge base) - answers the "dedicated KB" question
- Citation: Liu L, Yang L, Cao S, Gao Z, Yang B, Zhang G, Zhu R, Wu D. CyclicPepedia: a knowledge base of natural and synthetic cyclic peptides. Brief Bioinform 2024. DOI 10.1093/bib/bbae190. URL https://www.biosino.org/iMAC/cyclicpepedia/ (URL from search result; the paper's PMC page was walled).
- Contents (abstract): 8,744 cyclic peptides; sources, classifications, structural features, pharmacokinetic profiles, physicochemical properties, patented applications, key publications; retrieval system and calculators. Search result adds browse pages for sources, functions, families, targets, references, DrugBank (from a search snippet, not verified in the paper).
- Type: A (breadth, shallow), C partially (literature links), B (targets listed). It is the closest thing to a "cyclic-peptide knowledge base", but it is an entity database (peptide -> metadata), not a rules/design-lessons layer. Download route not verified.
- Import: scrape/export, InChIKey join. Effort 2-3 days (depends on export availability).

### 1.6 PepBDB (B)
- Citation: Wen Z, He J, Tao H, Huang SY. PepBDB: a comprehensive structural database of biological peptide-protein interactions. Bioinformatics 2019. DOI 10.1093/bioinformatics/bty579. URL http://huanglab.phys.hust.edu.cn/pepbdb/.
- Contents: cleaned peptide-protein complexes from PDB, peptides < 50 residues, monthly update (stated in the article). A secondary source (Database Commons, search snippet) gives 13,299 complexes, last update March 2020; NOT verified from the primary.
- Type B. Not cyclic-specific. Import: PDB ids -> PDB files, filter cyclic by connectivity (CONECT/LINK or ring closure) ourselves. Effort 2-3 days incl. cyclic filter.

### 1.7 Propedia v2.3 (B)
- Citation: Martins P, Mariano D, Carvalho FC, Bastos LL, Moraes L, Paixao V, de Melo-Minardi RC. Propedia v2.3. Front Bioinform 2023. DOI 10.3389/fbinf.2023.1103103. URL http://bioinfo.dcc.ufmg.br/propedia2/ (opened PMC9978205).
- Contents: >49,300 peptide-protein complexes from PDB (accessed 15 Nov 2022), peptides 2-50 residues, six functional subsets (antimicrobial, enzyme, hormone, membrane, plant, viral); graph-based structural signatures (aCSM-ALL, 3,600 features). Type B. Not cyclic-specific. Import: PDB-id driven, effort 2 days.

### 1.8 BioLiP2 (B)
- Citation: Zhang C, Zhang X, Freddolino L, Zhang Y. BioLiP2: an updated structure database for biologically relevant ligand-protein interactions. Nucleic Acids Res 2024;52:D404-D412. DOI 10.1093/nar/gkad630. URL https://zhanggroup.org/BioLiP (opened OUP page).
- Contents: 385,160 protein chains, 781,684 protein-ligand interactions; peptide ligands ~4% of interactions; ~50,064 interactions with binding affinity (BindingDB, Binding MOAD, PDBbind-CN, manual curation); weekly updated. Full sequences for peptide ligands in BioLiP2.
- Type B. Best bulk source for PDB peptide-ligand + affinity join. Import: download flat files, filter ligand type = peptide, ring-closure test for cyclic. Effort 2 days.

### 1.9 PDBbind
- Primary page not opened (Europe PMC returned only third-party use papers). Facts verified only from secondary: BioLiP2 abstract names PDBbind-CN as an affinity source. A 2025 Database paper (Gans et al., DOI 10.1093/database/baaf061) reports ~19% of PDBbind protein-protein records had Kd values not supported by their primary publications - a quality warning for the peptide-affinity subset. Counts: UNVERIFIED.

### 1.10 DBAASP v3 (A/C for antimicrobial peptides; includes cyclic subset)
- Citation: Pirtskhalava M et al. DBAASP v3. Nucleic Acids Res 2021. DOI 10.1093/nar/gkaa991. Abstract: >15,700 entries; sequences, chemical modifications, 3D structures, activity, toxicity. Also: Alimbarashvili E et al. Small Natural Cyclic Peptides from DBAASP Database. Pharmaceuticals 2024, DOI 10.3390/ph17070845 (analysis of cyclic peptides <= 25 aa: composition, cyclisation bonds, targets, mechanisms).
- Type: antimicrobial/toxicity only, little permeability/target-structure value for our scope. Effort to import cyclic subset: 1 day.

### 1.11 Norine (A/C, natural nonribosomal peptides)
- Citations: Flissi A et al. Norine: update of the nonribosomal peptide resource. NAR 2020, DOI 10.1093/nar/gkz1000 (539 new entries added); Pupin M et al. Synth Syst Biotechnol 2016, DOI 10.1016/j.synbio.2015.11.001 (1160+ annotated peptides). URL https://norine.univ-lille.fr/norine (from 2023 chapter, DOI 10.1007/978-1-0716-3214-7_16). Natural NRPs incl. many cyclic; structure-based search. Current total count: not verified. Effort 1 day.

### 1.12 NPAtlas 3.0 (natural products, not peptide-specific)
- Poynton EF et al. The Natural Products Atlas 3.0. NAR 2025, DOI 10.1093/nar/gkae1093: 36,545 microbial compounds, 1,347 papers curated for this update. Peptides are a subset; no permeability. Useful as natural-macrocycle structure source only. Effort 1 day.

### 1.13 Peptipedia (sequence-level, mostly linear)
- Quiroz C et al. Database 2021, DOI 10.1093/database/baab055: 30 databases merged, 92,055 sequences. Peptipedia v2.0: Cabas-Mora G et al. Database 2024, DOI 10.1093/database/baae113: +45% sequences, 90+ activity classifiers, 3.6 M sequences annotated by model. Sequence/activity only; no 3D or cyclisation focus. Not useful for A/B cyclic knowledge.

### 1.14 StraPep, CPPsite 2.0, THPdb, ConjuPepDB (peripheral)
- StraPep (Wang J et al., Database 2018, DOI 10.1093/database/bay038; http://isyslab.info/StraPep): structure database of bioactive peptides (abstract opened lacks counts - not verified).
- CPPsite 2.0 (Kardani K, Bolhassani A. J Mol Biol 2021, DOI 10.1016/j.jmb.2020.11.002): validated cell-penetrating peptides with predicted secondary and tertiary structures.
- THPdb (Usmani SS et al. PLoS One 2017, DOI 10.1371/journal.pone.0181748): 852 entries; 239 FDA-approved peptide/protein therapeutics and 380 variants; from 985 papers, 70 patents.
- ConjuPepDB (Balogh B et al. NAR 2021, DOI 10.1093/nar/gkaa950): peptide-drug conjugates; abstract not opened beyond title.
- All mostly linear/therapeutic; low relevance, use as cross-references only.

### 1.15 Peptide representation corpora
- PepLand: Zhang R et al. Brief Bioinform 2025, DOI 10.1093/bib/bbaf367: pre-trained heterogeneous-graph peptide model incl. non-canonical residues; downstream cell penetrability, solubility, binding affinity. Model/representation, not a knowledge collection. Training-corpus size: not verified.
- PepFlow (bioRxiv 2023, DOI 10.1101/2023.06.25.546443): conformational ensembles of peptides; method.
- Not opened (no record found): PepMNet, PepPrCLIP, PepBench-style benchmark; listed under UNVERIFIED.

### 1.16 Rule/review literature (A) - opened abstracts
| Citation | DOI | Content |
|---|---|---|
| Doak BC, Over B, Giordanetto F, Kihlberg J. Oral druggable space beyond the rule of 5. Chem Biol 2014 | 10.1016/j.chembiol.2014.08.013 | Analysis of oral drugs/candidates > 500 Da; intramolecular H-bonds, macrocyclisation, formulation as enablers |
| Over B et al. Structural and conformational determinants of macrocycle cell permeability. Nat Chem Biol 2016 | 10.1038/nchembio.2203 | > 200 synthetic macrocycles; functional groups/properties/3D conformations driving permeability; design approach for non-peptidic macrocycles |
| Naylor MR et al. Lipophilic permeability efficiency (LPE). J Med Chem 2018 | 10.1021/acs.jmedchem.8b01259 | Metric reconciling lipophilicity vs permeability/solubility for peptidic/macrocyclic drugs |
| White TR et al. On-resin N-methylation of cyclic peptides. Nat Chem Biol 2011 | 10.1038/nchembio.664 | Selective backbone N-methylation; hexapeptide with 28% rat oral bioavailability |
| Hosono Y et al. Amide-to-ester substitution as alternative to N-methylation. Nat Commun 2023 | 10.1038/s41467-023-36978-z | Ester substitution raises permeability; NMR + simulation |
| Rossi Sebastiano M et al. Computational physicochemical properties Ro5 to bRo5. J Med Chem 2022 | 10.1021/acs.jmedchem.2c00774 | Chameleonicity, IMHB, conformational ensembles for bRo5 ranking |
| Ermondi G et al. Solubility prediction in bRo5 chemical space. ADMET DMPK 2020 | 10.5599/admet.834 | Review of solubility modelling; flexibility/chameleon behaviour matters |

These are narrative knowledge in papers, not structured collections. Rezai 2006, Furukawa 2020, Kihlberg reviews beyond the above: UNVERIFIED (searches returned nothing).

### 1.17 Prior-work / design (C)
- Rettie SA et al. Accurate de novo design of high-affinity protein-binding macrocycles using deep learning (RFpeptides). Nat Chem Biol 2025. DOI 10.1038/s41589-025-01929-w: <= 20 designs per target against four targets gave medium-to-high affinity binders for all; one Kd < 10 nM; crystal structures within 1.5 A C-alpha RMSD of design.
- Rettie SA et al. Cyclic peptide structure prediction and design using AlphaFold (AfCycDesign). bioRxiv 2023, DOI 10.1101/2023.02.25.529956: 36 of 49 native structures predicted at RMSD < 1.5 A; ~10,000 designs for 7-13-mers; seven validated within 1.0 A.
- Zhang C et al. HighFold. bioRxiv 2023, DOI 10.1101/2023.08.27.554979: AlphaFold variant for cyclic peptide monomers/complexes.
- Permeability-prediction method papers (opened): MultiMol (IEEE JBHI 2026, DOI 10.1109/jbhi.2026.3717785), CPMP (Front Bioinform 2025, R2 0.67 PAMPA, 0.75/0.62/0.73 Caco-2/RRCK/MDCK), MSF-CPMP (CSBJ 2025, accuracy 0.9062, AUROC 0.9546), MD+ML protocol (ACS Omega 2026, 252 peptides, R 0.77). These show repeated modelling on the same CycPeptMPDB data with non-comparable splits; no common benchmark was found.
- No structured collection of design campaigns, hit rates or method comparisons for cyclic peptides was found in any opened record. Review/benchmark searches on Europe PMC for "cyclic peptide design review/benchmark" returned zero hits (search limitation possible; this is absence of evidence, not proof).

---

## 2. Coverage matrix (X = substantively covered by the resource; p = partial/indirect; blank = not covered; based on opened records only)

| Subtopic | CycPeptMPDB | CREMP | SweMacroDB | Macrocycle-DB | CyclicPepedia | PepBDB | Propedia | BioLiP2 | DBAASP/Norine | Reviews (Doak/Over/Naylor...) | Design papers (RFpeptides etc.) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 Permeability (measured) | X (7,334) | p (3,258 subset) | X (nonpeptidic, 4,216) | p | p | | | | | p (rules) | |
| A2 Solubility | | | | p (physchem) | p (physchem) | | | | | p | |
| A3 Metabolic / serum stability | | | | | p ("PK profiles") | | | | | p | |
| A4 N-methylation / backbone modification effects | p (inferable from sequences) | p (N-Me residues in model set) | | | | | | | | X (White 2011, Hosono 2023) | |
| A5 Conformational ensembles | | X (31 M, chloroform xTB) | | | | | | | | p | p (AfCycDesign) |
| A6 Intramolecular H-bonds / chameleonicity | | p | | | | | | | | X (Doak, Rossi Sebastiano) | |
| A7 Design rules, explicit | | | | | | | | | | p (narrative) | |
| B1 Peptide-protein complexes (PDB) | | | | p (co-crystals) | p (targets) | X | X (49,300) | X (peptide ~4% of 781,684) | | | |
| B2 Cyclic-specific complexes | | | | p (macrocycle co-crystals) | | p (filter needed) | p (filter needed) | p (filter needed) | | | |
| B3 Binding affinity paired to structure | | | | p | | | | X (~50,064) | | | |
| B4 Hotspots / interface rules | | | | | | | p (signatures) | | | | |
| C1 Design campaigns / hit rates | | | | | | | | | | | p (isolated papers) |
| C2 Benchmarks / method comparison | | | | | | | | | | | p (ad hoc per paper) |
| C3 Surveys | | | | | | | | | | p (permeability only) | |
| Natural cyclic peptides (sources, activity) | | | | | X (8,744) | | | | X | | |

---

## 3. Gaps nobody (in the records opened) covers
1. A unified, join-keyed layer linking sequence/structure -> measured property -> conformation -> target complex -> design outcome. Every resource is a silo with its own identifiers (HELM, SMILES, PDB id, internal ids).
2. Structured explicit design rules (e.g. "N-Me at position i of a hexapeptide changes Papp by x") with evidence provenance; only narrative text in reviews.
3. Cyclic-specific peptide-protein complex set with cyclisation type, ring size, binding mode annotation; PDB-wide peptide sets are not cyclic-filtered.
4. Stability (proteolytic, serum, microsomal) and solubility data for cyclic peptides: not found as a dedicated collection.
5. Design-campaign outcomes: per-target numbers of designs tested, hit rates, affinities, failures, method comparisons. Only scattered in papers (e.g. RFpeptides abstract). Negative results are essentially absent.
6. Common benchmark with standard splits for cyclic permeability / design; each prediction paper builds its own.
7. Hotspot/interface resources specific to macrocycle binders.

## 4. Recommendation: IMPORT vs BUILD
IMPORT (parsers + join on InChIKey / PDB id; estimated total 8-12 person-days):
- CycPeptMPDB (A1) and SweMacrocycleDB (A1, nonpeptidic) - primary property tables.
- CREMP permeability subset (A5), main set only if needed for conformer-based features.
- Macrocycle-DB (B/A, bulk macrocycle bioactivity + co-crystal PDB ids).
- BioLiP2 filtered to peptide ligands + ring-closure test (B1-B3); PepBDB/Propedia only as cross-checks (they derive from the same PDB source).
- CyclicPepedia for natural/synthetic cyclic peptide metadata and literature pointers (verify export route first).
- Norine for natural NRPs if natural-product precedent is wanted.
Skip: Peptipedia, StraPep, CPPsite, THPdb, ConjuPepDB, DBAASP beyond cyclic subset, NPAtlas (not matched to scope), PepLand (model, not data).

BUILD (nobody has it; this is our value):
- Curated, evidence-linked design-rule layer (A4, A6, A7): each rule with source DOI, assay, size range, effect size, applicability limits.
- Cyclic-specific complex annotation over BioLiP2/PDB (B2, B4): cyclisation chemistry, ring size, hotspot and contact pattern.
- Prior-work/campaign ledger (C1-C3): per method and target, designs tested, hits, affinities, failures, with PDF-page provenance.
- Stability and solubility data harvest from the literature (A2, A3), since not collected.
- A shared benchmark split definition over imported data.
Every built item must carry source citations; numbers from source, not memory.

## 5. Are we the first?
No for the entity and measurement layers: CycPeptMPDB (permeability, 7,334 peptides), CREMP (conformer ensembles), SweMacrocycleDB, Macrocycle-DB (45,525 macrocycles), CyclicPepedia (8,744 cyclic peptides, a dedicated knowledge base) and PDB-wide peptide-complex databases (PepBDB, Propedia, BioLiP2) already exist, and review papers (Doak 2014, Over 2016, Naylor 2018) already state the permeability rules in prose. Based on what I could open, we would be first only on the integrated layer: machine-usable, evidence-linked design rules; cyclic-specific complex annotation; and a design-campaign / benchmark ledger. I found no such collection, but my searches were limited (Europe PMC title searches plus a few web searches), several pages were inaccessible, and "not found" is not proof of absence. Do not claim "first to collect cyclic-peptide knowledge" externally; claim at most "first integrated, evidence-linked layer joining these resources" and only after a deeper literature check.

---

## UNVERIFIED (could not open a primary record; do not cite)
- CycPeptMPDB-4D (no record found; may not exist under that name).
- CycPeptMPDB total of 7,451 and any post-2023 version counts.
- PDBbind primary paper and peptide-subset counts.
- PepMNet, PepPrCLIP, PepBench (peptide-design benchmark), PepGLAD (search returned only unrelated "PEPbench").
- Rezai 2006 (JACS), Furukawa 2020 (J Med Chem), further Kihlberg/Lokey reviews (Europe PMC queries returned no match; not opened).
- ChEMBL macrocycle/peptide subset analyses (query returned nothing relevant).
- PDB cyclic-peptide ligand sets as a standalone curated resource.
- PepBDB's 13,299-complex count (secondary source only).
- Download formats, sizes and last-update dates for CycPeptMPDB, SweMacrocycleDB, Macrocycle-DB, CyclicPepedia, StraPep.
- Peptide ligand share in Macrocycle-DB; StraPep and ConjuPepDB counts.
