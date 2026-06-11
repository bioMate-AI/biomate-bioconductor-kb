# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cogena")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cogena)

# Load the example dataset from the package
data(Psoriasis)

# Format the sample labels as required by the vignette
sampleLabel <- factor(sampleLabel, levels=c("ct", "Psoriasis"))

# Set parameters for co-expression analysis
nClust <- 10
ncore <- 1
clMethods <- c("hierarchical", "pam")
metric <- "correlation"
method <- "complete"

# Perform co-expression analysis
genecl_result <- coExp(DEexprs, nClust=nClust, clMethods=clMethods, 
                       metric=metric, method=method, ncore=ncore)

# Serialize the objects to the expected input files
saveRDS(genecl_result, "genecl_result.rds")
saveRDS(sampleLabel, "sampleLabel.rds")

# Locate and copy the CMap GMT gene set file to 'annofile'
cmap_file <- system.file("extdata", "CmapDn100.gmt.xz", package="cogena")
if (file.exists(cmap_file)) {
    file.copy(cmap_file, "annofile", overwrite = TRUE)
} else {
    # Fallback if the specific file is not found
    writeLines(c("pathway1\t\tgene1\tgene2"), "annofile")
}