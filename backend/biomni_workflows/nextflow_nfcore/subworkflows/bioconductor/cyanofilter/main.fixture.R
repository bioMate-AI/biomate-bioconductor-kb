# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dplyr", "magrittr", "tidyr", "purrr", "flowCore", "flowDensity", "cyanoFilter", "stringr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dplyr)
library(magrittr)
library(tidyr)
library(purrr)
library(flowCore)
library(flowDensity)
library(cyanoFilter)
library(stringr) # Explicitly load stringr as it's used for str_extract and str_detect

# --- Reproduce VIGNETTE'S OWN data-preparation code for metadata ---

# Load raw metadata from package extdata
metadata_path_vignette <- system.file("extdata", "2019-03-25_Rstarted.csv",
                                      package = "cyanoFilter",
                                      mustWork = TRUE)
metafile <- read.csv(metadata_path_vignette, skip = 7, stringsAsFactors = FALSE,
                     check.names = TRUE)

# columns containing dilution, $\mu l$ and id information
metafile <- metafile %>%
  dplyr::select(Sample.Number,
                Sample.ID,
                Number.of.Events,
                Dilution.Factor,
                Original.Volume,
                Cells.L)

# extract the part of the Sample.ID that corresponds to BS4 or BS5
metafile <- metafile %>%
  dplyr::mutate(Sample.ID2 = stringr::str_extract(metafile$Sample.ID, "BS*[4-5]"))

# clean up the Cells.muL column names
names(metafile)[which(stringr::str_detect(names(metafile), "Cells."))] <- "CellspML"

# Determine good measurements
metafile <- metafile %>%
  mutate(Status = cyanoFilter::goodFcs(metafile = metafile,
                                       col_cpml = "CellspML",
                                       mxd_cellpML = 1000,
                                       mnd_cellpML = 50))

# Files to Retain
broken <- metafile %>% group_by(Sample.ID2) %>% nest()
metafile$Retained <- unlist(map(broken$data, function(.x) {
  retain(meta_files = .x,
         make_decision = "maxi",
         Status = "Status",
         CellspML = "CellspML")
}))

# --- Serialize metafile to metadata.csv ---
# Use row.names = FALSE to prevent writing an extra column for row numbers.
# Default quote = TRUE is generally safer for CSVs.
write.csv(metafile, "metadata.csv", row.names = FALSE)

# --- Reproduce VIGNETTE'S OWN data-preparation code for flowfile ---

# Load raw flow data from package extdata
flowfile_path_vignette <- system.file("extdata", "B4_18_1.fcs",
                                      package = "cyanoFilter",
                                      mustWork = TRUE)
flowfile <- read.FCS(flowfile_path_vignette,
                     alter.names = TRUE,
                     transformation = FALSE,
                     emptyValue = FALSE,
                     dataset = 1)

# --- Serialize flowfile to sample.fcs ---
# write.FCS from flowCore package saves a flowFrame object to an FCS file.
write.FCS(flowfile, "sample.fcs")