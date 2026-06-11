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

randFun = function(dseed, mname = "myRand") {
    #a helper function to pass additional variables to your method
    getdataaslist = getdataaslist
    return(function(set, mygslist, minsize) {#your method function
        set.seed(dseed)
        #this loads the dataset 
        data(list = set, package = "KEGGdzPathwaysGEO")
        #extract the required info using the function defined earlier 
        dlist = getdataaslist(set)
        #get rid of duplicates probesets per ENTREZ ID by keeping the probeset 
        #with smallest p-value (computed using limma) 
        aT1 = filteranot(esetm = dlist$dat.m, group = dlist$ano$Group, 
            paired = dlist$design == "Paired", block = dlist$ano$Block, 
            annotation = dlist$annotation)
        #create an output dataframe for this toy method with random gene set p-values
        mygslistSize = unlist(lapply(mygslist, function(x) {
            length(intersect(aT1$ENTREZID, x))
        }))
        res = data.frame(ID = names(mygslist), P = runif(length(mygslist)),
            Size = mygslistSize, stringsAsFactors = FALSE)
        res$FDR = p.adjust(res$P,"fdr")
        #drop genesets with less than minsize genes in the current dataset 
        res = res[res$Size >= minsize,]
        #compute ranks
        res$Rank = rank(res$P) / dim(res)[1]*100
        #needed to compare ranks between methods; must be the same as given 
        #in mymethods argument "list(myRand="
        res$Method = mname 
        #needed because comparisons of ranks between methods is paired at dataset level
        res$Dataset = dlist$dataset
        #output only result for the targetGeneSets 
        #which are gene sets expected to be relevant in this dataset
        return(res[res$ID %in% dlist$targetGeneSets,])
        }
    )
}

randomF = randFun(1)
saveRDS(randomF, "custom_method_function")

mysets = c("GSE9348", "GSE8671", "GSE1297")
saveRDS(mysets, "datasets")