#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GAprediction
// [GAprediction] predicts gestational age using Illumina HumanMethylation450 CpG data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GAprediction/inst/doc/GAprediction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GAprediction")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GAPREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gaprediction"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gaprediction:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gaprediction:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gaprediction_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gaprediction_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gaprediction_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GAprediction)
    library(jsonlite)

    # --- extract Sites [] ---
    # Key functions: extractSites
    require(GAprediction)
    cpgs <- extractSites( type="se" )
    allcpgs <- extractSites( type="all" )
    # --- predict G A [] ---
    # Key functions: predictGA
    mypred <- predictGA( mlmatr )
    head( mypred )
    # --- extract Sites [] ---
    # Key functions: extractSites
    cpgs <- extractSites( type="se" )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gaprediction_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gaprediction_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gaprediction_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GAPREDICTION:", paste0("    gaprediction: ", packageVersion("GAprediction"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gaprediction_results.csv
    touch ${prefix}_gaprediction_output.rds
    echo "BIOC_GAPREDICTION:" > versions.yml
    echo "    gaprediction: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GAPREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GAPREDICTION(ch_input)

    emit:
    results  = BIOC_GAPREDICTION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GAPREDICTION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GAPREDICTION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GAPREDICTION.out.versions  // channel: path(versions.yml)
}
