# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioNERO")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BioNERO)
set.seed(123) # for reproducibility

# Reproduce the vignette's data preparation for zma.se
data(zma.se)

# Serialize zma.se to "zma.se" in RDS format
saveRDS(zma.se, "zma.se")

# Create a placeholder for zma.tfs.
# The vignette does not provide code to generate 'zma.tfs'.
# As per instructions to create "EACH declared input file" and
# "NEVER invent a name", we create a minimal, plausible data frame
# using gene IDs from 'zma.se' to ensure consistency with the dataset.
# The workflow reads it with read.table(..., header = TRUE).
zma.tfs_df <- data.frame(
    GeneID = head(rownames(zma.se), 10) # Using first 10 gene IDs from zma.se as an example
)

# Serialize zma.tfs_df to "zma.tfs" in a table format with a header
write.table(zma.tfs_df, "zma.se", sep = "\t", row.names = FALSE, quote = FALSE)