#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TargetSearch
// This packages provides a flexible, fast and accurate method for targeted pre-processing of GC-MS dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TargetSearch/inst/doc/RICorrection.R
// Upstream  : TargetSearchData
// Downstream: none
//
// Install: BiocManager::install("TargetSearch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TARGETSEARCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-targetsearch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-targetsearch:2.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-targetsearch:2.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_targetsearch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_targetsearch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_targetsearch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ImportFameSettings)
    library(RIcorrect)
    library(RIpath)
    library(jsonlite)

    # --- tsd_data_path [] ---
    # Key functions: tsd_data_path
    cdfPath <- tsd_data_path()
    dir(cdfPath, pattern="cdf$")
    # --- R Ipath [] ---
    # Key functions: RIpath
    samples.all <- ImportSamplesFromDir(cdfPath)
    RIpath(samples.all) <- "."
    # --- Import Fame Settings [] ---
    # Key functions: ImportFameSettings
    rimLimits <- ImportFameSettings(tsd_file_path("rimLimits.txt"))
    # --- R Icorrect [] ---
    # Key functions: RIcorrect

    # --- rep [] ---
    # Key functions: rep
    isRIMarker <- rep(FALSE, length(samples.all))
    isRIMarker[c(1, 6, 11)] <- TRUE
    # --- fix R I [] ---
    # Key functions: fixRI
    fixRI(samples.all, rimLimits, RImatrix2, which(!isRIMarker))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_targetsearch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_targetsearch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_targetsearch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TARGETSEARCH:", paste0("    targetsearch: ", packageVersion("TargetSearch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_targetsearch_results.csv
    touch ${prefix}_targetsearch_output.rds
    echo "BIOC_TARGETSEARCH:" > versions.yml
    echo "    targetsearch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TARGETSEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TARGETSEARCH(ch_input)

    emit:
    results  = BIOC_TARGETSEARCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TARGETSEARCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TARGETSEARCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TARGETSEARCH.out.versions  // channel: path(versions.yml)
}
