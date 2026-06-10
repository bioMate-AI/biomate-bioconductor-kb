#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipqc — single_sample_chipseq_qc
// Assess quality metrics and generate diagnostic plots for a single ChIP-seq sample.
// Input: SRR568129.bam, SRR568129_chr22_peaks.bed
// Container: quay.io/biocontainers/bioconductor-chipqc:1.42.0--r44hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipqc:1.42.0--r44hdfd78af_0"

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
    .bm_deps <- c("ChIPQC")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(ChIPQC)
    
    # Define the input file paths in the working directory
    bam_file <- "SRR568129.bam"
    peak_file <- "SRR568129_chr22_peaks.bed"
    
    # Verify that the input files exist before proceeding
    if (!file.exists(bam_file)) {
      stop(paste("Required BAM file not found in the working directory:", bam_file))
    }
    if (!file.exists(peak_file)) {
      stop(paste("Required BED peak file not found in the working directory:", peak_file))
    }
    
    # 1. Construct a ChIPQCsample object for the single BAM file and its associated peak file
    # Using the exact function and argument names from the documented code
    CTCF1 = ChIPQCsample(bam_file, peaks=peak_file)
    
    # Display the object summary
    print(CTCF1)
    
    # Save the constructed ChIPQCsample object to an RDS file
    saveRDS(CTCF1, file = "CTCF1_ChIPQCsample.rds")
    
    # 2. Retrieve and display the primary quality metrics
    metrics <- QCmetrics(CTCF1)
    print(metrics)
    
    # Save the quality metrics to a CSV file
    # If metrics is a vector, convert it to a data frame first
    metrics_df <- as.data.frame(t(metrics))
    write.csv(metrics_df, file = "CTCF1_QCmetrics.csv", row.names = FALSE)
    
    # 3. Plot the cross-coverage score across successive strand shifts
    # Save the generated plot to a PDF file
    pdf("CTCF1_cross_coverage_plot.pdf", width = 7, height = 5)
    plotCC(CTCF1)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC":
        chipqc: \$(Rscript -e 'cat(as.character(packageVersion("chipqc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_chipseq_qc.csv versions.yml
    """
}

workflow BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SRR568129.bam, SRR568129_chr22_peaks.bed ] ]

    main:
    BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC(ch_input)

    emit:
    tables   = BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC.out.tables
    plots    = BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC.out.plots
    objects  = BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC.out.objects
    versions = BIOC_CHIPQC_SINGLE_SAMPLE_CHIPSEQ_QC.out.versions
}
