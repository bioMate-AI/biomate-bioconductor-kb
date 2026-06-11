# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cbaf")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cbaf)

# Reproduce the VIGNETTE'S OWN data-preparation code to materialize the example object.
# The 'genes' object is directly defined in the vignette's 'processOneStudy()' example.
genes <- list(K.demethylases = c("KDM1A", "KDM1B", "KDM2A", "KDM2B", "KDM3A", "KDM3B", "JMJD1C", "KDM4A"),
              K.methyltransferases = c("SUV39H1", "SUV39H2", "EHMT1", "EHMT2", "SETDB1", "SETDB2", "KMT2A", "KMT2A"))

# The 'studies' object is not explicitly created as a standalone object in the vignette's data prep.
# However, the 'processOneStudy()' and 'processMultipleStudies()' functions take a 'studyName'
# argument, which is a character string. Given the workflow reads a file named 'studies' (plural)
# using readRDS, a character vector containing one or more study names is the most appropriate
# representation, using the example study name from the vignette.
studies <- c("Breast Invasive Carcinoma (TCGA, Cell 2015)")

# Serialize the objects to EACH declared input file in the EXACT format the workflow reads.
# The workflow checks for 'genes.rds' and 'studies.rds' first.
saveRDS(genes, "genes.rds")
saveRDS(studies, "studies.rds")