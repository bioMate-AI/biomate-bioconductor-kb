# Expression and tissue/cell context

Queried 2026-09-11 using the installed Life Science Research plugin scripts for HPA, GTEx eQTL, CELLxGENE and Bgee. All four APIs succeeded after network-enabled execution. Raw payloads and requests are under `raw/expression_*`.

| Target | Score (1–5) | Confidence | Disease-relevant rationale |
|---|---:|---|---|
| TSLP | 4 | Moderate-high | Respiratory basal-cell expression plus human asthma airway induction. Baseline bulk expression alone understates inducible epithelial cytokine biology. No TSLP eQTL was returned for the tested asthma marker. |
| IL33 | 4 | Moderate-high | Respiratory basal/secretory and endothelial expression, human asthma epithelial–mast-cell feedback, and published airway regulatory evidence. Expression changes vary by asthma state/endotype; bulk queried marker yields only aorta eQTL. |
| IL1RL1 | 4 | Moderate-high | Lung, mast-cell, basophil and eosinophil expression; strong lung eQTL. Soluble decoy ST2 versus membrane signaling ST2 prevents interpreting total transcript direction as therapeutic direction. |

Scores assess plausible disease-relevant expression/context: 1 limited support; 2 adjacent or baseline only; 3 relevant tissue/cells; 4 tissue/cells plus direct human asthma functional/state support; 5 unusually complete replicated cell-state and isoform-resolved causal context. This lane does not award points for drug approval or GWAS significance itself. It cannot discriminate the three targets reliably enough to break an overall tie.

## Baseline expression (not asthma differential expression)

[HPA TSLP](https://www.proteinatlas.org/ENSG00000145777-TSLP): respiratory basal cells 21.7 nCPM, alongside fibroblasts and keratinocytes. Bulk tissue-enhanced annotation emphasizes liver/urinary bladder; this is not evidence against an inducible airway role. HPA reports not detected in its blood immune-cell summary, which does not mean absence from stimulated or disease-specific cells.

[HPA IL33](https://www.proteinatlas.org/ENSG00000137033-IL33): respiratory basal cells 262.6 nCPM, respiratory secretory cells 92.5, vascular endothelial cells 185.7, fibroblasts 100.1. These are baseline atlas values, not an asthma/control fold change, and should not be compared across genes as target validation strength.

[HPA IL1RL1](https://www.proteinatlas.org/ENSG00000115602-IL1RL1): lung 158.6 nTPM; mast cells 329.3 nCPM; blood basophils 38.4 and eosinophils 29.4 nTPM. HPA's gene-level summaries do not resolve soluble versus membrane ST2.

Bgee SPARQL returns a healthy lung expression relationship (UBERON:0002048) for all three genes. This is qualitative presence, not quantitative asthma replication. Saved distinct-gene query avoids counting multiple age/sex/condition records as independent evidence.

## Direct human asthma / airway evidence

- TSLP: a human asthma cohort reported higher airway TSLP in type-2-high asthma, while IL33 was not elevated in that cohort. [JCI Insight original study](https://insight.jci.org/articles/view/148103).
- TSLP and IL33: bronchial allergen challenge in patients with atopic asthma increased epithelial/submucosal alarmin immunoreactivity, correlated with late airway obstruction. This is direct asthma evidence in an allergic-asthma subset, not generic atopy evidence. [Original study, PMID 30185520](https://pubmed.ncbi.nlm.nih.gov/30185520/).
- IL33: primary human airway epithelial/mast-cell coculture and airway biopsy observations support a feed-forward type-2 circuit accentuated in asthma-derived epithelium. [JCI original study](https://www.jci.org/articles/view/126402).
- IL33: functional regulatory mapping implicates rs1888909 in airway IL33 expression. This published cell-context evidence is different from a bulk GTEx eQTL and is not a new colocalization analysis. [Nature Communications original study](https://www.nature.com/articles/s41467-021-26347-z).
- IL1RL1: rs1420101 associates with soluble ST2 transcript and secreted protein in cultured airway epithelial cells; isoform/tissue effects matter. [Original JCI study](https://pmc.ncbi.nlm.nih.gov/articles/PMC5033813/).
- IL1RL1: another study found bronchial-brush IL1RL1 gene expression not different between health and asthma, despite differences in ST2 protein/release. This limits a simple total-expression disease classifier. [Original study, PMID 32516479](https://pubmed.ncbi.nlm.nih.gov/32516479/).

## GTEx v10 variant queries

The plugin resolved rsIDs to GRCh38 and queried GTEx v2. These are eQTL p-values, NOT asthma GWAS p-values.

| Query marker | Returned evidence | Interpretation |
|---|---|---|
| rs1837253 (TSLP locus) | 3 rows: WDR36 in esophagus gastroesophageal junction/adipose; ENSG00000248428 in testis | No returned TSLP/lung row; absence in this query is not evidence of no regulatory effect. |
| rs928413 (IL33 locus) | IL33 in artery aorta: p=2.90e-7, NES=-0.169 | Supports regulatory activity in that bulk tissue, not airway-specific causality. |
| rs1420101 (IL1RL1 locus) | 58 rows; IL1RL1 lung p=1.80e-33, NES=-0.348; also IL18R1 lung and neighboring genes | Strong lung regulatory association but multi-gene locus and isoform ambiguity. |

NES is relative to the API's GRCh38 alternate allele (respectively C, A, T); no asthma risk-allele harmonization or colocalization was performed. Never infer protective versus harmful modulation from these signs alone. No cell-specific eQTL replication was newly computed.

## CELLxGENE discovery and adjacent phenotypes

Discovered 390 public collections, then retrieved [integrated Human Lung Cell Atlas](https://cellxgene.cziscience.com/collections/6f6d381a-7701-4781-935c-db10d30de293). The healthy core has 584,944 cells; full atlas 2,282,447 cells. Metadata lists normal and multiple lung diseases, including COPD and chronic rhinitis, but **does not list asthma** for these retrieved datasets. They are baseline/adjacent reference resources, not asthma replication. No matrix was downloaded and no per-target single-cell expression or differential expression was calculated here. Public discovery is not training ingestion. Atopy-only, rhinitis and COPD evidence is not counted toward the direct-asthma score.

## Main caveats

HPA/Bgee are primarily baseline references; disease activation, tissue compartment, medication and rare-cell dropout matter. Total IL1RL1 aggregates antagonistic soluble-decoy and membrane-signaling biology; total TSLP also lacks isoform resolution. Bulk GTEx association is not colocalization or therapeutic direction. Literature context overlaps the literature lane and must not be treated as independent replicated cohorts twice. Scores remain provisional pending harmonized asthma case/control cell-state and isoform analyses.

A negative human culture experiment further separates IL33-producing cells from responding cells: asthma/control bronchial epithelial organoids showed no genome-wide significant transcriptional response to IL-33 under the tested conditions, with low IL1RL1 expression. This is an assay/context limitation on epithelial-autocrine interpretations, not a refutation of signaling into immune cells. [Original study, PMID 38050688](https://pubmed.ncbi.nlm.nih.gov/38050688/). Literature-lane airway eQTL studies and the ST2 isoform study are shared sources, not new independent replication counts for this lane.
