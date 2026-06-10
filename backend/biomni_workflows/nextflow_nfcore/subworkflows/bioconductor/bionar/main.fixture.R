# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioNAR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BioNAR)

# 1. PPI_Presynaptic.csv
ppi_file <- system.file("extdata", "PPI_Presynaptic.csv", package = "BioNAR")
if (file.exists(ppi_file)) {
    file.copy(ppi_file, "PPI_Presynaptic.csv", overwrite = TRUE)
} else {
    ppi_data <- data.frame(
        entA = c(273, 273, 273, 273, 273, 273), 
        entB = c(1759, 1785, 26052, 824, 161, 1020), 
        We = c(1, 1, 1, 1, 1, 1)
    )
    write.table(ppi_data, "PPI_Presynaptic.csv", sep = "\t", row.names = FALSE, quote = FALSE)
}

# 2. flatfile_human_gene2HDO.csv
hdo_file <- system.file("extdata", "flatfile_human_gene2HDO.csv", package = "BioNAR")
if (file.exists(hdo_file)) {
    file.copy(hdo_file, "flatfile_human_gene2HDO.csv", overwrite = TRUE)
} else {
    writeLines(c(
        "GeneID\tHDO_ID\tDiseaseName", 
        "273\tDOID:10652\tAlzheimer's disease",
        "1759\tDOID:10652\tAlzheimer's disease"
    ), "flatfile_human_gene2HDO.csv")
}

# 3. SCH_flatfile.csv
sch_file <- system.file("extdata", "SCH_flatfile.csv", package = "BioNAR")
if (file.exists(sch_file)) {
    file.copy(sch_file, "SCH_flatfile.csv", overwrite = TRUE)
} else {
    writeLines(c(
        "GeneID\tAnnotation", 
        "273\tSchizophrenia_related",
        "1785\tSchizophrenia_related"
    ), "SCH_flatfile.csv")
}

# 4. flatfile.go.BP.csv
go_file <- system.file("extdata", "flatfile.go.BP.csv", package = "BioNAR")
if (file.exists(go_file)) {
    file.copy(go_file, "flatfile.go.BP.csv", overwrite = TRUE)
} else {
    writeLines(c(
        "GeneID\tGO_ID\tGO_Term", 
        "273\tGO:0008150\tbiological_process",
        "26052\tGO:0008150\tbiological_process"
    ), "flatfile.go.BP.csv")
}