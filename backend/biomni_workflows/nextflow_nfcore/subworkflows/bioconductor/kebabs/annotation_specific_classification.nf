#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kebabs — annotation_specific_classification
// Train a classifier that utilizes sequence annotations (e.g., exon/intron or heptad structures) aligned with the biological sequences.
// Input: sequences.fasta, annotations.txt, labels.txt
// Container: quay.io/biocontainers/bioconductor-kebabs:1.44.0--r45ha27e39d_0
// R packages: Biostrings, kebabs
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, kebabs
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Assign annotation metadata to sequences
//  * 2. [Input & Preparation] Define an annotation-specific kernel
//  * 3. [Core Analysis] Train the SVM model
//  * 4. [Core Analysis] Predict and evaluate

nextflow.enable.dsl = 2

process BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "kebabs")
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
        
    # Load required Bioconductor and CRAN libraries
    library(kebabs)
    library(Biostrings)
    
    # 1. Read User Inputs
    # Read biological sequences (auto-detect DNA, RNA, or AA to support various sequence types)
    ccseq <- tryCatch({
      readDNAStringSet("sequences.fasta")
    }, error = function(e) {
      tryCatch({
        readRNAStringSet("sequences.fasta")
      }, error = function(e) {
        readAAStringSet("sequences.fasta")
      })
    })
    
    # Read annotations (character strings of identical length to sequences)
    ccannot <- readLines("annotations.txt")
    
    # Read class labels and convert to numeric as expected by the workflow
    yCC <- as.numeric(readLines("labels.txt"))
    
    # 2. Setup Train/Test Split
    set.seed(42)
    numSamples <- length(ccseq)
    train_fraction <- 0.8
    train <- sample(1:numSamples, round(train_fraction * numSamples))
    test <- setdiff(1:numSamples, train)
    
    # 3. Documented Workflow (reproduced exactly as documented)
    # Dynamically determine the annotation charset from the provided annotations
    annCharset <- paste(unique(unlist(strsplit(ccannot, ""))), collapse="")
    annotationMetadata(ccseq, annCharset=annCharset) <- ccannot
    
    gappya <- gappyPairKernel(k=1, m=10, annSpec=TRUE)
    model <- kbsvm(ccseq[train], y=yCC[train], kernel=gappya,
                   pkg="LiblineaR", svm="C-svc", cost=100)
    pred <- predict(model, ccseq[test])
    
    # Capture the evaluation output to a file while keeping the exact function call
    sink("evaluation_report.txt")
    evaluatePrediction(pred, yCC[test], allLabels=unique(yCC))
    sink()
    
    # 4. Write Named Output Files
    # Save the trained model object
    saveRDS(model, "trained_model.rds")
    
    # Save predictions and true labels to a CSV file
    predictions_df <- data.frame(
      Sequence_Index = test,
      True_Label = yCC[test],
      Predicted_Label = as.vector(pred)
    )
    write.csv(predictions_df, "predictions.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION":',
        paste0('    kebabs: ', as.character(packageVersion('kebabs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotation_specific_classification.csv versions.yml
    """
}

workflow BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.fasta, annotations.txt, labels.txt ] ]

    main:
    BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION.out.tables
    plots    = BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION.out.plots
    objects  = BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION.out.objects
    versions = BIOC_KEBABS_ANNOTATION_SPECIFIC_CLASSIFICATION.out.versions
}
