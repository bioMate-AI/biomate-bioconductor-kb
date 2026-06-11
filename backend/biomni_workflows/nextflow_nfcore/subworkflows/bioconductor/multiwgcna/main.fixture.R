# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SummarizedExperiment", "S4Vectors")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SummarizedExperiment)
library(S4Vectors)

# Construct synthetic sample metadata matching the vignette's structure
samples <- c(paste0("EAE_", 1:18), paste0("healthy_", 19:36))
disease <- rep(c("EAE", "WT"), each = 18)
region <- rep(c("Cbl", "Ctx", "Hippo", "Sc"), length.out = 36)

sampleTable <- DataFrame(
    Sample = samples,
    Disease = disease,
    Region = region
)
rownames(sampleTable) <- samples

# Construct synthetic expression data
set.seed(123)
num_genes <- 500
num_samples <- 36
genes <- paste0("Gene_", 1:num_genes)
exprs <- matrix(runif(num_genes * num_samples, min = 0, max = 15), 
                nrow = num_genes, ncol = num_samples)
rownames(exprs) <- genes
colnames(exprs) <- samples

# Build the SummarizedExperiment object
astrocyte_se <- SummarizedExperiment(
    assays = list(exprs = exprs),
    colData = sampleTable
)

# Serialize the objects to the expected input files
saveRDS(astrocyte_se, "astrocyte_se.rds")
saveRDS(sampleTable, "sampleTable.rds")