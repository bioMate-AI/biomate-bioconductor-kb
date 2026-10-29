# A provenance-linked knowledge layer for cyclic-peptide design: survey of existing collections, gap analysis and construction

## Abstract

Design systems for cyclic peptides, including language-model-based generators, need machine-usable knowledge: how structure relates to permeability, stability and solubility; how cyclic peptides bind their targets; and what earlier design campaigns achieved. We introduce an integrated, provenance-linked knowledge layer for cyclic-peptide design that joins structure-property, target-structure and prior-work knowledge under one schema, shared join keys and evidence tiers, and we build it with a construction pipeline in which every extracted statement is verified by deterministic exact-quote matching against the retrieved source text. The layer draws on imports of existing collections, a hand-verified gold set of 107 entries (44 rules, 24 fundamentals, 11 cautions and 28 campaign cards from 45 external sources and 5 internal documents, every quote verified verbatim), literature mining at scale, patent mining in a separate evidence tier, and mining of protein-cyclic-peptide complex structures. It carries leak guards for use under held-out evaluation and loaders that turn it into decoding priors and retrieval context for a generative system. A survey of existing collections shows that curated resources cover the entity and measurement layers (for example a 7,334-peptide permeability database and peptide-protein complex databases with more than 49,300 complexes), while structured design rules with provenance, a campaign and benchmark ledger, cyclic-specific complex annotation, and stability and solubility collections were not found in the records we could open; the layer is built to fill those gaps and to link them to the existing resources. Checked against two large permeability sources that were not used to create or weight any entry, 17 rules agree in direction, 7 are mixed and none disagree (83 entries make no testable directional claim); N-methyl count, hydrogen-bond donor count, polar surface area and lipophilicity agree in both sources. A join control in which 3,256 of 3,258 peptides matched supports the shared stereo-aware key.

## 1. Introduction

Cyclic peptides and macrocycles occupy a chemical space between small molecules and biologics. Their permeability, stability and binding depend on conformation, intramolecular hydrogen bonding, backbone modification and stereochemistry in ways that two-dimensional descriptors capture only partly. A design system that proposes, filters and ranks candidates therefore needs more than a trained scorer: it needs rules and facts that can be inspected, cited and corrected.

Three kinds of knowledge matter. Structure-property knowledge covers how permeability, solubility, stability and conformation relate to chemistry (A). Target-structure knowledge covers how cyclic peptides bind their targets, in which conformation and through which contacts (B). Prior-work knowledge covers what earlier design and optimisation campaigns produced, including hit rates and failures (C). For a generative system the same knowledge is used in three ways: as hard constraints on what may be generated, as soft priors that bias generation, and as retrieved context in a prompt. Each use requires that the knowledge be structured, attributable to a source and checkable against it.

Our own earlier knowledge bases were small for this purpose. An internal audit (Section 2.4) found that the peptide-relevant content of the existing bases amounted to a handful of statements, that one flagship rule was mostly a between-laboratory effect, and that three of 57 citations could not be confirmed. Before building more, we surveyed what already exists (Section 2) and used the gaps it exposed to design the layer.

We make two contributions.

1. **An integrated, provenance-linked knowledge layer for cyclic-peptide design.** The layer joins structure-property knowledge, target-structure knowledge and prior-work and campaign knowledge in one schema, with join keys (stereo-aware InChIKey, PDB identifier, DOI) that connect structure or sequence, measured property, conformation, target complex and design outcome, and with evidence tiers that determine what may influence a generator. As parts of the layer, it includes leak guards that keep knowledge derived from evaluation data out of any prior used with that evaluation, and loaders that turn the layer into decoding priors and retrieval context.
2. **A construction pipeline with deterministic exact-quote verification of every extracted statement.** The pipeline combines imports of existing collections, literature mining, patent mining and structure mining; each extracted statement is kept only if its quote is an exact substring of the retrieved source text, so that every statement is attributable to a passage. Patent-derived statements form a separate evidence tier.

We release the schema, builders, loaders and the verified gold set with hashes and access dates.

## 2. Survey of existing resources

### 2.1 Method and verification status

Primary records were opened through the Europe PMC REST interface (title, authors, journal, year, DOI, abstract) or the publisher or PMC page. Several PMC pages returned a verification wall; for those, only the abstract is verified. Where a detail was not seen in an opened record it is marked not verified. Download routes were fetched and the files parsed (Section 5.1), and the downloaded files were compared with the published counts.

### 2.2 Inventory

Counts are those stated in the opened record. The "Downloaded file" column gives the count in the file fetched on 2026-10-29; a difference from the paper is reported, not explained.

