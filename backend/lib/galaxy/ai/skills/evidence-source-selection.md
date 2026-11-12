---
name: evidence-source-selection
title: Evidence Source Selection
triggers: [evidence, source, database, which source, data source, retrieve, look up, lookup, structure, sar, structure-activity, potency, affinity, ic50, binding, inhibitor, ligand, target, druggable, tractability, pathway, signalling, signaling, interaction, variant, mutation, expression, pharmacology, mechanism]
domains: [drug_discovery, pharmacology, biochemistry, genomics, systems_biology]
version: 1.0
---

## Role
Choose which external evidence sources a question actually needs, then gather from
**all relevant** ones — not just whichever the entity type happens to map to. The
wrong default (a target that reads as a "gene" → only gene databases) is why
structure/binding/target questions come back thin. Pick sources by the question's
**intent**, in parallel, and let literature corroborate — never stand alone — for a
factual answer.

This skill is the human/LLM-readable companion of the deterministic selector
`galaxy.ai.evidence_source_router.select_sources`; both draw their ids from the
canonical registry `galaxy.ai.data_sources` (the single source of truth — add a
source there, reference it here).

## Facet → sources (pick every facet the question raises)

| Facet (what the question asks) | Cues | Sources to query |
|---|---|---|
| **Structure / fold / conformation** | structure, crystal, fold, domain, pocket, DFG, allosteric, cryo-EM | PDB, PDBe, AlphaFold, InterPro, UniProt |
| **Bioactivity / SAR / potency / binding** | SAR, potency, IC50/EC50/Ki/Kd, affinity, inhibitor, selectivity, ligand, nanomolar, dose–response | **ChEMBL, BindingDB, PubChem, ChEBI, Pharos, UniProt, PDB** |
| **Target biology / druggability** | target, druggable, tractability, therapeutic target, target–disease | Pharos, Open Targets, ChEMBL, UniProt, STRING |
| **Pathway / network / signalling** | pathway, signalling, network, interactome, enrichment, upstream/downstream | KEGG, Reactome, GO, STRING |
| **Variant / mutation** | variant, mutation, SNP, allele, polymorphism, resistance mutation | ClinVar, dbSNP, gnomAD |
| **Disease / phenotype / clinical** | disease, phenotype, syndrome, indication, clinical, biomarker | Open Targets, HPO, OMIM, ClinVar, ClinicalTrials.gov |
| **Gene identity (baseline)** | a named gene/target, "what is GENE" | NCBI Gene, Ensembl, UniProt, GO, STRING |
| **Literature (always)** | — | PubMed, Europe PMC, Semantic Scholar, local corpus, Paperclip |

## Worked example — the failure this fixes
> *"Known SAR for imatinib-like phenylaminopyrimidines — what drives ABL1 potency?"*

Entity detection calls ABL1 a **gene**, so an entity-type router pulls only gene
sources and never reaches the medicinal-chemistry evidence. By **intent** this is a
*bioactivity + structure* question about a *target*, so the right sources are
**ChEMBL / BindingDB (IC50 series) + PDB (contact maps, DFG-out) + Pharos / Open
Targets (tractability) + UniProt**, with PubMed as corroboration. That is what the
answer needs — binding tables and structures, not just abstracts.

## Rules
- **Fan out in parallel** to every selected source; merge; deduplicate.
- **Literature never stands alone** for a factual/mechanistic claim — pair it with the
  structural/bioactivity/target records.
- **Cite the record id and its source** (e.g. ChEMBL id, PDB id); never invent one.
- Prefer **structures + binding tables over abstracts** for SAR/potency questions.
- Normalise target residue numbering (e.g. ABL1 1a/1b: Thr315 ≡ Thr334) so evidence
  for the same residue does not fragment across sources.
