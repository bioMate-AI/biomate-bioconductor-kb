# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("splatter", "scater")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(splatter)
    library(scater)
})

# Create mock data set as in the vignette
set.seed(1)
sce <- mockSCE()

# Estimate parameters from mock data
params <- splatEstimate(sce)

# Simulate data for sim1 using estimated parameters (default nGenes, which is 2000 from sce)
sim1 <- splatSimulate(params)

# Simulate data for sim2, adjusting nGenes as shown in the vignette
# Use a different seed for sim2 to ensure it's distinct from sim1,
# or rely on the parameter change to make it distinct.
# The vignette shows `sim <- splatSimulate(params, nGenes = 1000)`
# after the first simulation, implying a new simulation.
# To ensure reproducibility of this specific sim2, we can set a seed again,
# or just let it follow from the previous state if the intention is just "another simulation".
# Given the workflow reads sim1 and sim2, they should be distinct and reproducible.
# Let's use a different seed for the second simulation to ensure distinctness if the
# `nGenes` parameter alone isn't enough to make it sufficiently different for testing.
# However, the vignette only sets seed once for mockSCE. Sticking to vignette's exact code:
# The vignette's `splatSimulate(params, nGenes = 1000)` implicitly uses the global seed state.
# To make sim2 distinct and reproducible from sim1, it's safer to set a seed for it.
# Let's use set.seed(2) for sim2 to ensure it's a different simulation.
set.seed(2)
sim2 <- splatSimulate(params, nGenes = 1000)

# Save the simulated objects to .rds files
saveRDS(sim1, "sim1.rds")
saveRDS(sim2, "sim2.rds")