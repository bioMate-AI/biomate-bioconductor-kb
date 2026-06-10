# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("annotate", "GOstats", "graph", "hgu95av2.db", "genefilter", "ALL", "GSEAlm")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("annotate")
library("GOstats")
library("graph")
library("hgu95av2.db")
library("genefilter")
library("ALL")
library("GSEAlm")

data(ALL)

### Some filtering;
bcellIdx <- grep("^B", as.character(ALL$BT))
bcrOrNegIdx <- which(as.character(ALL$mol.biol)
                     %in% c("NEG", "BCR/ABL"))
esetA <- ALL[ , intersect(bcellIdx, bcrOrNegIdx)]
esetA$mol.biol = factor(esetA$mol.biol) # recode factor

### Non-specific filtering
esetASub <- nsFilter(esetA,var.cutoff=0.6,var.func=sd)$eset

minBandSize = 5
haveMAP = sapply(mget(featureNames(esetASub), hgu95av2MAP),
                 function(x) !all(is.na(x)))
workingEset = esetASub[haveMAP, ]
entrezUniv = unlist(mget(featureNames(workingEset), hgu95av2ENTREZID))

### Creating incidence matrix and keeping the graph structure
AgraphChr=makeChrBandGraph("hgu95av2.db",univ=entrezUniv)
AmatChr = makeChrBandInciMat(AgraphChr)
AmatChr3 = AmatChr[rowSums(AmatChr)>=minBandSize,]

# Re-ordering incidence matrix columns
egIds = sapply(featureNames(workingEset), function(x) hgu95av2ENTREZID[[x]])
idx = match(egIds, colnames(AmatChr))
AmatChr3 = AmatChr3[, idx]
colnames(AmatChr3)=featureNames(workingEset)

saveRDS(workingEset, "workingEset.rds")
saveRDS(AmatChr3, "AmatChr3.rds")