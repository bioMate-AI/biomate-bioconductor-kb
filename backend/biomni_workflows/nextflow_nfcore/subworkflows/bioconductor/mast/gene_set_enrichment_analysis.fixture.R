# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MAST")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MAST)

# Reproduce the VIGNETTE'S OWN data-preparation code
data(vbeta)
vbeta <- computeEtFromCt(vbeta)
vbeta.fa <- FromFlatDF(vbeta, idvars=c("Subject.ID", "Chip.Number", "Well"), 
                       primerid='Gene', measurement='Et', ncells='Number.of.Cells', 
                       geneid="Gene", cellvars=c('Number.of.Cells', 'Population'), 
                       phenovars=c('Stim.Condition','Time'), id='vbeta all', class='FluidigmAssay')

vbeta.1 <- subset(vbeta.fa, ncells==1)
# Consider the first 20 genes
vbeta.1 <- vbeta.1[1:20,]

# Fit the Zlm model
zlm.output <- zlm(~ Population + Subject.ID, vbeta.1)

# Serialize the fitted ZlmFit object
saveRDS(zlm.output, "fitted_zlm_model.rds")

# Construct a synthetic GMT file using the genes present in the model
genes <- rownames(vbeta.1)
gmt_lines <- c(
  paste(c("GeneSet_A", "Test Set A", genes[1:10]), collapse = "\t"),
  paste(c("GeneSet_B", "Test Set B", genes[11:20]), collapse = "\t")
)
writeLines(gmt_lines, "gene_sets.gmt")