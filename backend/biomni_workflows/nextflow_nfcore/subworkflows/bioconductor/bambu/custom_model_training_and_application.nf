#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bambu — custom_model_training_and_application
// Train a custom transcript discovery model on a well-annotated dataset and apply it to a poorly annotated or unannotated dataset.
// Input: sample1.bam, annotations, fa.file, sample2.bam, fa.file2
// Container: quay.io/biocontainers/bioconductor-bambu:3.12.1--r45ha27e39d_1
// R packages: bambu
// Bioconductor: 3.20 | R: 4.4
// Requires: bambu
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train the model on the annotated dataset using bambu with returnModel=TRUE
//  * 2. [Input & Preparation] Alternatively, train the model from an RDS read class file using trainBambu
//  * 3. [Core Analysis] Apply the trained model to the poorly annotated dataset using bambu with fitReadClassModel=FALSE

nextflow.enable.dsl = 2

process BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION {
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
    .bm_deps <- c("bambu", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(SummarizedExperiment)
    library(bambu)
    
    # Define input file paths from the working directory
    sample1.bam <- "sample1.bam"
    annotations_input <- "annotations"
    fa.file <- "fa.file"
    sample2.bam <- "sample2.bam"
    fa.file2 <- "fa.file2"
    
    # Prepare annotations from the user-provided annotations file
    # (Supports GTF, TxDb, or pre-prepared annotation RDS)
    if (grepl("\\\\.rds\$", annotations_input, ignore.case = TRUE)) {
      annotations <- readRDS(annotations_input)
    } else {
      annotations <- prepareAnnotations(annotations_input)
    }
    
    # Stage 1: Train the model on the annotated dataset using bambu with returnModel=TRUE
    # discovery and quant are set to FALSE to return the read class list
    se = bambu(
      reads = sample1.bam,
      annotations = annotations,
      genome = fa.file,
      discovery = FALSE,
      quant = FALSE,
      opt.discovery = list(returnModel = TRUE)
    )
    
    # Stage 2: Train the model from an RDS read class file using trainBambu
    # We save the read class object from the first step to a file to obtain pathToRcFile
    pathToRcFile <- "sample1_rc.rds"
    saveRDS(se[[1]], file = pathToRcFile)
    
    rcFile <- readRDS(pathToRcFile)
    newDefaultModel = trainBambu(rcFile)
    
    # Save the trained custom model
    saveRDS(newDefaultModel, file = "custom_trained_model.rds")
    
    # Stage 3: Apply the trained model to the poorly annotated dataset using bambu with fitReadClassModel=FALSE
    se <- bambu(
      reads = sample2.bam,
      annotations = NULL,
      genome = fa.file2,
      opt.discovery = list(defaultModels = newDefaultModel, fitReadClassModel = FALSE)
    )
    
    # Write meaningful output files
    # 1. Write transcript and gene expression estimates
    writeBambuOutput(se, path = ".", prefix = "sample2_bambu_output_")
    
    # 2. Export the extended annotations to a GTF file
    writeToGTF(rowRanges(se), file = "sample2_discovered_annotations.gtf")
    
    # 3. Save the final SummarizedExperiment object
    saveRDS(se, file = "sample2_se_output.rds")

    writeLines(c(
        '"BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION":',
        paste0('    bambu: ', as.character(packageVersion('bambu')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_model_training_and_application.csv versions.yml
    """
}

workflow BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample1.bam, annotations, fa.file, sample2.bam, fa.file2 ] ]

    main:
    BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION(ch_input)

    emit:
    tables   = BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION.out.tables
    plots    = BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION.out.plots
    objects  = BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION.out.objects
    versions = BIOC_BAMBU_CUSTOM_MODEL_TRAINING_AND_APPLICATION.out.versions
}
