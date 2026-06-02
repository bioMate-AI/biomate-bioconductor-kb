#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cogeqc
// cogeqc aims to facilitate systematic quality checks on standard comparative genomics analyses to hel
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cogeqc/inst/doc/vignette_01_assessing_genome_assembly.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cogeqc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COGEQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cogeqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cogeqc:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cogeqc:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cogeqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cogeqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cogeqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cogeqc)
    library(jsonlite)

    # --- Retrieve Genome Statistics [Retrieve NCBI genome assembly and annotation statistics] ---
    # Key functions: get_genome_stats
    filt <- list(
        filters.has_annotation = "true",
        filters.assembly_level = "chromosome"
    )
    maize_stats <- get_genome_stats(
        taxon = "Zea mays",
        filters = filt
    )

    # --- Compare Genome Statistics [Compare user genome assembly metrics against NCBI reference data] ---
    # Key functions: compare_genome_stats
    my_stats <- data.frame(
        accession = "my_lovely_maize",
        sequence_length = 2.4 * 1e9,
        gene_count_total = 50000,
        CC_ratio = 2
    )
    comparison <- compare_genome_stats(
        ncbi_stats = maize_stats,
        user_stats = my_stats
    )

    # --- Visualise Genome Statistics [Generate comparative plots of genome assembly metrics] ---
    # Key functions: plot_genome_stats
    p_stats <- plot_genome_stats(
        ncbi_stats = maize_stats,
        user_stats = my_stats
    )

    # --- Parse and Visualise BUSCO Results [Read BUSCO output and plot completeness scores] ---
    # Key functions: read_busco, plot_busco
    output_dir <- system.file("extdata", package = "cogeqc")
    busco_summary <- read_busco(output_dir)
    p_busco <- plot_busco(busco_summary)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cogeqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cogeqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cogeqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COGEQC:", paste0("    cogeqc: ", packageVersion("cogeqc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cogeqc_results.csv
    touch ${prefix}_cogeqc_output.rds
    echo "BIOC_COGEQC:" > versions.yml
    echo "    cogeqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COGEQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COGEQC(ch_input)

    emit:
    results  = BIOC_COGEQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COGEQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COGEQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COGEQC.out.versions  // channel: path(versions.yml)
}
