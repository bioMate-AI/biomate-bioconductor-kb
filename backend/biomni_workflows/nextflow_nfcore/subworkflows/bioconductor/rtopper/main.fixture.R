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

# Load example data provided by the package
data(exampleData)

# Create functional gene sets (fgsList)
kegg <- as.list(org.Hs.egPATH2EG)
go <- as.list(org.Hs.egGO2ALLEGS)

someKeggID <- c("00450", "04971", "00970", "04260", "05320")
kegg <- lapply(kegg[someKeggID], function(x) unique(unlist(mget(x, org.Hs.egSYMBOL))))

set.seed(9)
go <- lapply(go[sample(1:length(go), 5)], function(x) unique(unlist(mget(x, org.Hs.egSYMBOL))))

# Offline alternative to KEGGREST::keggGet to avoid internet queries
names(kegg) <- paste0("hsa", someKeggID)

# Annotate GO terms
names(go) <- paste(names(go), Term(names(go)), sep=".")

fgsList <- list(go=go, kegg=kegg)

# Serialize objects to the expected input files
saveRDS(dat, "dat.rds")
saveRDS(pheno, "pheno.rds")
saveRDS(fgsList, "fgsList.rds")