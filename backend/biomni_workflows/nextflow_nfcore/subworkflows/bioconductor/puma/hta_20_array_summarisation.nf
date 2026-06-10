#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: puma — hta_20_array_summarisation
// Calculate gene and transcript expression levels and standard errors from Affymetrix HTA 2.0 arrays.
// Input: celFiles
// Container: quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0
// Requires: oligo, puma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read CEL files using oligo
//  * 2. [Visualization & Output] Summarise to gene and transcript levels using gmhta
//  * 3. [Core Analysis] Extract expression and standard error values
//  * 4. [Visualization & Output] Export results using write.reslts

nextflow.enable.dsl = 2

process BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION {
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
    .bm_deps <- c("oligo", "puma")
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
    library(oligo)
    library(puma)
    
    # 1. Read CEL files from the working directory
    # The pipeline expects Affymetrix HTA 2.0 CEL files in the current working directory.
    celFiles <- oligo::list.celfiles(full.names = TRUE)
    
    if (length(celFiles) == 0) {
      stop("Error: No CEL files found in the working directory. Please place Affymetrix HTA 2.0 CEL files here.")
    }
    
    message("Found ", length(celFiles), " CEL files. Proceeding with reading...")
    oligo.hta <- read.celfiles(celFiles)
    
    # 2. Summarise to gene and transcript levels using gmhta
    message("Running gmhta summarisation (this may take some time)...")
    eset_gmhta <- gmhta(oligo.hta, gsnorm="none")
    
    # 3. Extract and display expression and standard error values
    message("Extracting expression and standard error values...")
    
    # Gene level
    if (nrow(exprs(eset_gmhta\$gene)) >= 2) {
      cat("Gene expression (row 2):\n")
      print(exprs(eset_gmhta\$gene)[2,])
      cat("Gene standard error (row 2):\n")
      print(se.exprs(eset_gmhta\$gene)[2,])
    } else {
      cat("Gene expression (all rows):\n")
      print(exprs(eset_gmhta\$gene))
      cat("Gene standard error (all rows):\n")
      print(se.exprs(eset_gmhta\$gene))
    }
    
    # Transcript level
    if (nrow(exprs(eset_gmhta\$transcript)) >= 2) {
      cat("Transcript expression (row 2):\n")
      print(exprs(eset_gmhta\$transcript)[2,])
      cat("Transcript standard error (row 2):\n")
      print(se.exprs(eset_gmhta\$transcript)[2,])
    } else {
      cat("Transcript expression (all rows):\n")
      print(exprs(eset_gmhta\$transcript))
      cat("Transcript standard error (all rows):\n")
      print(se.exprs(eset_gmhta\$transcript))
    }
    
    # 4. Export results using write.reslts
    message("Writing results to CSV files...")
    write.reslts(eset_gmhta\$gene, file="eset_gmhta_gene")
    write.reslts(eset_gmhta\$transcript, file="eset_gmhta_transcript")
    
    # Save the complete ExpressionSet list object as an RDS file for downstream R analyses
    saveRDS(eset_gmhta, file="eset_gmhta.rds")
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION":',
        paste0('    puma: ', as.character(packageVersion('puma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hta_20_array_summarisation.csv versions.yml
    """
}

workflow BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celFiles ] ]

    main:
    BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION(ch_input)

    emit:
    tables   = BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION.out.tables
    plots    = BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION.out.plots
    objects  = BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION.out.objects
    versions = BIOC_PUMA_HTA_20_ARRAY_SUMMARISATION.out.versions
}
