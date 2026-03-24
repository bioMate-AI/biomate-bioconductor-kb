#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CGHcall
// Calls aberrations for array CGH data using a six state mixture model as well as several biological c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CGHcall/inst/doc/CGHcall.R
// Upstream  : none
// Downstream: CGHnormaliter, GeneBreak
//
// Install: BiocManager::install("CGHcall")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CGHCALL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cghcall"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cghcall:2.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cghcall:2.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cghcall_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cghcall_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cghcall_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExpandCGHcall)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: make_cghRaw
    library(CGHcall)
    data(Wilting)
    Wilting <- make_cghRaw(Wilting)
    # --- Preprocess [] ---
    # Key functions: preprocess
    cghdata <- preprocess(Wilting, maxmiss=30, nchrom=22)
    # --- Normalize [] ---
    # Key functions: normalize
    norm.cghdata <- normalize(cghdata, method="median", smoothOutliers=TRUE)
    # --- Segmentdata [] ---
    # Key functions: segmentData
    norm.cghdata <- norm.cghdata[,1:2]
    seg.cghdata <- segmentData(norm.cghdata, method="DNAcopy",undo.splits="sdundo",undo.SD=3,
    clen=10, relSDlong=5)
    # --- Postsegnormalize [] ---
    # Key functions: postsegnormalize
    postseg.cghdata <- postsegnormalize(seg.cghdata)
    # --- Expandcghcall [] ---
    # Key functions: ExpandCGHcall
    result <- ExpandCGHcall(result,postseg.cghdata)
    # --- Frequencyplotcalls [] ---
    # Key functions: frequencyPlotCalls
    frequencyPlotCalls(result)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cghcall_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cghcall_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cghcall_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CGHCALL:", paste0("    cghcall: ", packageVersion("CGHcall"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cghcall_results.csv
    touch ${prefix}_cghcall_output.rds
    echo "BIOC_CGHCALL:" > versions.yml
    echo "    cghcall: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CGHCALL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CGHCALL(ch_input)

    emit:
    results  = BIOC_CGHCALL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CGHCALL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CGHCALL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CGHCALL.out.versions  // channel: path(versions.yml)
}
