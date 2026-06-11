# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DSS", "bsseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DSS)
library(bsseq)

# Read the example data shipped with the DSS package
path <- file.path(system.file(package="DSS"), "extdata")
dat1.1 <- read.table(file.path(path, "cond1_1.txt"), header=TRUE)
dat1.2 <- read.table(file.path(path, "cond1_2.txt"), header=TRUE)
dat2.1 <- read.table(file.path(path, "cond2_1.txt"), header=TRUE)
dat2.2 <- read.table(file.path(path, "cond2_2.txt"), header=TRUE)

# Create the BSseq object
BSobj <- makeBSseqData(list(dat1.1, dat1.2, dat2.1, dat2.2), c("C1", "C2", "N1", "N2"))

# Save the BSseq object to BSobj.RData
save(BSobj, file="BSobj.RData")

# Create a design data frame for the samples
design_df <- data.frame(
  Sample = c("C1", "C2", "N1", "N2"),
  condition = c("C", "C", "N", "N"),
  gender = c("M", "F", "M", "F")
)

# Save the design data frame to design_df.txt
write.table(design_df, file="design_df.txt", sep="\t", quote=FALSE, row.names=FALSE)