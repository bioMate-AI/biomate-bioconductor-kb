# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PathoStat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PathoStat)

# Create synthetic abundance data
abundance <- matrix(
    c(100, 20, 5, 2,
      150, 25, 0, 1,
      50, 100, 20, 0,
      20, 50, 100, 0,
      0, 10, 50, 100), 
    nrow = 4, ncol = 5, byrow = FALSE
)
rownames(abundance) <- c("ti|1|org|Bacteria", "ti|2|org|Viruses", "ti|3|org|Fungi", "ti|4|org|Archaea")
colnames(abundance) <- paste0("Sample", 1:5)

# Create synthetic coldata
coldata <- data.frame(
    Condition = c("Control", "Control", "Case", "Case", "Case"),
    Batch = c("B1", "B1", "B2", "B2", "B1"),
    Age = c(25, 30, 45, 50, 35),
    row.names = paste0("Sample", 1:5)
)

# Write to the required input files
write.csv(abundance, "abundance.csv", quote = FALSE)
write.csv(coldata, "coldata.csv", quote = FALSE)