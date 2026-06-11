#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rifiComparative — rifi_comparative_analysis
// Compare half-life and mRNA intensity at time 0 between two conditions to analyze transcriptional and post-transcriptional regulation.
// Input: stats_se_cdt1.rda, stats_se_cdt2.rda, differential_expression.rda, gff_synechocystis_6803.gff.gz
// Container: quay.io/biocontainers/bioconductor-rificomparative:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, rifiComparative
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load and Join Data
//  * 2. [Visualization & Output] Calculate Penalties
//  * 3. [Visualization & Output] Perform Fragmentation
//  * 4. [Visualization & Output] Run Statistical Tests
//  * 5. [Visualization & Output] Preprocess GFF3 and Visualize
//  * 6. [Visualization & Output] Adjust Half-Life and Intensity Fragments
//  * 7. [Visualization & Output] Generate Summary Plots
//  * 8. [Visualization & Output] Save Outputs

nextflow.enable.dsl = 2

process BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS {
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
    library(rifiComparative)
    
    # ==========================================
    # --- Load and Join Data ---
    # ==========================================
    
    # Load user-provided RDA files from the working directory
    load("stats_se_cdt1.rda")
    load("stats_se_cdt2.rda")
    load("differential_expression.rda")
    
    # Load and prepare data using loading_fun
    inp_s <- loading_fun(stats_se_cdt1, stats_se_cdt2, differential_expression)[[1]]
    inp_f <- loading_fun(stats_se_cdt1, stats_se_cdt2, differential_expression)[[2]]
    
    # Combine data row-wise
    data_combined_minimal <- joining_data_row(input1 = inp_s, input2 = inp_f)
    
    # Combine data column-wise
    df_comb_minimal <- joining_data_column(data = data_combined_minimal)
    
    # ==========================================
    # --- Calculate Penalties ---
    # ==========================================
    
    # Extract penalties for half-life and intensity
    penalties_res <- penalties(df_comb_minimal)
    penalties_df <- penalties_res[[1]]
    pen_HL <- penalties_res[[2]]
    pen_int <- penalties_res[[3]]
    
    # ==========================================
    # --- Perform Fragmentation ---
    # ==========================================
    
    # Perform half-life fragmentation
    penalties_df <- fragment_HL(
        probe = penalties_df,
        cores = 2,
        pen = pen_HL[[1]][[9]],
        pen_out = pen_HL[[1]][[10]]
    )
    
    # Perform intensity fragmentation
    fragment_int <- fragment_inty(
        probe = penalties_df,
        cores = 2,
        pen = pen_int[[1]][[9]],
        pen_out = pen_int[[1]][[10]]
    )
    
    # ==========================================
    # --- Run Statistical Tests ---
    # ==========================================
    
    # Run statistical tests on fragments
    stats_res <- statistics(data = fragment_int)
    stats_df_comb_minimal <- stats_res[[1]]
    df_comb_uniq_minimal <- stats_res[[2]]
    
    # ==========================================
    # --- Preprocess GFF3 and Visualize ---
    # ==========================================
    
    # Preprocess the user-provided GFF3 file
    annot_g <- gff3_preprocess(path = gzfile("gff_synechocystis_6803.gff.gz"))
    
    # Visualize the comparative fragments and save to PDF
    pdf("genome_fragments_comparison.pdf", width = 12, height = 8)
    rifi_visualization_comparison(
         data = data_combined_minimal,
         data_c = stats_df_comb_minimal,
         genomeLength = annot_g[[2]],
         annot = annot_g[[1]]
    )
    dev.off()
    
    # ==========================================
    # --- Adjust Half-Life and Intensity Fragments ---
    # ==========================================
    
    # Adjust half-life and intensity fragments and merge with genome annotation
    df_adjusting_HLToInt <- adjusting_HLToInt(
        data = stats_df_comb_minimal, 
        annotation = annot_g[[1]]
    )
    
    # ==========================================
    # --- Generate Summary Plots ---
    # ==========================================
    
    # Assign the adjusted data frame to df_mean_minimal for plotting
    df_mean_minimal <- df_adjusting_HLToInt
    
    # Generate and save summary plots to PDF
    pdf("summary_plots.pdf", width = 10, height = 8)
    figures_fun(
        data.1 = df_mean_minimal, 
        data.2 = data_combined_minimal,
        input.1 = df_comb_minimal, 
        input.2 = differential_expression, 
        cdt1 = "sc",
        cdt2 = "fe"
    )
    dev.off()
    
    # ==========================================
    # --- Save Outputs ---
    # ==========================================
    
    # Save key data frames as CSV and RDS files
    write.csv(df_adjusting_HLToInt, "df_adjusting_HLToInt.csv", row.names = FALSE)
    write.csv(stats_df_comb_minimal, "stats_df_comb_minimal.csv", row.names = FALSE)
    write.csv(df_comb_uniq_minimal, "df_comb_uniq_minimal.csv", row.names = FALSE)
    
    saveRDS(df_adjusting_HLToInt, "df_adjusting_HLToInt.rds")
    saveRDS(stats_df_comb_minimal, "stats_df_comb_minimal.rds")
    saveRDS(df_comb_uniq_minimal, "df_comb_uniq_minimal.rds")

    writeLines(c(
        '"BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS":',
        paste0('    rifiComparative: ', as.character(packageVersion('rifiComparative')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rifi_comparative_analysis.csv versions.yml
    """
}

workflow BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ stats_se_cdt1.rda, stats_se_cdt2.rda, differential_expression.rda, gff_synechocystis_6803.gff.gz ] ]

    main:
    BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS.out.tables
    plots    = BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS.out.plots
    objects  = BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS.out.objects
    versions = BIOC_RIFICOMPARATIVE_RIFI_COMPARATIVE_ANALYSIS.out.versions
}
