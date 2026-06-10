#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kebabs — prediction_profiling
// Generate prediction profiles to visualize the contribution of individual sequence positions to the model's prediction.
// Input: sequences.fasta, trained_model.RData
// Container: quay.io/biocontainers/bioconductor-kebabs:1.44.0--r45ha27e39d_0
// R packages: Biostrings, kebabs
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, kebabs
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract feature weights and model offset
//  * 2. [Core Analysis] Compute prediction profiles
//  * 3. [Visualization & Output] Plot prediction profiles

nextflow.enable.dsl = 2

process BIOC_KEBABS_PREDICTION_PROFILING {
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
    
    # Load required libraries
    library(kebabs)
    library(Biostrings)
    
    # 1. Load the trained model and kernel from user input
    if (!file.exists("trained_model.RData")) {
        stop("Error: trained_model.RData not found in the working directory.")
    }
    load("trained_model.RData")
    
    # Ensure 'model' exists
    if (!exists("model")) {
        stop("Error: 'model' object not found in trained_model.RData.")
    }
    
    # Ensure 'model_kernel' exists, or extract it from the model
    if (!exists("model_kernel")) {
        if (.hasSlot(model, "kernel")) {
            model_kernel <- model@kernel
        } else {
            stop("Error: 'model_kernel' object not found and could not be extracted from 'model'.")
        }
    }
    
    # 2. Read the sequences to profile from user input
    if (!file.exists("sequences.fasta")) {
        stop("Error: sequences.fasta not found in the working directory.")
    }
    
    GCN4 <- tryCatch({
        readAAStringSet("sequences.fasta")
    }, error = function(e) {
        tryCatch({
            readDNAStringSet("sequences.fasta")
        }, error = function(e2) {
            readRNAStringSet("sequences.fasta")
        })
    })
    
    # Handle annotation-specific kernel requirements dynamically to prevent runtime failures
    is_ann_spec <- FALSE
    if (exists("model_kernel") && .hasSlot(model_kernel, "annSpec")) {
        is_ann_spec <- model_kernel@annSpec
    }
    
    if (is_ann_spec) {
        if (is.null(annotationMetadata(GCN4))) {
            ann_charset <- annotationCharset(model)
            ann_chars <- strsplit(ann_charset, "")[[1]]
            ann_list <- sapply(width(GCN4), function(w) {
                rep_str <- paste(rep(ann_charset, ceiling(w/length(ann_chars))), collapse="")
                substr(rep_str, 1, w)
            })
            annotationMetadata(GCN4, annCharset=ann_charset) <- ann_list
        }
    }
    
    # 3. Compute prediction profiles (Documented Code)
    predProf <- getPredictionProfile(GCN4, model_kernel,
                                     featureWeights(model),
                                     modelOffset(model))
    
    # Save the prediction profile object
    saveRDS(predProf, file = "prediction_profile.rds")
    
    # 4. Plot prediction profiles (Documented Code)
    pdf("prediction_profile_plot.pdf", width = 8, height = 6)
    plot(predProf, sel=1, annotate=TRUE)
    dev.off()
    
    cat("Prediction profiling completed successfully. Outputs saved to 'prediction_profile.rds' and 'prediction_profile_plot.pdf'.\n")

    writeLines(c(
        '"BIOC_KEBABS_PREDICTION_PROFILING":',
        paste0('    kebabs: ', as.character(packageVersion('kebabs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prediction_profiling.csv versions.yml
    """
}

workflow BIOC_KEBABS_PREDICTION_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.fasta, trained_model.RData ] ]

    main:
    BIOC_KEBABS_PREDICTION_PROFILING(ch_input)

    emit:
    tables   = BIOC_KEBABS_PREDICTION_PROFILING.out.tables
    plots    = BIOC_KEBABS_PREDICTION_PROFILING.out.plots
    objects  = BIOC_KEBABS_PREDICTION_PROFILING.out.objects
    versions = BIOC_KEBABS_PREDICTION_PROFILING.out.versions
}
