#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multiMiR — mirna_target_pipeline
// Identify differentially expressed miRNAs from count data and retrieve their validated and predicted target genes using multiMiR.
// Input: counts.csv, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, multiMiR
// QC: TMM normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE {
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
    
    # --- Load required libraries ---
    library(edgeR)
    library(multiMiR)
    
    # --- Read and preprocess input data ---
    message("Reading input files...")
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Set row names for counts if 'gene_id' column exists
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    } else {
        rownames(counts_df) <- counts_df[, 1]
        counts_df <- counts_df[, -1, drop = FALSE]
    }
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts_df), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # --- Differential Expression Analysis using edgeR ---
    message("Performing differential expression analysis...")
    design <- model.matrix(~ condition, data = coldata)
    dge <- DGEList(counts = counts_df)
    dge <- calcNormFactors(dge)
    
    # Estimate dispersions
    dge <- estimateGLMCommonDisp(dge, design)
    dge <- estimateGLMTrendedDisp(dge, design)
    dge <- estimateGLMTagwiseDisp(dge, design)
    
    # Fit GLM model and perform Likelihood Ratio Test
    fit <- glmFit(dge, design)
    lrt <- glmLRT(fit, coef = 2)
    
    # Extract top differentially expressed miRNAs
    p_val_DE <- topTags(lrt, adjust.method = "BH", n = Inf)
    top_miRNAs <- rownames(p_val_DE\$table)[1:min(10, nrow(p_val_DE\$table))]
    message("Top miRNAs identified: ", paste(top_miRNAs, collapse = ", "))
    
    # Detect organism from miRNA names (default to human 'hsa')
    first_mirna <- top_miRNAs[1]
    org <- "hsa"
    if (startsWith(first_mirna, "mmu")) {
        org <- "mmu"
    } else if (startsWith(first_mirna, "rno")) {
        org <- "rno"
    }
    message("Detected organism: ", org)
    
    # --- Query multiMiR for Validated Targets ---
    message("Querying multiMiR for validated targets...")
    validated_results <- tryCatch({
        get_multimir(
            org = org,
            mirna = top_miRNAs,
            table = "validated",
            summary = TRUE
        )
    }, error = function(e) {
        message("Warning: multiMiR validated query failed or timed out: ", e\$message)
        NULL
    })
    
    # --- Query multiMiR for Predicted Targets ---
    message("Querying multiMiR for predicted targets...")
    predicted_results <- tryCatch({
        get_multimir(
            org = org,
            mirna = top_miRNAs,
            table = "predicted",
            predicted.cutoff = 20,
            predicted.cutoff.type = "p",
            summary = TRUE
        )
    }, error = function(e) {
        message("Warning: multiMiR predicted query failed or timed out: ", e\$message)
        NULL
    })
    
    # --- Process and Save Outputs ---
    # 1. Validated Targets
    if (!is.null(validated_results) && !is.null(validated_results@data) && nrow(validated_results@data) > 0) {
        write.csv(validated_results@data, "validated_targets.csv", row.names = FALSE)
        write.csv(validated_results@summary, "multimir_summary.csv", row.names = FALSE)
        
        # Demonstrate AnnotationDbi select method on the S4 object
        tryCatch({
            val_keys <- keys(validated_results, keytype = "mature_mirna_id")
            if (length(val_keys) > 0) {
                selected_data <- select(
                    validated_results,
                    keys = val_keys[1:min(5, length(val_keys))],
                    keytype = "mature_mirna_id",
                    columns = c("database", "target_symbol", "type")
                )
                message("Successfully ran AnnotationDbi select on validated results.")
            }
        }, error = function(e) {
            message("AnnotationDbi select helper failed: ", e\$message)
        })
    } else {
        message("No validated targets found or query failed. Writing empty placeholder.")
        write.csv(data.frame(Message = "No validated targets found or query failed"), "validated_targets.csv", row.names = FALSE)
        write.csv(data.frame(Message = "No summary available"), "multimir_summary.csv", row.names = FALSE)
    }
    
    # 2. Predicted Targets
    if (!is.null(predicted_results) && !is.null(predicted_results@data) && nrow(predicted_results@data) > 0) {
        write.csv(predicted_results@data, "predicted_targets.csv", row.names = FALSE)
    } else {
        message("No predicted targets found or query failed. Writing empty placeholder.")
        write.csv(data.frame(Message = "No predicted targets found or query failed"), "predicted_targets.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE":',
        paste0('    multiMiR: ', as.character(packageVersion('multiMiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_target_pipeline.csv versions.yml
    """
}

workflow BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE.out.tables
    plots    = BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE.out.plots
    objects  = BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE.out.objects
    versions = BIOC_MULTIMIR_MIRNA_TARGET_PIPELINE.out.versions
}
