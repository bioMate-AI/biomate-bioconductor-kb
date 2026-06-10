#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bacon — multiple_sets_and_meta_analysis
// Correct bias and inflation across multiple cohorts and perform a fixed-effect meta-analysis.
// Input: es, se
// Container: quay.io/biocontainers/bioconductor-bacon:1.38.0--r45h01b2380_0
// R packages: BiocParallel, bacon
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, bacon
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Register a parallel backend using BiocParallel
//  * 2. [Core Analysis] Run bacon on the effect sizes and standard errors
//  * 3. [Core Analysis] Extract corrected statistics (t-statistics, p-values, standard errors, effect sizes)
//  * 4. [Core Analysis] Diagnose individual cohort fits using traces, posteriors, and fit with the index parameter
//  * 5. [Core Analysis] Perform fixed-effect meta-analysis using meta
//  * 6. [Visualization & Output] Extract top results using topTable and plot meta-analysis QQ-plots

nextflow.enable.dsl = 2

process BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("BiocParallel", "bacon")
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
    library(bacon)
    library(BiocParallel)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    # The pipeline expects 'es' (matrix of effect sizes) and 'se' (matrix of standard errors)
    # in the working directory, either as RDS or CSV files.
    
    if (file.exists("es.rds")) {
      es <- readRDS("es.rds")
    } else if (file.exists("es.csv")) {
      es <- as.matrix(read.csv("es.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("es.txt")) {
      es <- as.matrix(read.table("es.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Effect sizes file ('es.rds', 'es.csv', or 'es.txt') not found in the working directory.")
    }
    
    if (file.exists("se.rds")) {
      se <- readRDS("se.rds")
    } else if (file.exists("se.csv")) {
      se <- as.matrix(read.csv("se.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("se.txt")) {
      se <- as.matrix(read.table("se.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Standard errors file ('se.rds', 'se.csv', or 'se.txt') not found in the working directory.")
    }
    
    # Ensure matrices are numeric
    es <- as.matrix(es)
    se <- as.matrix(se)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Register a parallel backend using BiocParallel
    # -----------------------------------------------------------------------------
    register(MulticoreParam(1, log=TRUE))
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run bacon on the effect sizes and standard errors
    # -----------------------------------------------------------------------------
    bc <- bacon(NULL, es, se)
    print(bc)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Extract corrected statistics
    # -----------------------------------------------------------------------------
    estimates_res <- estimates(bc)
    inflation_res <- inflation(bc)
    bias_res      <- bias(bc)
    
    tstat_res     <- tstat(bc)
    pval_res      <- pval(bc)
    se_res        <- se(bc)
    es_res        <- es(bc)
    
    # Print first few rows to stdout as in the documented code
    print(estimates_res)
    print(inflation_res)
    print(bias_res)
    print(tstat_res[1:5, , drop=FALSE])
    print(pval_res[1:5, , drop=FALSE])
    print(se_res[1:5, , drop=FALSE])
    print(es_res[1:5, , drop=FALSE])
    
    # Save extracted statistics to output files
    write.csv(estimates_res, "bacon_estimates.csv", row.names = TRUE)
    write.csv(as.data.frame(inflation_res), "bacon_inflation.csv", row.names = TRUE)
    write.csv(as.data.frame(bias_res), "bacon_bias.csv", row.names = TRUE)
    write.csv(tstat_res, "bacon_corrected_tstat.csv", row.names = TRUE)
    write.csv(pval_res, "bacon_corrected_pval.csv", row.names = TRUE)
    write.csv(se_res, "bacon_corrected_se.csv", row.names = TRUE)
    write.csv(es_res, "bacon_corrected_es.csv", row.names = TRUE)
    saveRDS(bc, "bacon_object.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 4: Diagnose individual cohort fits using traces, posteriors, and fit
    # -----------------------------------------------------------------------------
    # We wrap the plotting calls in a PDF device to save the diagnostic plots.
    # We use index=3 as documented in the vignette. If the input has fewer than 3
    # cohorts, we wrap in a tryCatch to prevent failure while keeping the exact call.
    pdf("bacon_diagnostics_index3.pdf", width = 8, height = 6)
    tryCatch({
      traces(bc, burnin=FALSE, index=3)
      posteriors(bc, index=3)
      fit(bc, n=100, index=3)
    }, error = function(e) {
      warning("Could not plot diagnostics for index=3: ", e\$message)
    })
    dev.off()
    
    pdf("bacon_plots.pdf", width = 8, height = 6)
    plot(bc, type="hist")
    plot(bc, type="qq")
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 5: Perform fixed-effect meta-analysis using meta
    # -----------------------------------------------------------------------------
    bcm <- meta(bc)
    saveRDS(bcm, "meta_object.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 6: Extract top results and plot meta-analysis QQ-plots
    # -----------------------------------------------------------------------------
    meta_pvals <- pval(bcm)
    print(head(meta_pvals))
    write.csv(meta_pvals, "meta_pvals.csv", row.names = TRUE)
    
    meta_top <- topTable(bcm)
    print(topTable(bcm))
    write.csv(meta_top, "meta_topTable.csv", row.names = TRUE)
    
    pdf("meta_plots.pdf", width = 8, height = 6)
    plot(bcm, type="qq")
    dev.off()

    writeLines(c(
        '"BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS":',
        paste0('    bacon: ', as.character(packageVersion('bacon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_sets_and_meta_analysis.csv versions.yml
    """
}

workflow BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ es, se ] ]

    main:
    BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS.out.tables
    plots    = BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS.out.plots
    objects  = BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS.out.objects
    versions = BIOC_BACON_MULTIPLE_SETS_AND_META_ANALYSIS.out.versions
}
