# A provenance-linked knowledge layer for cyclic-peptide design: survey of existing collections, gap analysis and construction

Status: draft v0.1 (2026-10-29). Every number is read from a committed file or an opened primary record; items that depend on workstreams still running are marked `[PENDING:<stream>]` and collected in the results registry (end of document). Literature tags: `[LIT-VERIFIED:full]` primary source opened in full text; `[LIT-VERIFIED:abstract]` primary record (title, authors, journal, year, DOI, abstract) opened through Europe PMC or the publisher page, details beyond the abstract not verified; `[LIT-UNVERIFIED]` could not be opened, kept out of conclusions. Streams: K = hand-verified gold set; K2 = imports and scaled literature extraction; K3 = structure knowledge; K4 = patent mining; I-B = retrieval and group-A mining.

## Abstract

Design systems for cyclic peptides, including language-model-based generators, need machine-usable knowledge: how structure relates to permeability, stability and solubility; how cyclic peptides bind their targets; and what earlier design campaigns achieved. We surveyed existing collections and found that the entity and measurement layers are covered by several curated resources (for example a 7,334-peptide permeability database, conformer ensembles for 36,198 macrocyclic peptides, and peptide-protein complex databases with more than 49,300 complexes), while structured design rules with provenance, a campaign and benchmark ledger, cyclic-specific complex annotation, and stability and solubility collections were not found in the records we could open. We describe a knowledge layer built from five content sources: imports of existing collections, a hand-verified gold set (48 entries from 19 papers at the time of writing, every quote machine-verified against the source text), literature mining at scale with an open-weight model under deterministic exact-quote verification, patent mining as a separate evidence tier, and a structure layer derived from protein-cyclic-peptide complexes. The layer carries evidence tiers, a leak guard for use with held-out evaluation, and loaders that produce soft-rule potentials and retrieval context for a generative system. We report the schema, the construction pipeline and the checks that have been run, and list the validation results that remain pending. The claim we make is limited to an integrated, evidence-linked layer, subject to a deeper literature check.

## 1. Introduction

Cyclic peptides and macrocycles occupy a chemical space between small molecules and biologics. Their permeability, stability and binding depend on conformation, intramolecular hydrogen bonding, backbone modification and stereochemistry in ways that two-dimensional descriptors capture only partly. A design system that proposes, filters and ranks candidates therefore needs more than a trained scorer: it needs rules and facts that can be inspected, cited and corrected.

Three kinds of knowledge matter. Structure-property knowledge covers how permeability, solubility, stability and conformation relate to chemistry (A). Target-structure knowledge covers how cyclic peptides bind their targets, in which conformation and through which contacts (B). Prior-work knowledge covers what earlier design and optimisation campaigns produced, including hit rates and failures (C). For a generative system the same knowledge is used in three ways: as hard constraints on what may be generated, as soft priors that bias generation, and as retrieved context in a prompt. Each use requires that the knowledge be structured, attributable to a source and checkable against it.

Our own earlier knowledge bases were small for this purpose. An internal audit (Section 2.4) found that the peptide-relevant content of the existing bases amounted to a handful of statements, that one flagship rule was mostly a between-laboratory effect, and that three of 57 citations could not be confirmed. Before building more, we asked what already exists. This manuscript reports that survey, the resulting gap analysis, and the construction and use of a layer designed for the gaps.

Contributions, stated narrowly: (i) a survey with verification status for each entry; (ii) a schema and pipeline that tie every rule to a verbatim quote verified by exact string match against the retrieved source text; (iii) a leak guard that prevents knowledge derived from evaluation data from entering a prior used with that evaluation; (iv) the construction of five content sources and the checks run on them; (v) an honest list of what is not yet measured.

## 2. Survey of existing resources

### 2.1 Method and verification status

Primary records were opened through the Europe PMC REST interface (title, authors, journal, year, DOI, abstract) or the publisher or PMC page. Several PMC pages returned a verification wall; for those, only the abstract is verified. The CycPeptMPDB site did not respond to the first fetch. Where a detail was not seen in an opened record it is marked not verified. Download routes were later checked by HEAD request by workstream K2 (Section 5.1), which revealed differences between published and live counts.

### 2.2 Inventory

Counts are those stated in the opened record. "Live" counts come from K2's route check of 2026-10-29 and differ from the papers in several cases.

