# Outcome-driven data collection and evaluation

## Decision

The therapeutic objectives require measured outcome labels and independent evaluation. More omics pretraining alone does not close these gaps. This collection is separate from existing pretraining assets: new candidate evaluation cohorts must remain quarantined from training and retrieval during blind evaluation until overlap and split decisions are frozen. No objective is promoted because an adapter runs.

## Collection lanes

| Objective | Priority source and present access | Required labels and next action | Evaluation unit and split |
|---|---|---|---|
| Sustained response / treatment withdrawal | ImmPort SDY1490 iWITH; ClinicalTrials.gov completed RA/asthma/lupus trials downloaded by paginated query | Obtain participant intervention, visit, assessment, adverse-event and withdrawal tables. Verify event/last-follow-up dates, censoring, discontinuation reasons, rescue medication and treatment strategy. ImmPort study API requires authentication; no participant download claimed. Trial summaries are aggregate evidence, not patient survival labels. | Patient trajectories; external trial/site validation; distinguish sustained response from optimal treatment duration. Optimal duration requires strategy-comparison evidence, not merely observed persistence. |
| Target durability | R4RA longitudinal synovial/clinical data; GEO GSE113156 and GSE35455 | Link pretreatment and on-treatment sample IDs to patients, treatment and outcomes; verify actual label tables. R4RA documents biopsies at baseline/16 weeks and clinical data at baseline/16/24 weeks. Changes alone do not establish target escape or causal durability. | Entire patient held out; independent study; all timepoints kept together. |
| Treatment response | GEO GSE15316, GSE113156, GSE35455; R4RA | Downloaded GEO SOFT records require sample-level label audit and matrix inspection. Extract pretreatment predictors and endpoint-specific response labels. GSE15316 is a small cohort (repository describes 9 patients), not broad validation. | Patient, study, treatment; compare clinical-only and linear expression baselines. |
| Modality-specific target tractability | Existing S3 BindingDB_All_202409.tsv.gz (493,860,614 bytes inventoried), ChEMBL | Parse assay target/organism, construct, binding type, units, inequalities, compound identity, source/publication and measured inactive results. Resolve overlap. Add modality-specific engagement evidence. Binding affinity is one component, not global druggability. | Target-family, compound-scaffold and publication/time splits; never equate untested with inactive. |
| Safety | ClinicalTrials.gov structured adverse-event results; ImmPort clinical tables | Preserve randomized arm denominators, follow-up, seriousness and event definitions. Genetic evidence is complementary, not adverse-event labels. Aggregate clinical outcomes cannot identify individual toxicity. | Trial/compound external holdout; patient holdout if authorized individual records available. |
| Combination benefit | DrugComb candidate, then disease-relevant immune combination screens | Retrieve observed dose matrices, single-agent controls, replicates and assay context. Preserve Bliss/Loewe/HSA/ZIP definitions. Oncology screens are transfer-learning candidates, not autoimmune efficacy validation. | Drug-pair and cell-context/study splits, including monotherapy comparison. |
| H1-H4 mechanisms | Existing CZI, paired anchors, ribosome, proteome and HAP1 inventory | Expand independent donor/target/assay/HLA contexts; require genuinely paired perturbation effects. Ribosome abundance is not translation efficiency. Peptide nondetection is not a measured negative. | Donor, perturbation target, study and HLA/context held out as appropriate. |

## Admission criteria

Each source must have a version and SHA256; access/license status; actual files and field dictionary; target/disease/modality scope; independent patient/donor/assay counts; observed labels and missingness; deduplication against all existing training/KG/text; and a frozen role (train, development, external test or evidence-only). Public accessibility alone is not a license assessment. Keep data training-ineligible pending review.

No universal sample-size cutoff is asserted. Determine adequacy from event counts, number of independent studies, label reliability, uncertainty intervals and a predeclared performance target. Establish endpoint-specific baselines and calibration before comparing complex models. Trial results can be used for aggregate outcome evidence but not silently converted to patient examples.

## Sources checked

- ImmPort iWITH listing: https://docs.immport.org/data/release/notes/DR43_DataRelease/
- ImmPort authenticated study API: https://docs.immport.org/apidocumentation/shareddataapi/study/
- R4RA data portal: https://r4ra.hpc.qmul.ac.uk/
- GEO: https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE15316 ; https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE113156 ; https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE35455
- ChEMBL API: https://chembl.gitbook.io/chembl-interface-documentation/web-services/chembl-data-web-services
- ClinicalTrials.gov results schema: https://clinicaltrials.gov/data-api/about-api/study-data-structure
- DrugComb primary report: https://pmc.ncbi.nlm.nih.gov/articles/PMC8218202/

## Execution

`acquire.py` downloads full GEO text responses (may include expression tables) and paginates a deliberately broad completed-trial discovery query for RA, asthma and lupus. Search matches are candidates, not adjudicated relevant trials. `acquisition_manifest.json` records successes/failures and hashes. Raw data remains local and outside Git; do not push raw participant-related files or large matrices with code. No new labels are used for optimization at this stage.
