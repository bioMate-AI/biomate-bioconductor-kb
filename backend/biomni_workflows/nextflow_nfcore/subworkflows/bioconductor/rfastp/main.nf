#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rfastp
// Rfastp is an R wrapper of fastp developed in c++. fastp performs quality control for fastq files. in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rfastp/inst/doc/Rfastp.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Rfastp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RFASTP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rfastp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rfastp:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rfastp:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rfastp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rfastp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rfastp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rfastp)
    library(jsonlite)

    # --- rfastp [] ---
    # Key functions: rfastp, catfastq, qcSummary, curvePlot, trimSummary
    umi_json_report <- rfastp(read1 = pe_read1, read2 = pe_read2,
    outputFastq = paste0(outputPrefix, '_umi2'), umi = TRUE, umiLoc = "read1",
    clipr_json_report <- rfastp(read1 = se_read1,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rfastp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rfastp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rfastp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RFASTP:", paste0("    rfastp: ", packageVersion("Rfastp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rfastp_results.csv
    touch ${prefix}_rfastp_output.rds
    echo "BIOC_RFASTP:" > versions.yml
    echo "    rfastp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RFASTP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RFASTP(ch_input)

    emit:
    results  = BIOC_RFASTP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RFASTP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RFASTP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RFASTP.out.versions  // channel: path(versions.yml)
}
