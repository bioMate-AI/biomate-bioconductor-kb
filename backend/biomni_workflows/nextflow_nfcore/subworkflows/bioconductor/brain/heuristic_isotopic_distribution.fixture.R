# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BRAIN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BRAIN)

# Reproduce the data preparation for uniprotBRAIN as shown in chunk 12 of the vignette.
# The vignette's `read.table` call omits `header=TRUE`, but the subsequent code
# (e.g., `uniprotBRAIN$monoMass`) relies on column names. Based on how `uniprotBRAIN.txt`
# is generated in the vignette (chunk 11, `write.table(unique(dfUniprot), ...)`,
# which would include a header by default), `header=TRUE` is necessary for correct parsing.
uniprotBRAIN <- read.table(system.file("extdata", "uniprotBRAIN.txt", package="BRAIN"), header = TRUE)

# Reproduce the filtering for uniprot10to5 as shown in chunk 13 of the vignette.
uniprot10to5 <- uniprotBRAIN[uniprotBRAIN$monoMass < 10^5,]

# Serialize the object to the declared input file: large_molecule_composition.txt.
# The original `uniprotBRAIN.txt` is read using `read.table`, implying a text file.
# We will write `uniprot10to5` as a tab-separated file without row names,
# consistent with typical data table formats.
write.table(uniprot10to5, "large_molecule_composition.txt", sep = "\t", row.names = FALSE, quote = FALSE)