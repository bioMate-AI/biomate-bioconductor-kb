#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TargetDecoy
// A first step in the data analysis of Mass Spectrometry (MS) based proteomics data is to identify pep
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TargetDecoy/inst/doc/TargetDecoy.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("TargetDecoy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TARGETDECOY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-targetdecoy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-targetdecoy:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-targetdecoy:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_targetdecoy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_targetdecoy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_targetdecoy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TargetDecoy)
    library(jsonlite)

    # --- Data Loading Examples [] ---
    # Key functions: mzID, openIDfile
    filename <- system.file("extdata/55merge_omssa.mzid", package = "mzID")
    ## mzID
    mzID_object <- mzID::mzID(filename)
    class(mzID_object)
    ## mzRIdent
    # --- Example1.1 Data [] ---
    # Key functions: data
    ## Load the example SwissProt dataset
    data("ModSwiss")
    # --- Evaltargetdecoys Plot [] ---
    # Key functions: evalTargetDecoys
    evalTargetDecoys(ModSwiss,
        decoy = "isdecoy", score = "ms-gf:specevalue",
        log10 = TRUE, nBins = 50
    )
    # --- Reproduce3 [] ---
    # Key functions: session_info
    options(width = 120)
    sessioninfo::session_info()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_targetdecoy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_targetdecoy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_targetdecoy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TARGETDECOY:", paste0("    targetdecoy: ", packageVersion("TargetDecoy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_targetdecoy_results.csv
    touch ${prefix}_targetdecoy_output.rds
    echo "BIOC_TARGETDECOY:" > versions.yml
    echo "    targetdecoy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TARGETDECOY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TARGETDECOY(ch_input)

    emit:
    results  = BIOC_TARGETDECOY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TARGETDECOY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TARGETDECOY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TARGETDECOY.out.versions  // channel: path(versions.yml)
}
