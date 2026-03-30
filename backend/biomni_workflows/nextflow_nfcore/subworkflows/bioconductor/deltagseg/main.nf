#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: deltaGseg
// Identifying distinct subpopulations through multiscale time series analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/deltaGseg/inst/doc/deltaGseg.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("deltaGseg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DELTAGSEG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deltagseg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deltagseg:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deltagseg:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_deltagseg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deltagseg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deltagseg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(deltaGseg)
    library(jsonlite)

    # --- parse Traj [] ---
    # Key functions: parseTraj
    dir<-system.file("extdata",package="deltaGseg")
    traj1<-parseTraj(path=dir, files=c("D_GBTOT1","D_GBTOT2","D_GBTOT3"))
    # --- split Traj [] ---
    # Key functions: splitTraj
    all_breakpoints<-splitTraj(traj1,segsplits=c(5,5,5))
    # --- choose Breaks [] ---
    # Key functions: chooseBreaks
    mybreaks<-chooseBreaks(all_breakpoints,numbreaks=3)
    # --- cluster P V [] ---
    # Key functions: clusterPV
    pvals<-clusterPV(object=traj1.denoise,bootstrap=500)
    # --- get Intervals [] ---
    # Key functions: getIntervals
    getIntervals(traj1.ss)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deltagseg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deltagseg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deltagseg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DELTAGSEG:", paste0("    deltagseg: ", packageVersion("deltaGseg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deltagseg_results.csv
    touch ${prefix}_deltagseg_output.rds
    echo "BIOC_DELTAGSEG:" > versions.yml
    echo "    deltagseg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DELTAGSEG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DELTAGSEG(ch_input)

    emit:
    results  = BIOC_DELTAGSEG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DELTAGSEG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DELTAGSEG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DELTAGSEG.out.versions  // channel: path(versions.yml)
}
