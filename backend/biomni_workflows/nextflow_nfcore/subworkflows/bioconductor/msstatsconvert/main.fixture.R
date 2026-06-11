# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MSstatsConvert")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MSstatsConvert)

# Reproduce the vignette's own data-preparation code
# The vignette itself sources its example data from system.file
maxquant_evidence_data <- read.csv(system.file("tinytest/raw_data/MaxQuant/mq_ev.csv", package = "MSstatsConvert"))
maxquant_proteins_data <- read.csv(system.file("tinytest/raw_data/MaxQuant/mq_pg.csv", package = "MSstatsConvert"))
maxquant_annotation_data <- read.csv(system.file("tinytest/raw_data/MaxQuant/annotation.csv", package = "MSstatsConvert"))

# Serialize the objects to the declared input files
write.csv(maxquant_evidence_data, "mq_ev.csv", row.names = FALSE)
write.csv(maxquant_proteins_data, "mq_pg.csv", row.names = FALSE)
write.csv(maxquant_annotation_data, "annotation.csv", row.names = FALSE)