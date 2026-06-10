# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SPIA", "hgu133plus2.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SPIA)
library(hgu133plus2.db)

data(colorectalcancer)

x <- hgu133plus2ENTREZID
top$ENTREZ<-unlist(as.list(x[top$ID]))
top<-top[!is.na(top$ENTREZ),]
top<-top[!duplicated(top$ENTREZ),]
tg1<-top[top$adj.P.Val<0.1,]
DE_Colorectal=tg1$logFC
names(DE_Colorectal)<-as.vector(tg1$ENTREZ)
ALL_Colorectal=top$ENTREZ

saveRDS(DE_Colorectal, file = "DE_Colorectal")
saveRDS(ALL_Colorectal, file = "ALL_Colorectal")

source_mydir_path <- system.file("extdata/keggxml/hsa", package="SPIA")
target_mydir_path <- "mydir"

if (!dir.exists(target_mydir_path)) {
  dir.create(target_mydir_path)
}

if (dir.exists(source_mydir_path)) {
  files_to_copy <- list.files(source_mydir_path, full.names = TRUE)
  file.copy(files_to_copy, target_mydir_path, recursive = TRUE)
} else {
  stop("Source directory for 'mydir' not found: ", source_mydir_path)
}