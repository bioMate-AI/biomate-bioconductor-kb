library(NanoStringNCTools)

# Locate the example data directory shipped with NanoStringNCTools
datadir <- system.file("extdata", "3D_Bio_Example_Data", package = "NanoStringNCTools")

# Identify the source files
rcc_files_src <- dir(datadir, pattern = "SKMEL.*\\.RCC$", full.names = TRUE)
rlf_file_src <- file.path(datadir, "3D_SolidTumor_Sig.rlf")
sample_annotation_src <- file.path(datadir, "3D_SolidTumor_PhenoData.csv")

# Copy the original files to the current working directory
file.copy(rcc_files_src, ".", overwrite = TRUE)
file.copy(rlf_file_src, basename(rlf_file_src), overwrite = TRUE)
file.copy(sample_annotation_src, basename(sample_annotation_src), overwrite = TRUE)

# Create the exact literal filenames expected by the test harness
# (In case the workflow variables are mapped directly to these literal input names)
file.copy(rcc_files_src[1], "rcc_files", overwrite = TRUE)
file.copy(rlf_file_src, "rlf_file", overwrite = TRUE)
file.copy(sample_annotation_src, "sample_annotation", overwrite = TRUE)