| Resource | Type | Content (as stated in opened record) | Live check (K2) | Verification |
|---|---|---|---|---|
| CycPeptMPDB (Li et al., J Chem Inf Model 2023, DOI 10.1021/acs.jcim.2c01573) | A | 7,334 cyclic peptides, measured membrane permeability, 45 papers and 2 pharma patents, HELM representation | download page lists 8,466 entries; our local loader holds 6,960 labelled peptides | `[LIT-VERIFIED:abstract]` |
| CREMP (Grambow et al., Sci Data 2024, DOI 10.1038/s41597-024-03698-y) | A | 36,198 homodetic 4-6-mer macrocyclic peptides, about 31.3 M conformers (CREST, GFN2-xTB, chloroform ALPB); plus a 3,258-peptide permeability subset with about 8.7 M conformers | Zenodo routes confirmed | `[LIT-VERIFIED:full]` |
| SweMacrocycleDB (Feng et al., Sci Data 2025, DOI 10.1038/s41597-024-04302-z) | A | 5,638 permeability datapoints for 4,216 nonpeptidic macrocycles | page shows 6,585 datapoints | `[LIT-VERIFIED:abstract]` |
| Macrocycle-DB (Jiang et al., Nucleic Acids Res 2026, DOI 10.1093/nar/gkaf1107) | A, B | 45,525 macrocycles, 76 approved drugs, 105 clinical candidates, 2,533 targets, co-crystal links | live statistics endpoint reports 18,969 macrocycles | `[LIT-VERIFIED:abstract]` |
| CyclicPepedia (Liu et al., Brief Bioinform 2024, DOI 10.1093/bib/bbae190) | A, C (shallow) | 8,744 cyclic peptides with sources, classifications, structural features, pharmacokinetic and physicochemical properties, patented applications, key publications | export route confirmed (13 tables and a structure archive) | `[LIT-VERIFIED:abstract]` |
| PepBDB (Wen et al., Bioinformatics 2019, DOI 10.1093/bioinformatics/bty579) | B | peptide-protein complexes from PDB, peptides under 50 residues, monthly updates (stated in the article); a secondary source gives 13,299 complexes | not checked | `[LIT-VERIFIED:abstract]`; count `[LIT-UNVERIFIED]` |
| Propedia v2.3 (Martins et al., Front Bioinform 2023, DOI 10.3389/fbinf.2023.1103103) | B | more than 49,300 peptide-protein complexes, peptides of 2-50 residues, six functional subsets, graph-based structural signatures | not checked | `[LIT-VERIFIED:full]` |
| BioLiP2 (Zhang et al., Nucleic Acids Res 2024, DOI 10.1093/nar/gkad630) | B | 385,160 protein chains and 781,684 protein-ligand interactions; peptide ligands about 4% of interactions; about 50,064 interactions with affinity | not checked | `[LIT-VERIFIED:full]` |
| DBAASP v3 (Pirtskhalava et al., Nucleic Acids Res 2021, DOI 10.1093/nar/gkaa991) | A, C (antimicrobial) | more than 15,700 entries with sequences, modifications, structures, activity, toxicity | not checked | `[LIT-VERIFIED:abstract]` |
| Norine (Flissi et al., Nucleic Acids Res 2020, DOI 10.1093/nar/gkz1000) | A, C (natural) | nonribosomal peptide resource; total count not verified | landing page reachable, no bulk route found | `[LIT-VERIFIED:abstract]` |
| Natural Products Atlas 3.0 (Poynton et al., Nucleic Acids Res 2025, DOI 10.1093/nar/gkae1093) | A (natural products) | 36,545 microbial compounds | not checked | `[LIT-VERIFIED:abstract]` |
| THPdb (Usmani et al., PLoS One 2017, DOI 10.1371/journal.pone.0181748) | C (therapeutics) | 852 entries from 985 papers and 70 patents | not checked | `[LIT-VERIFIED:abstract]` |
| Peptipedia (Quiroz et al., Database 2021, DOI 10.1093/database/baab055) | sequence/activity | 92,055 sequences from 30 databases | not checked | `[LIT-VERIFIED:abstract]` |

Peripheral resources (StraPep, CPPsite 2.0, ConjuPepDB) were opened at abstract level and are mostly linear or therapeutic; they are cross-references only. CycPeptMPDB-4D (a 2026 table of molecular-dynamics descriptors for 5,160 CycPeptMPDB peptides) could not be located by the survey; it was later opened by the ensemble-feature screening analysis (`docs/20261031_ENSEMBLE_FEATURES_PREREG.md`), which joined 4,918 labelled peptides to it, but only five sources are covered. PDBbind, PepMNet, PepPrCLIP and PepBench could not be opened `[LIT-UNVERIFIED]`.

