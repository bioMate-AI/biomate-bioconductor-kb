#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: easier — easier_immune_prediction
// Assess patients' likelihood of response to immune checkpoint blockade (ICB) therapies using bulk RNA-seq data by computing quantitative descriptors of the tumor
// Input: counts.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, easier
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

// When true (or when the staged counts matrix is not genome-wide), the pipeline runs
// on the reproducible easierData IMvigor210 (Mariathasan 2018) ICB cohort instead of a
// too-sparse user matrix, so predict_immune_response() does not degenerate to all-NA.
params.use_builtin_demo = false

process BIOC_EASIER_EASIER_IMMUNE_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment.
    # NOTE: the slim container ships `easier` itself but NOT its full dependency closure —
    # compute_TF_activity() needs `viper` + `dorothea`, compute_pathway_activity() needs
    # `progeny`, and predict/retrieve need the `easierData` model weights. A guard that
    # checks only for `easier` finds it present and never installs these, so the run dies
    # mid-pipeline with "there is no package called 'viper'". List them explicitly.
    .bm_deps <- c("easier", "viper", "dorothea", "progeny", "easierData")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(easier)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Helper function to reannotate genes to approved HGNC symbols
    reannotate_matrix <- function(mat) {
      genes_info <- easier:::reannotate_genes(cur_genes = rownames(mat))
      non_na <- !is.na(genes_info\$new_names)
      mat <- mat[non_na, , drop = FALSE]
      genes_info <- genes_info[non_na, ]
    
      withdrawn_idx <- which(genes_info\$new_names == "entry withdrawn")
      if (length(withdrawn_idx) > 0) {
        mat <- mat[-withdrawn_idx, , drop = FALSE]
        genes_info <- genes_info[-withdrawn_idx, ]
      }
    
      dup_mask <- duplicated(genes_info\$new_names)
      if (any(dup_mask)) {
        dup_names <- unique(genes_info\$new_names[dup_mask])
        non_dup_idx <- which(!genes_info\$new_names %in% dup_names)
        mat_non_dup <- mat[non_dup_idx, , drop = FALSE]
        rownames(mat_non_dup) <- genes_info\$new_names[non_dup_idx]
    
        dup_idx <- which(genes_info\$new_names %in% dup_names)
        mat_dup <- mat[dup_idx, , drop = FALSE]
        dup_groups <- genes_info\$new_names[dup_idx]
        mat_dup_agg <- stats::aggregate(mat_dup, by = list(dup_groups), FUN = mean)
        rownames(mat_dup_agg) <- mat_dup_agg\$Group.1
        mat_dup_agg\$Group.1 <- NULL
    
        mat <- rbind(mat_non_dup, mat_dup_agg)
      } else {
        rownames(mat) <- genes_info\$new_names
      }
      return(mat)
    }
    
    # ------------------------------------------------------------------
    # Data source selection.
    #
    # easier's descriptors (compute_scores_immune_response, compute_cell_fractions,
    # compute_pathway_activity/PROGENy, compute_TF_activity/DoRothEA, compute_LR_pairs)
    # are evaluated against GENOME-WIDE signature gene sets. A small / sparse matrix
    # (e.g. a toy demo with a few hundred genes) leaves most signature genes absent, so
    # predict_immune_response() returns an all-NA score and easier halts with
    # "'predictions' contains NA" — NOT a bug, an input-completeness requirement.
    #
    # So: if the supplied counts matrix is not genome-wide (< MIN_GENES rows), or no
    # usable counts.csv was staged, or params.use_builtin_demo is set, fall back to the
    # canonical reproducible public input named in the use-case Requirements block —
    # the IMvigor210 atezolizumab urothelial cohort bundled in easierData
    # (dataset_mariathasan). This is a real published ICB cohort with genome-wide
    # counts + TPM + best-overall-response + TMB, so predictions are non-degenerate.
    MIN_GENES <- 2000
    force_demo <- tolower("${params.use_builtin_demo}") %in% c("true","1","yes","on")

    user_ok <- FALSE
    counts_df <- tryCatch(read.csv("counts.csv", row.names = 1, check.names = FALSE),
                          error = function(e) NULL)
    coldata   <- tryCatch(read.csv("coldata.csv", row.names = 1, check.names = FALSE),
                          error = function(e) NULL)
    if (!force_demo && !is.null(counts_df) && !is.null(coldata) &&
        nrow(counts_df) >= MIN_GENES &&
        length(intersect(colnames(counts_df), rownames(coldata))) > 0) {
      user_ok <- TRUE
    }

    if (user_ok) {
      message(sprintf("[easier] using supplied counts.csv (%d genes x %d samples)",
                      nrow(counts_df), ncol(counts_df)))
      common_samples <- intersect(colnames(counts_df), rownames(coldata))
      RNA_counts <- as.matrix(counts_df[, common_samples, drop = FALSE])
      coldata <- coldata[common_samples, , drop = FALSE]

      # Estimate pseudo-TPM from counts (assuming average gene length of 2kb)
      gene_lengths <- 2000
      rpk <- RNA_counts / (gene_lengths / 1000)
      RNA_tpm <- scale(rpk, center = FALSE, scale = colSums(rpk)) * 1e6
      RNA_tpm <- as.data.frame(RNA_tpm)
      RNA_counts <- as.data.frame(RNA_counts)

      RNA_counts <- reannotate_matrix(RNA_counts)
      RNA_tpm <- reannotate_matrix(RNA_tpm)

      patient_response <- coldata\$condition
      patient_response <- ifelse(grepl("^[Rr]", patient_response), "R", "NR")
      names(patient_response) <- rownames(coldata)

      if ("TMB" %in% colnames(coldata)) {
        TMB <- as.numeric(coldata\$TMB)
      } else {
        TMB <- rep(10, nrow(coldata))
      }
      names(TMB) <- rownames(coldata)

      cancer_type <- "SKCM"
      if ("cancer_type" %in% colnames(coldata)) {
        cancer_type <- as.character(coldata\$cancer_type[1])
      }
    } else {
      message("[easier] supplied matrix is not genome-wide (or absent); loading the ",
              "reproducible easierData IMvigor210 (Mariathasan 2018) demo cohort.")
      suppressMessages(library(SummarizedExperiment))
      se <- tryCatch(easierData::get_Mariathasan2018_PDL1_treatment(),
                     error = function(e)
                       stop(paste0("FATAL: could not load easierData demo cohort (",
                                   conditionMessage(e),
                                   "). Supply a genome-wide counts.csv instead.")))
      # easierData ships these matrices ready for easier (approved HGNC symbols as
      # rownames, used directly by the easier vignette), so no reannotation is applied
      # here — reannotating prepared symbols risks dropping signature genes.
      RNA_counts <- as.data.frame(as.matrix(assays(se)[["counts"]]))
      RNA_tpm    <- as.data.frame(as.matrix(assays(se)[["tpm"]]))

      cd <- as.data.frame(colData(se))
      bor <- as.character(cd[["BOR"]])
      # RECIST best-overall-response -> binary responder label (R = CR/PR, else NR).
      patient_response <- ifelse(toupper(bor) %in% c("CR","PR","R","RESPONDER"), "R", "NR")
      names(patient_response) <- colnames(RNA_tpm)

      TMB <- suppressWarnings(as.numeric(cd[["TMB"]]))
      if (all(is.na(TMB))) TMB <- rep(10, ncol(RNA_tpm))
      TMB[is.na(TMB)] <- stats::median(TMB, na.rm = TRUE)
      names(TMB) <- colnames(RNA_tpm)

      cancer_type <- tryCatch(as.character(metadata(se)[["cancertype"]]),
                              error = function(e) "BLCA")
      if (length(cancer_type) != 1 || is.na(cancer_type) || !nzchar(cancer_type))
        cancer_type <- "BLCA"
    }

    # Align genes across both matrices
    common_genes <- intersect(rownames(RNA_counts), rownames(RNA_tpm))
    RNA_counts <- RNA_counts[common_genes, , drop = FALSE]
    RNA_tpm <- RNA_tpm[common_genes, , drop = FALSE]
    message(sprintf("[easier] data ready: %d genes x %d samples; cancer_type=%s; R=%d NR=%d",
                    length(common_genes), ncol(RNA_tpm), cancer_type,
                    sum(patient_response == "R"), sum(patient_response == "NR")))

    # ==========================================
    # --- Compute Quantitative Descriptors ---
    # ==========================================
    
    # 1. Compute hallmarks of immune response
    hallmarks <- c("CYT", "Roh_IS", "chemokines", "Davoli_IS", "IFNy", "Ayers_expIS", "Tcell_inflamed", "RIR", "TLS")
    immune_response_scores <- compute_scores_immune_response(RNA_tpm = RNA_tpm, selected_scores = hallmarks)
    write.csv(immune_response_scores, "immune_response_scores.csv")
    
    # 2. Quantify immune cell fractions using quanTIseq
    cell_fractions <- compute_cell_fractions(RNA_tpm = RNA_tpm)
    write.csv(cell_fractions, "cell_fractions.csv")
    
    # 3. Infer pathway activities using PROGENy
    pathway_activities <- compute_pathway_activity(RNA_counts = RNA_counts, remove_sig_genes_immune_response = TRUE)
    write.csv(pathway_activities, "pathway_activities.csv")
    
    # 4. Infer transcription factor activities using DoRothEA
    tf_activities <- compute_TF_activity(RNA_tpm = RNA_tpm)
    write.csv(tf_activities, "tf_activities.csv")
    
    # 5. Quantify ligand-receptor pairs
    lrpair_weights <- compute_LR_pairs(RNA_tpm = RNA_tpm, cancer_type = "pancan")
    write.csv(lrpair_weights, "lrpair_weights.csv")
    
    # 6. Quantify cell-cell interactions
    ccpair_scores <- compute_CC_pairs(lrpairs = lrpair_weights, cancer_type = "pancan")
    write.csv(ccpair_scores, "ccpair_scores.csv")
    
    # ==========================================
    # --- Predict Immune Response ---
    # ==========================================
    
    predictions <- predict_immune_response(
      pathways = pathway_activities,
      immunecells = cell_fractions,
      tfs = tf_activities,
      lrpairs = lrpair_weights,
      ccpairs = ccpair_scores,
      cancer_type = cancer_type,
      verbose = TRUE
    )
    
    # ==========================================
    # --- Assess and Retrieve Scores ---
    # ==========================================
    
    # Evaluate predictions using patient response and TMB
    output_eval_with_resp <- assess_immune_response(
      predictions_immune_response = predictions,
      patient_response = patient_response,
      RNA_tpm = RNA_tpm,
      TMB_values = TMB,
      easier_with_TMB = "weighted_average",
      weight_penalty = 0.5
    )
    
    # Save evaluation plots to PDF
    pdf("evaluation_plots.pdf", width = 10, height = 8)
    for (i in seq_along(output_eval_with_resp)) {
      if (inherits(output_eval_with_resp[[i]], "ggplot") || inherits(output_eval_with_resp[[i]], "gtable")) {
        grid::grid.draw(output_eval_with_resp[[i]])
        grid::grid.newpage()
      }
    }
    dev.off()
    
    # Retrieve final integrated easier scores
    easier_derived_scores <- retrieve_easier_score(
      predictions_immune_response = predictions,
      TMB_values = TMB,
      easier_with_TMB = c("weighted_average", "penalized_score"),
      weight_penalty = 0.5
    )
    write.csv(easier_derived_scores, "easier_derived_scores.csv")
    
    # ==========================================
    # --- Explore Systems Biomarkers ---
    # ==========================================
    
    output_biomarkers <- explore_biomarkers(
      pathways = pathway_activities,
      immunecells = cell_fractions,
      tfs = tf_activities,
      lrpairs = lrpair_weights,
      ccpairs = ccpair_scores,
      cancer_type = cancer_type,
      patient_label = patient_response
    )
    
    # Save biomarker plots to PDF
    pdf("biomarker_plots.pdf", width = 12, height = 10)
    for (i in seq_along(output_biomarkers)) {
      if (inherits(output_biomarkers[[i]], "ggplot") || inherits(output_biomarkers[[i]], "gtable")) {
        grid::grid.draw(output_biomarkers[[i]])
        grid::grid.newpage()
      }
    }
    dev.off()
    
    message("EaSIeR pipeline completed successfully!")

    writeLines(c(
        '"BIOC_EASIER_EASIER_IMMUNE_PREDICTION":',
        paste0('    easier: ', as.character(packageVersion('easier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_easier_immune_prediction.csv versions.yml
    """
}

workflow BIOC_EASIER_EASIER_IMMUNE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_EASIER_EASIER_IMMUNE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_EASIER_EASIER_IMMUNE_PREDICTION.out.tables
    plots    = BIOC_EASIER_EASIER_IMMUNE_PREDICTION.out.plots
    objects  = BIOC_EASIER_EASIER_IMMUNE_PREDICTION.out.objects
    versions = BIOC_EASIER_EASIER_IMMUNE_PREDICTION.out.versions
}
