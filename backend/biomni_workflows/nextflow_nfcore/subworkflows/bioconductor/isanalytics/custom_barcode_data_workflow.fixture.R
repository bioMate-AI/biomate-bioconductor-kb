library(ISAnalytics)
library(readr)

data_folder <- tempdir()
zip_path <- system.file("testdata", "testdata.zip", package = "ISAnalytics")

if (file.exists(zip_path)) {
    utils::unzip(zipfile = zip_path, exdir = data_folder, overwrite = TRUE)
    
    meta_file <- "barcodes_example_af.tsv.xz"
    matrix_file <- "GSE144340_Matrix_542.tsv.xz"
    
    meta_df <- readr::read_tsv(file.path(data_folder, meta_file), show_col_types = FALSE)
    readr::write_tsv(meta_df, "barcodes_metadata.tsv")
    
    file.copy(file.path(data_folder, matrix_file), "barcodes_matrix.tsv.xz", overwrite = TRUE)
} else {
    # Fallback if testdata.zip is not available
    meta_df <- data.frame(
        ProjectID = c("PMID32601433", "PMID32601433"),
        SubjectID = c("A0", "C3"),
        Tissue = c("BM", "PB"),
        TimePoint = c(21, 21),
        CellMarker = c("Whole", "Whole"),
        ID = c("BM_A0", "PB21_C3"),
        SourceFileName = c("GSE144340_Matrix_542.tsv.xz", "GSE144340_Matrix_542.tsv.xz"),
        Link = c("http", "http")
    )
    readr::write_tsv(meta_df, "barcodes_metadata.tsv")
    
    matrix_df <- data.frame(
        BarcodeSeq = c("AAAAAAAACACGGAGAACGACG", "AAAAAAAACGCGAACAACTACG", "AAAAAAAATTTTTAAACGTACC"),
        BM_A0 = c(0, 0, 1),
        PB21_C3 = c(2, 1, 0)
    )
    readr::write_tsv(matrix_df, "barcodes_matrix.tsv.xz")
}