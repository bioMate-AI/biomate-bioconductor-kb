#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RGSEA — rgsea_sd_features
// Measure similarities between query and reference transcriptome samples using standard deviation-based feature selection.
// Input: query_matrix.csv, reference_matrix.csv
// Container: quay.io/biocontainers/bioconductor-rgsea:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RGSEA
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run RGSEAsd to calculate similarity scores using features selected by standard deviation deviations
//  * 2. [Core Analysis] View the similarity results

nextflow.enable.dsl = 2

process BIOC_RGSEA_RGSEA_SD_FEATURES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    library(RGSEA)
    
    # 1. Read user input files
    if (!file.exists("query_matrix.csv") || !file.exists("reference_matrix.csv")) {
      stop("Error: Both 'query_matrix.csv' and 'reference_matrix.csv' must exist in the working directory.")
    }
    
    query_df <- read.csv("query_matrix.csv", row.names = 1, check.names = FALSE)
    ref_df <- read.csv("reference_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Find common features (genes)
    common_genes <- intersect(rownames(query_df), rownames(ref_df))
    if (length(common_genes) == 0) {
      stop("Error: No common features (row names) found between query and reference matrices.")
    }
    
    # Subset to common features
    query_df <- query_df[common_genes, , drop = FALSE]
    ref_df <- ref_df[common_genes, , drop = FALSE]
    
    # Ensure query has at least 1 column
    if (ncol(query_df) < 1) {
      stop("Error: query_matrix.csv must have at least 1 column of expression data.")
    }
    
    query_mat <- as.matrix(query_df)
    ref_mat <- as.matrix(ref_df)
    
    # 2. Run RGSEAsd with the full user matrices
    test2 <- RGSEAsd(query_mat, ref_mat, queryclasses=colnames(query_mat), 
                     refclasses=colnames(ref_mat), random=5000, sd=2, iteration=100)
    
    # 3. View and save the similarity results
    results_matrix <- test2[[1]]
    print(results_matrix)
    
    # Save results to CSV
    write.csv(results_matrix, "similarity_results.csv", row.names = TRUE)
    
    # Save the full list object to RDS
    saveRDS(test2, "rgsea_sd_results.rds")
    
    # Generate and save a barplot of the similarity scores
    tryCatch({
      pdf("similarity_plot.pdf", width = 8, height = 6)
      barplot(
        results_matrix,
        beside = TRUE,
        main = "RGSEA Similarity Scores (SD-based)",
        xlab = "Reference Samples",
        ylab = "Similarity Score",
        col = "skyblue",
        las = 2
      )
      dev.off()
    }, error = function(e) {
      warning("Could not generate PDF plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RGSEA_RGSEA_SD_FEATURES":',
        paste0('    RGSEA: ', as.character(packageVersion('RGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgsea_sd_features.csv versions.yml
    """
}

workflow BIOC_RGSEA_RGSEA_SD_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query_matrix.csv, reference_matrix.csv ] ]

    main:
    BIOC_RGSEA_RGSEA_SD_FEATURES(ch_input)

    emit:
    tables   = BIOC_RGSEA_RGSEA_SD_FEATURES.out.tables
    plots    = BIOC_RGSEA_RGSEA_SD_FEATURES.out.plots
    objects  = BIOC_RGSEA_RGSEA_SD_FEATURES.out.objects
    versions = BIOC_RGSEA_RGSEA_SD_FEATURES.out.versions
}
