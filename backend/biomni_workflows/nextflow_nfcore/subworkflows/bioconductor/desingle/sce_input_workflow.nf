#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEsingle — sce_input_workflow
// Detect and classify differentially expressed genes between two groups of cells using a SingleCellExperiment object.
// Input: sce.ext, group.ext
// Container: quay.io/biocontainers/bioconductor-desingle:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEsingle, SingleCellExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the packages and data
//  * 2. [Core Analysis] Convert raw counts to a SingleCellExperiment object
//  * 3. [Core Analysis] Specify the two groups to be compared as a factor vector
//  * 4. [Core Analysis] Detect DE genes using DEsingle() with the SingleCellExperiment object
//  * 5. [Core Analysis] Classify DE genes into three categories using DEtype()

nextflow.enable.dsl = 2

process BIOC_DESINGLE_SCE_INPUT_WORKFLOW {
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
    .bm_deps <- c("DEsingle")
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
    
    # 1. Load the packages and data
    library(DEsingle)
    
    # Read the user input files from the working directory
    sce <- readRDS("sce.ext")
    group <- readRDS("group.ext")
    
    # 2. Convert raw counts to a SingleCellExperiment object
    # (If the input is already a SingleCellExperiment, we use it directly.
    # If it is a matrix, we convert it to a SingleCellExperiment object as documented.)
    if (!inherits(sce, "SingleCellExperiment")) {
      sce <- SingleCellExperiment(assays = list(counts = as.matrix(sce)))
    }
    
    # 3. Specify the two groups to be compared as a factor vector
    if (!is.factor(group)) {
      group <- factor(group)
    }
    
    # 4. Detect DE genes using DEsingle() with the SingleCellExperiment object
    results <- DEsingle(counts = sce, group = group)
    
    # 5. Classify DE genes into three categories using DEtype()
    results.classified <- DEtype(results = results, threshold = 0.05)
    
    # Save the complete classified results
    saveRDS(results, file = "desingle_results.rds")
    saveRDS(results.classified, file = "results_classified.rds")
    write.csv(results.classified, file = "results_classified.csv", row.names = TRUE)
    
    # Extract and save significant DE genes at threshold of FDR < 0.05
    results.sig <- results.classified[results.classified\$pvalue.adj.FDR < 0.05, ]
    write.csv(results.sig, file = "significant_de_genes.csv", row.names = TRUE)
    
    # Extract and save the three types of DE genes separately
    results.DEs <- results.sig[results.sig\$Type == "DEs", ]
    results.DEa <- results.sig[results.sig\$Type == "DEa", ]
    results.DEg <- results.sig[results.sig\$Type == "DEg", ]
    
    write.csv(results.DEs, file = "results_DEs.csv", row.names = TRUE)
    write.csv(results.DEa, file = "results_DEa.csv", row.names = TRUE)
    write.csv(results.DEg, file = "results_DEg.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_DESINGLE_SCE_INPUT_WORKFLOW":',
        paste0('    DEsingle: ', as.character(packageVersion('DEsingle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sce_input_workflow.csv versions.yml
    """
}

workflow BIOC_DESINGLE_SCE_INPUT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.ext, group.ext ] ]

    main:
    BIOC_DESINGLE_SCE_INPUT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DESINGLE_SCE_INPUT_WORKFLOW.out.tables
    plots    = BIOC_DESINGLE_SCE_INPUT_WORKFLOW.out.plots
    objects  = BIOC_DESINGLE_SCE_INPUT_WORKFLOW.out.objects
    versions = BIOC_DESINGLE_SCE_INPUT_WORKFLOW.out.versions
}