| Resource | Type | Content (as stated in opened record) | Downloaded file | Evidence opened |
|---|---|---|---|---|
| CycPeptMPDB (Li et al., J Chem Inf Model 2023, DOI 10.1021/acs.jcim.2c01573) | A | 7,334 cyclic peptides, measured membrane permeability, 45 papers and 2 pharma patents, HELM representation | 8,466 rows, 7,988 unique stereo-aware structures; our local annotation table has 7,991 rows and the same 7,988 structures, so the additional rows are repeated measurements | abstract |
| CREMP (Grambow et al., Sci Data 2024, DOI 10.1038/s41597-024-03698-y) | A | 36,198 homodetic 4-6-mer macrocyclic peptides, about 31.3 M conformers (CREST, GFN2-xTB, chloroform ALPB); plus a 3,258-peptide permeability subset with about 8.7 M conformers | permeability-subset summary: 3,258 rows, 3,256 matched to the local CycPeptMPDB table by full InChIKey and 3,258 by flat key | full text |
| SweMacrocycleDB (Feng et al., Sci Data 2025, DOI 10.1038/s41597-024-04302-z) | A | 5,638 permeability datapoints for 4,216 nonpeptidic macrocycles | `Overall.csv`: 6,585 rows, 4,696 unique structures | abstract |
| Macrocycle-DB (Jiang et al., Nucleic Acids Res 2026, DOI 10.1093/nar/gkaf1107) | A, B | 45,525 macrocycles, 76 approved drugs, 105 clinical candidates, 2,533 targets, co-crystal links | three counts, see below | abstract |
| CyclicPepedia (Liu et al., Brief Bioinform 2024, DOI 10.1093/bib/bbae190) | A, C (shallow) | 8,744 cyclic peptides with sources, classifications, structural features, pharmacokinetic and physicochemical properties, patented applications, key publications | 13 tables and a structure archive; structure table 8,751 rows, 7,040 with a SMILES | abstract |
| PepBDB (Wen et al., Bioinformatics 2019, DOI 10.1093/bioinformatics/bty579) | B | peptide-protein complexes from PDB, peptides under 50 residues, monthly updates; a secondary source gives 13,299 complexes (not verified) | — | abstract |
| Propedia v2.3 (Martins et al., Front Bioinform 2023, DOI 10.3389/fbinf.2023.1103103) | B | more than 49,300 peptide-protein complexes, peptides of 2-50 residues, six functional subsets, graph-based structural signatures | — | full text |
| BioLiP2 (Zhang et al., Nucleic Acids Res 2024, DOI 10.1093/nar/gkad630) | B | 385,160 protein chains and 781,684 protein-ligand interactions; peptide ligands about 4% of interactions; about 50,064 interactions with affinity | — | full text |
| DBAASP v3 (Pirtskhalava et al., Nucleic Acids Res 2021, DOI 10.1093/nar/gkaa991) | A, C (antimicrobial) | more than 15,700 entries with sequences, modifications, structures, activity, toxicity | — | abstract |
| Norine (Flissi et al., Nucleic Acids Res 2020, DOI 10.1093/nar/gkz1000) | A, C (natural) | nonribosomal peptide resource; total count not verified | no bulk route found | abstract |
| Natural Products Atlas 3.0 (Poynton et al., Nucleic Acids Res 2025, DOI 10.1093/nar/gkae1093) | A (natural products) | 36,545 microbial compounds | — | abstract |
| THPdb (Usmani et al., PLoS One 2017, DOI 10.1371/journal.pone.0181748) | C (therapeutics) | 852 entries from 985 papers and 70 patents | — | abstract |
| Peptipedia (Quiroz et al., Database 2021, DOI 10.1093/database/baab055) | sequence/activity | 92,055 sequences from 30 databases | — | abstract |

Peripheral resources (StraPep, CPPsite 2.0, ConjuPepDB) were opened at abstract level and are mostly linear or therapeutic; they serve as cross-references. CycPeptMPDB-4D, a 2026 table of molecular-dynamics descriptors for 5,160 CycPeptMPDB peptides, joins to 4,918 of our labelled peptides but covers only five sources. PDBbind, PepMNet, PepPrCLIP and PepBench could not be opened and are not used.

Counts in papers and in downloaded files need not agree, and a count should be quoted from the file used. The live CycPeptMPDB file contains the same unique structures as our local table (7,988), with more rows because of repeated measurements. The SweMacrocycleDB file has 6,585 rows and 4,696 unique structures against 5,638 datapoints and 4,216 macrocycles in the paper. The CyclicPepedia structure table has 8,751 rows against 8,744 peptides in the abstract. For Macrocycle-DB three numbers appear for related quantities, and what each counts is not documented in the files checked: the abstract reports 45,525 macrocycles; the downloaded `All.csv` has 50,654 rows (47,966 unique structures); and the site's statistics endpoint reports 18,969 macrocycles, 58,310 activities, 2,533 targets and 3,752 PDB structures. We use the file counts for any computation and record the download date and hash of every file used.

### 2.3 Rules and design literature

The rules most used in practice are stated in prose in review and primary articles rather than in structured collections.

| Citation | Content (abstract-level) | Evidence opened |
|---|---|---|
| Doak et al., Chem Biol 2014 (10.1016/j.chembiol.2014.08.013) | oral druggable space beyond the rule of 5; intramolecular hydrogen bonds, macrocyclisation and formulation as enablers | abstract |
| Over et al., Nat Chem Biol 2016 (10.1038/nchembio.2203) | more than 200 synthetic macrocycles; functional groups, properties and conformations that drive permeability | abstract |
| Naylor et al., J Med Chem 2018 (10.1021/acs.jmedchem.8b01259) | lipophilic permeability efficiency, a metric relating lipophilicity to permeability and solubility | abstract |
| White et al., Nat Chem Biol 2011 (10.1038/nchembio.664) | on-resin N-methylation of cyclic peptides; a hexapeptide with 28% rat oral bioavailability | abstract |
| Hosono et al., Nat Commun 2023 (10.1038/s41467-023-36978-z) | amide-to-ester substitution as an alternative to N-methylation | abstract |
| Rossi Sebastiano et al., J Med Chem 2022 (10.1021/acs.jmedchem.2c00774) | chameleonicity and intramolecular hydrogen bonds for ranking beyond-rule-of-5 compounds | abstract |
| Ermondi et al., ADMET DMPK 2020 (10.5599/admet.834) | solubility prediction in beyond-rule-of-5 space | abstract |

