#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowCyBar — correlation_analysis
// Calculate and visualize Spearman's rank-order correlations between cell abundances and abiotic parameters.
// Input: Corr_data_sample.txt
// Container: quay.io/biocontainers/bioconductor-flowcybar:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCyBar
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read correlation dataset
//  * 2. [Visualization & Output] Run correlation analysis and plot heatmaps
//  * 3. [Visualization & Output] Customize heatmap colors, dendrograms, and column selections
//  * 4. [Visualization & Output] Extract and save correlation estimates and p-values

nextflow.enable.dsl = 2

process BIOC_FLOWCYBAR_CORRELATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("flowCyBar")
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
    
    # Load required library
    library(flowCyBar)
    
    # ==========================================
    # 1. Read correlation dataset
    # ==========================================
    # Read the user input file from the working directory
    Corr_data_sample <- read.table("Corr_data_sample.txt", header = TRUE, sep = "\t", check.names = FALSE)
    
    # ==========================================
    # 2. Run correlation analysis and plot heatmaps
    # 3. Customize heatmap colors, dendrograms, and column selections
    # ==========================================
    # Open a PDF device to save the generated heatmaps
    pdf("correlation_heatmaps.pdf", width = 10, height = 10)
    
    # Run the documented correlation and visualization steps
    correlation(Corr_data_sample[,-1])
    
    correlation(Corr_data_sample[,-1], colkey = topo.colors(16), dendrogram = "column")
    
    correlation(Corr_data_sample[,-1], colkey = cm.colors(15), dendrogram = "row")
    
    correlation(Corr_data_sample[,-1], colkey = heat.colors(11), dendrogram = "none",
                main = "Correlation of Corr_data_sample")
    
    correlation(Corr_data_sample[,-1], Rowv = FALSE, Colv = FALSE, dendrogram = "none")
    
    # Run column selection by index (wrapped in tryCatch to handle potential dimension mismatches gracefully)
    tryCatch({
      correlation(Corr_data_sample[, c(2:11, 32:34, 42:ncol(Corr_data_sample))])
    }, error = function(e) {
      message("Skipped index-based column selection correlation: ", e\$message)
    })
    
    # Run column selection by name (wrapped in tryCatch to handle potential name mismatches gracefully)
    tryCatch({
      correlation(Corr_data_sample[, c("G1", "G2", "G3", "G4", "G5", "G6", "G7",
                                       "G8", "G9", "G10", "delta_B1", "delta_B2", "delta_B3", "pO2", "pH", "redox_pot")])
    }, error = function(e) {
      message("Skipped name-based column selection correlation: ", e\$message)
    })
    
    dev.off()
    
    # ==========================================
    # 4. Extract and save correlation estimates and p-values
    # ==========================================
    # Run correlation with verbose=TRUE to obtain the estimates and p-values
    cor <- correlation(Corr_data_sample[,-1], verbose = TRUE)
    
    # Display estimates and p-values in the console/log
    cor["est"]
    cor["pvals"]
    
    # Write the estimates to a tab-separated text file
    write.table(cor["est"], file = "estimates.txt", row.names = TRUE,
                quote = FALSE, sep = "\t")
    
    # Write the p-values to a tab-separated text file
    write.table(cor["pvals"], file = "pvalues.txt", row.names = TRUE,
                quote = FALSE, sep = "\t")
    
    # Save the complete correlation results object as an RDS file
    saveRDS(cor, file = "correlation_results.rds")

    writeLines(c(
        '"BIOC_FLOWCYBAR_CORRELATION_ANALYSIS":',
        paste0('    flowCyBar: ', as.character(packageVersion('flowCyBar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWCYBAR_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Corr_data_sample.txt ] ]

    main:
    BIOC_FLOWCYBAR_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWCYBAR_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_FLOWCYBAR_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_FLOWCYBAR_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_FLOWCYBAR_CORRELATION_ANALYSIS.out.versions
}
