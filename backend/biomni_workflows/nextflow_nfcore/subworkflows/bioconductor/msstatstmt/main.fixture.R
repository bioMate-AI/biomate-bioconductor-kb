# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MSstatsTMT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MSstatsTMT)

vignette_raw_pd_path <- system.file("extdata", "161117_SILAC_HeLa_UPS1_TMT10_5Mixtures_3TechRep_UPSdB_Multiconsensus_PD22_Intensity_PSMs.txt", package = "MSstatsTMT")
vignette_annotation_pd_path <- system.file("extdata", "PD_Annotation.csv", package = "MSstatsTMT")

vignette_raw.pd <- read.delim(vignette_raw_pd_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
vignette_annotation.pd <- read.csv(vignette_annotation_pd_path, header = TRUE, stringsAsFactors = FALSE)

write.table(vignette_raw.pd, file = "raw.pd", sep = "\t", row.names = FALSE, quote = FALSE)
write.csv(vignette_annotation.pd, file = "annotation.pd", row.names = FALSE)