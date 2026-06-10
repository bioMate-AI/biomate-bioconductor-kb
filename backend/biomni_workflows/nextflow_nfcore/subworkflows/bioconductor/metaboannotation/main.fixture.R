# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MetaboAnnotation")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MetaboAnnotation)

# Locate the original files shipped with the package
ms1_file <- system.file("extdata", "MS1_example.txt", package = "MetaboAnnotation")
target_file <- system.file("extdata", "LipidMaps_CompDB.txt", package = "MetaboAnnotation")

# Read or construct ms1_features
if (file.exists(ms1_file)) {
    ms1_features <- read.table(ms1_file, header = TRUE, sep = "\t")
} else {
    ms1_features <- data.frame(
        feature_id = c("Cluster_0001", "Cluster_0002", "Cluster_0003", "Cluster_0004", "Cluster_0005", "Cluster_0006"),
        mz = c(102.1281, 102.1279, 102.1281, 102.1281, 102.1270, 102.1230),
        rtime = c(1.560147, 2.153590, 2.925570, 3.419617, 5.801039, 8.137535)
    )
}

# Read or construct LipidMaps_CompDB
if (file.exists(target_file)) {
    target_df <- read.table(target_file, header = TRUE, sep = "\t")
} else {
    target_df <- data.frame(
        headgroup = c("NAE", "NAT", "NAE", "NAE", "NAE", "NAE"),
        name = c("NAE 20:4;O", "NAT 20:4;O", "NAE 20:3;O2", "NAE 20:4", "NAE 18:2", "NAE 18:3"),
        exactmass = c(363.2773, 427.2392, 381.2879, 347.2824, 323.2824, 321.2668),
        formula = c("C22H37NO3", "C22H37NO5S", "C22H39NO4", "C22H37NO2", "C20H37NO2", "C20H35NO2"),
        chain_type = c("even", "even", "even", "even", "even", "even")
    )
}

# Write the files to the working directory as expected by the workflow
write.table(ms1_features, file = "ms1_features.txt", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(target_df, file = "LipidMaps_CompDB.txt", sep = "\t", row.names = FALSE, quote = FALSE)