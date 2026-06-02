#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epimutacions
// The package includes some statistical outlier detection methods for epimutations detection in DNA me
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epimutacions/inst/doc/epimutacions.R
// Upstream  : ExperimentHub, kableExtra, minfi
// Downstream: none
//
// Install: BiocManager::install("epimutacions")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIMUTACIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epimutacions"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epimutacions:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epimutacions:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epimutacions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epimutacions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epimutacions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epimutacions)
    library(jsonlite)

    # --- Parameter Initialization [epimutacions] ---
    # Key functions: norm_parameters, epi_parameters
    norm_params <- norm_parameters(
        illumina = list("bg.correct" = FALSE)
    )
    epi_params <- epi_parameters(
        manova = list("pvalue_cutoff" = 0.01),
        iso.forest = list("outlier_score_cutoff" = 0.15)
    )

    # --- Data Preprocessing [epimutacions] ---
    # Key functions: epi_preprocess
    GRset <- epi_preprocess(
        baseDir = tempdir(),
        reference_panel = NULL,
        pattern = "SampleSheet.csv"
    )

    # --- Epimutation Detection [epimutacions] ---
    # Key functions: epimutations
    epi_mvo <- epimutations(
        case_samples = case_samples,
        control_samples = control_samples,
        method = "manova",
        epi_params = epi_params
    )

    # --- Epimutation Annotation [epimutacions] ---
    # Key functions: annotate_epimutations
    rst_mvo <- annotate_epimutations(
        epi_results = epi_mvo,
        omim = TRUE,
        genome = "hg19"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epimutacions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epimutacions_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epimutacions_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIMUTACIONS:", paste0("    epimutacions: ", packageVersion("epimutacions"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epimutacions_results.csv
    touch ${prefix}_epimutacions_output.rds
    echo "BIOC_EPIMUTACIONS:" > versions.yml
    echo "    epimutacions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIMUTACIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIMUTACIONS(ch_input)

    emit:
    results  = BIOC_EPIMUTACIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIMUTACIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIMUTACIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIMUTACIONS.out.versions  // channel: path(versions.yml)
}
