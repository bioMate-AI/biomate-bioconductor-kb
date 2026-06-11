# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DominoEffect")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DominoEffect)

# Reproduce the vignette's data-preparation code
data("TestData", package = "DominoEffect")
data("SnpData", package = "DominoEffect")
data("DominoData", package = "DominoEffect")

# Serialize TestData to user_file_with_mutations.txt
write.table(TestData, "user_file_with_mutations.txt", header = TRUE, row.names = FALSE, quote = FALSE)

# Serialize DominoData to user_ensembl_gene_list.txt
write.table(DominoData, "user_ensembl_gene_list.txt", header = TRUE, row.names = FALSE, quote = FALSE)

# Serialize SnpData to user_population_SNPs_with_frequency.txt
write.table(SnpData, "user_population_SNPs_with_frequency.txt", header = TRUE, row.names = FALSE, quote = FALSE)