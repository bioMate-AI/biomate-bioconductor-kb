# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("aCGH")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(aCGH)

# Construct the path to the example data directory within the aCGH package
datadir <- system.file(package = "aCGH")
datadir <- paste(datadir, "/examples", sep="")

# Read the example data files into R objects, using the exact read.table calls
# from the vignette. These data frames will then be written to the working directory.
clones.info <-
      read.table(file = file.path(datadir, "clones.info.ex.txt"),
                 header = TRUE, sep = "\t", quote="", comment.char="")
log2.ratios <-
      read.table(file = file.path(datadir, "log2.ratios.ex.txt"),
                 header = TRUE, sep = "\t", quote="", comment.char="")
pheno.type <-
      read.table(file = file.path(datadir, "pheno.type.ex.txt"),
                 header = TRUE, sep = "\t", quote="", comment.char="")

# Write the R objects to files in the current working directory.
# The write.table arguments are chosen to match the format expected by the workflow's
# read.table calls (header=T, sep="\t", quote="", comment.char="").
# row.names = FALSE is used to prevent writing an extra column for R's internal row names,
# as the workflow's read.table calls do not specify how to handle row names,
# implying they are not part of the data columns.
write.table(clones.info, file = "clones.info.ex.txt",
            sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
write.table(log2.ratios, file = "log2.ratios.ex.txt",
            sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
write.table(pheno.type, file = "pheno.type.ex.txt",
            sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)