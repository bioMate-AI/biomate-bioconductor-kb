library(CAFE)

# 1. Reproduce the vignette's data-preparation code
data("CAFE_data")

# 2. The workflow expects .CEL files in the working directory.
# Since .CEL files are raw Affymetrix binary/text files and cannot be 
# reverse-engineered from the processed CAFE_data list, we construct 
# minimal synthetic .CEL files (Text format v3) to satisfy the input requirement.
# We name them after the samples present in the CAFE_data object.

sample_names <- names(CAFE_data[[2]])

dummy_cel_content <- c(
    "[CEL]",
    "Version=3",
    "[HEADER]",
    "Cols=2",
    "Rows=2",
    "TotalX=2",
    "TotalY=2",
    "GridCornerUL=0 0",
    "GridCornerUR=1 0",
    "GridCornerLR=1 1",
    "GridCornerLL=0 1",
    "DatHeader=[0..65535] dummy",
    "Algorithm=Percentile",
    "AlgorithmParameters=Percentile:75",
    "[INTENSITY]",
    "NumberCells=4",
    "CellHeader=X\tY\tMEAN\tSTDV\tNPIXELS",
    "0\t0\t100.0\t10.0\t25",
    "1\t0\t200.0\t20.0\t25",
    "0\t1\t300.0\t30.0\t25",
    "1\t1\t400.0\t40.0\t25"
)

# Write a few dummy .CEL files to the working directory
for (s in head(sample_names, 4)) {
    writeLines(dummy_cel_content, s)
}