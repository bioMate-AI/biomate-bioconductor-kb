# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("coMethDMR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(coMethDMR)

# Prepare coldata.csv using the vignette's phenotype data
data(pheno_df)
write.csv(pheno_df, "coldata.csv", row.names = FALSE)

# Prepare regions.bed using the vignette's genomic regions
closeByGeneAll_ls <- readRDS(
  system.file(
    "extdata", 
    "450k_Gene_3_200.rds", 
    package = 'coMethDMR', 
    mustWork = TRUE
  )
)

indx <- grep("chr22:", names(closeByGeneAll_ls))
closeByGene_ls <- closeByGeneAll_ls[indx]

# Extract the first 10 regions as used in the vignette
regions <- names(closeByGene_ls)[1:10]
chrom <- sub(":.*", "", regions)
start <- as.integer(sub(".*:(.*)-.*", "\\1", regions))
end <- as.integer(sub(".*-", "", regions))

bed_df <- data.frame(chrom = chrom, start = start, end = end)
write.table(bed_df, "regions.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)