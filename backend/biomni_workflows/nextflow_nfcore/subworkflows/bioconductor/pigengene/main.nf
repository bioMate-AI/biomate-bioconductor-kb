#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Pigengene — one_step_pipeline
// Run the entire Pigengene pipeline in a single function call to get eigengenes and decision trees.
// Input: expression_matrix.csv, sample_labels.csv
// Container: quay.io/biocontainers/bioconductor-pigengene:1.32.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Pigengene
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and format labels
//  * 2. [Core Analysis] Run the one-step Pigengene pipeline using one.step.pigengene
//  * 3. [Visualization & Output] Plot the resulting decision tree and eigengene heatmap

nextflow.enable.dsl = 2

process BIOC_PIGENGENE_ONE_STEP_PIPELINE {
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
    .bm_deps <- c("Pigengene")
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
        
    library(Pigengene)
    
    # 1. Load data and format labels from user input files
    d1 <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    d1 <- as.matrix(d1)
    
    labels_data <- read.csv("sample_labels.csv", stringsAsFactors = FALSE)
    if (ncol(labels_data) >= 2) {
      Labels <- as.character(labels_data[[2]])
      names(Labels) <- as.character(labels_data[[1]])
    } else {
      Labels <- as.character(labels_data[[1]])
      names(Labels) <- rownames(d1)
    }
    
    Disease <- as.data.frame(Labels)
    rownames(Disease) <- names(Labels)
    
    # Plot and save heatmap of raw data subset
    pdf("heatmap_raw_subset.pdf")
    h1 <- pheatmap.type(d1[, 1:min(20, ncol(d1))], annRow=Disease, show_rownames=FALSE)
    dev.off()
    
    # 2. Run the one-step Pigengene pipeline
    p1 <- one.step.pigengene(Data=d1,saveDir='pigengene', bnNum=0, verbose=1,
          seed=1, Labels=Labels, toCompact=FALSE, doHeat=FALSE)
    
    # Save intermediate outputs before p1 is overwritten
    write.csv(p1\$pigengene\$eigengenes, "eigengenes.csv", row.names = TRUE)
    saveRDS(p1, "pigengene_output.rds")
    
    # 3. Plot the resulting decision tree and eigengene heatmap
    pdf("decision_tree.pdf")
    # Ensure "34" exists in the list to prevent subscript out of bounds on custom data
    if (!"34" %in% names(p1\$c5treeRes\$c5Trees) && length(p1\$c5treeRes\$c5Trees) > 0) {
      p1\$c5treeRes\$c5Trees[["34"]] <- p1\$c5treeRes\$c5Trees[[1]]
    }
    plot(p1\$c5treeRes\$c5Trees[["34"]])
    dev.off()
    
    dim(p1\$pigengene\$eigengenes)
    
    pdf("heatmap_eigengenes.pdf")
    p1 <- pheatmap.type(p1\$pigengene\$eigengenes,annRow=Disease,show_rownames=FALSE)
    dev.off()

    writeLines(c(
        '"BIOC_PIGENGENE_ONE_STEP_PIPELINE":',
        paste0('    Pigengene: ', as.character(packageVersion('Pigengene')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_pipeline.csv versions.yml
    """
}

workflow BIOC_PIGENGENE_ONE_STEP_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_labels.csv ] ]

    main:
    BIOC_PIGENGENE_ONE_STEP_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PIGENGENE_ONE_STEP_PIPELINE.out.tables
    plots    = BIOC_PIGENGENE_ONE_STEP_PIPELINE.out.plots
    objects  = BIOC_PIGENGENE_ONE_STEP_PIPELINE.out.objects
    versions = BIOC_PIGENGENE_ONE_STEP_PIPELINE.out.versions
}
