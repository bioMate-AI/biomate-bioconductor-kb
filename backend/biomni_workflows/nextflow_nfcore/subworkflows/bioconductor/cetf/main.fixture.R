# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CeTF", "airway")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CeTF)
library(airway)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Loading airway data
data("airway")

# Creating a variable with annotation data
anno <- as.data.frame(colData(airway))
anno <- anno[order(anno$dex, decreasing = TRUE), ]
anno <- data.frame(cond = anno$dex, row.names = rownames(anno))

# Creating a variable with count data
counts <- assay(airway)
# Sorting count data samples by conditions (untrt and trt)
counts <- counts[, rownames(anno)]
colnames(counts) <- paste0(colnames(counts), c(rep("_untrt", 4), rep("_trt", 4)))

# Differential Expression analysis to use only informative genes
# Using lfc=2 as in the RIF section of the vignette
DEGenes <- expDiff(exp = counts, anno = anno, conditions = c('untrt', 'trt'), lfc = 2, padj = 0.05, diffMethod = "Reverter")

# Selecting only DE genes from counts data
counts <- counts[rownames(DEGenes$DE_unique), ]

# Converting count data to TPM
tpm <- apply(counts, 2, function(x) { (1e+06 * x) / sum(x) })

# Count normalization
Clean_Dat <- normExp(tpm)

# Loading the Transcript Factors (TFs) character data
data("TFs")

# Verifying which TFs are in the subsetted normalized data
TFs_filtered <- rownames(Clean_Dat)[rownames(Clean_Dat) %in% TFs]


# 2. Serialize objects to declared input files

# counts_matrix.tsv: Clean_Dat (normalized expression matrix)
write.table(Clean_Dat, file = "counts_matrix.tsv", sep = "\t", quote = FALSE, col.names = NA)

# sample_metadata.csv: anno (sample annotation data frame)
write.csv(anno, file = "sample_metadata.csv", row.names = TRUE, quote = FALSE)

# tf_list.txt: TFs_filtered (list of transcript factors)
writeLines(TFs_filtered, con = "tf_list.txt")