#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TOAST — partial_reference_free_deconvolution
// Estimate cell type proportions using cell type-specific markers (partial reference-free) with or without prior knowledge of cell compositions.
// Input: CBS_mix, LM_5, CellType
// Container: quay.io/biocontainers/bioconductor-toast:1.24.0--r45hdfd78af_0
// R packages: TOAST
// Bioconductor: 3.20 | R: 4.4
// Requires: TOAST
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read User Input Files
//  * 2. [Input & Preparation] Select cell type-specific markers from pure profiles
//  * 3. [Input & Preparation] Perform partial reference-free deconvolution without prior
//  * 4. [Input & Preparation] Define prior composition parameters manually or retrieve
//  * 5. [Input & Preparation] Perform partial reference-free deconvolution with priors
//  * 6. [Input & Preparation] Save Outputs

nextflow.enable.dsl = 2

process BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("TOAST")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(TOAST)
    
    # ----------------------------------------------------------------------
    # --- Read User Input Files ---
    # ----------------------------------------------------------------------
    # The pipeline expects CBS_mix.rds, LM_5.rds, and CellType.rds in the working directory.
    if (!file.exists("CBS_mix.rds") || !file.exists("LM_5.rds") || !file.exists("CellType.rds")) {
      stop("Required input files (CBS_mix.rds, LM_5.rds, CellType.rds) are missing from the working directory.")
    }
    
    CBS_mix <- readRDS("CBS_mix.rds")
    LM_5 <- readRDS("LM_5.rds")
    CellType <- readRDS("CellType.rds")
    
    # ----------------------------------------------------------------------
    # --- Select cell type-specific markers from pure profiles ---
    # ----------------------------------------------------------------------
    myMarker <- ChooseMarker(LM_5, CellType, nMarkCT = 20, chooseSig = TRUE, verbose = FALSE)
    
    # ----------------------------------------------------------------------
    # --- Perform partial reference-free deconvolution without prior ---
    # ----------------------------------------------------------------------
    resCBS0 <- MDeconv(CBS_mix, myMarker, epsilon = 1e-3, verbose = FALSE)
    
    # ----------------------------------------------------------------------
    # --- Define prior composition parameters manually or retrieve ---
    # ----------------------------------------------------------------------
    cell_types <- names(CellType)
    num_ct <- length(cell_types)
    
    # Default to uniform priors as a fallback
    prior_alpha <- rep(1 / num_ct, num_ct)
    prior_sigma <- rep(0.1, num_ct)
    names(prior_alpha) <- cell_types
    names(prior_sigma) <- cell_types
    
    supported_tissues <- c("human pbmc", "human liver", "human brain", "human pancreas", "human skin")
    detected_tissue <- NULL
    thisprior <- NULL
    
    # Clean names for robust matching
    c_names <- tolower(gsub("[^a-z0-9]", "", cell_types))
    
    for (t in supported_tissues) {
      p <- tryCatch(GetPrior(t), error = function(e) NULL)
      if (!is.null(p)) {
        p_names <- tolower(gsub("[^a-z0-9]", "", names(p\$alpha_prior)))
        
        # Check if the number of cell types matches and all can be mapped
        if (length(c_names) == length(p_names)) {
          match_idx <- sapply(c_names, function(cn) {
            idx <- which(p_names == cn)
            if (length(idx) == 0) {
              # Fallback to substring matching (e.g., "nk" matching "nkcells")
              idx <- which(sapply(p_names, function(pn) grepl(cn, pn, fixed = TRUE) || grepl(pn, cn, fixed = TRUE)))
            }
            if (length(idx) == 1) return(idx)
            return(NA)
          })
          
          if (!any(is.na(match_idx))) {
            detected_tissue <- t
            thisprior <- p
            # Reorder the retrieved priors to match the user's CellType order
            prior_alpha <- p\$alpha_prior[match_idx]
            prior_sigma <- p\$sigma_prior[match_idx]
            names(prior_alpha) <- cell_types
            names(prior_sigma) <- cell_types
            break
          }
        }
      }
    }
    
    if (is.null(detected_tissue)) {
      thisprior <- list(alpha_prior = prior_alpha, sigma_prior = prior_sigma)
      alpha_input <- prior_alpha
    } else {
      alpha_input <- detected_tissue
    }
    
    # ----------------------------------------------------------------------
    # --- Perform partial reference-free deconvolution with priors ---
    # ----------------------------------------------------------------------
    # Deconvolution using manually input alpha and sigma
    resCBS1 <- MDeconv(CBS_mix, myMarker, alpha = prior_alpha, sigma = prior_sigma, epsilon = 1e-3, verbose = FALSE)
    
    # Deconvolution using tissue type as alpha input (or fallback uniform prior if tissue is unknown)
    resCBS2 <- MDeconv(CBS_mix, myMarker, alpha = alpha_input, epsilon = 1e-3, verbose = FALSE)
    
    # ----------------------------------------------------------------------
    # --- Save Outputs ---
    # ----------------------------------------------------------------------
    # Save selected markers
    saveRDS(myMarker, "selected_markers.rds")
    max_len <- max(sapply(myMarker, length))
    markers_df <- as.data.frame(lapply(myMarker, function(x) {
      c(x, rep(NA, max_len - length(x)))
    }))
    write.csv(markers_df, "selected_markers.csv", row.names = FALSE)
    
    # Save prior information
    saveRDS(thisprior, "retrieved_prior.rds")
    
    # Save deconvolution results (RDS objects and CSV tables of estimated proportions)
    saveRDS(resCBS0, "resCBS0_no_prior.rds")
    write.csv(as.data.frame(resCBS0\$H), "proportions_no_prior.csv", row.names = TRUE)
    
    saveRDS(resCBS1, "resCBS1_manual_prior.rds")
    write.csv(as.data.frame(resCBS1\$H), "proportions_manual_prior.csv", row.names = TRUE)
    
    saveRDS(resCBS2, "resCBS2_tissue_prior.rds")
    write.csv(as.data.frame(resCBS2\$H), "proportions_tissue_prior.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION":',
        paste0('    TOAST: ', as.character(packageVersion('TOAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_partial_reference_free_deconvolution.csv versions.yml
    """
}

workflow BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CBS_mix, LM_5, CellType ] ]

    main:
    BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION.out.tables
    plots    = BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION.out.plots
    objects  = BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION.out.objects
    versions = BIOC_TOAST_PARTIAL_REFERENCE_FREE_DECONVOLUTION.out.versions
}
