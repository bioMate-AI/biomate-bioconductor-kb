# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("supersigs", "BSgenome.Hsapiens.UCSC.hg19", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library(supersigs)
  library(BSgenome.Hsapiens.UCSC.hg19)
  library(dplyr)
})

# Load the example dataset provided by the package
data("example_dt", package = "supersigs")

# Transform the data into a data frame of trinucleotide mutations
input_dt <- make_matrix(example_dt)

# Add the indicator variable (IndVar) as required for the supervised method
input_dt <- input_dt %>% 
  mutate(IndVar = c(1, 1, 1, 0, 0)) %>% 
  relocate(IndVar)

# Train the SuperSig object
set.seed(1)
supersig <- get_signature(data = input_dt, factor = "Smoking")

# Serialize the objects to the working directory
saveRDS(input_dt, file = "input_dt.csv")
saveRDS(supersig, file = "supersig.rds")