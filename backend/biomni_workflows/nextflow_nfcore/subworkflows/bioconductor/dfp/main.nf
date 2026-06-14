#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dfp — quick_discriminant_fuzzy_pattern
// Quickly identify differentially expressed genes from an ExpressionSet object using default parameters.
// Input: rmadataset
// Container: quay.io/biocontainers/bioconductor-dfp:1.68.0--r45hdfd78af_0
// R packages: Biobase, DFP
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dfp:1.68.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biobase", "DFP")
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
    library(DFP)
    library(Biobase)
    
    # Read the user input ExpressionSet object from the working directory
    if (file.exists("rmadataset")) {
      rmadataset <- readRDS("rmadataset")
    } else if (file.exists("rmadataset.rds")) {
      rmadataset <- readRDS("rmadataset.rds")
    } else {
      stop("Error: Input file 'rmadataset' or 'rmadataset.rds' not found in the working directory.")
    }
    
    # --- Run the wrapper function discriminantFuzzyPattern ---
    res <- discriminantFuzzyPattern(rmadataset)
    
    # Save the complete results list as an RDS object
    saveRDS(res, "dfp_results.rds")
    
    # Save the discriminant fuzzy pattern matrix as a CSV table
    write.csv(as.data.frame(res\$discriminant.fuzzy.pattern), "discriminant_fuzzy_pattern.csv", row.names = TRUE)
    
    # --- Plot the resulting discriminant fuzzy patterns to a PDF ---
    pdf("discriminant_fuzzy_pattern_plot.pdf", width = 11, height = 8.5)
    plotDiscriminantFuzzyPattern(res\$discriminant.fuzzy.pattern)
    dev.off()

    writeLines(c(
        '"BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN":',
        paste0('        dfp: ', as.character(packageVersion("dfp")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_discriminant_fuzzy_pattern.csv versions.yml
    """
}

workflow BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rmadataset ] ]

    main:
    BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN(ch_input)

    emit:
    tables   = BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN.out.tables
    plots    = BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN.out.plots
    objects  = BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN.out.objects
    versions = BIOC_DFP_QUICK_DISCRIMINANT_FUZZY_PATTERN.out.versions
}
