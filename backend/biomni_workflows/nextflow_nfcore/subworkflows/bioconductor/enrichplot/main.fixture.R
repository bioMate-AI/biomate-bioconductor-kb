# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("enrichplot")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(enrichplot)

# The vignette contains no code and points to an external book.
# The workflow expects 'input.csv' but provides no read excerpt.
# We generate a minimal synthetic 'input.csv' representing a typical enrichment result table to satisfy the file requirement.

df <- data.frame(
    ID = c("GO:0008150", "GO:0009987", "GO:0003674"),
    Description = c("biological_process", "cellular process", "molecular_function"),
    GeneRatio = c("10/100", "20/100", "15/100"),
    BgRatio = c("100/1000", "200/1000", "150/1000"),
    pvalue = c(0.001, 0.005, 0.01),
    p.adjust = c(0.002, 0.006, 0.02),
    qvalue = c(0.002, 0.006, 0.02),
    geneID = c("1/2/3", "4/5/6", "7/8/9"),
    Count = c(3, 3, 3),
    stringsAsFactors = FALSE
)

write.csv(df, "input.csv", row.names = FALSE)