Design and prior-work literature: RFpeptides (Rettie et al., Nat Chem Biol 2025, 10.1038/s41589-025-01929-w) reports at most 20 designs per target against four targets, all yielding medium-to-high affinity binders, one with Kd below 10 nM, and crystal structures within 1.5 A C-alpha RMSD of the design (abstract opened). AfCycDesign (bioRxiv 2023, 10.1101/2023.02.25.529956) predicts 36 of 49 native structures within 1.5 A and reports about 10,000 designs for 7-13-mers with seven validated within 1.0 A (abstract opened). HighFold (bioRxiv 2023, 10.1101/2023.08.27.554979) adapts AlphaFold for cyclic peptides (abstract opened). Several permeability-prediction papers model CycPeptMPDB with non-comparable splits (for example CPMP, R2 0.67 for PAMPA); the survey found no common benchmark.

### 2.4 Audit of our earlier internal knowledge bases

An internal audit examined the knowledge bases that preceded this work. Findings that bear on it:

- The experience base with its per-target files (16 targets) holds 151 entry instances, 73 distinct statements, 37 of them active knowledge. The 16 per-target pharmacophore entries reduce to two distinct statements (an RGD/MIDAS statement for four integrin targets and one generic hot-spot sentence for twelve others).
- The medicinal-chemistry base holds 1,585 small-molecule liability alerts and only four peptide-relevant modality statements. A second product-oriented base (45 entries) had no consumer other than tests and eleven entries duplicating the first. An ingested summary file holds counts only (4,225 approved drugs, 7,561 mechanisms) with no peptide-specific content.
- A Crossref check over 57 citations confirmed 54 and flagged 3; the self-asserted `verified` flag was set on all three flagged entries, so it is not a reliable signal. One target structure identifier was mislabelled.
- The 16 target-base targets map to 12 of 793 benchmark targets, to 1 of 46 in the primary analysis, and to 389 of 20,562 positives (1.9%).
- Entries carry no ingestion date, so no leak-safe time slicing is possible.
- A within-source validation harness (five tests) found TPSA, HBD, logP and Veber pass directionally consistent within source, and found the N-methyl count rule inconclusive within source (pooled rho 0.37 falling to a median within-source rho of 0.01, confidence interval -0.13 to 0.28, 9 of 18 sources positive). The harness separates between-laboratory effects from within-laboratory effects, which is why the schema of Section 4 records the assay and the number of supporting sources.

## 3. Gap analysis

Coverage was assessed per subtopic against the resources above (X = substantively covered by an opened record, p = partial, blank = not covered).

| Subtopic | Covered by |
|---|---|
| Measured permeability | CycPeptMPDB (X), SweMacrocycleDB (X, nonpeptidic), CREMP subset (p) |
| Conformational ensembles | CREMP (X, chloroform only) |
| N-methylation and backbone modification effects | review and primary articles (X in prose) |
| Intramolecular hydrogen bonds, chameleonicity | review articles (X in prose) |
| Solubility, serum and metabolic stability | no dedicated collection for cyclic peptides |
| Explicit design rules | prose only |
| Peptide-protein complexes | PepBDB, Propedia, BioLiP2 (X, not cyclic-specific) |
| Cyclic-specific complexes | none (filtering needed) |
| Binding affinity paired to structure | BioLiP2 (X, about 50,064 interactions) |
| Hotspot and interface rules for macrocycle binders | none |
| Design campaigns, hit rates, failures | scattered papers only |
| Benchmarks and method comparisons | ad hoc per paper |

No opened record covers: (1) a join-keyed layer linking structure, measured property, conformation, target complex and design outcome, since each resource uses its own identifiers; (2) structured design rules with evidence provenance; (3) a cyclic-annotated complex set with cyclisation chemistry, ring size and binding-mode annotation; (4) stability and solubility collections for cyclic peptides; (5) a campaign and benchmark ledger including negative outcomes; (6) a common benchmark with standard splits; (7) hotspot and interface resources specific to macrocycle binders.

Patents form a further source. CycPeptMPDB draws on two pharma patents, THPdb on 70 patents, and SweMacrocycleDB and CyclicPepedia list patents among their sources; the number of patent-derived records in each was not established. The pipeline therefore includes a patent stage (Section 5.3) and measures the overlap of its output with existing patent-derived collections.

## 4. The knowledge layer

### 4.1 Schema

The schema defines entries of four kinds: rule (a directional or windowed statement about an outcome), fundamental (a mechanistic statement), caution (a statement about data or method limits) and card (a structured summary of a target or campaign). Required fields are: identifier (pattern `LIT-<TOPIC>-nnn`, `CARD-...` or `INT-...`), kind, statement, direction (plus, minus, multi, window, context, caution or conflict), scope (a list of terms such as ring type and chemistry), outcome (the property concerned), evidence tier, source (PMCID, DOI, title, journal, year, URL; for internal entries a file path), a verbatim quote of at most 30 words, confidence (high, medium, low), access date, extractor, weight and a weight-eligibility flag, a quote-verification flag with the quote offset in the source text, applicable target and structure reference. Optional fields include effect size and units, windows with thresholds, and the computable feature to which the rule maps.

