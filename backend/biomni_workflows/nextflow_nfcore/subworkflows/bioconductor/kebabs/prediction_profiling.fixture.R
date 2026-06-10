# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("kebabs", "Biostrings")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(kebabs)
library(Biostrings)

# Load example data from the kebabs package
data(TFBS)

# 1. Generate sequences.fasta
# We use a subset of the enhancerFB DNAStringSet for the sequences to profile
sequences <- enhancerFB[1:50]
writeXStringSet(sequences, filepath = "sequences.fasta", format = "fasta")

# 2. Generate trained_model.RData
# We train a model using the vignette's exact logic
set.seed(0)
numSamples <- length(enhancerFB)
trainingFraction <- 0.7
train <- sample(1:numSamples, trainingFraction * numSamples)

specK2 <- spectrumKernel(k=2)
model <- kbsvm(x=enhancerFB[train], y=yFB[train], kernel=specK2,
               pkg="e1071", svm="C-svc", cost=15)

# Save the trained model object to the expected RData file
save(model, file = "trained_model.RData")