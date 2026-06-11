# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("topGO", "ALL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(topGO)
library(ALL)

# Load the ALL dataset and geneList as demonstrated in the vignette
data(ALL)
data(geneList)

# Determine and load the corresponding annotation package
affyLib <- paste(annotation(ALL), "db", sep = ".")
library(package = affyLib, character.only = TRUE)

# 1. Generate geneid2go.map
# Extract GO annotations for the genes in geneList
genes <- names(geneList)
go_map <- suppressMessages(AnnotationDbi::select(get(affyLib), 
                                                 keys = genes, 
                                                 columns = "GO", 
                                                 keytype = "PROBEID"))
go_map <- go_map[!is.na(go_map$GO), ]

# Aggregate GO terms by gene ID, separated by commas
go_agg <- aggregate(GO ~ PROBEID, data = go_map, FUN = function(x) paste(unique(x), collapse = ", "))

# Write to tab-separated file without quotes or headers
write.table(go_agg, file = "geneid2go.map", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# 2. Generate myInterestingGenes
# Identify interesting genes (e.g., p-value < 0.01) as done in the vignette's topDiffGenes logic
myInterestingGenes <- names(geneList)[geneList < 0.01]

# Write the character vector of interesting genes to a text file
writeLines(myInterestingGenes, "myInterestingGenes")