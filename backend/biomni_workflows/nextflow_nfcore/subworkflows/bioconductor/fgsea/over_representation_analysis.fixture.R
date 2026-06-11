# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("fgsea")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(fgsea)

# Load built-in example data from fgsea to avoid offline/network issues
data(exampleRanks, package = "fgsea")
data(examplePathways, package = "fgsea")

# 1. gene_list.txt: list of foreground genes of interest
# We take the top 200 genes from the example ranks
gene_list <- head(names(exampleRanks), 200)
writeLines(gene_list, "gene_list.txt")

# 2. background_universe.txt: list of all robustly detected genes
background_universe <- names(exampleRanks)
writeLines(background_universe, "background_universe.txt")

# 3. mouse.reactome.gmt: GMT file containing gene sets/pathways
# Construct GMT format: Pathway_Name \t Description \t Gene1 \t Gene2 ...
gmt_lines <- vapply(names(examplePathways), function(pw) {
    paste(c(pw, "Reactome Pathway", examplePathways[[pw]]), collapse = "\t")
}, character(1))
writeLines(gmt_lines, "mouse.reactome.gmt")