library(seahtrue)

# Locate the Excel file shipped with the package
src_file <- system.file("extdata", "20191219_SciRep_PBMCs_donor_A.xlsx", package = "seahtrue")

# Copy it to the current working directory to serve as the input fixture
if (file.exists(src_file)) {
  file.copy(src_file, "20191219_SciRep_PBMCs_donor_A.xlsx", overwrite = TRUE)
} else {
  stop("The required input file 20191219_SciRep_PBMCs_donor_A.xlsx was not found in the seahtrue package.")
}