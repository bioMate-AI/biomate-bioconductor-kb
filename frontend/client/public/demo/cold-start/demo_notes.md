# Cold-start demo inputs
These are public tutorial inputs, not your experimental data. sources.json identifies upstream datasets.
BACE assay pIC50 values are converted to IC50_nM. candidate_library.csv contains 500 existing BACE compounds, not newly generated candidates. plate_layout.csv reshapes the first 96 published BACE IC50 values into an illustrative plate layout; it is not an actual plate export. predicted_measured.csv uses a least-squares MW/logP baseline fitted only on the BACE Train split.
ChEMBL hERG uses exact IC50 measurements (nM); blocker threshold is 10,000 nM. Split by compound/scaffold and audit duplicate assays before evaluating.
LFQ-Analyst sample names are preserved. mixOmics nutrimouse is paired gene/lipid data; TCGA is matched mRNA/protein data. No omics measurements are generated.
The NCCTG lung cohort uses time in days, status 1=censored/2=dead, sex 1=male/2=female. This survival endpoint is not a treatment-response label.
The nf-core sequencing fixtures use GRCh37/b37, not GRCh38, and a tiny genomic subset. They demonstrate the pipeline, not clinical diagnostic coverage. MAGeCK has one initial/final column per cell line; these are not biological replicates.
herg_series.csv is one published chromone-2-carboxamide series (ChEMBL document CHEMBL1137327) with measured MCHR1 and hERG IC50 values in nM — a real hit series with a real hERG liability.
rizvi2015_*.csv are the published Rizvi 2015 NSCLC anti-PD-1 exomes (cBioPortal nsclc_mskcc_2015): 16 samples, 7 DCB versus 9 NDB. Real response groups, but a small cohort — report n and power.
ceph1463_genotypes.vcf.gz is the CEPH 1463 pedigree (Illumina Platinum Genomes, GRCh37) reduced to GT:DP:RO:AO over 19,991 sites, with declared relationships in ceph1463.ped. Genotypes are unchanged; depth-based metrics are limited to those sites.
ht29_brunello_counts.tsv and ht29_minlibcas9_counts.tsv are CRISPRcleanR example HT-29 screens, each with a plasmid column and three true screen replicates; CEGv2/NEGv1 are reference essential/non-essential gene lists, not screen data.
proteinGroups_batch.txt with proteomics_batch_design.txt is the 12-run LFQ-Analyst example batch (four replicates each of CD34High/Low/Neg), used for run-level QC only.
pbc_cohort.csv is the Mayo PBC randomised trial (trt 1=D-penicillamine, 2=placebo, NA for the 106 non-randomised cases); status 1 is a liver transplant, which must be handled explicitly.
RCSB structure sequences are experimental constructs, sometimes with tags. Proposed sequence variants must be labeled unmeasured and predicted, never completed assays.
