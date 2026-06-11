# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("limma")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(limma)

# Attempt to find real .CEL files from common Bioconductor data packages
cel_files_found <- FALSE
for (pkg in c("estrogen", "affydata", "CLL", "ALL")) {
    if (requireNamespace(pkg, quietly = TRUE)) {
        pkg_dir <- system.file("extdata", package = pkg)
        if (pkg_dir != "") {
            cels <- list.files(pkg_dir, pattern = "\\.CEL$|\\.cel$|\\.CEL\\.gz$|\\.cel\\.gz$", full.names = TRUE)
            if (length(cels) > 0) {
                cels_to_copy <- head(cels, 4)
                dest_files <- gsub("\\.gz$", "", basename(cels_to_copy))
                
                for (i in seq_along(cels_to_copy)) {
                    if (grepl("\\.gz$", cels_to_copy[i])) {
                        lines <- readLines(gzfile(cels_to_copy[i]), warn = FALSE)
                        writeLines(lines, dest_files[i])
                    } else {
                        file.copy(cels_to_copy[i], dest_files[i])
                    }
                }
                
                targets <- data.frame(
                    FileName = dest_files,
                    Treatment = rep(c("Control", "Treated"), length.out = length(dest_files))
                )
                write.table(targets, "targets.txt", sep = "\t", quote = FALSE, row.names = FALSE)
                cel_files_found <- TRUE
                break
            }
        }
    }
}

if (!cel_files_found) {
    # Fallback: create synthetic targets.txt and dummy .CEL files
    targets <- data.frame(
        FileName = c("sample1.CEL", "sample2.CEL", "sample3.CEL", "sample4.CEL"),
        Treatment = c("Control", "Control", "Treated", "Treated")
    )
    write.table(targets, "targets.txt", sep = "\t", quote = FALSE, row.names = FALSE)
    
    for (f in targets$FileName) {
        # Create a minimal valid-looking Affymetrix CEL file (version 3 text format)
        cel_content <- c(
            "[CEL]",
            "Version=3",
            "[HEADER]",
            "Cols=2",
            "Rows=2",
            "TotalX=2",
            "TotalY=2",
            "GridCornerUL=0 0",
            "GridCornerUR=2 0",
            "GridCornerLR=2 2",
            "GridCornerLL=0 2",
            "Axis-invertX=0",
            "AxisInvertY=0",
            "swapXY=0",
            "DatHeader=[0..65535]  sample",
            "Algorithm=Percentile",
            "AlgorithmParameters=Percentile:75;CellMargin:2;OutlierHigh:1.500;OutlierLow:1.004",
            "[INTENSITY]",
            "NumberCells=4",
            "CellHeader=X\tY\tMEAN\tSTDV\tNPIXELS",
            "0\t0\t100.0\t10.0\t25",
            "1\t0\t150.0\t15.0\t25",
            "0\t1\t200.0\t20.0\t25",
            "1\t1\t250.0\t25.0\t25"
        )
        writeLines(cel_content, f)
    }
}