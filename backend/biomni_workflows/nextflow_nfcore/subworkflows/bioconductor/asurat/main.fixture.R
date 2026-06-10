# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ASURAT", "SingleCellExperiment", "SummarizedExperiment", "TENxPBMCData", "AnnotationDbi", "org.Hs.eg.db", "ggplot2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ASURAT)
library(SingleCellExperiment)
library(SummarizedExperiment)
library(TENxPBMCData)
library(AnnotationDbi)
library(org.Hs.eg.db)
library(ggplot2) # Loaded by vignette, though not strictly for data generation here

# 4.1 Prepare SingleCellExperiment objects
# Load single-cell RNA sequencing (scRNA-seq) data.
sce <- TENxPBMCData::TENxPBMCData(dataset = c("pbmc4k"))
pbmc_counts <- as.matrix(assay(sce, "counts"))
rownames(pbmc_counts) <- make.unique(rowData(sce)$Symbol_TENx)
colnames(pbmc_counts) <- make.unique(colData(sce)$Barcode)

# Create SingleCellExperiment objects by inputting gene expression data.
pbmc <- SingleCellExperiment(
    assays = list(counts = pbmc_counts),
    rowData = data.frame(gene = rownames(pbmc_counts)),
    colData = data.frame(cell = colnames(pbmc_counts))
)

# 4.2 Control data quality
# Add metadata for both variables and samples using ASURAT function add_metadata().
pbmc <- add_metadata(sce = pbmc, mitochondria_symbol = "^MT-")

# 4.2.1 Remove variables based on expression profiles
pbmc <- remove_variables(sce = pbmc, min_nsamples = 10)

# 4.2.2 Remove samples based on expression profiles
pbmc <- remove_samples(sce = pbmc, min_nReads = 5000, max_nReads = 20000, min_nGenes = 100, max_nGenes = 1e+10, min_percMT = 0, max_percMT = 10)

# 4.2.3 Remove variables based on the mean read counts
pbmc <- remove_variables_second(sce = pbmc, min_meannReads = 0.05)

# 4.3 Normalize data
# Perform log-normalization with a pseudo count.
assay(pbmc, "logcounts") <- log(assay(pbmc, "counts") + 1)

# Center each row data.
mat <- assay(pbmc, "logcounts")
assay(pbmc, "centered") <- sweep(mat, 1, apply(mat, 1, mean), FUN = "-")

# Set gene expression data into altExp(sce).
sname <- "logcounts"
altExp(pbmc, sname) <- SummarizedExperiment(list(counts = assay(pbmc, sname)))

# Add ENTREZ Gene IDs to rowData(sce).
dictionary <- AnnotationDbi::select(org.Hs.eg.db::org.Hs.eg.db, key = rownames(pbmc), columns = "ENTREZID", keytype = "SYMBOL")
dictionary <- dictionary[!duplicated(dictionary$SYMBOL), ]
rowData(pbmc)$geneID <- dictionary$ENTREZID

# --- Serialize pbmc_counts to counts_matrix.csv ---
# The pbmc_counts object is the raw count matrix before being wrapped into SingleCellExperiment.
# The vignette shows pbmc_counts as the initial matrix.
write.csv(pbmc_counts, "counts_matrix.csv", row.names = TRUE)

# --- Create dummy database objects for database.rda ---
# The vignette uses url() to load these, which is forbidden by the "run fully OFFLINE" constraint.
# We create placeholder objects with the expected structure and names for ASURAT functions.

# Get available gene symbols and their ENTREZ IDs from the processed pbmc object
available_symbols <- rownames(pbmc)
available_entrez <- rowData(pbmc)$geneID
names(available_entrez) <- available_symbols
available_entrez <- available_entrez[!is.na(available_entrez)]
available_symbols_with_entrez <- names(available_entrez)

# Define some dummy terms
dummy_terms_cell <- c("T_CELL_DUMMY", "B_CELL_DUMMY", "MONOCYTE_DUMMY")
dummy_terms_go <- c("GO_IMMUNE_RESPONSE_DUMMY", "GO_CELL_DIVISION_DUMMY")
dummy_terms_kegg <- c("KEGG_PATHWAY_A_DUMMY", "KEGG_PATHWAY_B_DUMMY")

# Helper function to create a dummy gene-term mapping data frame
create_dummy_df <- function(symbols_with_entrez, terms, n_genes_per_term = 5) {
    if (length(symbols_with_entrez) == 0 || length(terms) == 0) {
        return(data.frame(SYMBOL = character(0), TERM = character(0), ENTREZID = character(0), stringsAsFactors = FALSE))
    }
    df_list <- list()
    for (term in terms) {
        num_genes_to_pick <- min(n_genes_per_term, length(symbols_with_entrez))
        if (num_genes_to_pick == 0) next
        selected_symbols <- sample(symbols_with_entrez, num_genes_to_pick, replace = FALSE)
        selected_entrez <- available_entrez[selected_symbols] # Use the globally defined available_entrez
        df_list[[term]] <- data.frame(
            SYMBOL = selected_symbols,
            TERM = term,
            ENTREZID = selected_entrez,
            stringsAsFactors = FALSE
        )
    }
    do.call(rbind, df_list)
}

# Create dummy human_CO
human_CO <- list()
human_CO[["cell"]] <- create_dummy_df(available_symbols_with_entrez, dummy_terms_cell, n_genes_per_term = 5)

# Create dummy human_MSigDB
human_MSigDB <- list()
human_MSigDB[["cell"]] <- create_dummy_df(available_symbols_with_entrez, dummy_terms_cell, n_genes_per_term = 5)

# Create dummy human_GO
human_GO <- list()
human_GO[["BP"]] <- create_dummy_df(available_symbols_with_entrez, dummy_terms_go, n_genes_per_term = 5)

# Create dummy human_KEGG
human_KEGG <- list()
human_KEGG[["pathway"]] <- create_dummy_df(available_symbols_with_entrez, dummy_terms_kegg, n_genes_per_term = 5)

# Create dummy similarity_matrix for human_GO
go_terms <- unique(human_GO[["BP"]]$TERM)
if (length(go_terms) > 0) {
    similarity_matrix_bp <- diag(length(go_terms))
    colnames(similarity_matrix_bp) <- go_terms
    rownames(similarity_matrix_bp) <- go_terms
    # Add some minimal off-diagonal values for testing if more than one term
    if (length(go_terms) > 1) {
        similarity_matrix_bp[1, 2] <- 0.5
        similarity_matrix_bp[2, 1] <- 0.5
    }
} else {
    similarity_matrix_bp <- matrix(numeric(0), nrow = 0, ncol = 0)
}
human_GO$similarity_matrix <- list(BP = similarity_matrix_bp)

# --- Serialize database objects to database.rda ---
save(human_CO, human_MSigDB, human_GO, human_KEGG, file = "database.rda")