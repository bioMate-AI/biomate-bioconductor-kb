# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DART", "Biobase", "breastCancerVDX", "breastCancerMAINZ")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DART)
library(Biobase)
library(breastCancerVDX) # Wang et al./Minn et al.
library(breastCancerMAINZ)

# Load initial ExpressionSet objects as per vignette chunk 2
data(vdx)
data(mainz)

# Prepare modelSig as per vignette chunk 3
data(dataDART)
modelSig <- dataDART$sign

# Prepare vdx.data as per vignette chunk 4
vdx.ord <- vdx[order(  apply(exprs(vdx), 1, sd,na.rm=T), decreasing=T ), ]
vdx.EntrezUniq <- vdx.ord[
	match(unique(fData(vdx.ord)$EntrezGene.ID), fData(vdx.ord)$EntrezGene.ID),]
vdx.data <- exprs(vdx.EntrezUniq)
rownames(vdx.data) <- fData(vdx.EntrezUniq)$EntrezGene.ID[
	match(rownames(vdx.data), rownames(fData(vdx.EntrezUniq))) ]
colnames(vdx.data) <- sub('.CEL.gz$','',pData(vdx.EntrezUniq)$filename)

# Prepare mainz.data as per vignette chunk 4
mainz.ord <- mainz[order(  apply(exprs(mainz), 1, sd,na.rm=T), decreasing=T ), ]
mainz.EntrezUniq <- mainz.ord[
	match(unique(fData(mainz.ord)$EntrezGene.ID),fData(mainz.ord)$EntrezGene.ID),]
mainz.data <- exprs(mainz.EntrezUniq)
rownames(mainz.data) <- fData(mainz.EntrezUniq)$EntrezGene.ID[
	match(rownames(mainz.data),rownames(fData(mainz.EntrezUniq))) ]
colnames(mainz.data) <- sub('.CEL.gz$','',pData(mainz.EntrezUniq)$filename)

# Save the prepared objects to .rds files, matching the workflow's read_input preference
saveRDS(vdx.data, "vdx.data.rds")
saveRDS(modelSig, "modelSig.rds")
saveRDS(mainz.data, "mainz.data.rds")