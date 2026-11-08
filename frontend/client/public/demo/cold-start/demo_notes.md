# Cold-start demo inputs
These are public tutorial inputs, not your experimental data. sources.json identifies upstream datasets.
BACE assay pIC50 values are converted to IC50_nM. candidate_library.csv contains 500 existing BACE compounds, not newly generated candidates. plate_layout.csv reshapes the first 96 published BACE IC50 values into an illustrative plate layout; it is not an actual plate export. predicted_measured.csv uses a least-squares MW/logP baseline fitted only on the BACE Train split.
ChEMBL hERG uses exact IC50 measurements (nM); blocker threshold is 10,000 nM. Split by compound/scaffold and audit duplicate assays before evaluating.
LFQ-Analyst sample names are preserved. mixOmics nutrimouse is paired gene/lipid data; TCGA is matched mRNA/protein data. No omics measurements are generated.
The NCCTG lung cohort uses time in days, status 1=censored/2=dead, sex 1=male/2=female. This survival endpoint is not a treatment-response label.
The nf-core sequencing fixtures use GRCh37/b37, not GRCh38, and a tiny genomic subset. They demonstrate the pipeline, not clinical diagnostic coverage. MAGeCK has one initial/final column per cell line; these are not biological replicates.
RCSB structure sequences are experimental constructs, sometimes with tags. Proposed sequence variants must be labeled unmeasured and predicted, never completed assays.
