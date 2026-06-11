# 1. Load necessary packages
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("breastCancerUPP", "hgu133a.db", "reactome.db", "safe", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(breastCancerUPP)
library(hgu133a.db)
library(reactome.db) # For reactomeEXTID2PATHID
library(safe)
library(Biobase)     # For exprs() and pData()

# Set options from vignette (optional, but good practice)
options(width = 150)

# 2. Reproduce the VIGNETTE'S OWN data-preparation code

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
# table(p53 = p3.upp$p53) # This line is for display, not data generation

# From chunk 10: SAFEmanual3.Rnw:157-162
entrez <- unlist(mget(names(genes),hgu133aENTREZID))
C.mat <- getCmatrix(gene.list = as.list(reactomeEXTID2PATHID),
                    present.genes = entrez,prefix = "REACTOME:",
                    min.size = 10, max.size = 500)
# results <- safe(e3.upp, p3.upp$p53, C.mat, print.it = FALSE) # This line is for analysis, not data generation

# 3. Serialize the objects to EACH declared input file
# Using .rds extension for R objects and sanitizing problematic characters in filenames.
# The workflow expects e3.upp, p3.upp$p53, p3.upp$er, C.mat.
# We save e3.upp and C.mat directly.
# For p3.upp$p53 and p3.upp$er, we extract the vectors and save them as separate .rds files
# to match the explicit listing of these as input files, using sanitized names.

saveRDS(e3.upp, "e3.upp.rds")
saveRDS(p3.upp$p53, "p3.upp_p53.rds")
saveRDS(p3.upp$er, "p3.upp_er.rds")
saveRDS(C.mat, "C.mat.rds")