# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("FGNet", "org.Sc.sgd.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(FGNet)
library(org.Sc.sgd.db)

# 1. Reproduce the vignette's data-preparation code for genesYeastExpr
genesYeast <- c("ADA2", "APC1", "APC11", "APC2", "APC4", "APC5", "APC9", "CDC16", 
                "CDC23", "CDC26", "CDC27", "CFT1", "CFT2", "DCP1", "DOC1", "FIP1", 
                "GCN5", "GLC7", "HFI1", "KEM1", "LSM1", "LSM2", "LSM3", "LSM4", 
                "LSM5", "LSM6", "LSM7", "LSM8", "MPE1", "NGG1", "PAP1", "PAT1", 
                "PFS2", "PTA1", "PTI1", "REF2", "RNA14", "RPN1", "RPN10", "RPN11", 
                "RPN13", "RPN2", "RPN3", "RPN5", "RPN6", "RPN8", "RPT1", "RPT3", 
                "RPT6", "SGF11", "SGF29", "SGF73", "SPT20", "SPT3", "SPT7", "SPT8", 
                "TRA1", "YSH1", "YTH1")

geneLabels <- unlist(as.list(org.Sc.sgdGENENAME))
genesYeast <- sort(geneLabels[which(geneLabels %in% genesYeast)])

# Optional: Gene expression (1=UP, -1=DW)
genesYeastExpr <- setNames(c(rep(1, 28), rep(-1, 30)), genesYeast)

# Serialize the object to the declared input file
saveRDS(genesYeastExpr, "genesYeastExpr.rds")

# 2. Construct a synthetic DAVID Functional Annotation Clustering report
david_content <- "Annotation Cluster 1\tEnrichment Score: 2.5
Category\tTerm\tCount\t%\tPValue\tGenes\tList Total\tPop Hits\tPop Total\tFold Enrichment\tBonferroni\tBenjamini\tFDR
GOTERM_BP_FAT\tGO:0000001~term1\t3\t10\t0.01\tADA2, APC1, APC11\t50\t100\t1000\t2\t0.1\t0.1\t0.1
GOTERM_BP_FAT\tGO:0000002~term2\t3\t10\t0.01\tAPC2, APC4, APC5\t50\t100\t1000\t2\t0.1\t0.1\t0.1

Annotation Cluster 2\tEnrichment Score: 1.5
Category\tTerm\tCount\t%\tPValue\tGenes\tList Total\tPop Hits\tPop Total\tFold Enrichment\tBonferroni\tBenjamini\tFDR
GOTERM_BP_FAT\tGO:0000003~term3\t3\t10\t0.01\tCDC16, CDC23, CDC26\t50\t100\t1000\t2\t0.1\t0.1\t0.1
"

# Write the mock DAVID file to the exact URL path structure to satisfy the offline read
dir.create("http://david.abcc.ncifcrf.gov/data/download", recursive=TRUE, showWarnings=FALSE)
writeLines(david_content, "http://david.abcc.ncifcrf.gov/data/download/90128.txt")

# Also write to the basename in the working directory as a fallback
writeLines(david_content, "90128.txt")