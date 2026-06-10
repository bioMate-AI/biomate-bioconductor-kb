# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BadRegionFinder")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BadRegionFinder)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Create 'samples' object
sample_file <- system.file("extdata", "SampleNames2.txt", package = "BadRegionFinder")
samples <- read.table(sample_file, header = FALSE, stringsAsFactors = FALSE)

# Create 'targetRegions' object
target_regions <- system.file("extdata", "targetRegions2.bed", package = "BadRegionFinder")
targetRegions <- read.table(target_regions, header = FALSE, stringsAsFactors = FALSE)

# Create 'regionsOfInterest' object
regionsOfInterest <- data.frame(chr = c(2,2,17),
                                start = c(198266420,198267200,74732940),
                                end = c(198267032,198267800,74733301))

# 2. Serialize objects to declared input files in the exact format

# Write SampleNames2.txt
write.table(samples, "SampleNames2.txt", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# Write targetRegions2.bed
write.table(targetRegions, "targetRegions2.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# Write regionsOfInterest.txt (matching the header=TRUE read option)
write.table(regionsOfInterest, "regionsOfInterest.txt", sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)

# Copy BAM/BAI files from extdata to the current working directory
bam_input_dir <- system.file("extdata", package = "BadRegionFinder")
bam_files <- list.files(bam_input_dir, pattern = "\\.bam$|\\.bai$", full.names = TRUE)
file.copy(bam_files, ".")