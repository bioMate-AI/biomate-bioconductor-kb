# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MiRaGE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MiRaGE)

src_file <- system.file("extdata", "x_all_7a.csv", package="MiRaGE")

if (file.exists(src_file)) {
    file.copy(src_file, "x_all_7a.csv", overwrite = TRUE)
} else {
    x_gene <- data.frame(
        gene_id = c("200000_s_at", "200001_at", "200002_at", "200003_s_at", "200004_at"),
        GSM1 = c(8.5, 9.2, 7.1, 5.5, 12.1),
        GSM2 = c(8.6, 9.1, 7.3, 5.6, 12.0),
        GSM3 = c(8.4, 9.3, 7.2, 5.4, 12.2),
        GSM4 = c(10.1, 8.2, 6.5, 7.5, 10.1),
        GSM5 = c(10.2, 8.1, 6.6, 7.6, 10.0),
        GSM6 = c(10.0, 8.3, 6.4, 7.4, 10.2)
    )
    write.table(x_gene, "x_all_7a.csv", sep="\t", row.names=FALSE, quote=FALSE)
}