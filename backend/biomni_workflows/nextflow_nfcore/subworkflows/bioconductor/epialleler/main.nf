#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleler — short_read_methylation_analysis
// Preprocess short-read BAM files and generate cytosine-level or region-level (BED/capture) methylation reports.
// Input: capture.bam, capture.bed
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("epialleler")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(epialleleR)
    
    # Define user input files from the working directory
    capture.bam <- "capture.bam"
    capture.bed <- "capture.bed"
    
    # 1. Preprocess BAM file using preprocessBam with target regions
    bam.data <- preprocessBam(capture.bam, targets=capture.bed)
    
    # 2. Generate cytosine-level VEF report using generateCytosineReport
    generateCytosineReport(bam.data)
    cg.vef.report <- generateCytosineReport(bam.data)
    
    # 3. Generate conventional cytosine report (beta values) by setting threshold.reads=FALSE
    cg.report <- generateCytosineReport(bam.data, threshold.reads=FALSE)
    cx.report <- generateCytosineReport(bam.data, threshold.reads=FALSE, report.context="CX")
    
    # 4. Generate region-level capture report using generateCaptureReport or generateBedReport
    capture.report <- generateCaptureReport(bam=capture.bam, bed=capture.bed)
    bed.report <- generateBedReport(bam=capture.bam, bed=capture.bed, bed.type="capture")
    
    # 5. Generate linearized Methylated Haplotype Load (lMHL) report using generateMhlReport
    mhl.report <- generateMhlReport(bam=capture.bam)
    
    # Write outputs to the working directory
    write.csv(cg.vef.report, file="cg_vef_report.csv", row.names=FALSE)
    write.csv(cg.report, file="cg_report.csv", row.names=FALSE)
    write.csv(cx.report, file="cx_report.csv", row.names=FALSE)
    write.csv(capture.report, file="capture_report.csv", row.names=FALSE)
    write.csv(bed.report, file="bed_report.csv", row.names=FALSE)
    write.csv(mhl.report, file="mhl_report.csv", row.names=FALSE)
    
    # Save preprocessed BAM data object for potential downstream analysis
    saveRDS(bam.data, file="preprocessed_bam_data.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS":
        epialleler: \$(Rscript -e 'cat(as.character(packageVersion("epialleler")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_short_read_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ capture.bam, capture.bed ] ]

    main:
    BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_EPIALLELER_SHORT_READ_METHYLATION_ANALYSIS.out.versions
}
