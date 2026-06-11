# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("geomeTriD")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(geomeTriD)

src_file <- system.file("extdata", "pbmc_small.3d.rds", package = "geomeTriD")

if (file.exists(src_file)) {
    file.copy(src_file, "pbmc_small.3d.rds", overwrite = TRUE)
} else {
    # Create a synthetic data frame based on the vignette if the file is missing
    cells <- data.frame(
        umap_1 = c(-2.195171, -2.425737, -1.300247, -1.280686, -2.077747, -1.896454),
        umap_2 = c(0.6205683, 0.3946877, -2.0641031, 2.2639842, 0.1443148, 0.3670673),
        umap_3 = c(1.1399260, 1.5394660, 0.2079445, 1.0135704, 1.2094155, 0.7782331),
        nCount_RNA = c(70, 85, 87, 127, 173, 70),
        nFeature_RNA = c(47, 52, 50, 56, 53, 48),
        RNA_snn_res.0.8 = c(0, 0, 0, 0, 0, 0),
        letter.idents = c("A", "A", "A", "A", "A", "A"),
        groups = c("g2", "g2", "g2", "g2", "g2", "g2"),
        RNA_snn_res.1 = c(0, 0, 0, 0, 0, 0),
        CD7 = c(5.658486, 0, 0, 0, 0, 0),
        row.names = c("ATGCCAGAACGACT", "CATGGCCTGTGCAT", "GAACCTGATGAACC", "TGACTGGATTCTCA", "AGTCAGACTGCACA", "TCTGATACACGTGT")
    )
    saveRDS(cells, "pbmc_small.3d.rds")
}