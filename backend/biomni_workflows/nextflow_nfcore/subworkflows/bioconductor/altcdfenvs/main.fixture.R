# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("altcdfenvs", "hgu133aprobe", "affy")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(altcdfenvs)
library(hgu133aprobe)
library(affy)

# 1. sample.fasta
fasta_src <- system.file("exampleData", "sample.fasta", package="altcdfenvs")
if (file.exists(fasta_src)) {
    file.copy(fasta_src, "sample.fasta", overwrite = TRUE)
} else {
    # Fallback synthetic FASTA if the package example data is missing
    writeLines(c(">gnl|UG|Hs#S1730546", 
                 "AACCCATTTCAACTGCCTATTCAGAGCATGCAGTAAGAGGAAATCCACCAAGTCTCAATATAATAATATTCTTTATTCCTGG"), 
               "sample.fasta")
}

# 2. hgu133aprobe
# The hgu133aprobe object is a data.frame provided by the hgu133aprobe package.
# Serializing it as an RDS file for the workflow to read.
saveRDS(hgu133aprobe, "hgu133aprobe")

# 3. abatch
# The workflow expects an AffyBatch object to be remapped.
# Creating a minimal valid AffyBatch object matching the HG-U133A chip type used in the vignette.
abatch <- new("AffyBatch", cdfName = "HG-U133A")
saveRDS(abatch, "abatch.rds")