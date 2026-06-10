# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cfTools", "utils")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cfTools)
library(utils)

# Define the path to the demo data within the cfTools package
demo.dir <- system.file("data", package="cfTools")

# --- 1. Reproduce data preparation and materialize objects ---

# demo.sorted.bed.txt.gz
# The vignette shows: PEReads <- file.path(demo.dir, "demo.sorted.bed.txt.gz")
# and then: head(read.table(PEReads, header=FALSE), 2)
# So, we read the content of this file as a data frame without a header.
df_demo_sorted_bed <- read.table(file.path(demo.dir, "demo.sorted.bed.txt.gz"), header = FALSE, sep = "\t")

# CpG_OT_demo.txt.gz
# The vignette shows: CpG_OT <- file.path(demo.dir, "CpG_OT_demo.txt.gz")
# and then: head(read.table(CpG_OT, header=FALSE), 2)
# So, we read the content of this file as a data frame without a header.
df_cpg_ot_demo <- read.table(file.path(demo.dir, "CpG_OT_demo.txt.gz"), header = FALSE, sep = "\t")

# CpG_OB_demo.txt.gz
# The vignette shows: CpG_OB <- file.path(demo.dir, "CpG_OB_demo.txt.gz")
# and then: head(read.table(CpG_OB, header=FALSE), 2)
# So, we read the content of this file as a data frame without a header.
df_cpg_ob_demo <- read.table(file.path(demo.dir, "CpG_OB_demo.txt.gz"), header = FALSE, sep = "\t")

# beta_matrix.txt.gz
# The vignette shows: methLevel <- read.table(file.path(demo.dir, "beta_matrix.txt.gz"), row.names=1, header = TRUE)
# So, we read the content of this file as a data frame with row names and a header.
df_beta_matrix <- read.table(file.path(demo.dir, "beta_matrix.txt.gz"), row.names = 1, header = TRUE, sep = "\t")

# sample_type.txt.gz
# The vignette shows: sampleTypes <- read.table(file.path(demo.dir, "sample_type.txt.gz"), row.names=1, header = TRUE)$sampleType
# We need to materialize the full data frame that contains the sampleType column.
df_sample_type <- read.table(file.path(demo.dir, "sample_type.txt.gz"), row.names = 1, header = TRUE, sep = "\t")

# marker_index.txt.gz
# The vignette shows: markerNames <- read.table(file.path(demo.dir, "marker_index.txt.gz"), row.names=1, header = TRUE)$markerIndex
# We need to materialize the full data frame that contains the markerIndex column.
df_marker_index <- read.table(file.path(demo.dir, "marker_index.txt.gz"), row.names = 1, header = TRUE, sep = "\t")


# --- 2. Serialize objects to declared input files ---

# Write demo.sorted.bed.txt.gz
write.table(df_demo_sorted_bed, file = "demo.sorted.bed.txt.gz",
            col.names = FALSE, row.names = FALSE, quote = FALSE, sep = "\t")

# Write CpG_OT_demo.txt.gz
write.table(df_cpg_ot_demo, file = "CpG_OT_demo.txt.gz",
            col.names = FALSE, row.names = FALSE, quote = FALSE, sep = "\t")

# Write CpG_OB_demo.txt.gz
write.table(df_cpg_ob_demo, file = "CpG_OB_demo.txt.gz",
            col.names = FALSE, row.names = FALSE, quote = FALSE, sep = "\t")

# Write beta_matrix.txt.gz
write.table(df_beta_matrix, file = "beta_matrix.txt.gz",
            col.names = TRUE, row.names = TRUE, quote = FALSE, sep = "\t")

# Write sample_type.txt.gz
write.table(df_sample_type, file = "sample_type.txt.gz",
            col.names = TRUE, row.names = TRUE, quote = FALSE, sep = "\t")

# Write marker_index.txt.gz
write.table(df_marker_index, file = "marker_index.txt.gz",
            col.names = TRUE, row.names = TRUE, quote = FALSE, sep = "\t")