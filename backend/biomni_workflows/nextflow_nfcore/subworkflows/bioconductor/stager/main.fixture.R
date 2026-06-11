# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("stageR", "edgeR", "Biobase", "limma")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(stageR)
library(edgeR)
library(Biobase)
library(limma)

# Load the Hammer dataset provided with stageR
data(hammer.eset, package="stageR")
eset <- hammer.eset

# Correct the typo in phenoData and set up factors
time <- factor(rep(c("mo2","w2"),each=4),levels=c("w2","mo2"))
treat <- factor(c("control","control","SNL","SNL","control","control","SNL","SNL"),levels=c("control","SNL"))

# Create design matrix
design <- model.matrix(~time*treat)
rownames(design) = paste0(time,treat,rep(1:2,4))
colnames(design)[4] = "timeMo2xTreatSNL"

# Independent filtering and normalization
cpmOffset <- 2
keep <- rowSums(cpm(exprs(eset)) > cpmOffset) >= 2
dge <- DGEList(exprs(eset)[keep,])
colnames(dge) = rownames(design)
dge <- calcNormFactors(dge)

# Conventional limma-voom analysis
voomObj <- voom(dge, design, plot=FALSE)
fit <- lmFit(voomObj, design)
contrast.matrix <- makeContrasts(treatSNL, treatSNL+timeMo2xTreatSNL, timeMo2xTreatSNL, levels=design)
fit2 <- contrasts.fit(fit, contrast.matrix)
fit2 <- eBayes(fit2)

nGenes <- nrow(dge)

# Screening hypothesis (F-test across contrasts)
tableF <- topTable(fit2, number=nGenes, sort.by="none")
pScreen <- tableF$P.Value
names(pScreen) = rownames(tableF)

# Confirmation stage (individual contrasts)
pConfirmation <- sapply(1:3, function(i) topTable(fit2, coef=i, number=nGenes, sort.by="none")$P.Value)
dimnames(pConfirmation) <- list(rownames(fit2), c("t1","t2","t1t2"))

# Serialize the objects to the expected input files
saveRDS(pScreen, "pScreen.rds")
saveRDS(pConfirmation, "pConfirmation.rds")