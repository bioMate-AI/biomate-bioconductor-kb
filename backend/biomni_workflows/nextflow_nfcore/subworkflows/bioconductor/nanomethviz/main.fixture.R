# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("NanoMethViz")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(NanoMethViz)

# 1. Prepare the tabular methylation calls
# We use the package's internal subset of methylation data, which contains
# the necessary columns (sample, chr, pos, strand, statistic, read_name).
methy_file <- system.file(package = "NanoMethViz", "methy_subset.tsv.bgz")
methy_data <- read.table(gzfile(methy_file), col.names = methy_col_names(), stringsAsFactors = FALSE)

# Write to the expected input file: methy_calls.tsv.gz
gz_out <- gzfile("methy_calls.tsv.gz", "w")
write.table(methy_data, gz_out, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
close(gz_out)

# 2. Prepare the sample annotation table
# We use the exact sample names present in the methy_subset data as shown in the vignette.
sample_names <- c(
  "B6Cast_Prom_1_bl6",
  "B6Cast_Prom_1_cast",
  "B6Cast_Prom_2_bl6",
  "B6Cast_Prom_2_cast",
  "B6Cast_Prom_3_bl6",
  "B6Cast_Prom_3_cast"
)
groups <- c("bl6", "cast", "bl6", "cast", "bl6", "cast")

sample_anno <- data.frame(
  sample = sample_names,
  group = groups,
  stringsAsFactors = FALSE
)

# Write to the expected input file: sample_anno.csv
write.csv(sample_anno, "sample_anno.csv", row.names = FALSE)