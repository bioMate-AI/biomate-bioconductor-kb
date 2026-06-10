# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MIRit")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MIRit)

data(geneCounts, package = "MIRit")
data(mirnaCounts, package = "MIRit")

meta <- data.frame(primary = colnames(mirnaCounts),
                   mirnaCol = colnames(mirnaCounts),
                   geneCol = colnames(geneCounts),
                   disease = c(rep("PTC", 8), rep("NTH", 8)),
                   patient = c(rep(paste("Sample_", seq(8), sep = ""), 2)))

experiment <- MirnaExperiment(mirnaExpr = mirnaCounts,
                              geneExpr = geneCounts,
                              samplesMetadata = meta,
                              pairedSamples = TRUE)

saveRDS(experiment, file = "experiment.rds")