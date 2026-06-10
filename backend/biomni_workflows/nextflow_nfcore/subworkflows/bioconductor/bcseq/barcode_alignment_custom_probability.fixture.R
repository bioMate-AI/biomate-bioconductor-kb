# Load the bcSeq package as it's the subject of the workflow.
# Although the data generation itself uses only base R functions,
# the prompt explicitly asks to load `bcSeq`.
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bcSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bcSeq)

# Set seed for reproducibility as specified in the vignette
set.seed(1121)

# --- Reproduce data preparation for libFile.fasta (from vignette 'genlib' chunk) ---
# The workflow expects 'libFile.fasta'
lFName    <- "./libFile.fasta"
bases     <- c(rep('A', 4), rep('C',4), rep('G',4), rep('T',4))
numOfBars <- 7
Barcodes  <- rep(NA, numOfBars*2)
for (i in 1:numOfBars){
    Barcodes[2*i-1] <- paste0(">barcode_ID: ", i)
    Barcodes[2*i]   <- paste(sample(bases, length(bases)), collapse = '')
}
write(Barcodes, lFName)

# --- Reproduce data preparation for sampleFile.fastq (from vignette 'genRead' chunk) ---
# The vignette generates 'readFile.fastq', which needs to be renamed to 'sampleFile.fastq'
rFName     <- "./readFile.fastq"
numOfReads <- 8
Reads      <- rep(NA, numOfReads*4)
for (i in 1:numOfReads){
    Reads[4*i-3] <- paste0("@read_ID_",i)
    Reads[4*i-2] <- Barcodes[2*sample(1:numOfBars,1,
        replace=TRUE, prob=seq(1:numOfBars))]
    Reads[4*i-1] <- "+"
    Reads[4*i]   <- paste(rawToChar(as.raw(
        33+sample(20:30, length(bases),replace=TRUE))),
        collapse='')
}
write(Reads, rFName)

# --- Rename the generated file to match the workflow's expected input name ---
# The workflow expects 'sampleFile.fastq', but the vignette creates 'readFile.fastq'.
file.rename(from = rFName, to = "./sampleFile.fastq")