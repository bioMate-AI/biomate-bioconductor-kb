# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("EBSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(EBSeq)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette uses `data(IsoList)` to get isoform-level data.
# This list contains IsoMat (isoform counts), IsoNames (isoform IDs),
# and IsosGeneNames (gene IDs for isoforms).
data(IsoList)

# Extract the necessary components from IsoList
IsoMat <- IsoList$IsoMat
IsoNames <- IsoList$IsoNames
IsosGeneNames <- IsoList$IsosGeneNames

# The workflow reads:
# IsoMat_df <- read.csv("isoform_counts.csv", row.names = 1, check.names = FALSE)
# IsoAnno <- read.csv("isoform_annotations.csv", stringsAsFactors = FALSE)
# SampleConds <- read.csv("sample_conditions.csv", stringsAsFactors = FALSE)

# 2. Serialize objects to declared input files

# For isoform_counts.csv:
# The workflow expects a CSV where the first column becomes row names.
# `IsoMat` is a matrix with row names (isoform IDs) and column names (sample IDs).
# `write.csv` by default writes row names as the first column, which matches the workflow's `read.csv`.
write.csv(IsoMat, "isoform_counts.csv")

# For isoform_annotations.csv:
# The workflow expects a data frame with isoform annotations.
# We can create this from `IsoNames` and `IsosGeneNames`.
IsoAnno_df <- data.frame(
    IsoformID = IsoNames,
    GeneID = IsosGeneNames,
    stringsAsFactors = FALSE
)
# The workflow reads this without specifying row.names, so we should not write row names.
write.csv(IsoAnno_df, "isoform_annotations.csv", row.names = FALSE)

# For sample_conditions.csv:
# The workflow expects a data frame with sample conditions.
# The vignette uses `Conditions=as.factor(rep(c("C1","C2"),each=5))` for 10 samples.
# `IsoMat` has 10 columns, which correspond to 10 samples.
SampleIDs <- colnames(IsoMat)
Conditions_vector <- rep(c("C1", "C2"), each = 5) # Matches the vignette's example conditions

SampleConds_df <- data.frame(
    SampleID = SampleIDs,
    Condition = Conditions_vector,
    stringsAsFactors = FALSE
)
# The workflow reads this without specifying row.names, so we should not write row names.
write.csv(SampleConds_df, "sample_conditions.csv", row.names = FALSE)