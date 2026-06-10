# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ReactomePA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ReactomePA)

if (requireNamespace("DOSE", quietly = TRUE)) {
    data(geneList, package = "DOSE")
    genes <- data.frame(
        Entrez = names(geneList),
        logFC = as.numeric(geneList),
        stringsAsFactors = FALSE
    )
} else {
    genes <- data.frame(
        Entrez = c("4312", "8318", "10874", "55143", "55388", "991", "6280", "2305", "4605", "9333"),
        logFC = c(4.5, 3.2, 2.8, 2.1, 1.9, -1.5, -2.0, -2.5, -3.1, -4.2),
        stringsAsFactors = FALSE
    )
}

write.table(genes, file = "ranked_genes.tsv", sep = "\t", row.names = FALSE, quote = FALSE)