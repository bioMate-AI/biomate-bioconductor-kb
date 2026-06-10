# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Clomial")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Clomial)

# Reproduce the vignette's data preparation
set.seed(1)
data(breastCancer)
Dc <- breastCancer$Dc
Dt <- breastCancer$Dt

# Serialize Dc to the required input file formats
# For .csv files, use write.csv with row.names = TRUE and quote = FALSE
write.csv(Dc, "Dc.csv", row.names = TRUE, quote = FALSE)

# For .tsv and .txt files, use write.table with sep = "\t", row.names = TRUE,
# col.names = NA (to ensure the header for the row names column is empty), and quote = FALSE.
# This matches the read.delim/read.table behavior with row.names = 1 and header = TRUE.
write.table(Dc, "Dc.csv", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)
write.table(Dc, "Dc.csv", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)

# Serialize Dt to the required input file formats
write.csv(Dt, "Dt.csv", row.names = TRUE, quote = FALSE)
write.table(Dt, "Dt.csv", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)
write.table(Dt, "Dt.csv", sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)