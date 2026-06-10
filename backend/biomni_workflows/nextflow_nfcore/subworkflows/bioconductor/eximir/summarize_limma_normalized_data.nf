#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ExiMiR — summarize_limma_normalized_data
// Summarize a MAList object normalized using limma methods by converting it to an AffyBatch and applying probe summarization.
// Input: RGList
// Container: quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0
// Requires: ExiMiR, affy, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize within and between arrays using limma
//  * 2. [Core Analysis] Convert MAList to AffyBatch using createAB
//  * 3. [Visualization & Output] Summarize probes using summarize.miR

nextflow.enable.dsl = 2

process BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA {
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
    .bm_deps <- c("ExiMiR", "affy", "limma")
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
    library(limma)
    library(ExiMiR)
    library(affy)
    
    # Define input file path
    input_file <- "RGList.rds"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    # Read the user input RGList object
    RGList <- readRDS(input_file)
    
    # Validate that the input is indeed an RGList
    if (!inherits(RGList, "RGList")) {
      stop("Error: The input file does not contain a valid limma RGList object.")
    }
    
    # 1. Normalize within and between arrays using limma
    MAList.tmp <- normalizeWithinArrays(RGList, method='loess')
    MAList <- normalizeBetweenArrays(MAList.tmp, method='Rquantile')
    
    # 2. Convert MAList to AffyBatch using createAB
    obatch <- createAB(MAList)
    
    # 3. Summarize probes using summarize.miR
    oset.rrma <- summarize.miR(obatch, summary.method='medianpolish')
    
    # Save the meaningful results
    # Save the complete ExpressionSet object as an RDS file
    saveRDS(oset.rrma, file = "oset_rrma.rds")
    
    # Extract and save the normalized, summarized expression matrix as a CSV file
    expression_matrix <- exprs(oset.rrma)
    write.csv(expression_matrix, file = "normalized_summarized_expression.csv", row.names = TRUE)
    
    cat("Pipeline completed successfully. Outputs saved to 'oset_rrma.rds' and 'normalized_summarized_expression.csv'.\n")

    writeLines(c(
        '"BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA":',
        paste0('    ExiMiR: ', as.character(packageVersion('ExiMiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarize_limma_normalized_data.csv versions.yml
    """
}

workflow BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RGList ] ]

    main:
    BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA(ch_input)

    emit:
    tables   = BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA.out.tables
    plots    = BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA.out.plots
    objects  = BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA.out.objects
    versions = BIOC_EXIMIR_SUMMARIZE_LIMMA_NORMALIZED_DATA.out.versions
}
