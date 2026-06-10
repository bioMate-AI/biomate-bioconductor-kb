library(puma)
library(pumadata)
library(oligo)

# Reproduce vignette data objects
data(oligo.estrogen)
data(eset_estrogen_mmgmos)
data(eset_gmoExon)
data(eset_gmhta)
data(pumapca_estrogen)
data(eset_estrogen_rma)
data(eset_estrogen_comb)
data(eset_mmgmos)
data(Clustii.exampleE)
data(Clustii.exampleStd)

# The workflow reads 'celFiles' as input.
# We provide a real CEL file named 'celFiles' so read.celfiles() can process it.
cel_candidates <- list.files(system.file("extdata", package="estrogen"), pattern="\\.cel$", full.names=TRUE, ignore.case=TRUE)

if (length(cel_candidates) > 0) {
    file.copy(cel_candidates[1], "celFiles", overwrite=TRUE)
} else {
    # Fallback synthetic CEL file if estrogen package is not available
    synthetic_cel <- c(
        "[CEL]",
        "Version=3",
        "FormatVersion=4",
        "[HEADER]",
        "Cols=2",
        "Rows=2",
        "TotalX=2",
        "TotalY=2",
        "[INTENSITY]",
        "NumberCells=4",
        "CellHeader=X\tY\tMEAN\tSTDV\tNPIXELS",
        "0\t0\t100.0\t10.0\t25",
        "1\t0\t200.0\t20.0\t25",
        "0\t1\t150.0\t15.0\t25",
        "1\t1\t250.0\t25.0\t25"
    )
    writeLines(synthetic_cel, "celFiles")
}