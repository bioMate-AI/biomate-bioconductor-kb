# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("gwascat", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(gwascat)
library(rtracklayer)

# Reproduce the vignette's data preparation to materialize an example GRanges object.
# The workflow reads 'c17tg' as a GFF3 file, which typically represents genomic ranges.
# The 'ebicat_2020_04_30' dataset from the gwascat package is a gwasloc object,
# which extends GRanges, making it suitable for export to GFF3 format.
data(ebicat_2020_04_30)

# Serialize the object to the declared input file 'c17tg' in GFF3 format.
# The 'export' function from rtracklayer is used for this purpose.
export(ebicat_2020_04_30, con = "c17tg", format = "gff3")