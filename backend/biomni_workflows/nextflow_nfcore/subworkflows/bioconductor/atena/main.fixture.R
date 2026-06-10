# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("atena", "BiocParallel")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(atena)
library(BiocParallel)

# Reproduce the vignette's data-preparation code to create the 'teann' object.
# This object contains parsed TE annotations, which will then be filtered
# to obtain LTR-specific annotations.
teann <- annotaTEs(genome="dm6", parsefun=OneCodeToFindThemAll, strict=FALSE, insert=500, BPPARAM=SerialParam(progress=FALSE))

# The workflow expects an object named 'rmskLTR'.
# The vignette provides 'getLINEs' as an example for filtering 'teann'.
# Following this pattern, we use 'getLTRs' to extract LTR elements from 'teann'.
# We use a relLength of 0.9, similar to the 'getLINEs' example in the vignette,
# as it's indicated that TEs with higher relative lengths are more interesting.
rmskLTR <- getLTRs(teann, relLength=0.9)

# Serialize the 'rmskLTR' object to the 'rmskLTR.rds' file,
# as specified by the workflow's input reading mechanism.
saveRDS(rmskLTR, "rmskLTR.rds")

# Note: The vignette does not provide code to generate *.bam files.
# Therefore, no *.bam file generation is included in this script,
# adhering to the instruction to only reproduce the vignette's own data-preparation code.