# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("graphite", "ALL", "hgu95av2.db", "graph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(graphite)
library(ALL)
library(hgu95av2.db)
library(graph)

# --- Data preparation for 'graph' and 'genes' (from vignette chunk 3) ---
kegg  <- pathways("hsapiens", "kegg")
graph <- convertIdentifiers(kegg[["Chronic myeloid leukemia"]], "entrez")
graph <- pathwayGraph(graph)
genes <- nodes(graph)

# --- Data preparation for 'ALL' and 'classes' (from vignette chunks 4-8) ---
data(ALL)
pAllB <- pData(ALL)[grep("B", pData(ALL)$BT),]
NEG <- pAllB$'mol.biol' == "NEG"
BCR <- pAllB$'mol.biol' == "BCR/ABL"
pAll <- pAllB[(NEG | BCR),]
classesUn <- as.character(pAll$'mol.biol')
classesUn[classesUn=="BCR/ABL"] <- 2
classesUn[classesUn=="NEG"] <- 1
classesUn <- as.numeric(classesUn)
names(classesUn) <- row.names(pAll)
classes <- sort(classesUn)

# --- Data preparation for 'exp' and final 'graph' (from vignette chunks 9-11) ---
all <- ALL[,names(classes)]
probesIDS <- row.names(exprs(all))
featureNames(all@assayData)<-unlist(mget(probesIDS, hgu95av2ENTREZID))
all <- all[(!is.na(row.names(exprs(all))))]

all_rnames <- featureNames(all@assayData)
featureNames(all@assayData) <- paste("ENTREZID", all_rnames, sep = ":")

# Final filtering and subgraph creation
genes <- intersect(genes, row.names(exprs(all)))
graph <- subGraph(genes, graph) # 'graph' is modified here
exp <- all[genes,,drop=FALSE]

# --- Save the objects to RData files ---
save(exp, file="expression_data.RData")
save(classes, file="class_labels.RData")
save(graph, file="pathway_graph.RData")