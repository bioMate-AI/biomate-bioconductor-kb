#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scruff — tenx_bam_qc
// Collect and visualize QC metrics from 10X Cell Ranger BAM files.
// Input: cell_ranger_output.bam, filtered_barcodes.tsv
// Container: quay.io/biocontainers/bioconductor-scruff:1.28.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRUFF_TENX_BAM_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-scruff:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("SingleCellExperiment", "ggplot2", "scruff")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(scruff)
    library(SingleCellExperiment)
    library(ggplot2)
    
    # Define user input files from the working directory
    bamfile10x <- "cell_ranger_output.bam"
    filteredBc <- "filtered_barcodes.tsv"
    
    # Verify that the required input files exist before proceeding
    if (!file.exists(bamfile10x)) {
        stop(paste("Required input BAM file not found:", bamfile10x))
    }
    if (!file.exists(filteredBc)) {
        stop(paste("Required input barcodes TSV file not found:", filteredBc))
    }
    
    # Stage 1: Run tenxBamqc to collect QC metrics
    message("Running tenxBamqc on input BAM file...")
    sce <- tenxBamqc(bam = bamfile10x, experiment = "Neurons_Sample_01", filter = filteredBc)
    
    # Stage 2: Plot QC metrics using qcplots
    message("Generating QC plots...")
    g <- qcplots(sce)
    
    # Save meaningful results to output files
    message("Saving output files...")
    
    # 1. Save the SingleCellExperiment object
    saveRDS(sce, file = "tenx_qc_sce.rds")
    
    # 2. Export the QC metrics table as a CSV file
    qc_metrics <- as.data.frame(SummarizedExperiment::colData(sce))
    write.csv(qc_metrics, file = "tenx_qc_metrics.csv", row.names = TRUE)
    
    # 3. Save the QC plots as a PDF file
    pdf("tenx_qc_plots.pdf", width = 11, height = 8.5)
    print(g)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: 'tenx_qc_sce.rds', 'tenx_qc_metrics.csv', 'tenx_qc_plots.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCRUFF_TENX_BAM_QC":
        scruff: \$(Rscript -e 'cat(as.character(packageVersion("scruff")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tenx_bam_qc.csv versions.yml
    """
}

workflow BIOC_SCRUFF_TENX_BAM_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cell_ranger_output.bam, filtered_barcodes.tsv ] ]

    main:
    BIOC_SCRUFF_TENX_BAM_QC(ch_input)

    emit:
    tables   = BIOC_SCRUFF_TENX_BAM_QC.out.tables
    plots    = BIOC_SCRUFF_TENX_BAM_QC.out.plots
    objects  = BIOC_SCRUFF_TENX_BAM_QC.out.objects
    versions = BIOC_SCRUFF_TENX_BAM_QC.out.versions
}
