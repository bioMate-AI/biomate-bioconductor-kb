# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BiSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BiSeq)

# Create colData as a DataFrame and save as RDS
colData <- DataFrame(group = c("cancer", "control"),
                     row.names = c("sample_1", "sample_2"))
saveRDS(colData, "colData.csv")

# Create files.ext as a Bismark CpG context output file (coverage format)
# Columns: <chr> <start> <end> <methylation percentage> <count methylated> <count unmethylated>
bismark_data <- data.frame(
  chr = rep("chr1", 3),
  start = c(1, 2, 3),
  end = c(1, 2, 3),
  meth_perc = rep(50, 3),
  count_meth = rep(5, 3),
  count_unmeth = rep(5, 3)
)
write.table(bismark_data, "files.ext", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)