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

process BIOC_EASIER_EASIER_IMMUNE_PREDICTION {
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
    
    # Read counts and coldata
    counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Ensure sample names match between counts and coldata
    common_samples <- intersect(colnames(counts_df), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv")
    }
    RNA_counts <- as.matrix(counts_df[, common_samples, drop = FALSE])
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Estimate pseudo-TPM from counts (assuming average gene length of 2kb)
    gene_lengths <- 2000
    rpk <- RNA_counts / (gene_lengths / 1000)
    RNA_tpm <- scale(rpk, center = FALSE, scale = colSums(rpk)) * 1e6
    RNA_tpm <- as.data.frame(RNA_tpm)
    RNA_counts <- as.data.frame(RNA_counts)
    
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
    
    # Reannotate both counts and TPM matrices
    RNA_counts <- reannotate_matrix(RNA_counts)
    RNA_tpm <- reannotate_matrix(RNA_tpm)
    
    # Align genes across both matrices
    common_genes <- intersect(rownames(RNA_counts), rownames(RNA_tpm))
    RNA_counts <- RNA_counts[common_genes, , drop = FALSE]
    RNA_tpm <- RNA_tpm[common_genes, , drop = FALSE]
    
    # Extract patient response and map to 'R' (Responder) and 'NR' (Non-Responder)
    patient_response <- coldata\$condition
    patient_response <- ifelse(grepl("^[Rr]", patient_response), "R", "NR")
    names(patient_response) <- rownames(coldata)
    
    # Extract or generate Tumor Mutational Burden (TMB) values
    if ("TMB" %in% colnames(coldata)) {
      TMB <- coldata\$TMB
    } else {
      # Fallback to dummy TMB values if not provided
      TMB <- rep(10, nrow(coldata))
    }
    names(TMB) <- rownames(coldata)
    
    # Determine cancer type model to use
    cancer_type <- "SKCM"
    if ("cancer_type" %in% colnames(coldata)) {
      cancer_type <- coldata\$cancer_type[1]
    }
    
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
