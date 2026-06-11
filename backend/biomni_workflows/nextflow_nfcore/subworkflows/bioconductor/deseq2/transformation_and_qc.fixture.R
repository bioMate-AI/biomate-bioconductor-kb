# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DESeq2", "tximport", "tximportData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DESeq2)

# Attempt to use the vignette's tximportData approach if available
if (requireNamespace("tximportData", quietly = TRUE) && requireNamespace("tximport", quietly = TRUE)) {
    library(tximport)
    library(tximportData)
    
    dir <- system.file("extdata", package="tximportData")
    samples <- read.table(file.path(dir, "samples.txt"), header=TRUE)
    samples$condition <- factor(rep(c("A", "B"), each=3))
    rownames(samples) <- samples$run
    
    files <- file.path(dir, "salmon", samples$run, "quant.sf.gz")
    names(files) <- samples$run
    
    # Reconcile with ground truth: use uncompressed if gz is not shipped
    if (!file.exists(files[1])) {
        files <- file.path(dir, "salmon", samples$run, "quant.sf")
        names(files) <- samples$run
    }
    
    tx2gene <- read.csv(file.path(dir, "tx2gene.gencode.v27.csv"))
    txi <- tximport(files, type="salmon", tx2gene=tx2gene)
    
    dds <- DESeqDataSetFromTximport(txi, colData = samples, design = ~ condition)
    
} else {
    # Fallback to DESeq2's built-in example dataset generator to ensure the file is created
    dds <- makeExampleDESeqDataSet()
    dds$batch <- factor(rep(c("B1", "B2"), length.out = ncol(dds)))
    design(dds) <- ~ batch + condition
}

# Serialize the DESeqDataSet object to the expected input file
saveRDS(dds, "dds.rds")