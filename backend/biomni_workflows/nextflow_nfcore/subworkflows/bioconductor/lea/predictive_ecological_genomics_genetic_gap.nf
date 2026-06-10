#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lea — predictive_ecological_genomics_genetic_gap
// Calculate genomic offset (genetic gap) to predict population maladaptation under environmental change.
// Input: Y, X, X.pred
// Container: quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0
// R packages: LEA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0"

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
    .bm_deps <- c("LEA")
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
    library(LEA)
    
    # Read user input files from the working directory
    if (!file.exists("Y.rds") || !file.exists("X.rds") || !file.exists("X.pred.rds")) {
      stop("Required input files (Y.rds, X.rds, X.pred.rds) not found in the working directory.")
    }
    
    Y <- readRDS("Y.rds")
    X <- readRDS("X.rds")
    X.pred <- readRDS("X.pred.rds")
    
    # Ensure inputs are in matrix format
    Y <- as.matrix(Y)
    X <- as.matrix(X)
    X.pred <- as.matrix(X.pred)
    
    # 1. Compute the geometric genetic gap using the genetic.gap() function
    g.gap.scaled <- genetic.gap(input = Y, env = X, pred.env = X.pred, scale = TRUE, K = 2)
    
    # Save the genetic gap object
    saveRDS(g.gap.scaled, "g_gap_scaled.rds")
    
    # 2. Extract relative contributions of environmental predictors to local adaptation
    contributions <- g.gap.scaled\$vectors[,1:2]^2
    write.csv(contributions, "environmental_contributions.csv", row.names = FALSE)
    
    # 3. Plot covariance eigenvalues and correlate the genetic gap with squared ecological distance
    pdf("genetic_gap_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    
    barplot(g.gap.scaled\$eigenvalues, col = "orange", xlab = "Axes", ylab = "Eigenvalues")
    
    Delta = X[,1:2] - X.pred[,1:2]
    squared.env.dist = rowSums(Delta^2)
    plot(squared.env.dist, g.gap.scaled\$offset,  cex = .6)
    
    dev.off()
    
    # Save the distance and offset data to a CSV
    offset_data <- data.frame(
      squared_env_dist = squared.env.dist,
      genetic_offset = g.gap.scaled\$offset
    )
    write.csv(offset_data, "ecological_distance_vs_offset.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP":
        lea: \$(Rscript -e 'cat(as.character(packageVersion("lea")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predictive_ecological_genomics_genetic_gap.csv versions.yml
    """
}

workflow BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, X, X.pred ] ]

    main:
    BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP(ch_input)

    emit:
    tables   = BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP.out.tables
    plots    = BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP.out.plots
    objects  = BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP.out.objects
    versions = BIOC_LEA_PREDICTIVE_ECOLOGICAL_GENOMICS_GENETIC_GAP.out.versions
}
