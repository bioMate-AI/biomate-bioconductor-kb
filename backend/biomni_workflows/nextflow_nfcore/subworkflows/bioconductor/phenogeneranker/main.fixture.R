# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PhenoGeneRanker")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PhenoGeneRanker)

extdata_dir <- system.file("extdata", package = "PhenoGeneRanker")

# 1. input_file.txt
inputDf <- read.table(file.path(extdata_dir, "input_file.txt"), header=TRUE, sep="\t", stringsAsFactors = FALSE)
inputDf_filtered <- inputDf[inputDf$file_name %in% c("gene_layer1.txt", "ptype_layer1.txt", "gene_ptype.txt"), ]
write.table(inputDf_filtered, "input_file.txt", sep="\t", row.names=FALSE, quote=FALSE)

# 2. gene_layer1.txt
geneLayerDf <- read.table(file.path(extdata_dir, "gene_layer1.txt"), header=TRUE, sep="\t", stringsAsFactors = FALSE)
write.table(geneLayerDf, "gene_layer1.txt", sep="\t", row.names=FALSE, quote=FALSE)

# 3. ptype_layer1.txt
ptypeLayerDf <- read.table(file.path(extdata_dir, "ptype_layer1.txt"), header=TRUE, sep="\t", stringsAsFactors = FALSE)
write.table(ptypeLayerDf, "ptype_layer1.txt", sep="\t", row.names=FALSE, quote=FALSE)

# 4. gene_ptype.txt
biLayerDf <- read.table(file.path(extdata_dir, "gene_ptype.txt"), header=TRUE, sep="\t", stringsAsFactors = FALSE)
write.table(biLayerDf, "gene_ptype.txt", sep="\t", row.names=FALSE, quote=FALSE)