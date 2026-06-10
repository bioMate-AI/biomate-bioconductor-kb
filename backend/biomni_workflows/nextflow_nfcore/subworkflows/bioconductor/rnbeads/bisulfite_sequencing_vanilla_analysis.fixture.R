# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RnBeads", "RnBeads.hg19")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(RnBeads))
suppressPackageStartupMessages(library(RnBeads.hg19))

# Reproduce the vignette's data-preparation code
# This loads the 'small.example.object' into the environment
data(small.example.object)

# The object created is 'rnb.set.example'
# rnb.set.example is an RnBSet object

# Serialize pheno data to sample_annotation.csv
# Extract the phenotypic data from the RnBSet object
pheno_data <- pheno(rnb.set.example)

# Write the phenotypic data to a CSV file
# The vignette uses 'sample.annotation.csv' as input
write.csv(pheno_data, "sample_annotation.csv", row.names = FALSE)

# Serialize annotation data to bed file
# Extract site annotations from the RnBSet object
site_annotations <- annotation(rnb.set.example)

# Prepare data for BED file format (chrom, chromStart, chromEnd, name)
# BED format is 0-indexed for chromStart, 1-indexed for chromEnd.
# RnBeads annotation 'Start' and 'End' are typically 1-indexed inclusive.
bed_data <- data.frame(
  chrom = site_annotations$Chromosome,
  chromStart = site_annotations$Start - 1, # Convert 1-based start to 0-based
  chromEnd = site_annotations$End,         # End is 1-based exclusive in BED, matches 1-based inclusive in RnBeads
  name = site_annotations$ID
)

# Write the BED data to a tab-separated file without header or row names
write.table(bed_data, "bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)