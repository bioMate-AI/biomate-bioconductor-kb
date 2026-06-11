# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dmrseq", "bsseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dmrseq)
library(bsseq)

# Locate the example Bismark coverage file from the bsseq package
infile <- system.file("extdata/test_data.fastq_bismark.bismark.cov.gz", package = 'bsseq')

if (file.exists(infile)) {
    file.copy(infile, "sample_bismark.cov.gz", overwrite = TRUE)
} else {
    # Fallback: create a synthetic Bismark coverage file if the package data is missing
    # Format: <chr> <start> <end> <methylation percentage> <count methylated> <count unmethylated>
    cov_data <- data.frame(
        chr = rep("chr21", 100),
        start = seq(9719962, by = 100, length.out = 100),
        end = seq(9719962, by = 100, length.out = 100),
        meth_perc = 50,
        meth = 15,
        unmeth = 15
    )
    gz1 <- gzfile("sample_bismark.cov.gz", "w")
    write.table(cov_data, gz1, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
    close(gz1)
}

# Create the corresponding sample metadata CSV
metadata <- data.frame(
    sampleNames = "sample_bismark",
    Condition = "treatment",
    CellType = "imr90",
    Replicate = "1"
)
write.csv(metadata, "sample_metadata.csv", row.names = FALSE)