### 4.2 Evidence tiers

| Tier | Definition | Use |
|---|---|---|
| T1 | primary peer-reviewed quantitative study | may carry weight |
| T2 | review, textbook or author background statement | may carry weight |
| T3 | secondary source (encyclopaedic, vendor, aggregator) | retrieval context only |
| T-internal | our own campaign documents (file path as source) | retrieval context only |
| P | patent-derived statement | retrieval context |

Patent-derived content is kept in a separate tier because its quality, claim style and level of verification differ from journal content.

### 4.3 Weight eligibility

An entry may carry a nonzero weight only if all of the following hold: tier T1 or T2; kind rule or fundamental; quote verified by string match; direction in the weighted set (plus, minus, multi, window); and at least one computable feature to which the rule maps. The computable feature set is TPSA, HBD, HBA, MW, cLogP, aLogP, number of rotatable bonds, heavy-atom count, N-methyl count, D-residue count and a cyclic flag. A rule whose natural feature is not computable from two-dimensional structure (for example exposed NH) may map to a proxy feature with its weight halved. Everything else is kept for retrieval context at weight zero. Weights are a uniform prior, 0.10 scaled by the confidence level (high 1.0, medium 0.5, low 0), and zero for conflicts, cautions and context entries; no label from our permeability data is used to create or weight any entry. Seventeen unit tests cover the schema, unique identifiers, provenance, quote verification against the stored text, that an unverified entry never carries a weight, that weights are restricted to T1 and T2 rules with computable features, that cautions and conflicts are weightless, the directional and window behaviour of the potential, that outcome classes are not mixed, that the loader rejects an unverified entry that carries weight, and that two builds give the same hash.

### 4.4 Provenance and citation integrity

Every entry traces to a source that was opened. Full texts are fetched from Europe PMC (open-access XML), arXiv (PDF text) or the repository (internal documents), normalised and stored with a sha256. The builder checks every quote, and every additional quote on cards, as an exact substring of the stored text and sets the verification flag from that match. In the scaled pipeline the rule is the same and stricter in its details: after whitespace normalisation (single spaces, case preserved, nothing else) the quote must be an exact substring of the stored normalised source text, its length must be between 6 and 30 words, any numerical effect size must occur as a digit string in the quote or the passage, and required fields must be present with values in closed vocabularies. An entry failing any check is discarded and never repaired. Controls: 20 synthetic rules with fabricated quotes must all be rejected; 20 quotes with altered words, dropped words or changed numbers must be rejected while 20 quotes differing only in whitespace must be accepted; entries paired with a different paper's text must fail. An exact quote establishes attribution and not that the statement is a correct reading of it; correctness is measured by judged precision on an audit sample (Section 6.3).

### 4.4a Merge, support and contradiction

Equivalent rules (same property, substructure class and direction, and statement token overlap of at least 0.5 on content words) are merged. Support is the number of distinct DOIs. Opposite directions on the same property, substructure class and scope key from different papers set a contradiction flag; contradictions are flagged and never resolved by the pipeline.

### 4.5 Leak guards for held-out evaluation

Knowledge derived from labelled evaluation data must not enter a prior used with that evaluation. Three guards are in place. First, a prior-cleanliness check refuses a prior whose mining sources overlap the sources on which a stop or held-out verifier is fitted; an earlier all-laboratory rule file (mined from all 21 training sources) fails this check against the stop and held-out groups, and a control confirms this. The literature layer is clean by construction because no label is used to create or weight an entry. Second, scaled extraction sets a `possible_benchmark_source` flag when a source paper matches a CycPeptMPDB source name by first author and year, so such rules can be excluded from priors used with held-out verifiers. Third, the consuming system splits the permeability sources into train, stop and held-out groups (Section 7.1), and anything data-derived is mined or tuned on the train group only. The schema stores an access date; the earlier bases did not.

### 4.6 Loaders

The loader provides two outputs. A sequence-level log-linear potential is built from the weight-eligible rules: directional rules contribute weight times sign times the standardised feature, with the mean and spread supplied by the caller from the train group only, and window rules contribute hinge penalties on the stated thresholds, with any-of and maximum-violation semantics for the guideline rules; permeability, stability and solubility rules are never summed into one potential. A second function returns short provenance-tagged snippets for retrieval-conditioned prompts, deterministically. Hard constraints (ring closure, ring size, N-methyl window, molecular-weight bound, structural-alert prefixes) are not data-mined and are compiled separately by the generation system.

## 5. Construction

The layer is built from five content sources, each with its own provenance rules and all sharing the schema of Section 4.1.

### 5.1 Imports of existing collections

The pipeline fetches existing collections and parses them into one canonical table. In the run reported here all 23 files were fetched with HTTP date, size and sha256 recorded, and 22 tables were parsed (the CyclicPepedia structure archive was fetched and not unpacked); there were no file-level parse failures. The files are the CycPeptMPDB peptide and monomer tables (the peptide table 19.07 MB); the SweMacrocycleDB overall table (3.71 MB); the CyclicPepedia spreadsheets (13 tables) and structure archive; the CREMP permeability summary (the 8.3 GB and 11.6 GB conformer archives are not imported); and the Macrocycle-DB static files (the 377 MB structure archive is not imported). Norine has no confirmed bulk route and is not imported.

