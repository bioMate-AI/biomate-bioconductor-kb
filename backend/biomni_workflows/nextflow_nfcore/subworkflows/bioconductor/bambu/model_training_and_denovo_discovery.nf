#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bambu — model_training_and_denovo_discovery
// Train a custom transcript discovery model on an annotated dataset and apply it to another sample (such as a poorly annotated or de-novo species) for transcript 
// Input: sample1.bam, annotations, fa.file, sample2.bam, fa.file2
// Container: quay.io/biocontainers/bioconductor-bambu:3.12.1--r45ha27e39d_1
// R packages: bambu
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-bambu:3.12.1--r45ha27e39d_1"

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
    
    
    library(SummarizedExperiment)
    library(bambu)
    
    # Define input files exactly as specified
    sample1.bam <- "sample1.bam"
    annotations_file <- "annotations"
    fa.file <- "fa.file"
    sample2.bam <- "sample2.bam"
    fa.file2 <- "fa.file2"
    
    # Prepare annotations from the input file
    annotations <- prepareAnnotations(annotations_file)
    
    # --- Train the model on the annotated sample using bambu with ---
    se = bambu(reads = sample1.bam, annotations = annotations, genome = fa.file, discovery = FALSE, quant = FALSE, opt.discovery = list(returnModel = TRUE))
    newDefaultModel = metadata(se[[1]])\$model
    
    # Save the intermediate rcFile to RDS to demonstrate the trainBambu workflow
    pathToRcFile <- "rcFile.rds"
    saveRDS(se[[1]], file = pathToRcFile)
    
    # Alternatively train the model using an rcFile
    rcFile <- readRDS(pathToRcFile)
    newDefaultModel = trainBambu(rcFile)
    
    # --- Run bambu on the target sample with annotations = NULL, ---
    se <- bambu(reads = sample2.bam, annotations = NULL, genome = fa.file2, opt.discovery = list(defaultModels = newDefaultModel, fitReadClassModel = FALSE))
    
    # Write outputs
    writeBambuOutput(se, path = ".", prefix = "target_sample_")
    writeToGTF(rowRanges(se), file = "target_sample_extended_annotations.gtf")
    saveRDS(se, file = "target_sample_se.rds")
    saveRDS(newDefaultModel, file = "trained_bambu_model.rds")

    writeLines(c(
        '"BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY":',
        paste0('        bambu: ', as.character(packageVersion("bambu")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_model_training_and_denovo_discovery.csv versions.yml
    """
}

workflow BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample1.bam, annotations, fa.file, sample2.bam, fa.file2 ] ]

    main:
    BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY.out.tables
    plots    = BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY.out.plots
    objects  = BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY.out.objects
    versions = BIOC_BAMBU_MODEL_TRAINING_AND_DENOVO_DISCOVERY.out.versions
}
