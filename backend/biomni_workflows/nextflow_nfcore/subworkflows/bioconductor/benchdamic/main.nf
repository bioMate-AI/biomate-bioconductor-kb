#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: benchdamic — goodness_of_fit_assessment
// Assess which parametric distributions best fit the count data and zero proportions of a microbiome dataset.
// Input: ps_stool_16S
// Container: quay.io/biocontainers/bioconductor-benchdamic:1.6.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: benchdamic, phyloseq
// Visualizations: mean-difference plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit a single model (e.g., Hurdle) to estimate counts and zero probabilities
//  * 2. [Input & Preparation] Prepare observed counts with matching scaling
//  * 3. [Core Analysis] Compute mean differences and zero probability differences
//  * 4. [Core Analysis] Fit multiple parametric models simultaneously
//  * 5. [Visualization & Output] Extract and plot Root Mean Squared Error (RMSE) and Mean Differences (MD)

nextflow.enable.dsl = 2

process BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT {
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
    .bm_deps <- c("benchdamic", "phyloseq")
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
    library(benchdamic)
    library(phyloseq)
    
    # 1. Read the user input file from the working directory
    if (file.exists("ps_stool_16S")) {
        ps_stool_16S <- readRDS("ps_stool_16S")
    } else if (file.exists("ps_stool_16S.rds")) {
        ps_stool_16S <- readRDS("ps_stool_16S.rds")
    } else {
        stop("Input file 'ps_stool_16S' or 'ps_stool_16S.rds' not found in the working directory.")
    }
    
    # 2. Fit a single model (Hurdle) to estimate counts and zero probabilities
    example_HURDLE <- fitHURDLE(
        object = ps_stool_16S,
        scale = "median"
    )
    saveRDS(example_HURDLE, "example_HURDLE.rds")
    
    # 3. Prepare observed counts with matching scaling
    observed_hurdle <- prepareObserved(
        object = ps_stool_16S, 
        scale = "median"
    )
    saveRDS(observed_hurdle, "observed_hurdle.rds")
    
    # 4. Compute mean differences and zero probability differences
    m_diffs <- meanDifferences(
        estimated = example_HURDLE,
        observed = observed_hurdle
    )
    write.csv(m_diffs, "mean_differences_hurdle.csv", row.names = TRUE)
    
    # 5. Fit multiple parametric models simultaneously
    GOF_stool_16S <- fitModels(
        object = ps_stool_16S,
        models = c("NB", "ZINB", "DM", "ZIG", "HURDLE"),
        scale_HURDLE = c("median", "default"),
        verbose = FALSE
    )
    saveRDS(GOF_stool_16S, "GOF_stool_16S.rds")
    
    # 6. Extract and plot Root Mean Squared Error (RMSE) and Mean Differences (MD)
    rmse_md <- plotRMSE(GOF_stool_16S, difference = "MD", plotIt = FALSE)
    write.csv(rmse_md, "rmse_md.csv", row.names = FALSE)
    
    rmse_zpd <- plotRMSE(GOF_stool_16S, difference = "ZPD", plotIt = FALSE)
    write.csv(rmse_zpd, "rmse_zpd.csv", row.names = FALSE)
    
    # Save the Mean Differences plot to a PDF file
    pdf("plot_md_split.pdf", width = 10, height = 8)
    p <- plotMD(
        data = GOF_stool_16S,
        difference = "MD",
        split = TRUE
    )
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT":',
        paste0('    benchdamic: ', as.character(packageVersion('benchdamic')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_goodness_of_fit_assessment.csv versions.yml
    """
}

workflow BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ps_stool_16S ] ]

    main:
    BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT.out.tables
    plots    = BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT.out.plots
    objects  = BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT.out.objects
    versions = BIOC_BENCHDAMIC_GOODNESS_OF_FIT_ASSESSMENT.out.versions
}
