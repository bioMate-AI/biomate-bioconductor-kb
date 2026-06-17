#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: matchBox — cat_curve_analysis
// Compare ranked lists of features across multiple datasets using Correspondence-At-the-Top (CAT) curves and compute statistical significance.
// Input: matchBoxExpression
// Container: quay.io/biocontainers/bioconductor-matchbox:1.52.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: matchBox
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Remove redundant features from each dataset using
//  * 2. [Visualization & Output] Merge datasets based on common identifiers using mergeData
//  * 3. [Visualization & Output] Compute CAT curves using computeCat
//  * 4. [Visualization & Output] Compute probability intervals using calcHypPI
//  * 5. [Visualization & Output] Plot the CAT curves and probability intervals using

nextflow.enable.dsl = 2

process BIOC_MATCHBOX_CAT_CURVE_ANALYSIS {
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
    .bm_deps <- c("matchBox")
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
    library(matchBox)
    
    # Read user input from the working directory
    input_file <- "matchBoxExpression"
    if (!file.exists(input_file)) {
      if (file.exists("matchBoxExpression.rds")) {
        input_file <- "matchBoxExpression.rds"
      } else {
        stop("Error: Input file 'matchBoxExpression' or 'matchBoxExpression.rds' not found in the working directory.")
      }
    }
    
    matchBoxExpression <- readRDS(input_file)
    
    # Dynamically determine column names from the first dataset
    id_col <- colnames(matchBoxExpression[[1]])[1]
    by_col <- colnames(matchBoxExpression[[1]])[2]
    
    # --- Remove redundant features from each dataset using ---
    allDataBySymbolAndT <- lapply(matchBoxExpression, filterRedundant, idCol=id_col, byCol=by_col, absolute=TRUE)
    
    # --- Merge datasets based on common identifiers using mergeData ---
    data <- mergeData(allDataBySymbolAndT, idCol=id_col, byCol=by_col)
    
    # Save merged data to CSV
    write.csv(data, file = "merged_data.csv", row.names = FALSE)
    
    # --- Compute CAT curves using computeCat ---
    # Dynamically set the reference to the first dataset's statistic column
    ref_col <- colnames(data)[2]
    catHigh2LowWithRefByEqualRanks <- computeCat(data = data, idCol = 1, ref=ref_col,  method="equalRank", decreasing=TRUE)
    
    # Save CAT results to RDS
    saveRDS(catHigh2LowWithRefByEqualRanks, file = "cat_results.rds")
    
    # --- Compute probability intervals using calcHypPI ---
    PIbyRefEqualRanks03 <- calcHypPI(data=data, expectedProp=0.3)
    
    # Save probability intervals to CSV
    write.csv(as.data.frame(PIbyRefEqualRanks03), file = "probability_intervals.csv", row.names = TRUE)
    
    # --- Plot the CAT curves and probability intervals using ---
    pdf("cat_plot.pdf", width = 10, height = 7)
    plotCat(catData = catHigh2LowWithRefByEqualRanks, 
    	preComputedPI=PIbyRefEqualRanks03,
    	cex=1.2, lwd=1.2, cexPts=1.2, spacePts=30, col=c("red", "blue"),
    	main=paste("CAT curves for decreasing", by_col),
    	where="center", legend=TRUE, legCex=1, ncol=1,
    	plotLayout = layout(matrix(1:2, ncol = 2), widths = c(2,1)))
    dev.off()

    writeLines(c(
        '"BIOC_MATCHBOX_CAT_CURVE_ANALYSIS":',
        paste0('    matchBox: ', as.character(packageVersion('matchBox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cat_curve_analysis.csv versions.yml
    """
}

workflow BIOC_MATCHBOX_CAT_CURVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matchBoxExpression ] ]

    main:
    BIOC_MATCHBOX_CAT_CURVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MATCHBOX_CAT_CURVE_ANALYSIS.out.tables
    plots    = BIOC_MATCHBOX_CAT_CURVE_ANALYSIS.out.plots
    objects  = BIOC_MATCHBOX_CAT_CURVE_ANALYSIS.out.objects
    versions = BIOC_MATCHBOX_CAT_CURVE_ANALYSIS.out.versions
}
