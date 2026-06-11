# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("coGPS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(coGPS)

data(Exon_exprs_matched)
data(Methy_exprs_matched)
data(CNV_exprs_matched)
data(Exon_classlab_matched)
data(Methy_classlab_matched)
data(CNV_classlab_matched)

Exon_exprs <- as.matrix(Exon_exprs_matched)
Methy_exprs <- as.matrix(Methy_exprs_matched)
CNV_exprs <- as.matrix(CNV_exprs_matched)

Exon_classlab <- unlist(Exon_classlab_matched)
Methy_classlab <- unlist(Methy_classlab_matched)
CNV_classlab <- unlist(CNV_classlab_matched)

write.csv(Exon_exprs, "gene_expression.csv", row.names = TRUE)
write.csv(Methy_exprs, "methylation.csv", row.names = TRUE)
write.csv(CNV_exprs, "cnv.csv", row.names = TRUE)

sample_names <- colnames(Exon_exprs)

class_labels_df <- data.frame(
  Exon_classlab = Exon_classlab,
  Methy_classlab = Methy_classlab,
  CNV_classlab = CNV_classlab
)
rownames(class_labels_df) <- sample_names

write.csv(class_labels_df, "class_labels.csv", row.names = TRUE)