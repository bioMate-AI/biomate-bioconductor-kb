library(ISAnalytics)
library(tibble)
library(fs)

# Set appropriate data and metadata specs as per vignette
metadata_specs <- tibble::tribble(
  ~names, ~types, ~transform, ~flag, ~tag,
  "ProjectID", "char", NULL, "required", "project_id",
  "SubjectID", "char", NULL, "required", "subject",
  "Tissue", "char", NULL, "required", "tissue",
  "TimePoint", "int", NULL, "required", "tp_days",
  "CellMarker", "char", NULL, "required", "cell_marker",
  "ID", "char", NULL, "required", "pcr_repl_id",
  "SourceFileName", "char", NULL, "optional", NA_character_,
  "Link", "char", NULL, "optional", NA_character_
)
set_af_columns_def(metadata_specs)

mandatory_specs <- tibble::tribble(
  ~names, ~types, ~transform, ~flag, ~tag,
  "BarcodeSeq", "char", NULL, "required", NA_character_
)
set_mandatory_IS_vars(mandatory_specs)

# Locate the shipped test data
data_folder <- tempdir()
zip_path <- system.file("testdata", "testdata.zip", package = "ISAnalytics")

meta_path <- ""
matrix_path <- ""

if (file.exists(zip_path)) {
  utils::unzip(zipfile = zip_path, exdir = data_folder, overwrite = TRUE)
  if (file.exists(fs::path(data_folder, "barcodes_example_af.tsv.xz"))) {
    meta_path <- fs::path(data_folder, "barcodes_example_af.tsv.xz")
  }
  if (file.exists(fs::path(data_folder, "GSE144340_Matrix_542.tsv.xz"))) {
    matrix_path <- fs::path(data_folder, "GSE144340_Matrix_542.tsv.xz")
  }
}

# Fallback to searching the package directory if not in the zip
if (meta_path == "") {
  all_meta <- list.files(system.file(package = "ISAnalytics"), pattern = "barcodes_example_af.tsv.xz", full.names = TRUE, recursive = TRUE)
  if (length(all_meta) > 0) meta_path <- all_meta[1]
}

if (matrix_path == "") {
  all_matrix <- list.files(system.file(package = "ISAnalytics"), pattern = "GSE144340_Matrix_542.tsv.xz", full.names = TRUE, recursive = TRUE)
  if (length(all_matrix) > 0) matrix_path <- all_matrix[1]
}

# Import data if files are found, otherwise create synthetic data matching the vignette structure
if (meta_path != "" && matrix_path != "") {
  af <- import_association_file(meta_path, report_path = NULL)
  matrix <- import_single_Vispa2Matrix(matrix_path, sample_names_to = "ID")
} else {
  af <- tibble::tibble(
    ProjectID = "PMID32601433",
    SubjectID = "A0",
    Tissue = "BM",
    TimePoint = 21L,
    CellMarker = "Whole",
    ID = "BM_A0",
    SourceFileName = "GSE144340_Matrix_542.tsv.xz",
    Link = "http"
  )
  matrix <- tibble::tibble(
    BarcodeSeq = "AAAAAAAACACGGAGAACGACG",
    ID = "BM_A0",
    Value = 2
  )
}

# Serialize to the exact filenames expected by the workflow's load_r_object() helper
saveRDS(matrix, "integration_matrices")
saveRDS(af, "association_file")