# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("anota2seq", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(anota2seq)
library(SummarizedExperiment)

data(anota2seq_data)

countData <- as.matrix(cbind(anota2seq_data_P[1:1000,], anota2seq_data_T[1:1000,]))

# annotations
anot <- data.frame(
    row.names = colnames(countData),
    #information on mRNA types
    RNA = c(rep("P",8),rep("T",8)), 
    #samples classes
    treatment = rep(c(rep("ctrl",4),rep("treatment",4)),2), 
    #sample Pairs
    samplePairs = rep(c(paste("ctrl",c(1:4),sep="_"),paste("treatment",c(1:4),sep="_")),2),
    # batch information, in this case replicate number
    batches = rep(c(1,2,3,4),4)) 

# Create the SummarizedExperiment
mySummarizedExperiment <- SummarizedExperiment(
    assays = list(counts = countData),
    colData = anot)

saveRDS(mySummarizedExperiment, "mySummarizedExperiment.rds")