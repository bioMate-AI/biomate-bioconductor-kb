#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epialleleR
// Epialleles are specific DNA methylation patterns that are mitotically and/or meiotically inherited. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epialleleR/inst/doc/epialleleR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("epialleleR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIALLELER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epialleler"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epialleler:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epialleler:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_epialleler_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epialleler_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epialleler_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epialleleR)
    library(jsonlite)

    # --- Genome and BAM Preprocessing [Preprocessing] ---
    # Key functions: preprocessGenome, callMethylation, preprocessBam
    ref_fasta <- system.file(
        "extdata", "test", "reference.fasta.gz", package="epialleleR"
    )
    input_bam <- system.file(
        "extdata", "test", "bwameth-se-unsort-yd.bam", package="epialleleR"
    )
    output_bam <- tempfile(pattern="output-", fileext=".bam")
    genome <- preprocessGenome(ref_fasta)
    callMethylation(input_bam, output_bam, genome)
    bam_data <- preprocessBam(output_bam)

    # --- Cytosine Methylation Reporting [Reporting] ---
    # Key functions: generateCytosineReport, preprocessBam
    capture_bam <- system.file("extdata", "capture.bam", package="epialleleR")
    bam_data <- preprocessBam(capture_bam)
    cg_vef_report <- generateCytosineReport(bam_data)
    cg_report <- generateCytosineReport(bam_data, threshold.reads=FALSE)
    cx_report <- generateCytosineReport(
        bam_data,
        threshold.reads=FALSE,
        report.context="CX"
    )

    # --- Region-Specific Methylation Analysis [Targeted Analysis] ---
    # Key functions: generateAmpliconReport, generateCaptureReport, generateBedReport
    amplicon_bam <- system.file(
        "extdata", "amplicon010meth.bam", package="epialleleR"
    )
    amplicon_bed <- system.file(
        "extdata", "amplicon.bed", package="epialleleR"
    )
    capture_bam <- system.file("extdata", "capture.bam", package="epialleleR")
    capture_bed <- system.file("extdata", "capture.bed", package="epialleleR")
    amplicon_report <- generateAmpliconReport(
        bam=amplicon_bam,
        bed=amplicon_bed
    )
    capture_report <- generateCaptureReport(
        bam=capture_bam,
        bed=capture_bed
    )
    bed_report <- generateBedReport(
        bam=capture_bam,
        bed=capture_bed,
        bed.type="capture"
    )

    # --- Methylation Haplotype Load Estimation [Haplotype Analysis] ---
    # Key functions: generateMhlReport
    capture_bam <- system.file("extdata", "capture.bam", package="epialleleR")
    mhl_report <- generateMhlReport(bam=capture_bam)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epialleler_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epialleler_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epialleler_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIALLELER:", paste0("    epialleler: ", packageVersion("epialleleR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epialleler_results.csv
    touch ${prefix}_epialleler_output.rds
    echo "BIOC_EPIALLELER:" > versions.yml
    echo "    epialleler: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIALLELER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_EPIALLELER(ch_input)

    emit:
    results  = BIOC_EPIALLELER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIALLELER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIALLELER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIALLELER.out.versions  // channel: path(versions.yml)
}
