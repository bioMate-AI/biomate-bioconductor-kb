# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DSS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DSS)

# Generate simulated count data as shown in the multifactor experiment vignette
counts = matrix(rpois(800, 10), ncol=8)
rownames(counts) = paste0("gene", 1:nrow(counts))
colnames(counts) = paste0("sample", 1:ncol(counts))

# Generate experimental design data frame
design = data.frame(
    gender = c(rep("M", 4), rep("F", 4)), 
    strain = rep(c("WT", "Mutant"), 4)
)
rownames(design) = colnames(counts)

# Write to the required input files
write.table(counts, file="counts.txt", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)
write.table(design, file="design_df.txt", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)