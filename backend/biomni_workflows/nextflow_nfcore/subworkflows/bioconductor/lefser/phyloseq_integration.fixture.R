# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("lefser", "phyloseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(lefser)
library(phyloseq)

# Reproduce the phyloseq object 'kostic' as shown in the vignette's "Interoperating with phyloseq" section.
fp <- system.file("extdata", "study_1457_split_library_seqs_and_mapping.zip", package = "phyloseq")
kostic <- microbio_me_qiime(fp)

# Serialize the 'kostic' phyloseq object to an RDS file,
# matching the workflow's read method (readRDS).
saveRDS(kostic, "phyloseq_input.rds")