Each record is parsed into a canonical table (resource, record identifier, SMILES, full and flat stereo-aware InChIKey, assay, value, unit, source reference, DOI); failures are counted and not dropped; joins use the full 27-character RDKit InChIKey and its first block (connectivity only) against the local CycPeptMPDB annotation table (7,991 rows, 7,988 unique full keys, 3,214 unique flat keys) and the live CycPeptMPDB file (8,466 rows, 7,988 unique full keys). Assay values are kept raw.

Join validation. The internal control is the CREMP permeability subset, which was built from CycPeptMPDB: 3,256 of its 3,258 peptides (99.94%) matched the local table on the full key and 3,258 of 3,258 on the flat key. The live CycPeptMPDB file matches the local table on 8,466 of 8,466 rows. This supports the InChIKey join for peptides that RDKit can parse; structures without a parsable SMILES cannot be joined (CyclicPepedia 1,711 of 8,751 rows, 19.6%, have no SMILES; Macrocycle-DB 2 rows) and are counted and kept in the canonical files.

Overlap with CycPeptMPDB is small for every other resource, measured on unique full keys: SweMacrocycleDB 154 of 4,696 (3.3%), Macrocycle-DB `All.csv` 240 of 47,966 (0.5%), CyclicPepedia 53 of 6,617 (0.8%). The imports therefore add chemistry and metadata that CycPeptMPDB lacks; they are not an independent permeability check on the same peptides except for the 154 SweMacrocycleDB structures. CyclicPepedia's metadata tables (sources, functions, families, targets, bioassays, references) are keyed by its own identifiers, which link them to its structure table.

### 5.2 Hand-verified gold set and campaign ledger

The gold set holds 107 entries: 44 rules, 24 fundamentals, 11 cautions and 28 cards. By tier there are 65 at T1, 31 at T2 and 11 internal (no T3). The entries rest on 45 external sources (41 Europe PMC open-access articles and 4 arXiv preprints) and 5 internal documents. All 107 quotes verify verbatim, with no schema problems. By outcome class, 55 entries concern permeability, 10 stability, 2 solubility and 40 other topics; 32 entries are weight-eligible (28 permeability, 1 stability, 1 solubility, 2 other). Topic coverage, where an entry can count in several topics: cyclisation, ring size and bridging 34; size, beyond-rule-of-5 and oral guidelines 24; N-methylation 13; intramolecular hydrogen bonds and chameleonicity 12; lipophilicity, solubility and aggregation 12; stability (proteolysis, serum, deamidation) 12; stereochemistry and D-residues 10; campaign cards 28. Examples of quantitative entries include the macrocycle drug window (HBD at most 7 together with MW below 1000 or cLogP above 2.5) and the non-monotonic dependence of permeability on lipophilicity; data cautions include that in one curated macrocycle permeability database 91% of the PAMPA records come from a single publication.

The campaign ledger is the 28 cards. Seventeen external cards record what was designed, the outcome, failure modes and lessons for RFpeptides, AfCycDesign, BindCraft (proteins), BindCraft for peptides, PepINVENT, HighFold-MeD, PepGLAD, PepTune, PepMLM, CP-Composer, CycDiff-DPO, random cyclic-peptide library screening (Keap1-Nrf2), CycloSEL, two Cyclin A/B macrocycle campaigns (permeability SAR; oral bioavailability), approved and clinical macrocycles, and romidepsin. Eleven internal cards record our own earlier campaigns with file paths: zero-shot affinity ceiling, permeability wall, generator DockQ gap, synthetic-only loop, rules as filter and not generator, multi-objective selection, an unlaunched RFpeptides plan, alphavbeta6 metal-free MM-GBSA, the PD-L1 blockade decision, the SNAT2 prior-art verdict and the alphavbeta6 gold-standard assay spread. Documents that carry intellectual-property content are not indexed. The ledger makes several lessons explicit, each backed by a verified quote: hit rates are reported per target and under incompatible definitions (relative ipTM, Delta-G below 0, affinity, functional readout); peptide design papers rarely report non-binders; BindCraft peptides gave no detectable binding for PD-1/PD-L1 while MDM2 gave 7 of 15; the AfCycDesign pLDDT above 0.85 filter was right for 80% (44 of 55) of predictions; PepGLAD notes that even ground-truth peptides reach only 36% under AF2-consistency evaluation; romidepsin shows that removing a reducible disulfide for stability cost 10-100-fold potency; and permeability-raising N-methylation cost cellular activity and selectivity in matched pairs.

### 5.3 Patent mining

Medicinal-chemistry knowledge on macrocyclic peptides appears in patents as well as in journals. The patent stage of the pipeline extracts knowledge statements from public patent documents: example compounds with sequences or structures and activity values, assay conditions, SAR statements, permeability and ADME data, and binding-mode and design-rationale statements. It performs knowledge extraction only; it makes no freedom-to-operate, claim-scope or validity assessment, and unpublished or internal material is out of scope. Extracted statements carry the separate tier P (Section 4.2).