Resource drift is itself a finding. For three resources the live count differs from the published abstract (CycPeptMPDB 8,466 against 7,334; SweMacrocycleDB 6,585 against 5,638 datapoints; Macrocycle-DB 18,969 against 45,525 macrocycles). Any study that cites a resource by its paper count while using a download should record the download date and hash.

### 2.3 Rules and design literature

The rules most used in practice are stated in prose in review and primary articles rather than in structured collections.

| Citation | Content (abstract-level) | Tag |
|---|---|---|
| Doak et al., Chem Biol 2014 (10.1016/j.chembiol.2014.08.013) | oral druggable space beyond the rule of 5; intramolecular hydrogen bonds, macrocyclisation and formulation as enablers | `[LIT-VERIFIED:abstract]` |
| Over et al., Nat Chem Biol 2016 (10.1038/nchembio.2203) | more than 200 synthetic macrocycles; functional groups, properties and conformations that drive permeability | `[LIT-VERIFIED:abstract]` |
| Naylor et al., J Med Chem 2018 (10.1021/acs.jmedchem.8b01259) | lipophilic permeability efficiency, a metric relating lipophilicity to permeability and solubility | `[LIT-VERIFIED:abstract]` |
| White et al., Nat Chem Biol 2011 (10.1038/nchembio.664) | on-resin N-methylation of cyclic peptides; a hexapeptide with 28% rat oral bioavailability | `[LIT-VERIFIED:abstract]` |
| Hosono et al., Nat Commun 2023 (10.1038/s41467-023-36978-z) | amide-to-ester substitution as an alternative to N-methylation | `[LIT-VERIFIED:abstract]` |
| Rossi Sebastiano et al., J Med Chem 2022 (10.1021/acs.jmedchem.2c00774) | chameleonicity and intramolecular hydrogen bonds for ranking beyond-rule-of-5 compounds | `[LIT-VERIFIED:abstract]` |
| Ermondi et al., ADMET DMPK 2020 (10.5599/admet.834) | solubility prediction in beyond-rule-of-5 space | `[LIT-VERIFIED:abstract]` |

Design and prior-work literature: RFpeptides (Rettie et al., Nat Chem Biol 2025, 10.1038/s41589-025-01929-w) reports at most 20 designs per target against four targets, all yielding medium-to-high affinity binders, one with Kd below 10 nM, and crystal structures within 1.5 A C-alpha RMSD of the design `[LIT-VERIFIED:abstract]`. AfCycDesign (bioRxiv 2023, 10.1101/2023.02.25.529956) predicts 36 of 49 native structures within 1.5 A and reports about 10,000 designs for 7-13-mers with seven validated within 1.0 A `[LIT-VERIFIED:abstract]`. HighFold (bioRxiv 2023, 10.1101/2023.08.27.554979) adapts AlphaFold for cyclic peptides `[LIT-VERIFIED:abstract]`. Several permeability-prediction papers model CycPeptMPDB with non-comparable splits (for example CPMP, R2 0.67 for PAMPA); the survey found no common benchmark.

### 2.4 Audit of our earlier internal knowledge bases

An internal audit (`docs/20261029_KB_AUDIT_AND_GAPS.md`) examined the knowledge bases under `research/guangzhou_all_atom/cyclic_llm/`. Findings that bear on this work:

- `experience_kb.py` with `target_kb/` (16 targets): 151 entry instances, 73 distinct statements, 37 of them active knowledge. The 16 per-target pharmacophore entries reduce to two distinct statements (an RGD/MIDAS statement for four integrin targets and one generic hot-spot sentence for twelve others).
- `medchem_kb.py`: 1,585 small-molecule liability alerts and only four peptide-relevant modality statements. `medchem_kb_product.py` (45 entries) had no non-test consumer and eleven entries duplicating `medchem_kb`. `medchem_kb_ingested_large.json` holds summary counts only (4,225 approved drugs, 7,561 mechanisms) with no peptide-specific content.
- Citation check by Crossref over 57 citations: 54 confirmed, 3 flagged; the self-asserted `verified` flag was set on all three flagged entries, so it is not a reliable signal. One target structure identifier was mislabelled.
- Coverage on the benchmark: the 16 knowledge-base targets map to 12 of 793 benchmark targets, to 1 of 46 in the primary analysis, and to 389 of 20,562 positives (1.9%).
- Entries carry no ingestion date, so no leak-safe time slicing is possible.
- A within-source validation harness (`kb_rule_validity.py`, five tests) found TPSA, HBD, logP and Veber pass directionally consistent within source, and found the N-methyl count rule inconclusive within source (pooled rho 0.37 falling to a median within-source rho of 0.01, confidence interval -0.13 to 0.28, 9 of 18 sources positive). The harness therefore separates between-laboratory effects from within-laboratory effects, which is the reason the schema of Section 4 records the assay and the number of supporting sources.

