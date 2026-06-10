# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RITANdata", "RITAN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RITANdata)
library(RITAN)

# We define a query using gene symbols as shown in the vignette
my_genes <- c('ABCA2', 'ACAT2', 'ACSS2', 'CD9', 'CPEB2', 'CTNNB1', 'FASN', 'LDLR', 'LPL', 'LSS')

# Write the gene symbols to my_genes.txt
writeLines(my_genes, "my_genes.txt")

# Create a synthetic GMT file for curated_gene_disease_associations.gmt.gz
# Format: GeneSetName \t Description \t Gene1 \t Gene2 \t ...
gmt_lines <- c(
  "Disease_A\tCustom_Disease_A\tABCA2\tACAT2\tACSS2",
  "Disease_B\tCustom_Disease_B\tCD9\tCPEB2\tCTNNB1"
)

gz1 <- gzfile("curated_gene_disease_associations.gmt.gz", "w")
writeLines(gmt_lines, gz1)
close(gz1)