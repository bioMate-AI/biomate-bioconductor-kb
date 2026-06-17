#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genefilter — independent_filtering_diagnostics
// Optimize the independent filtering threshold to maximize the number of discoveries while controlling the false discovery rate.
// Input: ALL
// Container: quay.io/biocontainers/bioconductor-genefilter:1.92.0--r45h9e4a190_0
// R packages: Biobase, genefilter
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, genefilter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subset the dataset to relevant samples
//  * 2. [Core Analysis] Compute a filter statistic (row variances) and unadjusted p-values (row t-tests)
//  * 3. [Core Analysis] Compute adjusted p-values across a range of filtering thresholds (theta) using filtered_p
//  * 4. [Visualization & Output] Visualize the number of rejections across thresholds using rejection_plot
//  * 5. [Visualization & Output] Calculate the exact number of rejections at a given alpha level across thresholds using filtered_R and plot the results

nextflow.enable.dsl = 2

process BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS {
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
    .bm_deps <- c("Biobase", "genefilter")
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
    library("Biobase")
    library("genefilter")
    
    # Read the input file 'ALL' from the working directory.
    if (file.exists("ALL")) {
      ALL <- tryCatch({
        readRDS("ALL")
      }, error = function(e) {
        env <- new.env()
        load("ALL", envir = env)
        if (exists("ALL", envir = env)) {
          env\$ALL
        } else {
          env[[ls(env)[1]]]
        }
      })
    } else if (file.exists("ALL.rds")) {
      ALL <- readRDS("ALL.rds")
    } else if (file.exists("ALL.RData")) {
      env <- new.env()
      load("ALL.RData", envir = env)
      if (exists("ALL", envir = env)) {
        ALL <- env\$ALL
      } else {
        ALL <- env[[ls(env)[1]]]
      }
    } else {
      stop("Error: Input file 'ALL' (or 'ALL.rds'/'ALL.RData') not found in the working directory.")
    }
    
    # 1. Subset the dataset to relevant samples
    bcell <- grep("^B", as.character(ALL\$BT))
    moltyp <- which(as.character(ALL\$mol.biol) %in% 
                    c("NEG", "BCR/ABL"))
    ALL_bcrneg <- ALL[, intersect(bcell, moltyp)]
    ALL_bcrneg\$mol.biol <- factor(ALL_bcrneg\$mol.biol)
    
    # 2. Compute a filter statistic (row variances) and unadjusted p-values (row t-tests)
    S2 <- rowVars(exprs(ALL_bcrneg))
    p2 <- rowttests(ALL_bcrneg, "mol.biol")\$p.value
    
    # 3. Compute adjusted p-values across a range of filtering thresholds (theta) using filtered_p
    theta <- seq(0, .5, .1)
    p_bh <- filtered_p(S2, p2, theta, method="BH")
    head(p_bh)
    
    # Save adjusted p-values to a CSV file
    write.csv(p_bh, file = "p_bh_adjusted_pvalues.csv", row.names = TRUE)
    
    # 4. Visualize the number of rejections across thresholds using rejection_plot
    pdf("rejection_plot.pdf", width = 6, height = 6)
    rejection_plot(p_bh, at="sample",
                   xlim=c(0,.3), ylim=c(0,1000),
                   main="Benjamini & Hochberg adjustment")
    dev.off()
    
    # 5. Calculate the exact number of rejections at a given alpha level across thresholds using filtered_R and plot the results
    theta <- seq(0, .80, .01)
    R_BH <- filtered_R(alpha=.10, S2, p2, theta, method="BH")
    head(R_BH)
    
    # Save rejections data to a CSV file
    rejections_df <- data.frame(theta = theta, Rejections = R_BH)
    write.csv(rejections_df, file = "rejections_by_theta.csv", row.names = FALSE)
    
    # Plot the results
    pdf("filtered_R_plot.pdf", width = 6, height = 6)
    plot(theta, R_BH, type="l",
         xlab=expression(theta), ylab="Rejections",
         main="BH cutoff = 0.1")
    dev.off()

    writeLines(c(
        '"BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS":',
        paste0('    genefilter: ', as.character(packageVersion('genefilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_independent_filtering_diagnostics.csv versions.yml
    """
}

workflow BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ALL ] ]

    main:
    BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS(ch_input)

    emit:
    tables   = BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS.out.tables
    plots    = BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS.out.plots
    objects  = BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS.out.objects
    versions = BIOC_GENEFILTER_INDEPENDENT_FILTERING_DIAGNOSTICS.out.versions
}
