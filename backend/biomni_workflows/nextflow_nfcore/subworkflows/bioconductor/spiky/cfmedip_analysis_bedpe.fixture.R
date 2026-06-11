library(spiky)

# Locate the example BEDPE files provided by the package
pkg_genomic <- system.file("extdata", "example_chr21_bedpe.bed.gz", package="spiky", mustWork=TRUE)
pkg_spike <- system.file("extdata", "example_spike_bedpe.bed.gz", package="spiky", mustWork=TRUE)

# Copy the main files to the expected input file names
file.copy(pkg_genomic, "genomic_bedpe_path", overwrite = TRUE)
file.copy(pkg_spike, "spike_bedpe_path", overwrite = TRUE)

# Also copy the tabix index files if they exist, matching the new file names
pkg_genomic_tbi <- paste0(pkg_genomic, ".tbi")
if (file.exists(pkg_genomic_tbi)) {
    file.copy(pkg_genomic_tbi, "genomic_bedpe_path.tbi", overwrite = TRUE)
}

pkg_spike_tbi <- paste0(pkg_spike, ".tbi")
if (file.exists(pkg_spike_tbi)) {
    file.copy(pkg_spike_tbi, "spike_bedpe_path.tbi", overwrite = TRUE)
}