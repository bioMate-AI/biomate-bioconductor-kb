# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PADOG", "KEGGdzPathwaysGEO", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PADOG)
library(KEGGdzPathwaysGEO)
library(Biobase)

set = "GSE9348"
data(list = set, package = "KEGGdzPathwaysGEO")

# write a function to extract required info into a list
getdataaslist = function(x) {
    x = get(x)
    exp = experimentData(x)
    dataset = exp@name
    disease = notes(exp)$disease
    dat.m = exprs(x)
    ano = pData(x)
    design = notes(exp)$design
    annotation = paste(x@annotation, ".db", sep = "")
    targetGeneSets = notes(exp)$targetGeneSets
    list = list(dataset, disease, dat.m, ano, design, annotation, targetGeneSets)
    names(list) = c("dataset", "disease", "dat.m", "ano", "design", "annotation", 
        "targetGeneSets")
    return(list)
}

dlist = getdataaslist(set)

# Serialize the objects to the declared input files
saveRDS(dlist$dat.m, "esetm.csv")
saveRDS(dlist$ano$Group, "group.txt")
saveRDS(dlist$annotation, "annotation.txt")

# Also save with .rds extension as a fallback
saveRDS(dlist$dat.m, "esetm.csv")
saveRDS(dlist$ano$Group, "group.txt")
saveRDS(dlist$annotation, "annotation.txt")