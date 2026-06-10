# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("derfinder", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(derfinder)
library(GenomicRanges)

# Load example data from derfinder
data(genomeDataRaw, package = "derfinder")
data(genomeInfo, package = "derfinder")

# 1. fullCov: list containing raw coverage data
fullCov <- list("chr21" = genomeDataRaw)
saveRDS(fullCov, "fullCov.rds")

# 2. prefix: directory containing merged derfinder results
dir.create("prefix", showWarnings = FALSE)

# Prepare models for derfinder analysis
collapsedFull <- collapseFullCoverage(fullCov, verbose = FALSE)
sampleDepths <- sampleDepth(collapsedFull, probs = c(0.5), verbose = FALSE)

group <- genomeInfo$pop
adjustvars <- data.frame(gender = genomeInfo$gender)
models <- makeModels(sampleDepths, testvars = group, adjustvars = adjustvars)

# Run analyzeChr to generate optionsStats.Rdata and region data
suppressMessages({
    analyzeChr(chr = "chr21", coverageInfo = fullCov, models = models,
               cutoffFstat = 1, cutoffType = "manual", groupInfo = group,
               mc.cores = 1, writeOutput = TRUE, returnOutput = FALSE,
               outdir = "prefix")
    
    # Run mergeResults to generate merged derfinder results in the prefix directory
    mergeResults(chrs = "chr21", prefix = "prefix", genomicState = NULL)
})

# 3. optionsStats: Rdata file containing options used during the derfinder statistical analysis
options_file <- file.path("prefix", "chr21", "optionsStats.Rdata")
if (file.exists(options_file)) {
    file.copy(options_file, "optionsStats.Rdata", overwrite = TRUE)
} else {
    # Fallback if not created
    optionsStats <- list(mc.cores = 1)
    save(optionsStats, file = "optionsStats")
}