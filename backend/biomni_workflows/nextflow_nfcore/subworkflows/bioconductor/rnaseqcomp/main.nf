#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rnaseqcomp
// Several quantitative and visualized benchmarks for RNA-seq quantification pipelines. Two-condition q
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rnaseqcomp/inst/doc/rnaseqcomp.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rnaseqcomp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNASEQCOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnaseqcomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnaseqcomp:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnaseqcomp:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnaseqcomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnaseqcomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnaseqcomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rnaseqcomp)
    library(jsonlite)

    # --- markdown [] ---
    # Key functions: markdown
    BiocStyle::markdown()
    # --- rep [] ---
    # Key functions: rep
    condInfo <- factor(simdata$samp$condition)
    repInfo <- factor(simdata$samp$replicate)
    evaluationFeature <- rep(TRUE, nrow(simdata$meta))
    # --- signal Calibrate [] ---
    # Key functions: signalCalibrate, show

    # --- plot S D [] ---
    # Key functions: plotSD
    plotSD(dat,ylim=c(0,1.4))
    # --- plot N E [] ---
    # Key functions: plotNE
    plotNE(dat,xlim=c(0.5,1))
    # --- plot2 T X [] ---
    # Key functions: plot2TX
    plot2TX(dat,genes=simdata$meta$gene,ylim=c(0,0.6))
    # --- plot R O C [] ---
    # Key functions: plotROC
    plotROC(dat,simdata$meta$positive,simdata$meta$fcsign,ylim=c(0,0.8))
    # --- plot F C [] ---
    # Key functions: plotFC
    plotFC(dat,simdata$meta$positive,simdata$meta$fcsign,ylim=c(0,1.2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnaseqcomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnaseqcomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnaseqcomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNASEQCOMP:", paste0("    rnaseqcomp: ", packageVersion("rnaseqcomp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseqcomp_results.csv
    touch ${prefix}_rnaseqcomp_output.rds
    echo "BIOC_RNASEQCOMP:" > versions.yml
    echo "    rnaseqcomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNASEQCOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNASEQCOMP(ch_input)

    emit:
    results  = BIOC_RNASEQCOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNASEQCOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNASEQCOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNASEQCOMP.out.versions  // channel: path(versions.yml)
}
