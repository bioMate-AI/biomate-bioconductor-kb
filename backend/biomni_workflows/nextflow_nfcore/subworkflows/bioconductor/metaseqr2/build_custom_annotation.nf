#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaseqR2 — build_custom_annotation
// Import custom genome annotations from a GTF file and metadata into the local SQLite database.
// Input: Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz, bamForInfo
// Container: quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0
// Requires: metaseqR2
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare GTF file and chromosome metadata
//  * 2. [Input & Preparation] Build custom annotation using buildCustomAnnotation
//  * 3. [Core Analysis] Retrieve the custom annotation using loadAnnotation

nextflow.enable.dsl = 2

process BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("metaseqR2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(metaseqR2)
    
    # Define directories and database path
    # The user input files are expected to be in the current working directory
    customDir <- "."
    myDb <- "custom_annotation.sqlite"
    
    # Define the BAM file for chromosome info (provided as user input in the working directory)
    bamForInfo <- "bamForInfo"
    
    # Step 1 & 2: Build custom annotation using buildCustomAnnotation
    # The GTF file "Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz" is read from the working directory
    buildCustomAnnotation(
        gtfFile=file.path(customDir,"Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz"),
        metadata=list(
            organism="dasNov3_test",
            source="ensembl_test",
            chromInfo=bamForInfo
        ),
        db=myDb
    )
    
    # Step 3: Retrieve the custom annotation using loadAnnotation
    dasGenes <- loadAnnotation(genome="dasNov3_test",refdb="ensembl_test",
        level="gene",type="gene",db=myDb)
    
    # Print retrieved annotation to console
    print(dasGenes)
    
    # Save the retrieved annotation to output files
    # Save as RDS object
    saveRDS(dasGenes, file="dasGenes.rds")
    
    # Save as CSV table
    write.csv(as.data.frame(dasGenes), file="dasGenes.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION":',
        paste0('    metaseqR2: ', as.character(packageVersion('metaseqR2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_build_custom_annotation.csv versions.yml
    """
}

workflow BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz, bamForInfo ] ]

    main:
    BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION.out.tables
    plots    = BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION.out.plots
    objects  = BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION.out.objects
    versions = BIOC_METASEQR2_BUILD_CUSTOM_ANNOTATION.out.versions
}
