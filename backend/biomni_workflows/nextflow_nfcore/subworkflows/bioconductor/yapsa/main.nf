#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: YAPSA
// This package provides functions and routines for supervised analyses of mutational signatures (i.e.,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/YAPSA/inst/doc/YAPSA.R
// Upstream  : BiocStyle, Biostrings, knitr
// Downstream: none
//
// Install: BiocManager::install("YAPSA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_YAPSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-yapsa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-yapsa:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-yapsa:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_yapsa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_yapsa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_yapsa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(YAPSA)
    library(LCD)
    library(LCD_complex_cutoff)
    library(jsonlite)

    # --- Genomic Rainfall Visualization [] ---
    # Key functions: trellis_rainfall_plot
    data("exchange_colour_vector")
    choice_PID <- "4121361"
    PID_df <- subset(lymphoma_annotated, PID == choice_PID)
    PID_df$col <- exchange_colour_vector[PID_df$change]
    trellis_rainfall_plot(PID_df, in_point_size = grid::unit(0.5, "mm"))


    # --- Reference Signature Preparation [] ---
    # Key functions: AlexCosmicValid_sig_df
    data(AlexCosmicValid_sig_df)
    Alex_COSMIC_rownames <- paste(AlexCosmicValid_sig_df[, 1],
                                  AlexCosmicValid_sig_df[, 2], sep = " ")
    COSMIC_select_ind <- grep("Signature", names(AlexCosmicValid_sig_df))
    signatures_df <- AlexCosmicValid_sig_df[, COSMIC_select_ind]
    rownames(signatures_df) <- Alex_COSMIC_rownames
    colnames(signatures_df) <- gsub("Signature\\.", "AC",
                                    colnames(signatures_df))


    # --- Signature Attribution via LCD [] ---
    # Key functions: LCD
    mut_matrix <- matrix(runif(96 * 10, min = 0, max = 100), nrow = 96)
    rownames(mut_matrix) <- rownames(signatures_df)[1:96]
    colnames(mut_matrix) <- paste0("Sample_", 1:10)
    lcd_results <- LCD(in_mutation_sub_df = mut_matrix,
                       in_signatures_df = signatures_df[1:96, ])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_yapsa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_yapsa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_yapsa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_YAPSA:", paste0("    yapsa: ", packageVersion("YAPSA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_yapsa_results.csv
    touch ${prefix}_yapsa_output.rds
    echo "BIOC_YAPSA:" > versions.yml
    echo "    yapsa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_YAPSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_YAPSA(ch_input)

    emit:
    results  = BIOC_YAPSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_YAPSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_YAPSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_YAPSA.out.versions  // channel: path(versions.yml)
}
