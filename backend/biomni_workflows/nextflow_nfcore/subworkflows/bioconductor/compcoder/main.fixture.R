# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("compcodeR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(compcodeR)

# Generate synthetic data as described in the vignette
# (n.vars and n.diffexp are scaled down slightly for a lightweight test fixture)
B_625_625 <- generateSyntheticData(
    dataset = "B_625_625", 
    n.vars = 1250, 
    samples.per.cond = 5, 
    n.diffexp = 125, 
    repl.id = 1, 
    seqdepth = 1e7, 
    fraction.upregulated = 0.5, 
    between.group.diffdisp = FALSE, 
    filter.threshold.total = 1, 
    filter.threshold.mediancpm = 0, 
    fraction.non.overdispersed = 0, 
    output.file = "B_625_625_5spc_repl1.rds"
)

# Extract the count matrix and sample annotations from the compData object
counts <- count.matrix(B_625_625)
annot <- sample.annotations(B_625_625)

# Serialize to the expected input files
write.table(counts, file = "count.matrix", sep = "\t", quote = FALSE, col.names = NA)
write.table(annot, file = "sample.annot", sep = "\t", quote = FALSE, col.names = NA)