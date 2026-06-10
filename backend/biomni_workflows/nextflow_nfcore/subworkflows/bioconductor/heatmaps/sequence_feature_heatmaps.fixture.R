# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("heatmaps", "rtracklayer", "GenomicRanges", "BSgenome.Drerio.UCSC.danRer7")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(heatmaps)
library(rtracklayer)
library(GenomicRanges)
library(BSgenome.Drerio.UCSC.danRer7)

# 1. genomic_intervals.bed
# Extract the BED file used in the vignette
bed_file <- system.file("extdata", "30pEpi_proms.bed", package="heatmaps")
if (file.exists(bed_file)) {
    file.copy(bed_file, "genomic_intervals.bed", overwrite = TRUE)
} else {
    # Fallback synthetic BED file if the package data is missing
    gr <- GRanges(seqnames = "chr1", ranges = IRanges(start = 10000, end = 11000))
    export(gr, "genomic_intervals.bed", format = "BED")
}

# 2. reference_genome
# The workflow expects a BSgenome object for sequence extraction
saveRDS(Drerio, "reference_genome")

# 3. pwm_matrix
# Extract the PWM matrix from the package's example data
example_data <- new.env()
data("HeatmapExamples", package = "heatmaps", envir = example_data)

if (exists("tata_pwm", envir = example_data)) {
    tata_pwm <- get("tata_pwm", envir = example_data)
} else {
    # Fallback synthetic PWM if not found
    tata_pwm <- matrix(c(0.1, 0.8, 0.1, 0.0,
                         0.8, 0.1, 0.0, 0.1,
                         0.1, 0.1, 0.7, 0.1,
                         0.0, 0.1, 0.1, 0.8), 
                       nrow = 4, dimnames = list(c("A", "C", "G", "T"), NULL))
}
saveRDS(tata_pwm, "pwm_matrix")