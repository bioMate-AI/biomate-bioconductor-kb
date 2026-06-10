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
library(graph) # For subGraph

# 1. Prepare 'graph' and initial 'genes' from vignette chunk 3
kegg  <- pathways("hsapiens", "kegg")
graph_temp <- convertIdentifiers(kegg[["Chronic myeloid leukemia"]], "entrez")
graph_temp <- pathwayGraph(graph_temp)
genes_temp <- nodes(graph_temp)

# 2. Prepare 'classes' from vignette chunks 4, 6, 7, 8
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

# 3. Prepare 'all' (ExpressionSet) from vignette chunks 9, 10
all <- ALL[,names(classes)]
probesIDS <- row.names(exprs(all))
# Use ifnotfound=NA to handle probes not found, as the vignette filters NAs later.
featureNames(all@assayData) <- unlist(mget(probesIDS, hgu95av2ENTREZID, ifnotfound = NA))
all <- all[(!is.na(row.names(exprs(all))))]

all_rnames <- featureNames(all@assayData)
featureNames(all@assayData) <- paste("ENTREZID", all_rnames, sep = ":")

# 4. Obtain final 'genes' and subset 'graph' and 'exp' from vignette chunk 11
# The 'genes' variable is updated in the vignette to be the intersection
# of genes from the graph and genes present in the expression data.
genes <- intersect(genes_temp, row.names(exprs(all)))

# Final 'graph' object
graph <- subGraph(genes, graph_temp)

# Final 'exp' object
exp <- all[genes,,drop=FALSE]

# 5. Save the objects to RData files
# Each .RData file should contain a single object with the specified name
# (exp, classes, graph) as expected by the workflow's load_rdata_object function.

save(exp, file = "expression_data.RData")
save(classes, file = "class_labels.RData")
save(graph, file = "pathway_graph.RData")