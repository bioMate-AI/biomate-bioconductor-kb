# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("arrow")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(arrow)

# Construct synthetic DIA-NN/Spectronaut precursor-level quantification table in long format
# based on the vignette's peptide data but reshaped to match the expected parquet input
report <- data.frame(
  Run = rep(c("6A_7", "6A_8", "6A_9", "6B_7", "6B_8", "6B_9"), each = 6),
  Protein.Group = rep(c(
    "sp|P38915|SPT8_YEAST", 
    "sp|Q3E792|RS25A_YEAST", 
    "sp|Q3E792|RS25A_YEAST", 
    "sp|P09938|RIR2_YEAST", 
    "sp|P09938|RIR2_YEAST", 
    "sp|P53075|SHE10_YEAST"
  ), 6),
  Precursor.Id = rep(c(
    "AAAAGAGGAGDSGDAVTK", 
    "AAAALAGGK", 
    "AAAALAGGKK", 
    "AAADALSDLEIK", 
    "AAADALSDLEIKDSK", 
    "AAAEEFQR"
  ), 6),
  Precursor.Quantity = c(
    1190800, 280990000, 33360000, 54622000, 18910000, 1158600,
    0, 2441300, 1029200, 515460, 331130, 0,
    0, 1220000, 668040, 670780, 420900, 0,
    66760, 1337600, 638990, 712140, 365560, 51558,
    0, 2850900, 777030, 426580, 329250, 0,
    37436, 935580, 641270, 620510, 380820, 76970
  ),
  Q.Value = rep(0.001, 36),
  PG.Q.Value = rep(0.001, 36)
)

write_parquet(report, "report.parquet")

# Construct sample annotation table mapping runs to experimental conditions
experimental_design <- data.frame(
  run = c("6A_7", "6A_8", "6A_9", "6B_7", "6B_8", "6B_9"),
  condition = c("A", "A", "A", "B", "B", "B")
)

write.csv(experimental_design, "experimental_design.csv", row.names = FALSE)