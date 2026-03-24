#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SWATH2stats
// This package is intended to transform SWATH data from the OpenSWATH software into a format readable 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SWATH2stats/inst/doc/SWATH2stats_example_script.R
// Upstream  : BiocManager, MSstats, PECA, aLFQ, imsbInfer
// Downstream: none
//
// Install: BiocManager::install("SWATH2stats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWATH2STATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-swath2stats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-swath2stats:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-swath2stats:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_swath2stats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_swath2stats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_swath2stats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SWATH2stats)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(SWATH2stats)
    library(data.table)
    data('Spyogenes', package = 'SWATH2stats')
    # --- Sample Annotation [] ---
    # Key functions: sample_annotation
    ---------------------------------------------------------------------
    data.annotated <- sample_annotation(data, Study_design, column_file = "align_origfilename")
    # --- Subset [] ---
    # Key functions: subset
    ---------------------------------------------------------------------
    data.annotated.nodecoy <- subset(data.annotated, decoy==FALSE)
    # --- Count Analytes [] ---
    # Key functions: count_analytes
    ---------------------------------------------------------------------
    count_analytes(data.annotated.nodecoy)
    # --- Write Matrix Peptides [] ---
    # Key functions: write_matrix_peptides, write_matrix_proteins
    ---------------------------------------------------------------------
    peptide_signal <- write_matrix_peptides(data.annotated.nodecoy)
    protein_signal <- write_matrix_proteins(data.annotated.nodecoy)
    head(protein_signal)
    # --- mscore4protfdr [] ---
    # Key functions: mscore4protfdr
    ---------------------------------------------------------------------
    mscore4protfdr(data, FFT = 0.25, fdr_target = 0.05)
    # --- Filter Mscore Condition [] ---
    # Key functions: filter_mscore_condition
    ---------------------------------------------------------------------
    data.filtered <- filter_mscore_condition(data.annotated, 0.001, n_replica = 2)
    # --- Filter On Max Peptides [] ---
    # Key functions: filter_on_max_peptides
    ---------------------------------------------------------------------
    data.filtered2 <- filter_on_max_peptides(data.filtered, n_peptides = 10)
    # --- Filter On Min Peptides [] ---
    # Key functions: filter_on_min_peptides
    ---------------------------------------------------------------------
    data.filtered3 <- filter_on_min_peptides(data.filtered2, n_peptides = 2)
    # --- Disaggregate [] ---
    # Key functions: disaggregate
    ---------------------------------------------------------------------
    data.transition <- disaggregate(data.filtered3)
    # --- convert4 M Sstats [] ---
    # Key functions: convert4MSstats
    ---------------------------------------------------------------------
    MSstats.input <- convert4MSstats(data.transition)
    head(MSstats.input)
    # --- convert4map D I A [] ---
    # Key functions: convert4mapDIA
    ---------------------------------------------------------------------
    mapDIA.input <- convert4mapDIA(data.transition)
    head(mapDIA.input)
    # --- convert4a L F Q [] ---
    # Key functions: convert4aLFQ
    ---------------------------------------------------------------------
    aLFQ.input <- convert4aLFQ(data.transition)
    head(aLFQ.input)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_swath2stats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_swath2stats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_swath2stats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SWATH2STATS:", paste0("    swath2stats: ", packageVersion("SWATH2stats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_swath2stats_results.csv
    touch ${prefix}_swath2stats_output.rds
    echo "BIOC_SWATH2STATS:" > versions.yml
    echo "    swath2stats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SWATH2STATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SWATH2STATS(ch_input)

    emit:
    results  = BIOC_SWATH2STATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SWATH2STATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SWATH2STATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SWATH2STATS.out.versions  // channel: path(versions.yml)
}
