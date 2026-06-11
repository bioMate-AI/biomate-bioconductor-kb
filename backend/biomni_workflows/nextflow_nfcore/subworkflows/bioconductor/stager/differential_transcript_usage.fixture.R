# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("stageR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(stageR)

# Construct synthetic data for stageRTx since the vignette's transcript dataset is not provided
genes <- paste0("gene", 1:50)
transcripts <- paste0("tx", 1:150)

tx2gene <- data.frame(
  transcript = transcripts,
  gene = rep(genes, each = 3),
  stringsAsFactors = FALSE
)

set.seed(123)
pScreen <- runif(length(genes))
names(pScreen) <- genes

pConfirmation <- matrix(runif(length(transcripts) * 2), nrow = length(transcripts), ncol = 2)
rownames(pConfirmation) <- transcripts
colnames(pConfirmation) <- c("contrast1", "contrast2")

saveRDS(pScreen, "pScreen.rds")
saveRDS(pConfirmation, "pConfirmation.rds")
saveRDS(tx2gene, "tx2gene.rds")