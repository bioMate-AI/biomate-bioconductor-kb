#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ssviz
// Small RNA sequencing viewer
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ssviz/inst/doc/ssviz.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ssviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ssviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ssviz:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ssviz:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ssviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ssviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ssviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ssviz)
    library(jsonlite)

    # --- read Bam [] ---
    # Key functions: readBam
    bam.files<-dir(system.file("extdata", package="ssviz"), full=TRUE, patt="bam$")
    ctrlbam<-readBam(bam.files[1])
    treatbam<-readBam(bam.files[2])
    # --- plot Distro [] ---
    # Key functions: plotDistro
    plotDistro(list(ctrl.count), type="qwidth", samplenames=c("Control"), ncounts=counts[1])
    # --- plot Region [] ---
    # Key functions: plotRegion
    plotRegion(list(ctrl.count), region=region)
    # --- plot P P [] ---
    # Key functions: plotPP
    pp.ctrl<-pingpong(pctrlbam.count)
    plotPP(list(pp.ctrl), samplenames=c("Control"))
    # --- plot Freq [] ---
    # Key functions: plotFreq
    pctrlbam.count<-getCountMatrix(pctrlbam)
    freq.ctrl<-ntfreq(pctrlbam.count, ntlength=10)
    plotFreq(freq.ctrl)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ssviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ssviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ssviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SSVIZ:", paste0("    ssviz: ", packageVersion("ssviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ssviz_results.csv
    touch ${prefix}_ssviz_output.rds
    echo "BIOC_SSVIZ:" > versions.yml
    echo "    ssviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SSVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SSVIZ(ch_input)

    emit:
    results  = BIOC_SSVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SSVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SSVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SSVIZ.out.versions  // channel: path(versions.yml)
}
