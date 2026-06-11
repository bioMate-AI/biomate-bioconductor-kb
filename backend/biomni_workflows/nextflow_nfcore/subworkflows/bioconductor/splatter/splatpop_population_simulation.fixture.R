# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("splatter", "scater", "VariantAnnotation", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(splatter)
    library(scater)
    library(VariantAnnotation) # Required for example VCF file path
    library(rtracklayer)     # Required for example GFF file path
})

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# This section generates a SingleCellExperiment object 'sim'
# as demonstrated in the splatter vignette.
set.seed(1)
sce <- mockSCE()
params <- splatEstimate(sce)
sim <- splatSimulate(params)

# 2. Serialize objects to declared input files (vcf.rds, gff.rds)
# The workflow excerpt indicates that 'vcf.rds