library(ISAnalytics)
library(tibble)

# Attempt to load the standard datasets shipped with ISAnalytics
env <- new.env()
has_data <- FALSE

try({
    data("association_file", package = "ISAnalytics", envir = env)
    data("integration_matrices", package = "ISAnalytics", envir = env)
    if (exists("association_file", envir = env) && exists("integration_matrices", envir = env)) {
        has_data <- TRUE
    }
}, silent = TRUE)

if (has_data) {
    association_file <- env$association_file
    integration_matrices <- env$integration_matrices
} else {
    # Fallback: Construct minimal standard IS data if datasets are unavailable
    association_file <- tibble::tribble(
        ~ProjectID, ~SubjectID, ~Tissue, ~TimePoint, ~CellMarker, ~PCRReplicate, ~FusionID, ~PoolID, ~TagID, ~VectorID, ~CompleteAmplificationID,
        "Proj1", "Subj1", "PB", 30, "CD34", "Rep1", "Fus1", "Pool1", "Tag1", "Vec1", "Proj1_Subj1_PB_30_CD34_Rep1",
        "Proj1", "Subj1", "BM", 30, "CD34", "Rep1", "Fus2", "Pool1", "Tag2", "Vec1", "Proj1_Subj1_BM_30_CD34_Rep1"
    )
    
    integration_matrices <- list(
        seqCount = tibble::tribble(
            ~chr, ~integration_locus, ~strand, ~GeneName, ~GeneStrand, ~Proj1_Subj1_PB_30_CD34_Rep1, ~Proj1_Subj1_BM_30_CD34_Rep1,
            "chr1", 123456, "+", "GENE1", "+", 10, 5,
            "chr2", 654321, "-", "GENE2", "-", 0, 15
        )
    )
}

# Serialize to the exact filenames expected by the workflow
saveRDS(integration_matrices, "integration_matrices.rds")
saveRDS(association_file, "association_file.rds")