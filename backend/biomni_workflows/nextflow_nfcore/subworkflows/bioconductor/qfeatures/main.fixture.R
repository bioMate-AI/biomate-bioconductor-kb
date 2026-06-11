# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("QFeatures")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("QFeatures")

# Load the example dataset from the QFeatures package as shown in the vignette
data("hlpsms", package = "QFeatures")

# Write the tabular peptide-level quantification file
write.table(hlpsms, file = "cptac_a_b_peptides.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# Create and write the annotations.csv sample metadata sheet
# The vignette uses columns 1:10 as quantitative columns and assigns specific tags
sample_names <- colnames(hlpsms)[1:10]
tags <- c("126", "127N", "127C", "128N", "128C", "129N", "129C", "130N", "130C", "131")

annotations <- data.frame(
    Sample = sample_names,
    tag = tags
)

write.csv(annotations, file = "annotations.csv", row.names = FALSE, quote = FALSE)