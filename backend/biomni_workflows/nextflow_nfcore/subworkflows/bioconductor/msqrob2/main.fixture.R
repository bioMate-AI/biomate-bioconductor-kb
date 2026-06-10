# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("QFeatures", "dplyr", "tidyr", "msqrob2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library("QFeatures")
  library("dplyr")
  library("tidyr")
  library("msqrob2")
})

# Construct synthetic MaxQuant peptide-level intensity table
peptides <- data.frame(
  Sequence = c("AAAAGAGGAGDSGDAVTK", "AAAALAGGK", "AAAALAGGKK", "AAADALSDLEIK", "AAADALSDLEIKDSK", "AAAEEFQR"),
  Proteins = c("sp|P38915|SPT8_YEAST", "sp|Q3E792|RS25A_YEAST;sp|P0C0T4|RS25B_YEAST", "sp|Q3E792|RS25A_YEAST;sp|P0C0T4|RS25B_YEAST", "sp|P09938|RIR2_YEAST", "sp|P09938|RIR2_YEAST", "sp|P53075|SHE10_YEAST"),
  Intensity.6A_7 = c(1190800, 280990000, 33360000, 54622000, 18910000, 1158600),
  Intensity.6A_8 = c(0, 2441300, 1029200, 515460, 331130, 0),
  Intensity.6A_9 = c(0, 1220000, 668040, 670780, 420900, 0),
  Intensity.6B_7 = c(66760, 1337600, 638990, 712140, 365560, 51558),
  Intensity.6B_8 = c(0, 2850900, 777030, 426580, 329250, 0),
  Intensity.6B_9 = c(37436, 935580, 641270, 620510, 380820, 0),
  Reverse = rep("", 6),
  Potential.contaminant = rep("", 6)
)

# Construct sample annotation table
annot <- data.frame(
  quantCols = c("Intensity.6A_7", "Intensity.6A_8", "Intensity.6A_9", "Intensity.6B_7", "Intensity.6B_8", "Intensity.6B_9"),
  sampleId = c("A_7", "A_8", "A_9", "B_7", "B_8", "B_9"),
  condition = c("A", "A", "A", "B", "B", "B"),
  rep = c(7, 8, 9, 7, 8, 9)
)

# Write to the expected input files
write.table(peptides, "peptides.txt", sep = "\t", row.names = FALSE, quote = FALSE)
write.csv(annot, "experimental_design.csv", row.names = FALSE, quote = FALSE)