## 3. Gap analysis

Coverage was assessed per subtopic against the resources above (coverage matrix, condensed; X = substantively covered by an opened record, p = partial, blank = not covered).

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

The gaps that no opened record covers are: (1) a join-keyed layer linking structure, measured property, conformation, target complex and design outcome, since each resource uses its own identifiers; (2) structured design rules with evidence provenance; (3) a cyclic-annotated complex set with cyclisation chemistry, ring size and binding-mode annotation; (4) stability and solubility collections for cyclic peptides; (5) a campaign and benchmark ledger including negative outcomes; (6) a common benchmark with standard splits; (7) hotspot and interface resources specific to macrocycle binders. These were established from searches that were limited (Europe PMC title searches and a few web searches) and several pages were inaccessible; absence of a record is not proof of absence, and we claim no more than that none was found.

Patents form a further candidate gap. Among the opened records, CycPeptMPDB draws on two pharma patents, SweMacrocycleDB lists patents among its sources, CyclicPepedia has a patented-applications field, and THPdb draws on 70 patents; the number of patent-derived records in each was not verified. Our hypothesis, to be measured by workstream K4 and not assumed, is that existing collections cover only part of the cyclic-peptide patent literature (Section 5.3).

## 4. The knowledge layer

### 4.1 Schema

The schema (`allatom_paper/knowledge/kb_schema.py`, version 1.0) defines entries of four kinds: rule (a directional or windowed statement about an outcome), fundamental (a mechanistic statement), caution (a statement about data or method limits) and card (a structured summary of a target or campaign). Required fields are: identifier (pattern `LIT-<TOPIC>-nnn`, `CARD-...` or `INT-...`), kind, statement, direction (plus, minus, multi, window, context, caution or conflict), scope (a list of terms such as ring type and chemistry), outcome (the property concerned), evidence tier, source (PMCID, DOI, title, journal, year, URL; for internal entries a file path), a verbatim quote of at most 30 words, confidence (high, medium, low), access date, extractor, weight and a weight-eligibility flag, a quote-verification flag with the quote offset in the source text, applicable target and structure reference. Optional fields include effect size and units, windows with thresholds, and the computable feature to which the rule maps.

### 4.2 Evidence tiers

| Tier | Definition | Use |
|---|---|---|
| T1 | primary peer-reviewed quantitative study | may carry weight |
| T2 | review, textbook or author background statement | may carry weight |
| T3 | secondary source (encyclopaedic, vendor, aggregator) | retrieval context only |
| T-internal | our own campaign documents (file path as source) | retrieval context only |
| P | patent-derived statement (workstream K4) | retrieval context; weighting rule decided in the K4 pre-registration `[PENDING:K4]` |

Patent-derived content is kept in a separate tier because its quality, claim style and level of verification differ from journal content.

### 4.3 Weight eligibility

An entry may carry a nonzero weight only if all of the following hold: tier T1 or T2; kind rule or fundamental; quote verified by string match; direction in the weighted set (plus, minus, multi, window); and at least one computable feature to which the rule maps. The computable feature set is TPSA, HBD, HBA, MW, cLogP, aLogP, number of rotatable bonds, heavy-atom count, N-methyl count, D-residue count and a cyclic flag. A rule whose natural feature is not computable from two-dimensional structure (for example exposed NH) may map to a proxy feature with its weight halved. Everything else is kept for retrieval context at weight zero. The unit tests (14 in `test_knowledge.py`, all passing at the time of writing) include that an unverified entry never carries a weight and that window rules penalise violations only.

### 4.4 Provenance and citation integrity

