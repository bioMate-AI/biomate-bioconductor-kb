# Literature and public-dataset evidence

Scores: **TSLP 4/5; IL33 4/5; IL1RL1 4/5.** Confidence: moderate-high for human asthma pathway relevance; this lane does not distinguish therapeutic success or establish a numeric probability. All requested skills were executed.

Rubric: 1 little direct human evidence; 2 chiefly adjacent/animal support; 3 direct association with limited function; 4 multiple human asthma mechanistic observations; 5 independently replicated target-specific human perturbation. Trial results are reserved for the clinical lane.

## Direct asthma evidence

- **L1 · TSLP, IL33 · direct asthma: mild atopic asthma**. 16 people, paired bronchial biopsy before/24h after inhaled allergen. TSLP and IL33 immunoreactivity increased in epithelium and submucosa and correlated with late airway obstruction. This is disease-specific human provocation evidence, not a target-specific intervention. [Primary source](https://pubmed.ncbi.nlm.nih.gov/30185520/)
- **L2 · TSLP, IL33 · direct asthma / separately eosinophils and eosinophilic esophagitis**. human airway cis-eQTL: BEC n107, BAL n94. TSLP rs2416257 protective asthma allele linked to lower expression; rs1837253 lacked expression association. IL33 rs992969 risk allele associated with increased BEC expression. Overlaps genetics lane; do not count twice. [Primary source](https://pubmed.ncbi.nlm.nih.gov/26119467/)
- **L3 · IL33 · direct asthma, especially eosinophilic asthma; no association with atopy for main signals**. Lifelines/DAG/GASP, airway eQTL and human epithelial overexpression. IL33 genetic signals linked to bronchial but not bulk-lung expression; overexpression reduced viability/ROS capture. Shares cohorts with genetic functional literature. [Primary source](https://pubmed.ncbi.nlm.nih.gov/32442646/)
- **L4 · IL1RL1 · direct asthma, type2-high**. human bronchial brush RNA 83 asthma,22 healthy; isoform and plasma function studies. Membrane ST2 and soluble decoy sST2 have different functions; sST2 correlated with inhibition of IL33 signaling. Total gene expression cannot specify the desired perturbation. [Primary source](https://pmc.ncbi.nlm.nih.gov/articles/PMC5033813/)
- **L5 · IL1RL1 · direct asthma severe/eosinophilic features**. 4 cohorts plus lung and epithelial functional experiments. Context-dependent regulation of membrane/soluble isoforms and receptor signaling; genetic findings overlap genetics lane. [Primary source](https://pmc.ncbi.nlm.nih.gov/articles/PMC7205441/)
- **L6 · IL33, IL1RL1 · direct asthma and healthy donor cultures**. ALI n6 controls; organoids n8 controls/n7 asthma, RNA-seq after IL33. No genome-wide significant epithelial transcriptional response; low IL1RL1 expression. Useful negative control: epithelial IL33 source is not necessarily responder. [Primary source](https://pubmed.ncbi.nlm.nih.gov/38050688/)
- **L7 · IL33 · direct asthma**. African-ancestry TWAS n9284; PREPRINT. Nasal IL33 predicted expression associated with asthma at adjusted P<0.1. Hypothesis-support only; no causal proof or separate replication count. bioRxiv API published=NA. [Primary source](https://doi.org/10.1101/2025.02.06.25321273)

## Public datasets ready for follow-up

These are verified metadata records, not new analyses.

- [E-GEOD-67472 / GSE67472](https://www.ebi.ac.uk/biostudies/arrayexpress/studies/E-GEOD-67472) — transcription profiling by array, Homo sapiens. Airway epithelial brushings were obtained for microarray analysis by research bronchoscopy in 62 subjects with mild-to-moderate asthma not on inhaled steroids and 43 healthy controls. Asthma subjects were stratified into 2 subgroups, Th2 high and Th2 low asthma, based on their expression of a three-gene signature of Type 2 inflammation: POSTN, SERPINB2, and CLCA1. Gene expression comparisons were made between: 1. asthmatics and healthy controls, and 2. Th2 high asthma and Th2 Low asthma/Healthy controls. The gene expression alterations most associated with asthma were then used in gene set enrichment analyses and gene signature development to compare this asthma dataset to COPD gene expression datasets.

- [E-GEOD-44037 / GSE44037](https://www.ebi.ac.uk/biostudies/arrayexpress/studies/E-GEOD-44037) — transcription profiling by array, Homo sapiens. The link between upper and lower airways in patients with both asthma and allergic rhinitis is still poorly understood. As the biological complexity of these disorders can be captured by gene expression profiling we hypothesized that the clinical expression of rhinitis and/or asthma is related to differential gene expression between upper and lower airways epithelium. We used micro array to profile gene expression of primary nasal and bronchial epithelial cells from the same individuals and examining the impact of allergic rhinitis with and without concomitant allergic asthma on expression profiles. 17 subjects were included in a cross-sectional study (6 allergic asthma and allergic rhinitis; 5 allergic rhinitis; 6 healthy controls). RNA was extracted from isolated and cultured epithelial cells from bronchial brushes and nasal biopsies, and analyzed by microarray (Affymetrix U133+ PM Genechip Array).

- [E-GEOD-51392 / GSE51392](https://www.ebi.ac.uk/biostudies/arrayexpress/studies/E-GEOD-51392) — transcription profiling by array, Homo sapiens. Rhinovirus infections are the most common cause of asthma exacerbations. The complex responses by the airway epithelium to rhinovirus can be captured by gene expression profiling. We hypothesized that the upper and lower airway epithelium exhibit differential responses to double-stranded RNA (dsRNA), and that this is modulated by the presence of asthma and allergic rhinitis. Identification of dsRNA-induced gene expression profiles by microarray of primary nasal and bronchial epithelial cells from the same individuals and examining the impact of allergic rhinitis with and without concomitant allergic asthma on expression profiles. 17 subjects were included in a cross-sectional study (6 allergic asthma and allergic rhinitis; 5 allergic rhinitis; 6 healthy controls). RNA was extracted from isolated and cultured epithelial cells that were stimulated with Poly(I:C) for 24 hours from bronchial brushes and nasal biopsies, and analyzed by microarray (Affymetrix U133+ PM Genechip Array).

Use GSE67472 for donor-level Th2-high/low asthma comparison and GSE44037/51392 to distinguish asthma-plus-rhinitis from rhinitis alone and viral-mimic responses. Check probe mapping/isoform resolution and study overlap before integrating; microarray total IL1RL1 or TSLP measurements may not resolve functionally different isoforms.

## Adjacent phenotypes and caveats

Rhinitis-only subjects in GSE44037/51392 are adjacent comparator groups, not asthma replication. Eosinophil count and esophagitis findings in L2 are separate traits. No COPD result counted as direct asthma evidence.

- No article-count scoring; clinical-trial publications excluded from independent functional scoring.
- Genetic/eQTL literature is shared evidence with genetics lane, not independent causal support.
- GSE44037 and GSE51392 use same group sizes/site/authors and likely overlapping 17 donors; treat as one cohort until subject identifiers establish independence.
- Dataset accession availability is not evidence of target differential expression.
- PMC OA skill failed HTTP404; saved failure. Web PMC views sometimes returned CAPTCHA; indexed primary article text used.
- Initial PubMed latest-record searches were not comprehensive/date-filtered and are saved for audit only; those unreviewed hits do not enter scores.
- Preprint API has no linked published DOI; not an exhaustive proof it remains unpublished.

Raw plugin responses and failures: `raw/literature_*`. NCBI Datasets returned gene metadata for all three targets; these identity records are not disease evidence.
