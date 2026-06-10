#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OPWeight — one_step_opw
// Perform optimal p-value weighting and hypothesis testing in a single step using the main opw function.
// Input: de_res_air$pvalue, de_res_air$baseMean
// Container: quay.io/biocontainers/bioconductor-opweight:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OPWeight, cowplot, ggplot2, tibble
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Add a small constant to filter statistics to ensure they are positive for Box-Cox transformation
//  * 2. [Core Analysis] Run the opw function with specified parameters to compute weights and identify significant tests

nextflow.enable.dsl = 2

process BIOC_OPWEIGHT_ONE_STEP_OPW {
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
        library("OPWeight")
        library("ggplot2")
        library("cowplot")
        library("tibble")
        
        # Read the user input file from the working directory
        # The input is expected to be a CSV file named "de_res_air.csv" 
        # containing at least the columns "pvalue" and "baseMean"
        if (file.exists("de_res_air.csv")) {
          de_res_air <- read.csv("de_res_air.csv")
        } else {
          stop("Error: Required input file 'de_res_air.csv' not found in the working directory.")
        }
        
        # Pre-process: Remove rows with NA values in pvalue or baseMean to ensure robust execution
        de_res_air <- de_res_air[!is.na(de_res_air\$pvalue) & !is.na(de_res_air\$baseMean), ]
        
        # Stage 1: Add a small constant to filter statistics to ensure they are positive for Box-Cox transformation
        filters = de_res_air\$baseMean + .0001 # add a small constant to make all values positive
        
        # Stage 2: Run the opw function with specified parameters to compute weights and identify significant tests
        set.seed(123) # one should use more nrep to obtain more acurate results
        opw_results <- opw(pvalue = de_res_air\$pvalue, filter = filters, nrep = 1000, alpha = .1, tail = 2, effectType = "continuous", method = "BH")
        
        # Save the full RDS object of the results
        saveRDS(opw_results, file = "opw_results.rds")
        
        # Save a summary of the results to a CSV file
        summary_df <- data.frame(
          totalTests = opw_results\$totalTests,
          nullProp = opw_results\$nullProp,
          rejections = opw_results\$rejections
        )
        write.csv(summary_df, "opw_summary.csv", row.names = FALSE)
        
        # Save the detailed table of p-values, filters, weights, and rank probabilities
        order_idx <- order(filters, decreasing = TRUE)
        results_table <- data.frame(
          pvalue = de_res_air\$pvalue[order_idx],
          filter = filters[order_idx],
          weight = opw_results\$weight,
          ranksProb = opw_results\$ranksProb
        )
        write.csv(results_table, "opw_results_table.csv", row.names = FALSE)
        
        # Save the list of rejections if available
        if (!is.null(opw_results\$rejections_list)) {
          write.csv(as.data.frame(opw_results\$rejections_list), "opw_rejections_list.csv", row.names = FALSE)
        }
        
        # Generate and save the diagnostic plots (Rank Probability and Weight versus Test Rank)
        m = opw_results\$totalTests
        testRanks = 1:m
        probs = opw_results\$ranksProb
        weights = opw_results\$weight
        dat = tibble(testRanks, probs, weights)
        
        p_prob = ggplot(dat, aes(x = testRanks, y = probs)) + 
          geom_point(size = .5, col="firebrick4") + 
          labs(x = "Test rank" , y = "p(rank | effect)")
        
        p_weight = ggplot(dat, aes(x = testRanks, y = weights)) + 
          geom_point(size = .5, col="firebrick4") + 
          labs(x = "Test rank" , y = "Weight")
        
        p_grid <- plot_grid(p_prob, p_weight, labels = c("a", "b"))
        ggsave("opw_plots.pdf", plot = p_grid, width = 10, height = 5)

    writeLines(c(
        '"BIOC_OPWEIGHT_ONE_STEP_OPW":',
        paste0('    OPWeight: ', as.character(packageVersion('OPWeight')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_opw.csv versions.yml
    """
}

workflow BIOC_OPWEIGHT_ONE_STEP_OPW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ de_res_air$pvalue, de_res_air$baseMean ] ]

    main:
    BIOC_OPWEIGHT_ONE_STEP_OPW(ch_input)

    emit:
    tables   = BIOC_OPWEIGHT_ONE_STEP_OPW.out.tables
    plots    = BIOC_OPWEIGHT_ONE_STEP_OPW.out.plots
    objects  = BIOC_OPWEIGHT_ONE_STEP_OPW.out.objects
    versions = BIOC_OPWEIGHT_ONE_STEP_OPW.out.versions
}
