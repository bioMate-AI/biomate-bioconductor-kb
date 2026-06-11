# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("fgsea")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(fgsea)

# Locate the shipped files from the package's extdata directory
rnk_candidates <- list.files(system.file("extdata", package="fgsea"), pattern="naive.vs.th1.rnk", recursive=TRUE, full.names=TRUE)
gmt_candidates <- list.files(system.file("extdata", package="fgsea"), pattern="mouse.reactome.gmt", recursive=TRUE, full.names=TRUE)

# Copy or generate naive.vs.th1.rnk
if (length(rnk_candidates) > 0 && file.exists(rnk_candidates[1])) {
    file.copy(rnk_candidates[1], "naive.vs.th1.rnk", overwrite=TRUE)
} else {
    # Synthetic fallback matching the expected tab-separated format (Gene ID, Stat)
    rnk_data <- data.frame(
        Gene = c("143384", "264270", "317754", "12443", "12444"),
        Stat = c(5.4, 3.2, -2.1, 1.5, -3.8)
    )
    write.table(rnk_data, "naive.vs.th1.rnk", sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE)
}

# Copy or generate mouse.reactome.gmt
if (length(gmt_candidates) > 0 && file.exists(gmt_candidates[1])) {
    file.copy(gmt_candidates[1], "mouse.reactome.gmt", overwrite=TRUE)
} else {
    # Synthetic fallback matching the expected GMT format (Pathway, Description, Gene1, Gene2, ...)
    gmt_lines <- c(
        "Reactome_Pathway_1\t\t143384\t264270\t12443",
        "Reactome_Pathway_2\t\t317754\t12444"
    )
    writeLines(gmt_lines, "mouse.reactome.gmt")
}