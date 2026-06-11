# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("seqPattern", "BSgenome.Drerio.UCSC.danRer7")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(seqPattern)
library(BSgenome.Drerio.UCSC.danRer7) # Required for the genome assembly name

# 1. Reproduce the vignette's data-preparation code to materialize example objects

# Load zebrafish promoter coordinates and associated features
data(zebrafishPromoters24h)

# Load the TBP position weight matrix (PWM)
data(TBPpwm)

# 2. Serialize objects to declared input files in the exact format the workflow reads

# For coordinates.txt:
# The workflow reads this as a tab-separated file with a header.
# zebrafishPromoters24h is a data.frame that fits this description.
write.table(zebrafishPromoters24h, "coordinates.txt", sep = "\t", row.names = FALSE, quote = FALSE)

# For genome_assembly:
# The workflow reads the first line as the BSgenome package name.
genome_package_name <- "BSgenome.Drerio.UCSC.danRer7"
writeLines(genome_package_name, "genome_assembly")

# For pwm_matrix.RData:
# The workflow uses `load("pwm_matrix.RData", envir = env)` to load a PWM object.
# The TBPpwm object is the required PWM.
save(TBPpwm, file = "pwm_matrix.RData")