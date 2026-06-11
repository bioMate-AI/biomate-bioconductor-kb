library(puma)
library(pumadata)
library(oligo)

# The workflow expects raw Affymetrix 3' array CEL files in the working directory.
# We first search for any real CEL files shipped with installed packages (e.g., companion data).
cel_paths <- list.files(.libPaths(), pattern="(?i)\\.cel(?:\\.gz)?$", recursive=TRUE, full.names=TRUE)

if (length(cel_paths) > 0) {
    # Copy up to 8 real CEL files to the working directory to match the vignette's estrogen example size
    n_files <- min(8, length(cel_paths))
    selected_cels <- cel_paths[1:n_files]
    file.copy(selected_cels, basename(selected_cels))
} else {
    # If no real CEL files are found in the environment, construct synthetic text-based CEL files (Version 3).
    # This guarantees the files exist and match the structural format expected by read.celfiles().
    dummy_cel_content <- c(
        "[CEL]",
        "Version=3",
        "",
        "[HEADER]",
        "Cols=2",
        "Rows=2",
        "TotalX=2",
        "TotalY=2",
        "GridCornerUL=0 0",
        "GridCornerUR=1 0",
        "GridCornerLR=1 1",
        "GridCornerLL=0 1",
        "Axis-invertX=0",
        "AxisInvertY=0",
        "swapXY=0",
        "DatHeader=[0..65535] dummy",
        "Algorithm=Percentile",
        "AlgorithmParameters=Percentile:75",
        "",
        "[INTENSITY]",
        "NumberCells=4",
        "CellHeader=X\tY\tMEAN\tSTDV\tNPIXELS",
        "0\t0\t100.0\t10.0\t25",
        "1\t0\t200.0\t20.0\t25",
        "0\t1\t150.0\t15.0\t25",
        "1\t1\t250.0\t25.0\t25",
        "",
        "[MASKS]",
        "NumberCells=0",
        "CellHeader=X\tY",
        "",
        "[OUTLIERS]",
        "NumberCells=0",
        "CellHeader=X\tY",
        "",
        "[MODIFIED]",
        "NumberCells=0",
        "CellHeader=X\tY"
    )
    
    for (i in 1:8) {
        writeLines(dummy_cel_content, sprintf("synthetic_sample_%d.CEL", i))
    }
}