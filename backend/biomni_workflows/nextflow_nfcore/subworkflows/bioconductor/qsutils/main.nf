#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QSutils
// Set of utility functions for viral quasispecies analysis with NGS data. Most functions are equally u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QSutils/inst/doc/QSUtils-Alignment.R
// Upstream  : Biostrings, ape, ggplot2, psych
// Downstream: none
//
// Install: BiocManager::install("QSutils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qsutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qsutils:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qsutils:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qsutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qsutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qsutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Collapse)
    library(CorrectGapsAndNs)
    library(DottedAlignment)
    library(FreqMat)
    library(GetQSData)
    library(IntersectStrandHpls)
    library(MutsTbl)
    library(ReadAmplSeqs)
    library(Recollapse)
    library(SortByMutations)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, scale_x_continuous, theme
    dplot <- data.frame(IC=GetInfProfile(lst$hseqs,lst$nr),
    pos=1:width(lst$hseqs)[1])
    ggplot(dplot, aes(x=pos, y=IC)) + geom_point() +
    # --- ReadAmplSeqs analysis [] ---
    # Key functions: ReadAmplSeqs, GetQSData, readDNAStringSet, Collapse, DottedAlignment, CorrectGapsAndNs, Recollapse, IntersectStrandHpls
    lstI <- IntersectStrandHpls(lstFW$nr,lstFW$hseqs,lstRV$nr,lstRV$hseqs)
    cat("FW and Rv total reads:",sum(lstFW$nr)+sum(lstRV$nr),"\n")
    cat("FW and Rv reads above thr:",sum(lstI$pFW)+sum(lstI$pRV),"\n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qsutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qsutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qsutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QSUTILS:", paste0("    qsutils: ", packageVersion("QSutils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qsutils_results.csv
    touch ${prefix}_qsutils_output.rds
    echo "BIOC_QSUTILS:" > versions.yml
    echo "    qsutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QSUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QSUTILS(ch_input)

    emit:
    results  = BIOC_QSUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QSUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QSUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QSUTILS.out.versions  // channel: path(versions.yml)
}
