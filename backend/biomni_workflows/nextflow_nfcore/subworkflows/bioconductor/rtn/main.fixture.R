# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RTN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RTN)

# Load the datasets provided by the RTN package
data(tniData)
data(tnaData)

# 1. expression_matrix.csv
# Normalized gene expression matrix with genes on rows and samples on columns
write.csv(tniData$expData, "expression_matrix.csv", row.names = TRUE)

# 2. tf_list.txt
# Vector of transcription factor gene symbols
tfs <- c("FOXM1", "E2F2", "E2F3", "RUNX2", "PTTG1")
writeLines(tfs, "tf_list.txt")

# 3. gene_annotation.csv
# Data frame with gene annotations
write.csv(tniData$rowAnnotation, "gene_annotation.csv", row.names = TRUE)

# 4. sample_annotation.csv
# Data frame with sample annotations
write.csv(tniData$colAnnotation, "sample_annotation.csv", row.names = TRUE)

# 5. phenotype_signature.tsv
# Named numeric vector of log2 fold changes and character vector of differentially expressed genes
# Combined into a single TSV for structured input
pheno_df <- data.frame(
  Gene = names(tnaData$phenotype),
  logFC = as.numeric(tnaData$phenotype),
  is_hit = names(tnaData$phenotype) %in% tnaData$hits,
  stringsAsFactors = FALSE
)
write.table(pheno_df, "phenotype_signature.tsv", sep = "\t", row.names = FALSE, quote = FALSE)