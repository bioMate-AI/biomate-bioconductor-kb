# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("breastCancerUPP", "hgu133a.db", "safe")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(breastCancerUPP)
library(hgu133a.db)
library(safe)

# Reproduce data preparation from vignette

# From chunk 3: SAFEmanual3.Rnw:91-96
data(upp)
ex.upp <- exprs(upp)
p.upp <- pData(upp)
data(p53.stat)
p.upp <- cbind(p.upp, p53 = p53.stat$p53)

# From chunk 4: SAFEmanual3.Rnw:101-109
grade.3 <- which(p.upp$grade == 3)
p3.upp <- p.upp[grade.3,]
genes <- unlist(as.list(hgu133aSYMBOL))
drop <- grep("AFFX", names(genes))
genes <- genes[-drop]
e3.upp <- ex.upp[match(names(genes), rownames(ex.upp)),
                 grade.3]

# From chunk 10: SAFEmanual3.Rnw:157-162
entrez <- unlist(mget(names(genes),hgu133aENTREZID))
C.mat <- getCmatrix(gene.list = as.list(reactomeEXTID2PATHID),
                    present.genes = entrez,prefix = "REACTOME:",
                    min.size = 10, max.size = 500)

# Serialize the objects to files
saveRDS(e3.upp, "e3.upp.rds")
saveRDS(p3.upp$t.rfs, "p3.upp$t.rfs")
saveRDS(p3.upp$e.rfs, "p3.upp$e.rfs")
saveRDS(C.mat, "C.mat.rds")