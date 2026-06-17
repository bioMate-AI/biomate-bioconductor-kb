#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TurboNorm — weighted_methylation_normalization
// Perform weighted P-spline normalization on array-based DNA methylation data using an invariant subset to prevent overcorrection.
// Input: methylation.RData
// Container: quay.io/biocontainers/bioconductor-turbonorm:1.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TurboNorm, lattice, limma
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the TurboNorm library and methylation data
//  * 2. [Input & Preparation] Define weights based on the invariant subset indices
//  * 3. [Core Analysis] Convert intensities to M and A values without background correction
//  * 4. [Visualization & Output] Plot and compare lowess and pspline fits using panel.pspline() within a lattice xyplot

nextflow.enable.dsl = 2

process BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("TurboNorm", "lattice", "limma")
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
    library(TurboNorm)
    library(lattice)
    library(limma)
    
    # 1. Load the methylation data from the working directory
    # The file 'methylation.RData' contains the RGList object named 'methylation'
    load("methylation.RData")
    
    # 2. Define weights based on the invariant subset indices
    indices <- methylation\$weights[,1]
    weights <- rep(1, length(indices))
    weights[indices] <- length(indices)/sum(indices)
    
    # 3. Convert intensities to M and A values without background correction
    MA <- normalizeWithinArrays(methylation, method="none", bc.method="none")
    
    # Prepare labels and data frame for plotting
    labels <- paste("NMB", c("(untreated)", "(treated)"))
    labels <- paste(rep(c("Raw"), each=2), labels)
    
    data <- data.frame(
      M = as.vector(MA\$M),
      A = as.vector(MA\$A),
      Array = factor(rep(labels, each=nrow(MA\$A)), levels=rev(labels))
    )
    
    # 4. Plot and compare lowess and pspline fits using panel.pspline() within a lattice xyplot
    pdf("methylation_normalization_plot.pdf", width=10, height=8)
    print(xyplot(M~A|Array, xlab="", ylab="", data=data, type='g',
      panel = function(x, y) {
        panel.xyplot(x, y, col="grey")
        lpoints(x[indices], y[indices], pch=20, col="black")
        panel.pspline(x, y, weights = weights, col="red", lwd=2)
        panel.loess(x, y, col="green", lwd=2)
      }
    ))
    dev.off()
    
    # Save meaningful results to output files
    write.csv(data, "methylation_data.csv", row.names=FALSE)
    saveRDS(MA, "MA_raw.rds")
    saveRDS(weights, "computed_weights.rds")

    writeLines(c(
        '"BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION":',
        paste0('    TurboNorm: ', as.character(packageVersion('TurboNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weighted_methylation_normalization.csv versions.yml
    """
}

workflow BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ methylation.RData ] ]

    main:
    BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION.out.tables
    plots    = BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION.out.plots
    objects  = BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION.out.objects
    versions = BIOC_TURBONORM_WEIGHTED_METHYLATION_NORMALIZATION.out.versions
}
