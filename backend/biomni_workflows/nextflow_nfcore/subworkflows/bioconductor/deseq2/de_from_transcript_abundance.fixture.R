# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DESeq2", "tximport", "readr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DESeq2)
library(tximport)
library(readr)

# The vignette uses tximportData for its example files
if (requireNamespace("tximportData", quietly = TRUE)) {
    extdata_dir <- system.file("extdata", package = "tximportData")
    
    # 1. samples.txt
    samples_path <- list.files(extdata_dir, pattern = "samples.txt$", recursive = TRUE, full.names = TRUE)[1]
    if (!is.na(samples_path) && file.exists(samples_path)) {
        file.copy(samples_path, "samples.txt", overwrite = TRUE)
    } else {
        samples_df <- data.frame(sample = c("sample1", "sample2"), condition = c("A", "B"))
        write.table(samples_df, "samples.txt", sep = "\t", quote = FALSE, row.names = FALSE)
    }
    
    # 2. quant.sf.gz
    quant_path <- list.files(extdata_dir, pattern = "quant.sf.gz$", recursive = TRUE, full.names = TRUE)[1]
    if (!is.na(quant_path) && file.exists(quant_path)) {
        file.copy(quant_path, "quant.sf.gz", overwrite = TRUE)
    } else {
        # Fallback to uncompressed quant.sf if .gz is not found
        quant_path_nogz <- list.files(extdata_dir, pattern = "quant.sf$", recursive = TRUE, full.names = TRUE)[1]
        if (!is.na(quant_path_nogz) && file.exists(quant_path_nogz)) {
            txt <- readLines(quant_path_nogz)
            gz <- gzfile("quant.sf.gz", "w")
            writeLines(txt, gz)
            close(gz)
        } else {
            quant_df <- data.frame(
                Name = c("ENST00000456328.2", "ENST00000450305.2"),
                Length = c(1657, 1700),
                EffectiveLength = c(1400, 1500),
                TPM = c(10.5, 0),
                NumReads = c(120, 0)
            )
            gz <- gzfile("quant.sf.gz", "w")
            write.table(quant_df, gz, sep = "\t", quote = FALSE, row.names = FALSE)
            close(gz)
        }
    }
    
    # 3. tx2gene.gencode.v27.csv
    tx2gene_path <- list.files(extdata_dir, pattern = "tx2gene.gencode.v27.csv$", recursive = TRUE, full.names = TRUE)[1]
    if (!is.na(tx2gene_path) && file.exists(tx2gene_path)) {
        file.copy(tx2gene_path, "tx2gene.gencode.v27.csv", overwrite = TRUE)
    } else {
        # Fallback to any tx2gene csv if the specific v27 is not found
        tx2gene_alt <- list.files(extdata_dir, pattern = "tx2gene.*\\.csv$", recursive = TRUE, full.names = TRUE)[1]
        if (!is.na(tx2gene_alt) && file.exists(tx2gene_alt)) {
            file.copy(tx2gene_alt, "tx2gene.gencode.v27.csv", overwrite = TRUE)
        } else {
            tx2gene_df <- data.frame(
                TXNAME = c("ENST00000456328.2", "ENST00000450305.2"),
                GENEID = c("ENSG00000223972.5", "ENSG00000223972.5")
            )
            write.csv(tx2gene_df, "tx2gene.gencode.v27.csv", quote = FALSE, row.names = FALSE)
        }
    }
} else {
    # Fallback if tximportData is not installed
    samples_df <- data.frame(sample = c("sample1", "sample2"), condition = c("A", "B"))
    write.table(samples_df, "samples.txt", sep = "\t", quote = FALSE, row.names = FALSE)
    
    quant_df <- data.frame(
        Name = c("ENST00000456328.2", "ENST00000450305.2"),
        Length = c(1657, 1700),
        EffectiveLength = c(1400, 1500),
        TPM = c(10.5, 0),
        NumReads = c(120, 0)
    )
    gz <- gzfile("quant.sf.gz", "w")
    write.table(quant_df, gz, sep = "\t", quote = FALSE, row.names = FALSE)
    close(gz)
    
    tx2gene_df <- data.frame(
        TXNAME = c("ENST00000456328.2", "ENST00000450305.2"),
        GENEID = c("ENSG00000223972.5", "ENSG00000223972.5")
    )
    write.csv(tx2gene_df, "tx2gene.gencode.v27.csv", quote = FALSE, row.names = FALSE)
}