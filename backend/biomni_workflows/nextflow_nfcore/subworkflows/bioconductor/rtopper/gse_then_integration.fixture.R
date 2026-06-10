# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RTopper", "org.Hs.eg.db", "GO.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RTopper)
library(org.Hs.eg.db)
library(GO.db)

set.seed(9)

# Load example data which provides 'dat' and 'pheno'
data(exampleData)

# Create fgsList based on the vignette
kegg <- as.list(org.Hs.egPATH2EG)
go <- as.list(org.Hs.egGO2ALLEGS)

someKeggID <- c("00450", "04971", "00970", "04260", "05320")
kegg <- lapply(kegg[someKeggID], function(x) unique(unlist(mget(x, org.Hs.egSYMBOL))))

# Offline replacement for KEGGREST::keggGet to avoid internet dependency
names(kegg) <- paste0("KEGG_Pathway_", someKeggID)

go <- lapply(go[sample(1:length(go), 5)], function(x) unique(unlist(mget(x, org.Hs.egSYMBOL))))
names(go) <- paste(names(go), Term(names(go)), sep=".")

fgsList <- list(go=go, kegg=kegg)

# Serialize to the required input files
saveRDS(dat, "dat.rds")
saveRDS(pheno, "pheno.rds")
saveRDS(fgsList, "fgsList.rds")