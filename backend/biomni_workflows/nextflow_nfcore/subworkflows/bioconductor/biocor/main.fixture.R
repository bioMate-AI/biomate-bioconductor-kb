# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioCor", "org.Hs.eg.db", "reactome.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("BioCor")
library("org.Hs.eg.db")
library("reactome.db")

# Reproduce the vignette's data preparation for genesReact
genesKegg <- as.list(org.Hs.egPATH) # Not directly saved, but part of vignette prep
genesReact <- as.list(reactomeEXTID2PATHID)
genesReact <- lapply(genesReact, function(x){
  unique(grep("R-HSA-", x, value = TRUE))
})
genesReact <- genesReact[lengths(genesReact) >= 1]

# Serialize genesReact to "genesReact" as an RDS file
saveRDS(genesReact, file = "genesReact.rds")

# Create a sample set of gene IDs from the vignette examples
# The workflow reads "genes.id" trying RDS first, then plain text lines.
# A character vector saved as RDS is robust for both.
genes_id_data <- c("672", "675", "10", "100", "1", "18", "83")

# Serialize genes_id_data to "genes.id" as an RDS file
saveRDS(genes_id_data, file = "genes.id")