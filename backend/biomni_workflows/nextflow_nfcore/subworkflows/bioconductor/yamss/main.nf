#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: yamss
// Tools to analyze and visualize high-throughput metabolomics data aquired using chromatography-mass s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/yamss/inst/doc/yamss.R
// Upstream  : mtbls2
// Downstream: none
//
// Install: BiocManager::install("yamss")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_YAMSS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-yamss"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-yamss:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-yamss:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_yamss_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_yamss_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_yamss_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(yamss)
    library(jsonlite)


    # --- Dependencies [] ---
    # Key functions: find.package, list.files, rep, DataFrame, readMSdata, bakedpi, mtbls2, mzML
    library(yamss)
    library(mtbls2)

    ## -----------------------------------------------------------------------------
    filepath <- file.path(find.package("mtbls2"), "mzML")
    files <- list.files(filepath, pattern = "MSpos-Ex1", recursive = TRUE, full.names = TRUE)
    classes <- rep(c("wild-type", "mutant"), each = 4)

    ## -----------------------------------------------------------------------------
    colData <- DataFrame(sampClasses = classes, ionmode = "pos")
    cmsRaw <- readMSdata(files = files, colData = colData, mzsubset = c(500,520), verbose = TRUE)
    cmsRaw

    ## -----------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_yamss_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_yamss_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_yamss_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_YAMSS:", paste0("    yamss: ", packageVersion("yamss"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_yamss_results.csv
    touch ${prefix}_yamss_output.rds
    echo "BIOC_YAMSS:" > versions.yml
    echo "    yamss: 0.0.0" >> versions.yml
    """
}


workflow BIOC_YAMSS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_YAMSS(ch_input)

    emit:
    results  = BIOC_YAMSS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_YAMSS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_YAMSS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_YAMSS.out.versions  // channel: path(versions.yml)
}