Sources. Candidate patents are identified from the SureChEMBL bulk snapshot of 2026-05-15 (compound, patent-compound map and patent tables of 3.9 to 5.5 GB). The BindingDB patent subset and Google Patents pages are used for curated SAR, overlap measurement and full text (the patent path permits automated retrieval; requests use a fixed delay and an identifying user agent). PatentsView bulk tables, USPTO bulk data, Espacenet and WIPO PATENTSCOPE were not reachable by automated access, Lens.org requires a token and BigQuery public patents requires a billed project; none is used. Cooperative Patent Classification codes C07K 7/50 to 7/66 for cyclic peptides were verified against the USPTO scheme page; A61K 38/12 could not be verified and is used only as a query hint.

Selection. Candidate compounds have molecular weight 500 to 2,600, a ring of at least 12 atoms and at least three amide bonds in or attached to the ring, and are mapped to patents published from 2000. The evaluation corpus takes the 120 highest-ranked patents by number of distinct qualifying compounds plus 80 drawn at random (seed 20261031) from the next 2,000 ranked patents, 200 in total, to limit selection bias. Patents whose retrieved page lacks a description are dropped and counted.

Extraction. An open-weight model (Qwen3-8B) run with vLLM at temperature 0 processes passages matching example, table and SAR patterns and returns five item kinds (example compound, SAR statement, ADME or permeability, binding mode, design rationale), each with a verbatim quote of 6 to 40 words.

Verification. A failing item is discarded. The quote must be an exact whitespace-normalised substring of the retrieved patent text; every numeric value and unit given as a field must occur in the quote or the passage; a structure string (SMILES, sequence or HELM) must occur verbatim and SMILES must parse in RDKit; sequences are mapped to canonical SMILES by the pipeline's converter and failures are flagged; patent number, passage offset, kind code and publication date must be present. Examples with measured data are tagged `example` and claim text `claim`, because their reliability differs.

Measurements. The stage reports patents retrieved, passages processed, items extracted, verified and rejected by reason, structure parse success, and precision from an audit of at least 50 kept items stratified by kind, together with the sample file so that the audit can be redrawn independently. It reports overlap and novelty by comparing kept example compounds, by stereo-aware InChIKey, with the BindingDB patent subset, with the two patent-derived entries in CycPeptMPDB and with SureChEMBL membership of the same patent, as the share not present in BindingDB. Scale-up beyond the corpus requires audit precision of at least 0.80 (Wilson interval reported), structure parse success of at least 0.60 among example compounds with a structure string, and at least 20 patents contributing verified example compounds. Limits: loss of layout in HTML text, no mapping of IUPAC names to structures, English- and US-centric selection, and selection by compound density favours patents with large libraries.

| Measure | Value |
|---|---|
| Patents retrieved | — |
| Passages processed | — |
| Items extracted / verified / rejected | — |
| Structure parse success | — |
| Audit precision (Wilson interval) | — |
| Patents contributing verified example compounds | — |
| Share of kept example compounds not in the BindingDB patent subset | — |

### 5.4 Scaled literature mining

Corpus. Europe PMC open-access full text (PMC XML in the first stage), retrieved by 40 topic queries covering four topics: SAR rules, structure-property fundamentals, prior-work campaigns, and target-structure statements for the 16 targets of the internal target base. A first stage processes 150 to 300 papers (at most 8 per query) and the full run 2,000 to 5,000.

Extraction. An open-weight model (Qwen3-8B) run with vLLM on a single 24 GB GPU, temperature 0, one pass per passage of about 700 to 900 words after topic-keyword filtering, returns JSON in the schema fields. A second, independent prompt asks whether the quote supports the stated direction; this is reported as a proxy and not as precision, since it can share the model's blind spots. Tiers follow the source type (research article T1, review T2, other T3). Verification, merge and contradiction handling follow Sections 4.4 and 4.4a.

Evaluation criteria. A raw-output quote-match rate below 40% makes the first stage inconclusive for the model. Precision is judged on a sample of 100 surviving rules (fixed seed, stratified by topic and tier) and must be at least 0.80. Coverage is measured on the property by substructure matrix of the internal audit: a cell is filled with at least three verified rules from at least three papers including at least one T1 or T2 source, and scaling requires that the first stage projects at least 60% of cells filled. Recall against the gold set is reported without a threshold, because the number of gold rules whose paper is in the corpus is small.

### 5.5 Structure knowledge layer