Every rule traces to a source that was opened. For the gold set the statements were written by an AI assistant (workstream K) while reading the opened papers, and the builder (`build_kb.py`) verifies every quote verbatim against the stored Europe PMC open-access full text, using the same whitespace normalisation, and sets the verification flag from that match. The statements themselves have not yet been independently judged against their quotes (Section 8). For scaled extraction the rule is stricter and deterministic: after whitespace normalisation (single spaces, case preserved, nothing else) the quote must be an exact substring of the stored normalised source text, its length must be between 6 and 30 words, any numerical effect size must occur as a digit string in the quote or the passage, and required fields must be present with values in closed vocabularies. A rule failing any check is discarded and never repaired. Controls specified in advance: 20 synthetic rules with fabricated quotes must all be rejected; 20 quotes with altered words, dropped words or changed numbers must be rejected while 20 quotes differing only in whitespace must be accepted; rules paired with a different paper's text must fail. An exact quote does not establish that the statement is a correct reading of it; that is measured separately by judged precision on an audit sample (Section 6.3).

### 4.4a Merge, support and contradiction

Equivalent rules (same property, substructure class and direction, and statement token overlap of at least 0.5 on content words) are merged. Support is the number of distinct DOIs. Opposite directions on the same property, substructure class and scope key from different papers set a contradiction flag; contradictions are flagged and never resolved by the pipeline.

### 4.5 Leak guards for held-out evaluation

Knowledge derived from labelled evaluation data must not enter a prior used with that evaluation. Three guards are in place. First, `assert_priors_clean` (`ihlm/symbolic.py`) refuses a prior whose mining sources overlap the sources on which a stop or held-out verifier is fitted; the earlier all-laboratory rule file (`peptide_sar_rules_v1.json`, mined from all 21 training sources) fails this check against the stop and held-out groups, and a control confirms this. Second, scaled extraction sets a `possible_benchmark_source` flag when a source paper matches a CycPeptMPDB source name by first author and year, so such rules can be excluded from priors used with held-out verifiers. Third, the consuming system splits the permeability sources into train, stop and held-out groups (Section 7.1) and mines or tunes anything data-derived on the train group only. The new schema stores an access date; the earlier bases did not.

### 4.6 Loaders

`knowledge_loader.py` provides two outputs. `KnowledgePotential` builds a sequence-level log-linear potential from the weight-eligible rules: directional rules contribute weight times sign times the standardised feature, with the mean and spread supplied by the caller from the train group only, and window rules contribute hinge penalties on the stated thresholds. `rules_text()` returns short provenance-tagged snippets for retrieval-conditioned prompts. Hard constraints (ring closure, ring size, N-methyl window, molecular-weight bound, structural-alert prefixes) are not data-mined and are compiled separately by the generation system.

## 5. Construction

The layer is built from five content sources, each with its own provenance rules.

### 5.1 Imports of existing collections (K2)

Download routes were checked by HEAD request on 2026-10-29. CycPeptMPDB provides CSV files for peptides (19.07 MB), per-assay tables (Caco-2, MDCK, PAMPA) and monomers; SweMacrocycleDB provides CSV downloads (3.71 MB for the overall table); CyclicPepedia provides 13 spreadsheet tables and a two-dimensional structure archive (the survey had marked this route unverified); the CREMP permeability subset is available as a summary table and two large conformer archives, of which only the summary table is imported; Macrocycle-DB provides static CSV files (29.1 MB for the main table, 2.54 MB for PDB links) and a structure archive; Norine's landing page is reachable but no bulk route was found, so it is optional. The import design is frozen in the K2 pre-registration (amendment A2): each file is fetched with its HTTP date, size and sha256; records are parsed into one canonical table (resource, record identifier, SMILES, full and flat stereo-aware InChIKey, assay, value, unit, source reference, DOI); failures are counted and never dropped silently; joins to the local CycPeptMPDB table (6,960 rows) and the live download use the full key and the flat key. Acceptance: at least 95% of rows parsed per resource, otherwise the resource is marked partial. Results (rows parsed, join rates, discrepancies between local and live CycPeptMPDB) `[PENDING:K2]`.

### 5.2 Hand-verified gold set (K)

The gold set (`knowledge_kb_v1.json`, sha256 `5f6843f8ec79df4c857ee9cb55af6adbf5add6b08e59907204cd4a735528f5e9`, access date 2026-10-29) holds 48 entries from 19 distinct source papers: 38 at tier T1 and 10 at tier T2; 37 rules, 8 fundamentals and 3 cautions. All 48 quotes pass the machine check; 21 entries are weight-eligible. By direction: context 16, window 9, minus 9, plus 7, caution 4, multi 2, conflict 1. Confidence: 23 high, 24 medium, 1 low. Topics at this version include beyond-rule-of-5 guidelines for macrocycles (windows on HBD, MW, cLogP and TPSA), intramolecular hydrogen bonds and chameleonic behaviour, backbone N-methylation (including placement sensitivity), hydrogen-bond-donor count and ring size effects, lipophilicity non-monotonicity, size dependence, solubility and aggregation of lipophilic cyclic heptapeptides, stereochemistry effects on solubility, and data cautions (for example that in one curated macrocycle permeability database 67% of records are PAMPA and 91% of those come from a single source). Coverage is uneven: stability has one entry and the target-structure and prior-work topics are not yet represented; the planned size is at least 60 entries `[PENDING:K]`. A registry of what the final gold set contains will be given in `docs/20261031_ALLATOM_KNOWLEDGE_LAYER.md` `[PENDING:K]`.

