# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CelliD", "Seurat", "scuttle", "tidyverse")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CelliD)
library(Seurat)
library(scuttle) # For mockSCE
library(tidyverse) # As loaded in vignette, though not strictly needed for this data prep

# --- Data Preparation mimicking the vignette's structure ---

# CRITICAL: The vignette uses readRDS(url(...)) for BaronMatrix and BaronMetaData.
# Per instructions: "MUST run fully OFFLINE: NEVER use download.file(), url(), ...
# Use ONLY data shipped in installed packages (system.file/data()/companion ExperimentData)."
# Therefore, we cannot use the exact BaronMatrix/BaronMetaData from the vignette.
# We will generate a mock SingleCellExperiment object and process it similarly.

set.seed(123) # For reproducibility of mockSCE
sce <- mockSCE(ncells = 100, ngenes = 500, nbatches = 1)

# Add mock metadata to mimic BaronMetaData structure
colData(sce)$cell.type <- sample(c("Alpha", "Beta", "Delta", "Gamma", "Acinar"),
                                 ncol(sce), replace = TRUE)
colData(sce)$donor <- sample(c("Donor1", "Donor2"), ncol(sce), replace = TRUE)

# Load protein-coding genes as per vignette (Section 4.1)
data("HgProteinCodingGenes", package = "CelliD")

# To make the filtering step meaningful, ensure some mockSCE genes are "protein-coding".
# Rename a subset of mockSCE genes to actual human protein-coding gene symbols.
num_pc_genes_in_mock <- 200 # Number of mock genes to make "protein-coding"
if (num_pc_genes_in_mock > nrow(sce)) num_pc_genes_in_mock <- nrow(sce)

# Get a random subset of actual protein-coding genes from HgProteinCodingGenes
actual_pc_genes_subset <- sample(HgProteinCodingGenes, num_pc_genes_in_mock)

# Assign these to the first 'num_pc_genes_in_mock' genes in mockSCE
rownames(sce)[1:num_pc_genes_in_mock] <- actual_pc_genes_subset

# Apply the filtering step as in the vignette (Section 4.1)
# BaronMatrixProt <- BaronMatrix[rownames(BaronMatrix) %in% HgProteinCodingGenes,]
mockMatrixProt <- counts(sce)[rownames(counts(sce)) %in% HgProteinCodingGenes, ]
mockMetaData <- as.data.frame(colData(sce))

# Create Seurat object and process (Section 4.3)
# Baron <- CreateSeuratObject(counts = BaronMatrixProt, project = "Baron", min.cells = 5, meta.data = BaronMetaData)
mockSeurat <- CreateSeuratObject(counts = mockMatrixProt,
                                 project = "MockBaron",
                                 min.cells = 5, # Genes