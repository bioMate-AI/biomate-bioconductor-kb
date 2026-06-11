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
# The workflow reads multi-condition isoform data.
# Chunks 15-19 of the vignette provide this data.
data(IsoMultiList)
IsoMultiMat <- IsoMultiList[[1]]
IsoNames.Multi <- IsoMultiList$IsoNames
IsosGeneNames.Multi <- IsoMultiList$IsosGeneNames
Conditions <- c("C1","C1","C2","C2","C3","C3","C4","C4")

# 2. Serialize objects to EACH declared input file

# multi_condition_isoform_counts.csv
# The workflow reads this with `row.names = 1`.
# Therefore, the first column of the CSV should contain the row names (isoform IDs).
write.csv(IsoMultiMat, "multi_condition_isoform_counts.csv", row.names = TRUE)

# isoform_annotations.csv
# The workflow reads this without specifying row names, implying no row names are expected.
# This file should contain isoform IDs and their corresponding gene IDs.
anno_df <- data.frame(
    IsoformID = IsoNames.Multi,
    GeneID = IsosGeneNames.Multi,
    stringsAsFactors = FALSE
)
write.csv(anno_df, "isoform_annotations.csv", row.names = FALSE)

# multi_conditions.csv
# The workflow reads this without specifying row names, implying no row names are expected.
# This file should contain sample names and their experimental conditions.
# The sample names are the column names of IsoMultiMat.
cond_df <- data.frame(
    Sample = colnames(IsoMultiMat),
    Condition = Conditions,
    stringsAsFactors = FALSE
)
write.csv(cond_df, "multi_conditions.csv", row.names = FALSE)