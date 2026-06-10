#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ssPATHS — single_sample_pathway_scoring
// Learn gene weightings for a specific pathway from a reference cohort and apply them to score new samples.
// Input: reference_expression.csv, reference_metadata.csv, new_expression.csv, new_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sspaths:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, ssPATHS
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Format reference expression and metadata into a SummarizedExperiment object
//  * 2. [Input & Preparation] Retrieve or define pathway gene IDs
//  * 3. [Input & Preparation] Define the binary classification target variable Y in the reference metadata
//  * 4. [Core Analysis] Learn gene weights and sample scores using get_gene_weights
//  * 5. [Core Analysis] Evaluate classification accuracy using get_classification_accuracy
//  * 6. [Visualization & Output] Format new sample expression and metadata into a SummarizedExperiment object
//  * 7. [Core Analysis] Apply learned gene weights to score new samples using get_new_samp_score

nextflow.enable.dsl = 2

process BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING {
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
    library("ROCR")
    library("ggplot2")
    library("ssPATHS")
    library("SummarizedExperiment")
    
    # ==========================================
    # 1. Read and Format Reference Data
    # ==========================================
    
    # Read reference metadata
    ref_meta <- read.csv("reference_metadata.csv", check.names = FALSE)
    if ("sample_id" %in% colnames(ref_meta)) {
        rownames(ref_meta) <- ref_meta\$sample_id
    } else {
        rownames(ref_meta) <- ref_meta[, 1]
        ref_meta\$sample_id <- ref_meta[, 1]
    }
    
    # Read reference expression matrix
    ref_expr <- read.csv("reference_expression.csv", row.names = 1, check.names = FALSE)
    
    # Align orientation of expression matrix (ensure genes are rows, samples are columns)
    sample_ids <- ref_meta\$sample_id
    if (any(sample_ids %in% rownames(ref_expr)) && !any(sample_ids %in% colnames(ref_expr))) {
        ref_expr <- as.data.frame(t(ref_expr))
    }
    
    # Subset to common samples
    common_ref <- intersect(colnames(ref_expr), ref_meta\$sample_id)
    ref_expr <- ref_expr[, common_ref, drop = FALSE]
    ref_meta <- ref_meta[common_ref, , drop = FALSE]
    
    # Construct SummarizedExperiment object for reference cohort
    tcga_se <- SummarizedExperiment(assays = list(counts = as.matrix(ref_expr)),
                                    colData = ref_meta)
    colnames(tcga_se) <- ref_meta\$sample_id
    colData(tcga_se)\$sample_id <- ref_meta\$sample_id
    
    # Ensure 'is_normal' column exists in colData (fallback to first binary column if missing)
    if (!"is_normal" %in% colnames(colData(tcga_se))) {
        binary_cols <- sapply(colData(tcga_se), function(x) length(unique(x)) == 2)
        if (any(binary_cols)) {
            colData(tcga_se)\$is_normal <- colData(tcga_se)[[which(binary_cols)[1]]]
        } else {
            other_cols <- setdiff(colnames(colData(tcga_se)), "sample_id")
            if (length(other_cols) > 0) {
                colData(tcga_se)\$is_normal <- colData(tcga_se)[[other_cols[1]]]
            } else {
                stop("No binary classification column found in reference_metadata.csv")
            }
        }
    }
    
    # ==========================================
    # 2. Retrieve Pathway Gene IDs
    # ==========================================
    
    hypoxia_gene_ids <- get_hypoxia_genes()
    hypoxia_gene_ids <- intersect(hypoxia_gene_ids, rownames(tcga_se))
    
    # ==========================================
    # 3. Define Binary Classification Target
    # ==========================================
    
    is_norm <- colData(tcga_se)\$is_normal
    if (!is.logical(is_norm)) {
        if (is.character(is_norm) || is.factor(is_norm)) {
            is_norm_char <- tolower(as.character(is_norm))
            norm_terms <- c("normal", "control", "false", "0", "healthy", "wt", "wildtype")
            if (any(is_norm_char %in% norm_terms)) {
                is_norm <- is_norm_char %in% norm_terms
            } else {
                is_norm <- is_norm_char == is_norm_char[1]
            }
        } else {
            is_norm <- as.logical(is_norm)
        }
    }
    colData(tcga_se)\$Y <- ifelse(is_norm, 0, 1)
    
    # ==========================================
    # 4. Learn Gene Weights and Sample Scores
    # ==========================================
    
    res <- get_gene_weights(tcga_se, hypoxia_gene_ids, unidirectional=TRUE)
    gene_weights <- res[[1]]
    sample_scores <- res[[2]]
    
    # Save learned weights and reference scores
    write.csv(as.data.frame(gene_weights), "gene_weights.csv", row.names = TRUE)
    write.csv(as.data.frame(sample_scores), "reference_sample_scores.csv", row.names = FALSE)
    
    # ==========================================
    # 5. Evaluate Classification Accuracy
    # ==========================================
    
    training_res <- get_classification_accuracy(sample_scores, positive_val=1)
    
    # Plot and save ROC curve
    pdf("roc_curve.pdf")
    plot(training_res[[4]], col="blue", ylim=c(0, 1))
    roc_text <- paste("AUC:", round(training_res\$auc_roc,3))
    legend(0.1,0.8, roc_text,
           border="white",cex=1,box.col = "white")
    dev.off()
    
    # Plot and save PR curve
    pdf("pr_curve.pdf")
    plot(training_res[[3]], col="orange", ylim=c(0, 1))
    pr_text <- paste("AUC:", round(training_res\$auc_pr,3))
    legend(0.1,0.8, pr_text,
           border="white",cex=1,box.col = "white")
    dev.off()
    
    # ==========================================
    # 6. Format New Sample Data
    # ==========================================
    
    # Read new metadata
    new_meta <- read.csv("new_metadata.csv", check.names = FALSE)
    if ("sample_id" %in% colnames(new_meta)) {
        rownames(new_meta) <- new_meta\$sample_id
    } else {
        rownames(new_meta) <- new_meta[, 1]
        new_meta\$sample_id <- new_meta[, 1]
    }
    
    # Read new expression matrix
    new_expr <- read.csv("new_expression.csv", row.names = 1, check.names = FALSE)
    
    # Align orientation of new expression matrix
    new_sample_ids <- new_meta\$sample_id
    if (any(new_sample_ids %in% rownames(new_expr)) && !any(new_sample_ids %in% colnames(new_expr))) {
        new_expr <- as.data.frame(t(new_expr))
    }
    
    # Subset to common samples
    common_new <- intersect(colnames(new_expr), new_meta\$sample_id)
    new_expr <- new_expr[, common_new, drop = FALSE]
    new_meta <- new_meta[common_new, , drop = FALSE]
    
    # Construct SummarizedExperiment object for new samples
    new_samp_se <- SummarizedExperiment(assays = list(counts = as.matrix(new_expr)),
                                        colData = new_meta[, "sample_id", drop = FALSE])
    colnames(colData(new_samp_se)) <- "sample_id"
    
    # ==========================================
    # 7. Apply Learned Weights to New Samples
    # ==========================================
    
    new_score_df <- get_new_samp_score(gene_weights, new_samp_se)
    
    # Save new sample scores
    write.csv(as.data.frame(new_score_df), "new_sample_scores.csv", row.names = FALSE)
    
    # Plot and save boxplot of new scores
    plot_scores <- function(hif_scores){
        # format the sample IDS robustly
        hif_scores\$sample_type <- sapply(hif_scores\$sample_id, function(id) {
            if (nchar(id) > 2) {
                return(substr(id, 1, nchar(id) - 2))
            } else {
                return(id)
            }
        })
        colnames(hif_scores)[2] <- "pathway_score"
    
        gg <- ggplot(hif_scores, aes(x=sample_type, y=pathway_score,
                                      fill=sample_type)) +
            geom_boxplot() +
            theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
            theme_bw()
    
        return(gg)
    }
    
    tryCatch({
        pdf("new_scores_boxplot.pdf")
        gg <- plot_scores(as.data.frame(new_score_df))
        print(gg)
        dev.off()
    }, error = function(e) {
        warning("Could not generate boxplot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING":',
        paste0('    ssPATHS: ', as.character(packageVersion('ssPATHS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_pathway_scoring.csv versions.yml
    """
}

workflow BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference_expression.csv, reference_metadata.csv, new_expression.csv, new_metadata.csv ] ]

    main:
    BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING(ch_input)

    emit:
    tables   = BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING.out.tables
    plots    = BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING.out.plots
    objects  = BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING.out.objects
    versions = BIOC_SSPATHS_SINGLE_SAMPLE_PATHWAY_SCORING.out.versions
}
