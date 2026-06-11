# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CoSIA", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CoSIA)
library(dplyr)

# Attempt to load the dataset from the package's extdata
rda_file <- list.files(system.file("extdata", package="CoSIA"), 
                       pattern="monogenic_kidney_genes.rda", 
                       recursive=TRUE, full.names=TRUE)

if (length(rda_file) > 0) {
    load(rda_file[1])
    set.seed(42)
    monogenic_kid_sample <- dplyr::sample_n(monogenic_kidney_genes, 20)
    gene_set <- unique(monogenic_kid_sample$Gene)
} else {
    # Fallback to the exact genes used in the vignette if the file is not shipped
    gene_set <- c("SDCCAG8", "TACO1", "FANCA", "BMP7", "AP2S1", "SCARB2", 
                  "AQP2", "XDH", "PCBD1", "AMN", "PPP3CA", "LMX1B", "NPHS1", 
                  "EBP", "SLX4", "CYP11B2", "TTR", "BICC1", "OFD1", "UCP3")
}

# Define the tissues as used in the vignette
map_tissues <- c("adult mammalian kidney", "heart")

# Serialize the objects to the expected input files
saveRDS(gene_set, "gene_set.txt")
saveRDS(map_tissues, "map_tissues.txt")