# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("goseq", "edgeR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(goseq)
library(edgeR)

# Read the summary table shipped with goseq
table.summary <- read.table(system.file("extdata", "Li_sum.txt", package = "goseq"),
  sep = "\t", header = TRUE, stringsAsFactors = FALSE
)

# Extract counts matrix
counts <- table.summary[, -1]
rownames(counts) <- table.summary[, 1]
counts <- as.matrix(counts)

# Perform differential expression analysis to get DE genes
grp <- factor(rep(c("Control", "Treated"), times = c(4, 3)))
summarized <- DGEList(counts, lib.size = colSums(counts), group = grp)

disp <- estimateCommonDisp(summarized)
tested <- exactTest(disp)

# Create named binary vector of assayed genes and DE status
genes <- as.integer(p.adjust(tested$table$PValue[tested$table$logFC != 0],
  method = "BH"
) < .05)
names(genes) <- row.names(tested$table[tested$table$logFC != 0, ])

# Serialize objects to the expected input files
saveRDS(genes, "genes.rds")
saveRDS(counts, "counts.rds")