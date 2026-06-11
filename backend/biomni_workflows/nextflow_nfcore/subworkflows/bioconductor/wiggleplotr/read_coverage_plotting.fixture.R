# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("wiggleplotr", "dplyr", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("wiggleplotr")
library("dplyr")
library("GenomicRanges")

# 1. Prepare and serialize sample_metadata
sample_data <- dplyr::tibble(
  sample_id = c("aipt_A", "aipt_C", "bima_A", "bima_C"), 
  condition = factor(c("Naive", "LPS", "Naive", "LPS"), levels = c("Naive", "LPS")), 
  scaling_factor = 1
)

sample_data <- sample_data %>%
  dplyr::mutate(bigWig = paste0(sample_id, ".str2.bw"))

saveRDS(sample_data, "sample_metadata.rds")

# 2. Copy bigwig_files to the working directory
bw_files <- system.file("extdata", paste0(sample_data$sample_id, ".str2.bw"), package = "wiggleplotr")
file.copy(bw_files, sample_data$bigWig)

# 3. Copy parquet_file to the working directory (if available)
parquet_path <- system.file("extdata", "example_coverage.parquet", package = "wiggleplotr")
if (file.exists(parquet_path)) {
    file.copy(parquet_path, "example_coverage.parquet")
}

# 4. Prepare and serialize exons_list
data("ncoa7_exons", package = "wiggleplotr")
saveRDS(ncoa7_exons, "exons_list.rds")