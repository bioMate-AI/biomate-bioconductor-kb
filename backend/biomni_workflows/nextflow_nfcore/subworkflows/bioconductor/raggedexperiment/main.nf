#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RaggedExperiment
// This package provides a flexible representation of copy number, mutation, and other data that fit in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RaggedExperiment/inst/doc/ASCAT_to_RaggedExperiment.R
// Upstream  : GenomicRanges, Matrix
// Downstream: CNVRanger, SARC, curatedPCaData
//
// Install: BiocManager::install("RaggedExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAGGEDEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-raggedexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-raggedexperiment:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-raggedexperiment:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_raggedexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_raggedexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_raggedexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(GRanges)
    library(GRangesList)
    library(IRanges)
    library(RaggedExperiment)
    library(Rle)
    library(jsonlite)

    # --- Delim [] ---
    # Key functions: delim
    ---------------------------------------------------------------------
    # --- Granges [] ---
    # Key functions: GRanges, Rle, IRanges, strand
    ---------------------------------------------------------------------
    # --- Makegrangesfromdataframe [] ---
    # Key functions: makeGRangesFromDataFrame
    ---------------------------------------------------------------------
    # --- Split [] ---
    # Key functions: split
    ---------------------------------------------------------------------
    sample_list <- split(
        ASCAT_data_All,
        f = ASCAT_data_All$sample
    )
    # --- Makegrangeslistfromdataframe [] ---
    # Key functions: makeGRangesListFromDataFrame
    ---------------------------------------------------------------------
    # --- Grangeslist [] ---
    # Key functions: GRangesList
    ---------------------------------------------------------------------
    sample_list_GRanges_ex3 <- GRangesList(
        sample1 = sample1_ex1
    )
    sample_list_GRanges_ex3
    # --- Dataframe [] ---
    # Key functions: DataFrame, RaggedExperiment
    ---------------------------------------------------------------------
    colDat_1 = DataFrame(id = 1)
    # --- Raggedexperiment [] ---
    # Key functions: RaggedExperiment
    ---------------------------------------------------------------------
    ragexp_2 <- RaggedExperiment(
        sample_list_GRanges_ex1,
        colData = colDat_1
    )
    # --- Dataframe [] ---
    # Key functions: DataFrame, RaggedExperiment
    ---------------------------------------------------------------------
    colDat_3 = DataFrame(id = 1:3)
    # --- Raggedexperiment [] ---
    # Key functions: RaggedExperiment
    ---------------------------------------------------------------------
    ragexp_4  <- RaggedExperiment(
        sample_list_GRanges_ex3,
        colData = colDat_1
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_raggedexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_raggedexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_raggedexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAGGEDEXPERIMENT:", paste0("    raggedexperiment: ", packageVersion("RaggedExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raggedexperiment_results.csv
    touch ${prefix}_raggedexperiment_output.rds
    echo "BIOC_RAGGEDEXPERIMENT:" > versions.yml
    echo "    raggedexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAGGEDEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAGGEDEXPERIMENT(ch_input)

    emit:
    results  = BIOC_RAGGEDEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAGGEDEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAGGEDEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAGGEDEXPERIMENT.out.versions  // channel: path(versions.yml)
}
