# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ShortRead")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ShortRead)

# Find the export file shipped with the package
export_files <- list.files(system.file("extdata", package="ShortRead"), 
                           pattern="s_2_export.txt", 
                           recursive=TRUE, 
                           full.names=TRUE)

if (length(export_files) > 0) {
    file.copy(export_files[1], "export_file.txt")
} else {
    # Fallback: create a dummy export file matching the vignette's structure
    # Column 9 is sequence, Column 10 is quality
    row1 <- c("HWI-EAS88", "3", "2", "1", "451", "945", "", "", 
              "CCAGAGCCCCCCGCTCACTCCTGAACCAGTCTCTC", "YQMIMIMMLMMIGIGMFICMFFFIMMHIIHAAGAH", 
              "NM", "", "", "", "", "", "", "", "", "", "", "N")
    row2 <- c("HWI-EAS88", "3", "2", "1", "451", "946", "", "", 
              "AGCCTCCCTCTTTCTGAATATACGGCAGAGCTGTT", "ZXZUYXZQYYXUZXYZYYZZXXZZIMFHXQSUPPO", 
              "NM", "", "", "", "", "", "", "", "", "", "", "N")
    row3 <- c("HWI-EAS88", "3", "2", "1", "451", "947", "", "", 
              "ACCAAAAACACCACATACACGAGCAACACACGTAC", "LGDHLILLLLLLLIGFLLALDIFDILLHFIAECAE", 
              "NM", "", "", "", "", "", "", "", "", "", "", "N")
    
    write.table(rbind(row1, row2, row3), file="export_file.txt", 
                sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}