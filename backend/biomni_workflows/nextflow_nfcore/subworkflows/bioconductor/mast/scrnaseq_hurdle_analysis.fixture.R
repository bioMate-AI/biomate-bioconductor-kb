# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MAST")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MAST)

data(vbeta)
vbeta <- computeEtFromCt(vbeta)
vbeta.fa <- FromFlatDF(vbeta, 
                       idvars=c("Subject.ID", "Chip.Number", "Well"),
                       primerid='Gene', 
                       measurement='Et', 
                       ncells='Number.of.Cells',
                       geneid="Gene",  
                       cellvars=c('Number.of.Cells', 'Population'),
                       phenovars=c('Stim.Condition','Time'), 
                       id='vbeta all', 
                       class='FluidigmAssay')

exprs_mat <- assay(vbeta.fa, "Et")
cell_meta <- as.data.frame(colData(vbeta.fa))
feat_meta <- as.data.frame(rowData(vbeta.fa))

write.csv(exprs_mat, "expression_matrix.csv", row.names = TRUE)
write.csv(cell_meta, "cell_metadata.csv", row.names = TRUE)
write.csv(feat_meta, "feature_metadata.csv", row.names = TRUE)