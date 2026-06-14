#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: arrayQualityMetrics — standard_qc_report
// Generate a standard, comprehensive HTML quality report from a microarray data container.
// Input: MLL.A, CCl4
// Container: quay.io/biocontainers/bioconductor-arrayqualitymetrics:3.62.0--r44hdfd78af_0
// R packages: Biobase, affy, allmll, arrayQualityMetrics, ccl4, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, affy, arrayQualityMetrics, vsn
// Visualizations: box plot
// QC: variance-stabilizing normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load raw data
//  * 2. [Core Analysis] Run arrayQualityMetrics on raw data with log transformation
//  * 3. [Core Analysis] Preprocess data (using rma or justvsn)
//  * 4. [Core Analysis] Run arrayQualityMetrics on preprocessed data
//  * 5. [Core Analysis] Add experimental factors or spatial coordinates to metadata
//  * 6. [Core Analysis] Run arrayQualityMetrics with metadata factors

nextflow.enable.dsl = 2

process BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT {
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
    .bm_deps <- c("Biobase", "affy", "allmll", "arrayQualityMetrics", "ccl4", "vsn")
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
    library("arrayQualityMetrics")
    library("Biobase")
    library("affy")
    library("vsn")
    
    # 1. Read the user input file 'MLL.A' from the working directory
    if (file.exists("MLL.A")) {
      MLL.A = tryCatch({
        readRDS("MLL.A")
      }, error = function(e) {
        env = new.env()
        load("MLL.A", envir = env)
        # Retrieve the first object loaded from the RData file
        env[[names(env)[1]]]
      })
    } else {
      stop("Required input file 'MLL.A' (AffyBatch object) not found in the working directory.")
    }
    
    # Verify that the loaded object is indeed an AffyBatch or ExpressionSet
    if (!inherits(MLL.A, "AffyBatch") && !inherits(MLL.A, "ExpressionSet")) {
      stop("Loaded object 'MLL.A' must be of class 'AffyBatch' or 'ExpressionSet'.")
    }
    
    # Read the user input file 'CCl4' from the working directory
    if (file.exists("CCl4")) {
      CCl4 = tryCatch({
        readRDS("CCl4")
      }, error = function(e) {
        env = new.env()
        load("CCl4", envir = env)
        env[[names(env)[1]]]
      })
    } else {
      stop("Required input file 'CCl4' (NChannelSet object) not found in the working directory.")
    }
    
    if (!inherits(CCl4, "NChannelSet") && !inherits(CCl4, "ExpressionSet")) {
      stop("Loaded object 'CCl4' must be of class 'NChannelSet' or 'ExpressionSet'.")
    }
    
    # --- PLANNED STAGES ---
    # Preprocessing with rma/justvsn
    nMLL = rma(MLL.A)
    nCCl4 = justvsn(CCl4, subsample = 15000)
    
    # Adding metadata factors
    pData(nMLL)\$condition = rep(letters[1:4], length.out = ncol(nMLL))
    pData(nMLL)\$batch = rep(paste(1:4), length.out = ncol(nMLL))
    
    pd = pData(CCl4)
    rownames(pd) = NULL
    RIN = with(pd, ifelse( Cy3=="CCl4", RIN.Cy3, RIN.Cy5))
    fRIN = factor(RIN)
    levels(fRIN) = c("poor", "medium", "good")
    pData(nCCl4)\$"RNA-integrity" = fRIN
    
    # Running arrayQualityMetrics on preprocessed data
    arrayQualityMetrics(expressionset = nMLL, outdir = "Report_for_nMLL", force = TRUE)
    arrayQualityMetrics(expressionset = nCCl4, outdir = "Report_for_nCCl4", force = TRUE)
    arrayQualityMetrics(expressionset = nMLL, outdir = "Report_for_nMLL_with_factors", force = TRUE, intgroup = c("condition", "batch"))
    arrayQualityMetrics(expressionset = nCCl4, outdir = "Report_for_nCCl4_with_RIN", force = TRUE, intgroup = "RNA-integrity")
    # ----------------------
    
    # 2. Prepare data using prepdata to perform common pre-computations
    preparedData = prepdata(expressionset = MLL.A, 
                            intgroup = c(), 
                            do.logtransform = TRUE)
    
    # 3. Generate individual report modules using aqm.boxplot and aqm.density
    bo = aqm.boxplot(preparedData)
    de = aqm.density(preparedData)
    
    # 4. Combine modules into a list
    qm = list("Boxplot" = bo, "Density" = de)
    
    # 5. Inspect outlier detection statistics programmatically and save them
    bo@outliers
    
    # Extract outlier statistics and save to a CSV file
    outliers_stat = bo@outliers@statistic
    outliers_threshold = bo@outliers@threshold
    outliers_which = bo@outliers@which
    
    # Determine which arrays are classified as outliers
    is_outlier = rep(FALSE, length(outliers_stat))
    names(is_outlier) = names(outliers_stat)
    if (length(outliers_which) > 0) {
      is_outlier[outliers_which] = TRUE
    }
    
    outliers_df = data.frame(
      Array = names(outliers_stat),
      KS_Statistic = outliers_stat,
      Threshold = outliers_threshold,
      IsOutlier = is_outlier,
      stringsAsFactors = FALSE
    )
    
    write.csv(outliers_df, "boxplot_outliers.csv", row.names = FALSE)
    
    # Save the prepared data and modules as RDS objects for downstream analysis
    saveRDS(preparedData, "prepared_data.rds")
    saveRDS(qm, "qc_modules.rds")
    
    # 6. Render the standard comprehensive report using arrayQualityMetrics
    outdir = "custom_qc_report"
    arrayQualityMetrics(expressionset = MLL.A, outdir = outdir, force = TRUE, do.logtransform = TRUE)
    
    cat("Pipeline completed successfully. Outputs saved to 'boxplot_outliers.csv', 'prepared_data.rds', 'qc_modules.rds', and the HTML report directory '", outdir, "'.\n", sep = "")

    writeLines(c(
        '"BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT":',
        paste0('    arrayQualityMetrics: ', as.character(packageVersion('arrayQualityMetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_qc_report.csv versions.yml
    """
}

workflow BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MLL.A, CCl4 ] ]

    main:
    BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT(ch_input)

    emit:
    tables   = BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT.out.tables
    plots    = BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT.out.plots
    objects  = BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT.out.objects
    versions = BIOC_ARRAYQUALITYMETRICS_STANDARD_QC_REPORT.out.versions
}
