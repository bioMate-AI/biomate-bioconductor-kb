# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GSAR", "GSVAdata", "org.Hs.eg.db", "GSEABase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GSAR)
library(GSVAdata)
library(org.Hs.eg.db)
library(GSEABase)

data(p53DataSet)
data(c2BroadSets)

C2 <- as.list(geneIds(c2BroadSets))
len <- length(C2)
genes.entrez <- unique(unlist(C2))
genes.symbol <- array("",c(length(genes.entrez),1))
x <- org.Hs.egSYMBOL
mapped_genes <- mappedkeys(x)
xx <- as.list(x[mapped_genes])
for (ind in 1:length(genes.entrez)){
    if (length(xx[[genes.entrez[ind]]])!=0)
        genes.symbol[ind] <- xx[[genes.entrez[ind]]]
}

genes.no.mapping <- which(genes.symbol == "")
if(length(genes.no.mapping) > 0){
    genes.entrez <- genes.entrez[-genes.no.mapping]
    genes.symbol <- genes.symbol[-genes.no.mapping]
}
names(genes.symbol) <- genes.entrez

p53genes <- rownames(p53DataSet)
remained <- array(0,c(1,len))
for (k in seq(1, len, by=1)) {
    remained[k] <- sum((genes.symbol[C2[[k]]] %in% p53genes) & 
    (C2[[k]] %in% genes.entrez))
}

C2 <- C2[(remained>=10)&(remained<=500)]
pathway.names <- names(C2)
c2.pathways <- list()
for (k in seq(1, length(C2), by=1)) {
    selected.genes <- which(p53genes %in% genes.symbol[C2[[k]]])
    c2.pathways[[length(c2.pathways)+1]] <- p53genes[selected.genes]
}
names(c2.pathways) <- pathway.names

group.label <- c(rep(1,17), rep(2,33))

saveRDS(p53DataSet, "p53DataSet.rds")
saveRDS(c2.pathways, "c2.pathways.rds")
saveRDS(group.label, "group.label.rds")