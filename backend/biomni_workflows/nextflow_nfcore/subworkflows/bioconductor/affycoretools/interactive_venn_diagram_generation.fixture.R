# 1. Load necessary packages
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("affycoretools", "hgu95av2.db", "limma")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library(affycoretools))
suppressMessages(library(hgu95av2.db))
suppressMessages(library(limma))

# 2. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the example ExpressionSet
data(sample.ExpressionSet)
eset <- sample.ExpressionSet

# Add annotation data to the ExpressionSet
eset <- annotateEset(eset, hgu95av2.db)

# Extract phenoData for model matrix creation
pd <- pData(phenoData(eset))

# Create the design matrix
design <- model.matrix(~0+type+sex, pd)
colnames(design) <- gsub("type|sex", "", colnames(design))

# Create the contrast matrix
contrast <- matrix(c(1,-1,0))
colnames(contrast) <- "Case vs control"

# Fit linear model and contrasts using limma
fit <- lmFit(eset, design)
fit2 <- contrasts.fit(fit, contrast)
# Apply eBayes. CRITICAL: Following the vignette verbatim, eBayes is applied to 'fit',
# not 'fit2', which then overwrites 'fit2'.
fit2 <- eBayes(fit) 

# 3. Serialize objects to declared input files
saveRDS(fit2, "fit2.rds")
saveRDS(contrast, "contrast.rds")
saveRDS(design, "design.rds")