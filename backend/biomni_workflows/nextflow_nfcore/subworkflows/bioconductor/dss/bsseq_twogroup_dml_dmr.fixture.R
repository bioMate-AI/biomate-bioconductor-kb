# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DSS", "bsseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DSS)
library(bsseq)

# Locate the example data shipped with the DSS package
path <- file.path(system.file(package="DSS"), "extdata")
files <- list.files(path, pattern="cond.*\\.txt$", full.names=TRUE)

if (length(files) > 0) {
    # Copy the vignette's exact files to the working directory
    for (f in files) {
        file.copy(f, basename(f), overwrite = TRUE)
    }
    # Also create 'sample_files.txt' to strictly satisfy the requested filename
    file.copy(files[1], "sample_files.txt", overwrite = TRUE)
} else {
    # Fallback: generate synthetic data matching the exact format if extdata is missing
    set.seed(123)
    chr <- rep("chr18", 100)
    pos <- seq(3014904, by=100, length.out=100)
    
    for (cond in c("cond1_1", "cond1_2", "cond2_1", "cond2_2")) {
        N <- rpois(100, lambda=30)
        X <- rbinom(100, size=N, prob=runif(100, 0.1, 0.9))
        df <- data.frame(chr=chr, pos=pos, N=N, X=X)
        write.table(df, file=paste0(cond, ".txt"), sep="\t", quote=FALSE, row.names=FALSE)
    }
    
    # Create the explicitly requested file
    N <- rpois(100, lambda=30)
    X <- rbinom(100, size=N, prob=runif(100, 0.1, 0.9))
    df <- data.frame(chr=chr, pos=pos, N=N, X=X)
    write.table(df, file="sample_files.txt", sep="\t", quote=FALSE, row.names=FALSE)
}