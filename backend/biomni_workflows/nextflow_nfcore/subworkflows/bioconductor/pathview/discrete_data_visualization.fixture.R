# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pathview", "org.Hs.eg.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(pathview)
library(org.Hs.eg.db)

# Prepare gene data from vignette
data(gse16873.d)
gse16873.t <- apply(gse16873.d, 1, function(x) t.test(x, alternative = "two.sided")$p.value)
sel.genes <- names(gse16873.t)[gse16873.t < 0.1]

# Prepare compound data from vignette
set.seed(123)
sim.cpd.data <- sim.mol.data(mol.type="cpd", nmol=3000)
sel.cpds <- names(sim.cpd.data)[abs(sim.cpd.data) > 0.5]

# Write to expected input files
writeLines(as.character(sel.genes), "significant_genes.txt")
writeLines(as.character(sel.cpds), "significant_compounds.txt")