### 5.3 Patent mining (K4)

Rationale and hypothesis. Medicinal-chemistry knowledge on macrocyclic peptides appears in patents as well as in journals. The opened records show that existing collections draw on patents only to a limited, unmeasured degree (CycPeptMPDB two patents; THPdb 70 patents; SweMacrocycleDB and CyclicPepedia mention patents without stated counts in the abstracts). The hypothesis H-P is that existing collections cover only part of the patent literature on cyclic peptides; it is a hypothesis until K4 measures it.

Scope. Workstream K4 (`allatom_paper/patent_mining/`, design document `docs/20261031_ALLATOM_PATENT_KNOWLEDGE.md`) extracts knowledge statements (structure-property relations, SAR observations, measured values and design lessons) from patent full text. It is knowledge extraction only; it makes no freedom-to-operate or validity assessment and no legal conclusion. Statements are assigned tier P (Section 4.2). Verification is the same exact-quote check against the retrieved full text as in Section 4.4.

Comparators. The overlap and novelty of extracted content are to be measured against SureChEMBL, the patent subset of BindingDB and the two patents in CycPeptMPDB; the contents and coverage of the first two were not verified by the survey `[LIT-UNVERIFIED]` and will be established by K4 from opened records. Results: corpus size, retrieval route, rules extracted and surviving verification, overlap with the comparators, and the fraction of content not found in the comparators `[PENDING:K4]`.

### 5.4 Scaled literature mining (K2)

Design (pre-registered before any extraction). Corpus: Europe PMC open-access full text with the pilot restricted to PMC XML; 40 topic queries covering four topics (SAR rules, structure-property fundamentals, prior-work campaigns, target-structure statements for the 16 targets of the internal target base); the pilot processes 150-300 papers (at most 8 per query), the full run 2,000-5,000. Extractor: Qwen3-8B (open weights) run with vLLM on one A10G spot instance, temperature 0, one pass per passage of about 700-900 words after topic-keyword filtering, returning JSON in the schema fields. Verification: Section 4.4. A second, independent prompt asks whether the quote supports the stated direction; this is reported as a proxy and not as precision, since it can share the model's blind spots. Tiers follow the source type (research article T1, review T2, other T3). Merge and contradiction handling: Section 4.4a.

Acceptance thresholds, fixed in advance: raw-output quote-match rate below 40% makes the pilot inconclusive for the model; precision of at least 0.80 on a judged audit sample of 100 surviving rules (fixed seed, stratified by topic and tier); coverage measured on the property by substructure matrix of the internal audit (a cell is filled with at least three verified rules from at least three papers including at least one T1 or T2), with scaling justified only if the pilot projects at least 60% of cells filled; recall against the gold set reported without a threshold because the denominator is expected to be small. The full-scale run needs a separate go-ahead with a measured cost. Pilot results: corpus, surviving rules, quote-match pass rate, precision, recall, coverage change, cost `[PENDING:K2]`.

### 5.5 Structure knowledge layer (K3)

