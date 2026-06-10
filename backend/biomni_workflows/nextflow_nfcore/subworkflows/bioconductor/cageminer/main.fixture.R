# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cageminer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cageminer)

# Set seed for reproducibility if any random operations were involved,
# though data() calls are deterministic.
set.seed(123)

# 1. Reproduce data-preparation code from the vignette
# GRanges of gene coordinates
data(gene_ranges)

# GRanges of SNP positions
data(snp_pos)

# SummarizedExperiment of pepper response to Phytophthora root rot (RNA-seq)
data(pepper_se)

# Load guide genes
data(guides)

# 2. Serialize objects to the declared input files

# gene_ranges.gr (GRanges object)
saveRDS(gene_ranges, "gene_ranges.gr")

# snp_pos.gr (GRanges object)
saveRDS(snp_pos, "snp_pos.gr")

# pepper_se.rds (SummarizedExperiment object)
saveRDS(pepper_se, "pepper_se.rds")

# guides.tsv (data frame)
# Match read.table parameters: header = TRUE, sep = "\t", stringsAsFactors = FALSE
write.table(guides, "guides.tsv", sep = "\t", row.names = FALSE, quote = FALSE, col.names = TRUE)

# Note: The file 'tfs.tsv' is listed as an input file in the workflow's read excerpt,
# but the provided vignette excerpt does not contain any data preparation code
# for an object named 'tfs' or for generating 'tfs.tsv'.
# Following the instruction to "Reproduces the VIGNETTE'S OWN data-preparation code"
# and "NEVER invent a name", 'tfs.tsv' cannot be generated based on the provided vignette.