The library is built from protein-cyclic-peptide complexes in the Protein Data Bank, using the existing peptide-complex resources as a base and the internal manifest of bound cyclic complexes. For each complex the pipeline re-detects cyclisation from coordinates independently of the manifest label and reports agreement; detects D residues geometrically (sign of the C-alpha chirality volume against the receptor's L-amino-acid majority) and N-methylation geometrically (a backbone-nitrogen carbon with no other heavy neighbour), without assuming chemical component dictionary codes; classifies backbone turns with fixed textbook windows (descriptive classes, not fits); and computes interface features (buried surface, contacts, hydrogen bonds, hotspot residues). One target card is produced for each of the 16 internal targets, using the reference structure named in the target base, UniProt accessions from the PDB service, matched library complexes, and medians computed from them. A card states explicitly when no cyclic-peptide complex exists for the target, and a paper is recorded as opened only when it was opened. Aggregate bound-conformation statistics are exported as retrieval snippets and as soft-rule potentials, each tagged with the targets from which it was computed, so that a prior cannot be built from a target held out for a retrieval or recovery test.

| Measure | Value |
|---|---|
| Complexes in the library, by cyclisation type | — |
| Agreement of re-detected cyclisation with the manifest label | — |
| Target cards completed / flagged "no structure available" | — |
| Bound-conformation priors exported | — |
| Stability of priors under leave-one-target-out | — |

### 5.6 Cross-source integration

The five sources share the schema of Section 4.1 and the join keys of Section 5.1 (stereo-aware InChIKey, PDB identifier, DOI). The integrated layer is the join of structure or sequence, measured property, conformation, target complex and design outcome. The fraction of records joinable across these links is a property of the finished layer: —.

## 6. Validation

### 6.1 Direction checks against data, on training sources only

For each literature entry with a directional claim about permeability, the direction is checked against the PAMPA data of the train group (source group A) and never against the stop or held-out groups. Group A is 2020_Townsend (n = 2,881) and 2021_Kelly (n = 1,518); rows from every other source are dropped while reading, and the script asserts that only group A sources remain. The statistic is the within-source Spearman correlation of the computable feature with the raw PAMPA value (equivalent to using the within-source z score), with intervals from a cluster bootstrap over flat-structure (stereoisomer) groups (B = 300, seed 0). The check is descriptive, with no multiplicity correction. Only entries whose stated outcome is permeability are tested; solubility and stability entries are marked not applicable.

Over the 107 entries, 17 agree in direction, 7 are mixed, none disagree, and 83 are not testable (cards, cautions and context entries have no directional claim, and some windows lack a group size).

| Feature (expected sign) | 2020_Townsend rho [95% CI] | 2021_Kelly rho [95% CI] | Reading |
|---|---|---|---|
| N-methyl count (+) | +0.50 [0.43, 0.57] | +0.53 [0.33, 0.66] | agrees in both |
| HBD (-) | -0.44 [-0.51, -0.36] | -0.53 [-0.66, -0.35] | agrees in both |
| TPSA (-) | -0.47 [-0.55, -0.37] | -0.49 [-0.61, -0.28] | agrees in both |
| cLogP (+, Crippen) | +0.29 [0.18, 0.38] | +0.49 [0.29, 0.62] | agrees in both |
| HBA (-) | -0.26 [-0.37, -0.13] | -0.07 [-0.13, -0.01] | agrees, weak in Kelly |
| MW / heavy atoms (-) | -0.12 [-0.24, -0.02] | +0.48 [0.30, 0.61] | sign flips between sources |
| Rotatable bonds (-) | +0.16 [0.06, 0.27] | -0.10 [-0.28, 0.08] | mixed |
| D-residue count (+) | -0.04 [-0.09, 0.01] | +0.02 [-0.05, 0.08] | no signal at count level |

Windows and shapes: the lipophilicity peak (inverted U; quadratic coefficient -0.113 [-0.144, -0.085] in Townsend and -0.120 [-0.167, -0.063] in Kelly) agrees in both sources; the macrocycle drug window (HBD at most 7 with MW below 1000 or cLogP above 2.5) shows inside-window peptides more permeable in Kelly (+0.43 [0.09, 0.63], 1,172 inside against 346 outside) and is untestable in Townsend, where all peptides are inside; the polarity window (cLogP below 4) is weakly contradicted in Townsend (-0.12 [-0.24, 0.04]).

N-methyl count, HBD, TPSA and cLogP are therefore the stable, literature-supported directions on the two largest sources. The size and D-residue rules show an unstable sign or no signal and should not be weighted; the stored uniform weights for them are a placeholder. Both sources are laboratories known for heavily N-methylated series, so agreement is evidence of consistency and not of causation.

For comparison, rule candidates mined from our own labels on group A alone reached no validated status: the unmodified mining criteria require at least three sources and group A has two. The within-source directions were nonetheless consistent across the two laboratories and with the textbook directions (TPSA -0.470 and -0.485, HBD -0.439 and -0.527, logP +0.287 and +0.488; mean within-source z effect of N-methyl addition +0.623 and +0.483; pooled +0.554, interval 0.373 to 0.735, I-squared 0.95). These are descriptive and are not used as weights, so priors with weight come from the literature and the data check their direction.

### 6.2 Earlier within-source validation

The earlier harness (Section 2.4) found the physicochemical directions consistent within source and the N-methyl count rule inconclusive within source. These results concern the earlier internal rules.

### 6.3 Extraction fidelity, precision and recall

| Measure | Value |
|---|---|
| Raw-output quote-match rate | — |
| Surviving rules | — |
| Precision on the judged sample of 100 | — |
| Recall against the gold set | — |
| Proxy entailment rate | — |
| Planted-quote, altered-quote and shuffled-source controls | — |
| Determinism (identical hashes on repeated runs) | — |

### 6.4 Coverage

The gold set covers the topics listed in Section 5.2. Coverage of the property by substructure matrix for the scaled layer, the target by structure-feature matrix (16 targets by 5 features) and lesson-type counts for the scaled ledger are: —.

## 7. Use in a generative system

### 7.1 Consumption under train, stop and held-out source groups

The layer is consumed by a hybrid generation system, described in a companion manuscript, under a fixed split of the permeability sources into a train group (A), a stop group (S) and a held-out group (B). A is 2020_Townsend plus 2021_Kelly (4,399 peptides, 64.84% of 6,784); S has nine sources (1,269 peptides) and B has nine sources (1,116 peptides). Priors that depend on data are mined or tuned on A only; the stop group supplies the early-stopping signal and the held-out group the final evaluation. An earlier split (7, 7 and 6 sources) is retained for a robustness arm. The split limits leakage but has two features that matter: group A is two laboratories, and the stop and held-out groups are each dominated by one laboratory (CHUGAI about 69% of S; 2016_Furukawa about 59% of B).

### 7.2 Three uses

Hard rules are compiled into a token-level constraint for generation and are not data-mined. Soft priors are the weight-eligible literature rules, with weights set from the effect size stated in the source or from the uniform prior and tuned on A only. Retrieval context combines the nearest known peptides (stereo-aware similarity, with measured values) with provenance-tagged rule snippets and, where a target card exists, its pharmacophore text. The retrieval package includes a blind rule for recovery tests (excluded documents, answer-set structures and a year cutoff are rejected, with controls that fail when violated); on the integrin set its store holds 4,634 exact-value rows, 2,826 isomers and 230 documents spanning 1991 to 2025 for 8 targets. Three configurations are compared in the companion manuscript: hard rules only, literature priors, and the data-descriptive directions of Section 6.1 as an ablation.

## 8. Discussion

The two contributions in context. The layer (contribution 1) adds what existing collections lack; the pipeline (contribution 2) is what makes the layer trustworthy at scale.

What the layer adds. Existing collections give a designer measurements and structures; they do not give a statement such as "adding a hydrogen-bond donor and enlarging the ring are expected to lower permeability" together with its source, quote, evidence tier, scope and the feature it maps to. We introduce that statement-level layer and link it to the measurement and structure resources through shared keys, so that a rule can be traced to a paper or patent passage, checked against data on training sources, and consumed by a generator as a prior or as retrieved context. Three properties distinguish the construction from a literature table: attribution is machine-verified rather than asserted, evidence tier controls what may influence a model, and the leak guards make the layer safe to use inside a held-out evaluation. Patent-derived statements are kept in their own tier so that their different quality and verification profile is visible to every consumer. The campaign ledger records negative and partial outcomes alongside successes, and our own earlier campaigns sit beside the published ones.

What the construction showed. The imports worked on every route and the join control passed, which supports using one stereo-aware key across resources. They also showed that files and papers disagree on counts, so counts must be quoted from the file used. The direction check on two independent large sources agreed with the literature for the rules that could be tested (17 agree, none disagree), and the stable directions are the ones a generator can safely weight. Data-derived rules need several independent sources to reach validated status, so literature rules carry the weights and the data check their direction. Quantitative, computable rules are a minority of statements (32 of 107 weight-eligible), which is why retrieval context and hard constraints carry much of the use.

How the layer is used and evaluated. The layer is consumed by a hybrid generation system under a fixed split of permeability sources, and whether the priors improve generation is reported in the companion manuscript.

## 9. Limitations

Coverage is limited to open-access full text and to the sources named; paywalled primary studies are missed, and target pharmacophore rules, encyclopaedic and database facts, display-campaign hit rates and per-drug properties of approved cyclic peptides are not in the gold set. Table extraction from XML is lossy. An 8-billion-parameter extractor can misread direction or comparator even when the quote is exact; exact-match verification guarantees attribution, not correctness, which is why precision is judged on a sample. The statements of the gold set were written by an AI assistant while reading the opened papers; only the quotes are machine-verified, and the fidelity of statement to quote has not been judged by a person. Review-level statements (tier T2) are attributed to the review, and their primary sources were not re-opened; several sources are recent 2026 articles that have not been independently reviewed by us. Weights are a uniform prior and have not been tuned. The direction check uses two sources, one of which dominates, descriptors from the stratification annotation (Crippen logP, RDKit TPSA and HBD), a cluster bootstrap by flat structure and not by laboratory, no multiplicity control, and PAMPA only; both sources are laboratories known for heavily N-methylated series. Source papers whose data are in CycPeptMPDB are flagged, not removed, so a literature rule may reflect data that also underlies the evaluation. Assays and laboratories differ across sources, and the earlier audit showed that a flagship rule (N-methylation) was mostly a between-laboratory effect; the schema records assay and support but cannot remove this heterogeneity. Group A is two laboratories. Files differ from their papers in several cases (Section 2.2) and may change; counts must be quoted from the file used. Several survey details could not be opened (Section 2.2), and the survey's search was limited to Europe PMC title searches and a few web searches, so absence of a record is not proof of absence. The degree to which existing collections cover the patent literature was not established by the survey. One rule (grazoprevir) and the depsipeptide and macrobicycle series are not peptides in the strict sense; their scope fields say so. The comparison with other knowledge bases is by content type and counts, not by head-to-head use in a downstream task.

## 10. Data and code availability

Code and data are in the project repository under `research/guangzhou_all_atom/cyclic_llm/allatom_paper/`: `knowledge/` (schema, builder, loader, tests, direction check, and `knowledge_kb_v1.json` with sha256 `b6c8988545bc1ae9dcda73521a03a2ec5bd735504bfca7d300a6e1f9261d42b7`), `knowledge_scale/` (acquisition, extraction, verification, merge, import and measurement scripts), `structure_knowledge/` (features, target cards, library driver), `patent_mining/` (selection, retrieval, extraction, verification), `retrieval/` (store, index, prompt builder, blind rule) and `track_e/source_groups_v2.json` (source-group membership, sha256 `be8a9945f5042b97afa177d85c23f80b9343c933722c54f02188bd75b276db1c`). Each build records file hashes and access dates; resources are cited by DOI and by the date and hash of the file used.
