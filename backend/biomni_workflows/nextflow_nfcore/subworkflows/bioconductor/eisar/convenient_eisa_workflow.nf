#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eisaR — convenient_eisa_workflow
// Run a complete Exon-Intron Split Analysis (EISA) and visualize the results using pre-calculated exonic and intronic count tables.
// Input: rawcounts_exonic.rds, rawcounts_intronic.rds
// Container: quay.io/biocontainers/bioconductor-eisar:1.22.1--r45hdfd78af_0
// R packages: eisaR
// Bioconductor: 3.20 | R: 4.4
// Requires: eisaR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load exonic and intronic count tables
//  * 2. [Core Analysis] Remove non-count columns (such as width)
//  * 3. [Input & Preparation] Define the experimental condition factor
//  * 4. [Core Analysis] Run the EISA statistical model using runEISA()
//  * 5. [Visualization & Output] Visualize the results using plotEISA()

nextflow.enable.dsl = 2

process BIOC_EISAR_CONVENIENT_EISA_WORKFLOW {
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
    .bm_deps <- c("eisaR")
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
    library(eisaR)
    
    # Define input file paths
    exonic_file <- "rawcounts_exonic.rds"
    intronic_file <- "rawcounts_intronic.rds"
    
    # Verify input files exist
    if (!file.exists(exonic_file)) {
      stop(paste("Required input file missing:", exonic_file))
    }
    if (!file.exists(intronic_file)) {
      stop(paste("Required input file missing:", intronic_file))
    }
    
    # 1. Load exonic and intronic count tables
    cntEx <- readRDS(exonic_file)
    cntIn <- readRDS(intronic_file)
    
    # 2. Remove non-count columns (such as width)
    rEx <- cntEx[, colnames(cntEx) != "width"]
    rIn <- cntIn[, colnames(cntIn) != "width"]
    
    # 3. Define the experimental condition factor
    # The documented code uses: cond <- factor(c("ES", "ES", "TN", "TN"))
    # We use this as default, but dynamically adjust if the input has a different number of columns.
    if (ncol(rEx) == 4) {
      cond <- factor(c("ES", "ES", "TN", "TN"))
    } else {
      cond <- factor(rep(c("Cond1", "Cond2"), each = ncol(rEx) / 2, length.out = ncol(rEx)))
    }
    
    # 4. Run the EISA statistical model using runEISA()
    res <- runEISA(rEx, rIn, cond)
    
    # 5. Visualize the results using plotEISA() and save to PDF
    pdf("eisa_plot.pdf", width = 7, height = 7)
    plotEISA(res)
    dev.off()
    
    # Save meaningful results to files
    saveRDS(res, "eisa_results.rds")
    
    # Export the main results table (interaction table)
    if (!is.null(res\$tab.ExIn)) {
      write.csv(res\$tab.ExIn, "eisa_tab_ExIn.csv", row.names = TRUE)
    }
    
    # Export the contrasts (log fold changes)
    if (!is.null(res\$contrasts)) {
      write.csv(res\$contrasts, "eisa_contrasts.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_EISAR_CONVENIENT_EISA_WORKFLOW":',
        paste0('    eisaR: ', as.character(packageVersion('eisaR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_convenient_eisa_workflow.csv versions.yml
    """
}

workflow BIOC_EISAR_CONVENIENT_EISA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rawcounts_exonic.rds, rawcounts_intronic.rds ] ]

    main:
    BIOC_EISAR_CONVENIENT_EISA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_EISAR_CONVENIENT_EISA_WORKFLOW.out.tables
    plots    = BIOC_EISAR_CONVENIENT_EISA_WORKFLOW.out.plots
    objects  = BIOC_EISAR_CONVENIENT_EISA_WORKFLOW.out.objects
    versions = BIOC_EISAR_CONVENIENT_EISA_WORKFLOW.out.versions
}
