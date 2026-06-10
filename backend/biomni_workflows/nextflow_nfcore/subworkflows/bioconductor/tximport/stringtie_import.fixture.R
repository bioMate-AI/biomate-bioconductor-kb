# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tximportData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(tximportData)

# Locate the tximportData extdata directory
dir <- system.file("extdata", package = "tximportData")

# Read the sample metadata to find a valid run accession
samples <- read.table(file.path(dir, "samples.txt"), header = TRUE)

# Use the first salmon quantification file as a basis for our StringTie mock
salmon_file <- file.path(dir, "salmon", samples$run[1], "quant.sf.gz")
salmon_data <- read.table(salmon_file, header = TRUE, stringsAsFactors = FALSE)

# Read the transcript-to-gene mapping
tx2gene_file <- file.path(dir, "tx2gene.gencode.v27.csv")
tx2gene <- read.csv(tx2gene_file, stringsAsFactors = FALSE)

# Construct a StringTie t_data.ctab formatted data frame
# Required columns for tximport's stringtie type: t_name, length, gene_name, cov, FPKM
t_data <- data.frame(
    t_id = seq_len(nrow(salmon_data)),
    chr = "chr1",
    strand = "+",
    start = 1,
    end = salmon_data$Length,
    t_name = salmon_data$Name,
    num_exons = 1,
    length = salmon_data$Length,
    gene_id = salmon_data$Name,
    gene_name = salmon_data$Name,
    cov = salmon_data$NumReads,
    FPKM = salmon_data$TPM,
    stringsAsFactors = FALSE
)

# Map transcript IDs to gene IDs where available
idx <- match(t_data$t_name, tx2gene[[1]])
matched <- !is.na(idx)
t_data$gene_id[matched] <- tx2gene[[2]][idx[matched]]
t_data$gene_name[matched] <- tx2gene[[2]][idx[matched]]

# Write the StringTie transcript abundance file to the working directory
write.table(t_data, "t_data.ctab", sep = "\t", quote = FALSE, row.names = FALSE)