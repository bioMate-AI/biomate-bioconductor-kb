#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: synergyfinder — higher_order_combinations
// Analyze and visualize higher-order drug combinations (3 or more drugs) using dimension reduction.
// Input: higher_order_screening_data.csv
// Container: quay.io/biocontainers/bioconductor-synergyfinder:3.18.0--r45hdfd78af_0
// Requires: htmlwidgets, plotly, synergyfinder
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Reshape and pre-process higher-order data using ReshapeData
//  * 2. [Core Analysis] Calculate multi-drug synergy scores using CalculateSynergy
//  * 3. [Core Analysis] Calculate multi-drug sensitivity scores using CalculateSensitivity
//  * 4. [Visualization & Output] Visualize high-dimensional landscapes using PlotMultiDrugSurface

nextflow.enable.dsl = 2

process BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
            
        # Load required libraries
        library(synergyfinder)
        
        # 1. Read user input
        input_file <- "higher_order_screening_data.csv"
        if (!file.exists(input_file)) {
          stop(paste("Input file not found:", input_file))
        }
        screening_data <- read.csv(input_file, stringsAsFactors = FALSE)
        
        # 2. Reshape and pre-process higher-order data using ReshapeData
        res <- ReshapeData(
          data = screening_data,
          data_type = "inhibition",
          impute = TRUE,
          impute_method = NULL,
          noise = TRUE,
          seed = 1
        )
        
        # 3. Calculate multi-drug synergy scores using CalculateSynergy
        res <- CalculateSynergy(
          data = res,
          method = c("ZIP", "HSA", "Bliss", "Loewe"),
          Emin = NA,
          Emax = NA,
          correct_baseline = "non"
        )
        
        # 4. Calculate multi-drug sensitivity scores using CalculateSensitivity
        res <- CalculateSensitivity(
          data = res,
          correct_baseline = "non"
        )
        
        # Save the processed R object
        saveRDS(res, file = "synergy_sensitivity_results.rds")
        
        # Export tables to CSV
        if (!is.null(res\$synergy_scores)) {
          write.csv(res\$synergy_scores, "synergy_scores.csv", row.names = FALSE)
        }
        if (!is.null(res\$drug_pairs)) {
          write.csv(res\$drug_pairs, "drug_pairs_metrics.csv", row.names = FALSE)
        }
        
        # 5. Visualize high-dimensional landscapes using PlotMultiDrugBar
        blocks <- res\$drug_pairs\$block_id
        block_p1 <- if (length(blocks) >= 2) blocks[2] else blocks[1]
        block_p2 <- blocks[1]
        
        p1 <- PlotMultiDrugBar(
          data = res,
          plot_block = block_p1,
          plot_value = "response"
        )
        
        p2 <- PlotMultiDrugBar(
          data = res,
          plot_block = block_p2,
          plot_value = "ZIP_synergy"
        )
        
        # Save interactive plotly plots as HTML files
        tryCatch({
          if (requireNamespace("htmlwidgets", quietly = TRUE) && requireNamespace("plotly", quietly = TRUE)) {
            htmlwidgets::saveWidget(plotly::ggplotly(p1), "multidrug_bar_block2_response.html", selfcontained = TRUE)
            htmlwidgets::saveWidget(plotly::ggplotly(p2), "multidrug_bar_block1_zip_synergy.html", selfcontained = TRUE)
          } else {
            warning("htmlwidgets and/or plotly package is not installed. Interactive HTML plots could not be saved.")
          }
        }, error = function(e) {
          warning("Failed to save interactive plots as HTML: ", e\$message)
        })

    writeLines(c(
        '"BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS":',
        paste0('    synergyfinder: ', as.character(packageVersion('synergyfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_higher_order_combinations.csv versions.yml
    """
}

workflow BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ higher_order_screening_data.csv ] ]

    main:
    BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS(ch_input)

    emit:
    tables   = BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS.out.tables
    plots    = BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS.out.plots
    objects  = BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS.out.objects
    versions = BIOC_SYNERGYFINDER_HIGHER_ORDER_COMBINATIONS.out.versions
}
