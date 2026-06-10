# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("fastseg")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(fastseg)

# Reproduce the vignette's data-preparation code to materialize the example object
# Load the coriell dataset
data(coriell)

# Extract samplenames, data matrix, chromosome, and map location
samplenames <- colnames(coriell)[4:5]
data <- as.matrix(coriell[4:5])
# The vignette comments out the NA handling, so we will too.
# data[is.na(data)] <- median(data, na.rm=TRUE)
chrom <- coriell$Chromosome
maploc <- coriell$Position

# The 'data' object (a matrix) is the primary input for various fastseg calls
# and is the most likely candidate for the 'data2' file content.

# Serialize the 'data' object to EACH declared input file in the exact format

# For data2.rds: readRDS("data2.rds")
saveRDS(data, "data2.rds")

# For data2.csv: read.csv("data2.csv", header = TRUE, check.names = FALSE)
# write.csv by default writes column names and uses comma separator.
# row.names = FALSE prevents writing an extra column for row names.
write.csv(data, "data2.rds", row.names = FALSE)

# For data2.tsv: read.delim("data2.tsv", header = TRUE, check.names = FALSE)
# write.table with sep = "\t" and quote = FALSE for TSV format.
write.table(data, "data2.rds", sep = "\t", row.names = FALSE, quote = FALSE)

# For data2.txt: read.table("data2.txt", header = TRUE, check.names = FALSE)
# Assuming tab-separated for consistency with read.delim and common practice.
write.table(data, "data2.rds", sep = "\t", row.names = FALSE, quote = FALSE)

# For the ambiguous "data2" file (no extension):
# The workflow tries readRDS, then read.csv, then read.table.
# To satisfy the first successful read, we save it as an RDS file.
saveRDS(data, "data2.rds")