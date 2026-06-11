#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: synergyfinder — two_drug_without_replicates
// Analyze and visualize synergy and sensitivity for two-drug combinations without replicates.
// Input: drug_screening_data.csv
// Container: quay.io/biocontainers/bioconductor-synergyfinder:3.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: synergyfinder
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Reshape and pre-process the input data using ReshapeData
//  * 2. [Core Analysis] Calculate synergy scores for multiple reference models using CalculateSynergy
//  * 3. [Core Analysis] Calculate sensitivity scores (IC50, RI, CSS) using CalculateSensitivity
//  * 4. [Visualization & Output] Visualize dose-response curves, heatmaps, 2D contours, synergy barometers, and synergy-sensitivity plots

nextflow.enable.dsl = 2

process BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES {
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
            
        # Load required library
        library(synergyfinder)
        
        # 1. Read user input data
        input_data <- read.csv("drug_screening_data.csv", stringsAsFactors = FALSE)
        
        # 2. Reshape and pre-process the input data
        res <- ReshapeData(
          data = input_data,
          data_type = "viability",
          impute = TRUE,
          impute_method = NULL,
          noise = TRUE,
          seed = 1
        )
        
        # 3. Calculate synergy scores for multiple reference models
        res <- CalculateSynergy(
          data = res,
          method = c("ZIP", "HSA", "Bliss", "Loewe"),
          Emin = NA,
          Emax = NA,
          correct_baseline = "non"
        )
        
        # 4. Calculate sensitivity scores (IC50, RI, CSS)
        res <- CalculateSensitivity(
          data = res,
          correct_baseline = "non"
        )
        
        # 5. Save tabular results
        write.csv(res\$drug_pairs, "drug_pairs_metrics.csv", row.names = FALSE)
        write.csv(res\$synergy_scores, "synergy_scores.csv", row.names = FALSE)
        saveRDS(res, "synergy_sensitivity_results.rds")
        
        # 6. Generate and save visualizations to a PDF file
        pdf("synergy_plots.pdf", width = 10, height = 8)
        
        # Dynamically get the first block_id to avoid hardcoding
        first_block <- res\$drug_pairs\$block_id[1]
        
        # Dose-response curves
        for (i in c(1, 2)){
          PlotDoseResponseCurve(
            data = res,
            plot_block = first_block,
            drug_index = i,
            plot_new = FALSE,
            record_plot = FALSE
          )
        }
        
        # 2-Drug Heatmap
        p_heatmap <- Plot2DrugHeatmap(
          data = res,
          plot_block = first_block,
          drugs = c(1, 2),
          plot_value = "response",
          dynamic = FALSE,
          summary_statistic = c("mean",  "median")
        )
        print(p_heatmap)
        
        # 2-Drug Contour
        p_contour <- Plot2DrugContour(
          data = res,
          plot_block = first_block,
          drugs = c(1, 2),
          plot_value = "response",
          dynamic = FALSE,
          summary_statistic = c("mean", "median")
        )
        print(p_contour)
        
        # Get valid concentrations for the first block to avoid hardcoded values
        block1_scores <- res\$synergy_scores[res\$synergy_scores\$block_id == first_block, ]
        comb_scores <- block1_scores[block1_scores\$conc1 > 0 & block1_scores\$conc2 > 0, ]
        if (nrow(comb_scores) > 0) {
          plot_concs <- c(comb_scores\$conc1[1], comb_scores\$conc2[1])
        } else {
          plot_concs <- c(block1_scores\$conc1[1], block1_scores\$conc2[1])
        }
        
        # Synergy Barometer
        p_barometer <- PlotBarometer(
          data = res,
          plot_block = first_block,
          plot_concs = plot_concs, 
          needle_text_offset = 2.5
        )
        print(p_barometer)
        
        # Multi-Drug Barplot
        p_multibar <- PlotMultiDrugBar(
          data = res,
          plot_block = first_block,
          plot_value = c("response", "ZIP_synergy", "Loewe_synergy", "HSA_synergy", "Bliss_synergy"),
          sort_by = "response",
          highlight_row = plot_concs,
          highlight_label_size = 8
        )
        print(p_multibar)
        
        # Synergy-Sensitivity Plot
        p_sens_syn <- PlotSensitivitySynergy(
          data = res,
          plot_synergy = "ZIP",
          show_labels = TRUE,
          dynamic = FALSE
        )
        print(p_sens_syn)
        
        dev.off()

    writeLines(c(
        '"BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES":',
        paste0('    synergyfinder: ', as.character(packageVersion('synergyfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_drug_without_replicates.csv versions.yml
    """
}

workflow BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ drug_screening_data.csv ] ]

    main:
    BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES(ch_input)

    emit:
    tables   = BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES.out.tables
    plots    = BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES.out.plots
    objects  = BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES.out.objects
    versions = BIOC_SYNERGYFINDER_TWO_DRUG_WITHOUT_REPLICATES.out.versions
}
