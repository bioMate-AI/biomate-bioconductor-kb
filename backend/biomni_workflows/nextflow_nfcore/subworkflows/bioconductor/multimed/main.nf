#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MultiMed — multiple_mediation_analysis
// Test multiple potential mediators simultaneously between an exposure and an outcome, adjusting for covariates and applying observational weights.
// Input: NavyAdenoma
// Container: quay.io/biocontainers/bioconductor-multimed:2.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiMed
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the MultiMed package and the dataset
//  * 2. [Core Analysis] Calculate observational weights based on disease prevalence and case-control proportions
//  * 3. [Core Analysis] Run the mediation test using medTest with specified permutations, covariates, and weights
//  * 4. [Core Analysis] Identify the top mediators by sorting or filtering the resulting p-values

nextflow.enable.dsl = 2

process BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MultiMed")
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
        
    # Load required library
    library(MultiMed)
    
    # 1. Read the input file 'NavyAdenoma' from the working directory
    if (file.exists("NavyAdenoma")) {
      NavyAdenoma <- tryCatch({
        readRDS("NavyAdenoma")
      }, error = function(e) {
        tryCatch({
          read.csv("NavyAdenoma", check.names = FALSE)
        }, error = function(e2) {
          read.table("NavyAdenoma", header = TRUE, check.names = FALSE)
        })
      })
    } else if (file.exists("NavyAdenoma.csv")) {
      NavyAdenoma <- read.csv("NavyAdenoma.csv", check.names = FALSE)
    } else if (file.exists("NavyAdenoma.rds")) {
      NavyAdenoma <- readRDS("NavyAdenoma.rds")
    } else {
      stop("Required input file 'NavyAdenoma' (or NavyAdenoma.csv/rds) not found in the working directory.")
    }
    
    # Ensure NavyAdenoma is a data frame
    NavyAdenoma <- as.data.frame(NavyAdenoma)
    
    # Handle potential row names column if read from a CSV
    if ("Fish" %in% colnames(NavyAdenoma)) {
      fish_idx <- which(colnames(NavyAdenoma) == "Fish")
      if (length(fish_idx) > 0 && fish_idx > 1) {
        rownames(NavyAdenoma) <- NavyAdenoma[[1]]
        NavyAdenoma <- NavyAdenoma[, -1, drop = FALSE]
      }
    }
    
    # 2. Calculate observational weights based on disease prevalence and case-control proportions
    prev <- 0.228
    p <- sum(NavyAdenoma\$Adenoma == 1) / nrow(NavyAdenoma)
    
    w <- rep(NA, nrow(NavyAdenoma))
    w[NavyAdenoma\$Adenoma == 1] <- prev / p
    w[NavyAdenoma\$Adenoma == 0] <- (1 - prev) / (1 - p)
    
    # 3. Run the mediation test using medTest with specified permutations, covariates, and weights
    set.seed(840218)
    medsFish <- medTest(E = NavyAdenoma\$Fish,
                        M = NavyAdenoma[, 6:154],
                        Y = NavyAdenoma\$Adenoma,
                        Z = NavyAdenoma[, 2:5],
                        nperm = 1000, w = w,
                        useWeightsZ = FALSE)
    
    # 4. Identify the top mediators by sorting or filtering the resulting p-values
    rownames(medsFish) <- colnames(NavyAdenoma)[6:154]
    top_mediator <- medsFish[which.min(medsFish[, "p"]), , drop = FALSE]
    
    # Write outputs to the working directory
    write.csv(as.data.frame(medsFish), "mediation_results.csv", row.names = TRUE)
    write.csv(as.data.frame(top_mediator), "top_mediator.csv", row.names = TRUE)
    saveRDS(medsFish, "mediation_results.rds")
    
    # Generate a diagnostic plot of the p-value distribution
    tryCatch({
      pdf("mediation_pvalues_histogram.pdf", width = 6, height = 5)
      hist(medsFish[, "p"], breaks = 20, col = "skyblue", border = "white",
           main = "Distribution of Mediation P-values",
           xlab = "P-value", ylab = "Frequency")
      dev.off()
    }, error = function(e) {
      warning("Could not generate the PDF plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS":',
        paste0('    MultiMed: ', as.character(packageVersion('MultiMed')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_mediation_analysis.csv versions.yml
    """
}

workflow BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NavyAdenoma ] ]

    main:
    BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS.out.tables
    plots    = BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS.out.plots
    objects  = BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS.out.objects
    versions = BIOC_MULTIMED_MULTIPLE_MEDIATION_ANALYSIS.out.versions
}
