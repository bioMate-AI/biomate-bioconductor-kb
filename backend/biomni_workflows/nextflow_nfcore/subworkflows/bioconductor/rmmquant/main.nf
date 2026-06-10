#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmmquant — file_based_quantification
// Quantify gene expression directly from GTF annotation and BAM alignment files.
// Input: test.gtf, test.bam
// Container: quay.io/biocontainers/bioconductor-rmmquant:1.28.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rmmquant:1.28.0--r45ha27e39d_0"

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
    .bm_deps <- c("biocstyle", "deseq2", "rmmquant", "s4vectors", "summarizedexperiment", "tbx20bamsubset")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(Rmmquant)
    library(SummarizedExperiment)
    library(S4Vectors)
    
    # 1. Locate input files from the working directory
    gtfFile <- "test.gtf"
    bamFile <- "test.bam"
    
    # Verify that the input files exist before running
    if (!file.exists(gtfFile)) {
      stop(paste("Required GTF file not found in the working directory:", gtfFile))
    }
    if (!file.exists(bamFile)) {
      stop(paste("Required BAM file not found in the working directory:", bamFile))
    }
    
    # 2. Run quantification using RmmquantRun
    output <- RmmquantRun(gtfFile, bamFile)
    
    # 3. Extract count matrix
    counts_matrix <- assays(output)\$counts
    
    # 4. Extract mapping statistics
    mapping_stats <- colData(output)
    
    # 5. Write named output files for the results
    # Save the count matrix as a CSV file
    write.csv(as.matrix(counts_matrix), "gene_counts.csv", row.names = TRUE)
    
    # Save the mapping statistics as a CSV file
    write.csv(as.data.frame(mapping_stats), "mapping_statistics.csv", row.names = TRUE)
    
    # Save the complete SummarizedExperiment output object as an RDS file
    saveRDS(output, "rmmquant_output.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION":
        rmmquant: \$(Rscript -e 'cat(as.character(packageVersion("rmmquant")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_file_based_quantification.csv versions.yml
    """
}

workflow BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.gtf, test.bam ] ]

    main:
    BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.tables
    plots    = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.plots
    objects  = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.objects
    versions = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.versions
}
