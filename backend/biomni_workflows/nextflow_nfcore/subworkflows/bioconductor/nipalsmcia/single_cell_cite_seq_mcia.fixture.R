# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("nipalsMCIA", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(nipalsMCIA)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the NCI60 dataset provided by the package
data(NCI60, package = "nipalsMCIA")

# 2. Serialize to EACH declared input file
# obj: processed and annotated Seurat object containing RNA and ADT assays
if (requireNamespace("Seurat", quietly = TRUE)) {
    suppressPackageStartupMessages(library(Seurat))
    
    # Extract RNA and ADT (protein) data from the NCI60 dataset
    # The vignette shows samples are rows and features are columns, so we transpose
    rna_counts <- t(data_blocks$mrna)
    adt_counts <- t(data_blocks$prot)
    
    # Create Seurat object with RNA assay
    seurat_obj <- CreateSeuratObject(counts = rna_counts, assay = "RNA")
    
    # Add ADT assay
    adt_assay <- CreateAssayObject(counts = adt_counts)
    seurat_obj[["ADT"]] <- adt_assay
    
    # Add metadata
    seurat_obj <- AddMetaData(seurat_obj, metadata = metadata_NCI60)
    
    saveRDS(seurat_obj, file = "obj.rds")
} else {
    # Fallback mock object if Seurat is not available in the environment
    seurat_obj <- list(
        RNA = t(data_blocks$mrna),
        ADT = t(data_blocks$prot),
        meta.data = metadata_NCI60
    )
    class(seurat_obj) <- "Seurat"
    saveRDS(seurat_obj, file = "obj.rds")
}

# metadata_sc: data frame containing cell-type annotations and metadata
# We save it as a CSV file, which is standard for metadata data frames
write.csv(metadata_NCI60, file = "metadata_sc.csv", row.names = TRUE)