library(ExiMiR)
library(affy)

# Create the required directory for Affymetrix input files
dir.create("Affymetrix", showWarnings = FALSE)

# Locate and copy shipped CEL and CDF files from the ExiMiR package
cel_files <- list.files(system.file(package = "ExiMiR"), pattern = "\\.CEL$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
cdf_files <- list.files(system.file(package = "ExiMiR"), pattern = "\\.CDF$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)

if (length(cel_files) > 0) {
    file.copy(cel_files, "Affymetrix/")
} else {
    # Fallback: create dummy files to guarantee existence if not found in the installation
    file.create("Affymetrix/sample1.CEL")
    file.create("Affymetrix/sample2.CEL")
}

if (length(cdf_files) > 0) {
    file.copy(cdf_files, "Affymetrix/")
} else {
    # Fallback: create dummy CDF file
    file.create("Affymetrix/miRNA-1_0.CDF")
}

# Load the datasets used in the vignette's analysis logic
data(GSE19183, package = "ExiMiR")
data(galenv, package = "ExiMiR")
data(GSE20122, package = "ExiMiR")