Design (from `allatom_paper/structure_knowledge/`). The library is built from protein-cyclic-peptide complexes in the Protein Data Bank, using the existing peptide-complex resources as a base and the internal manifest of bound cyclic complexes. For each complex the pipeline re-detects cyclisation from coordinates independently of the manifest label and reports agreement; detects D residues geometrically (sign of the C-alpha chirality volume against the receptor's L-amino-acid majority) and N-methylation geometrically (a backbone-nitrogen carbon with no other heavy neighbour), without assuming chemical component dictionary codes; classifies backbone turns with fixed textbook windows (descriptive classes, not fits); and computes interface features (buried surface, contacts, hydrogen bonds, hotspot residues). One target card is produced for each of the 16 internal targets, using the reference structure named in the internal target base, UniProt accessions from the PDB service, matched library complexes, and medians computed from them; a card states explicitly when no cyclic-peptide complex exists for the target, and a paper is recorded as opened only when someone has opened it. Aggregate bound-conformation statistics are exported as retrieval snippets and as soft-rule potentials, each tagged with the targets from which it was computed, so that a prior cannot be built from a target held out for a retrieval or recovery test. Results (complex counts by cyclisation type, agreement of re-detection with the manifest, target cards completed, priors exported, stability under leave-one-target-out) `[PENDING:K3]`.

### 5.6 Cross-source integration

The five sources share the schema of Section 4.1 and the join keys of Section 5.1 (stereo-aware InChIKey, PDB identifier, DOI). The integrated layer is the join of structure or sequence, measured property, conformation, target complex and design outcome; the extent to which it can be populated is a result of the construction, not an assumption `[PENDING:K, K2, K3, K4]`.

## 6. Validation

### 6.1 Direction checks against data, on training sources only

For each quantifiable literature rule the direction is checked against the permeability data of the train group (source group A) and never against the stop or held-out groups. Results per rule (agree, disagree, not testable, with n and per-source consistency) `[PENDING:K]`.

What exists today concerns the data-derived rule candidates of the earlier internal harness, re-mined on group A (committed `rules_mining/`). With group A reduced to two sources (2020_Townsend and 2021_Kelly, 4,399 peptides), no rule reaches validated status, because the unmodified criteria require at least three sources: statuses were inconclusive for TPSA, HBD, logP, Veber pass and N-methyl addition, and no consistent direction for D-flip. Descriptive within-source evidence (Spearman with PAMPA, within-source standardised) was:

| Source | n | TPSA | HBD | logP | N-methyl added (mean within-source z effect) |
|---|---|---|---|---|---|
| 2020_Townsend | 2,881 | -0.470 | -0.439 | +0.287 | +0.623 |
| 2021_Kelly | 1,518 | -0.485 | -0.527 | +0.488 | +0.483 |

The directions agree across the two laboratories and with the textbook directions; pooled N-methyl effect +0.554 (confidence interval 0.373 to 0.735) with I-squared 0.95, indicating strong context dependence. These are small-sample descriptive leads and are not used as weights. The consequence for the layer is that priors with weight must come from the literature, with the data used to check direction, not to set it.

### 6.2 Earlier within-source validation

The earlier harness (Section 2.4) found the physicochemical directions consistent within source and the N-methyl count rule inconclusive within source. These results concern the earlier internal rules and are reported for context.

### 6.3 Extraction fidelity, precision and recall

Quote-match rate of raw outputs, precision on the judged audit sample, recall against the gold set (with the number of gold rules whose source paper was in the pilot corpus), the proxy entailment rate, the planted-quote, altered-quote and shuffled-source controls, and determinism (identical hashes on repeated runs) `[PENDING:K2]`.

### 6.4 Coverage

Cells of the property by substructure matrix filled before and after (before: from the internal audit, where the peptide-relevant content was a handful of statements; after) `[PENDING:K2, K]`; topic and tier counts; the 16-target by five-structure-feature matrix `[PENDING:K3]`; lesson-type counts for the campaign ledger `[PENDING:K, K2]`; and the gap list per topic.

## 7. Use in a generative system

### 7.1 Consumption under train, stop and held-out source groups

The layer is consumed by the hybrid generation system of the method manuscript under a fixed split of the permeability sources into a train group (A), a stop group (S) and a held-out group (B), defined in `allatom_paper/track_e/source_groups_v2.json` (membership sha256 `be8a9945f5042b97afa177d85c23f80b9343c933722c54f02188bd75b276db1c`): A is 2020_Townsend plus 2021_Kelly (4,399 peptides, 64.84% of 6,784), S has nine sources (1,269 peptides) and B has nine sources (1,116 peptides). Priors that depend on data are mined or tuned on A only; the stop group supplies the early-stopping signal and the held-out group the final evaluation. An earlier split (v1, 7/7/6 sources) is retained for a robustness arm. This limits leakage but leaves two features of the split that matter: group A is two laboratories, and the stop and held-out groups are each dominated by one laboratory (CHUGAI about 69% of S; 2016_Furukawa about 59% of B).

### 7.2 Three uses

Hard rules are compiled into a token-level constraint for generation and are not data-mined. Soft priors are the weight-eligible literature rules, with weights set from the effect size stated in the source or from a uniform prior and tuned on A only. Retrieval context combines the nearest known peptides (stereo-aware similarity, with measured values) with provenance-tagged rule snippets and, where a target card exists, its pharmacophore text. The retrieval package (`allatom_paper/retrieval/`) includes a blind rule for recovery tests (excluded documents, answer-set structures and a year cutoff are rejected, with controls that fail when violated); on the integrin set its store holds 4,634 exact-value rows, 2,826 isomers and 230 documents spanning 1991-2025 for 8 targets (committed README of that package). Three configurations are compared in the method manuscript: hard rules only, literature priors, and the data-descriptive directions of Section 6.1 as an ablation. Results are deferred to that manuscript.

## 8. Limitations

Coverage is limited to open-access full text and to the sources named; paywalled primary studies are missed. Table extraction from XML is lossy. An 8-billion-parameter extractor can misread direction or comparator even when the quote is exact; exact-match verification guarantees attribution, not correctness, which is why precision is judged on a sample. The gold set is small and permeability-heavy at this version, and its statements were written by an AI assistant: only the quotes are machine-verified, and the fidelity of statement to quote has not yet been judged by a person `[PENDING:K]`. Source papers whose data are in CycPeptMPDB are flagged, not removed, so a literature rule may reflect data that also underlies the evaluation. Assays and laboratories differ across sources, and the earlier audit showed that a flagship rule (N-methylation) was mostly a between-laboratory effect; the schema records assay and support but cannot remove this heterogeneity. Group A is two laboratories. Live resources differ from their papers and may change. Several survey details are unverified (Section 2.2), and the survey's search was limited. The statement that existing collections cover only part of the patent literature is a hypothesis pending K4. The comparison with other knowledge bases is by content type and counts, not by head-to-head use in a downstream task.

## 9. Data and code availability

Code and data live in the project repository under `research/guangzhou_all_atom/cyclic_llm/allatom_paper/`: `knowledge/` (schema, builder, loader, tests, `knowledge_kb_v1.json` with sha256 `5f6843f8...f5e9`), `knowledge_scale/` (acquisition, extraction, verification, merge, import and measurement scripts, pre-registration `docs/20261031_ALLATOM_KNOWLEDGE_SCALE_PREREG.md`), `structure_knowledge/` (features, cards, library driver), `patent_mining/` `[PENDING:K4]`, `retrieval/` and `rules_mining/` (I-B), and `track_e/source_groups_v2.json`. Survey and audit documents: `docs/20261031_SURVEY_EXISTING_CYCLIC_PEPTIDE_KNOWLEDGE.md`, `docs/20261029_KB_AUDIT_AND_GAPS.md`. Each build records file hashes and access dates; resources are cited by DOI and by the date and hash of the file used.

## Results registry (every pending item)

| Item | Stream | File that will fill it |
|---|---|---|
| Final gold-set size, topic and tier counts, prior-work and stability entries | K | `docs/20261031_ALLATOM_KNOWLEDGE_LAYER.md`, `knowledge/knowledge_kb_v1.json` (or later version) |
| Direction checks of literature rules against group A (n, per-source consistency) | K | `docs/20261031_ALLATOM_KNOWLEDGE_LAYER.md` |
| Import results: rows parsed, join rates, local vs live CycPeptMPDB differences | K2 | `knowledge_scale/import_summary.json`, `docs/20261031_ALLATOM_KNOWLEDGE_SCALE.md` |
| Pilot extraction: quote-match rate, precision (judged sample), recall vs gold, entailment proxy, controls, cost | K2 | `docs/20261031_ALLATOM_KNOWLEDGE_SCALE.md` |
| Coverage matrix before and after; per-topic counts; gap list | K2, K | `docs/20261031_ALLATOM_KNOWLEDGE_SCALE.md` |
| Complex library counts by cyclisation type; re-detection agreement; target cards; bound-conformation priors; leave-one-target-out stability | K3 | `docs/20261031_ALLATOM_STRUCTURE_KNOWLEDGE.md` |
| Patent corpus, retrieval route, rules extracted and verified, tier-P weighting rule | K4 | `docs/20261031_ALLATOM_PATENT_KNOWLEDGE.md` |
| Overlap and novelty against SureChEMBL, BindingDB patent subset and CycPeptMPDB's two patents; test of hypothesis H-P | K4 | `docs/20261031_ALLATOM_PATENT_KNOWLEDGE.md` |
| Cross-source integration: fraction of records joinable across structure, property, conformation, complex, outcome | K, K2, K3, K4 | integration note to be written after the streams land |
| Use in generation: comparison of hard-only, literature-prior and data-descriptive configurations | method manuscript | `docs/20261031_ALLATOM_LLM_PAPER_DESIGN.md` results sections |
