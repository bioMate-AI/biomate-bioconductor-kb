# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "limma", "hgu95av2.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(limma)
library(hgu95av2.db) # Required for feature annotation data

# Reproduce the vignette's data preparation steps verbatim

# From vignette chunk number 1: annHeatmap.Rnw:44-45
options(width=65)

# From vignette chunk number 2: setup01
data(sample.ExpressionSet)
exdat = sample.ExpressionSet

# From vignette chunk number 3: setup02
design1 = model.matrix( ~ type, data=pData(exdat))
lm1 = lmFit(exprs(exdat), design1)
lm1 = eBayes(lm1)
geneID = rownames(topTable(lm1, coef=2, num=100, adjust="none", 
	p.value=0.05))

# From vignette chunk number 4: setup03
exdat2 = exdat[geneID,]

# From vignette chunk number 12: setupX1
SE = apply(get("se.exprs", assayData(exdat2)), 1, median)

# From vignette chunk number 13: setupX2
CO = cor(t(exprs(exdat2)), pData(exdat2)$score)
df = nrow(exdat2)-2
TT = sqrt(df) * CO/sqrt(1-CO^2)
PV = 2*pt(-abs(TT), df=df)

# From vignette chunk number 14: setupX3
# The 'hgu95av2GO' object is provided by the 'hgu95av2.db' annotation package.
allGO = as.list(mget(featureNames(exdat2), hgu95av2GO))
isTransElong = sapply(allGO, function(x) "GO:0006414" %in% names(x))

# From vignette chunk number 15: setupX4
annFeatures = data.frame(standard.errors=SE, sigCorScore=PV<0.05, isTransElong)


# Prepare data for output files in the format expected by the workflow

# 1. exprs_matrix.csv: Expression matrix
# The workflow reads this with `as.matrix(read.csv(..., row.names=1))`
exprs_matrix_data = exprs(exdat2)
write.csv(exprs_matrix_data, "exprs_matrix.csv", row.names = TRUE)

# 2. sample_metadata.csv: Sample annotation data frame
# The workflow reads this with `read.csv(..., row.names=1)`
sample_metadata_data = pData(exdat2)
write.csv(sample_metadata_data, "sample_metadata.csv", row.names = TRUE)

# 3. feature_metadata.csv: Feature annotation data frame
# The workflow reads this with `read.csv(..., row.names=1)`
# The vignette uses 'annFeatures' for row annotation in annHeatmap2,
# which is a derived feature annotation. This is a suitable candidate
# for the 'feature_metadata.csv' input.
feature_metadata_data = annFeatures
write.csv(feature_metadata_data, "feature_metadata.csv", row.names = TRUE)